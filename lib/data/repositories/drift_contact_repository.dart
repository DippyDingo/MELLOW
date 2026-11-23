import 'package:drift/drift.dart' hide Column;
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/mappers/contact_mapper.dart';
import 'package:mellow/domain/entities/contact.dart';
import 'package:mellow/domain/repositories/contact_repository.dart';
import 'package:uuid/uuid.dart';

/// Drift-backed [ContactRepository].
///
/// Address rows are the source of truth for who a contact is; contacts are
/// created together with at least one address, and an address belongs to at
/// most one contact (unique index on `contact_emails.email`).
class DriftContactRepository implements ContactRepository {
  DriftContactRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  @override
  Stream<List<Contact>> watchContacts() {
    final query = _db.select(_db.contacts).join([
      leftOuterJoin(
        _db.contactEmails,
        _db.contactEmails.contactId.equalsExp(_db.contacts.id),
      ),
    ])
      ..orderBy([
        OrderingTerm(expression: _db.contacts.isFavorite, mode: OrderingMode.desc),
        OrderingTerm(expression: _db.contacts.displayName.lower()),
      ]);

    return query.watch().map(_groupJoinedRows);
  }

  Future<List<Contact>> getContacts() async {
    final rows = await _joinedQuery().get();
    return _groupJoinedRows(rows);
  }

  @override
  Future<List<Contact>> search(String query) async {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return getContacts();

    final rows = await _joinedQuery(term: term).get();
    return _groupJoinedRows(rows);
  }

  @override
  Future<Contact?> getContact(String id) async {
    final row = await (_db.select(_db.contacts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return ContactMapper.toEntity(row, await _emailsFor(id));
  }

  @override
  Future<Contact?> findByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    final row = await (_db.select(_db.contactEmails)
          ..where((t) => t.email.equals(normalized)))
        .getSingleOrNull();
    if (row == null) return null;
    return getContact(row.contactId);
  }

  @override
  Future<Contact> saveContact(Contact contact) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.contacts).insertOnConflictUpdate(
            ContactMapper.toCompanion(contact, now: now),
          );
      await (_db.delete(_db.contactEmails)
            ..where((t) => t.contactId.equals(contact.id)))
          .go();
      for (var i = 0; i < contact.addresses.length; i++) {
        final address = contact.addresses[i];
        await _db.into(_db.contactEmails).insert(
              ContactMapper.emailToCompanion(
                id: _uuid.v4(),
                contactId: contact.id,
                email: address.copyWith(isPrimary: i == 0),
              ),
            );
      }
    });
    return (await getContact(contact.id)) ?? contact;
  }

  @override
  Future<void> addAddress(String contactId, ContactEmail email) async {
    final normalized = email.email.trim().toLowerCase();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.contactEmails)
            ..where((t) => t.email.equals(normalized)))
          .getSingleOrNull();
      if (existing != null) {
        if (existing.contactId == contactId) return;
        throw StateError('Address $normalized already belongs to a contact');
      }
      final hasPrimary = await (_db.select(_db.contactEmails)
            ..where((t) => t.contactId.equals(contactId)))
          .get()
          .then((rows) => rows.any((row) => row.isPrimary));
      await _db.into(_db.contactEmails).insert(
            ContactMapper.emailToCompanion(
              id: _uuid.v4(),
              contactId: contactId,
              email: email.copyWith(isPrimary: !hasPrimary),
            ),
          );
      await _touch(contactId);
    });
  }

  @override
  Future<void> removeAddress(String email) async {
    final normalized = email.trim().toLowerCase();
    final row = await (_db.select(_db.contactEmails)
          ..where((t) => t.email.equals(normalized)))
        .getSingleOrNull();
    if (row == null) return;
    await _db.transaction(() async {
      await (_db.delete(_db.contactEmails)..where((t) => t.id.equals(row.id))).go();
      if (row.isPrimary) {
        final remaining = await _emailsFor(row.contactId);
        if (remaining.isNotEmpty) {
          await (_db.update(_db.contactEmails)
                ..where((t) => t.id.equals(remaining.first.id)))
              .write(const ContactEmailsCompanion(isPrimary: Value(true)));
        }
      }
      await _touch(row.contactId);
    });
  }

  @override
  Future<void> setFavorite(String contactId, {required bool isFavorite}) async {
    await (_db.update(_db.contacts)..where((t) => t.id.equals(contactId))).write(
      ContactsCompanion(
        isFavorite: Value(isFavorite),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> mergeContacts({
    required String targetId,
    required String sourceId,
  }) async {
    if (targetId == sourceId) return;
    await _db.transaction(() async {
      await (_db.update(_db.contactEmails)
            ..where((t) => t.contactId.equals(sourceId)))
          .write(ContactEmailsCompanion(contactId: Value(targetId)));
      await (_db.update(_db.conversations)
            ..where((t) => t.contactId.equals(sourceId)))
          .write(ConversationsCompanion(contactId: Value(targetId)));
      await (_db.update(_db.conversationParticipants)
            ..where((t) => t.contactId.equals(sourceId)))
          .write(ConversationParticipantsCompanion(contactId: Value(targetId)));
      await (_db.delete(_db.contacts)..where((t) => t.id.equals(sourceId))).go();
      await _touch(targetId);
    });
  }

  @override
  Future<void> deleteContact(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.contactEmails)..where((t) => t.contactId.equals(id))).go();
      await (_db.update(_db.conversations)..where((t) => t.contactId.equals(id)))
          .write(const ConversationsCompanion(contactId: Value(null)));
      await (_db.delete(_db.contacts)..where((t) => t.id.equals(id))).go();
    });
  }

  JoinedSelectStatement<HasResultSet, dynamic> _joinedQuery({String? term}) {
    final query = _db.select(_db.contacts).join([
      leftOuterJoin(
        _db.contactEmails,
        _db.contactEmails.contactId.equalsExp(_db.contacts.id),
      ),
    ])
      ..orderBy([
        OrderingTerm(expression: _db.contacts.isFavorite, mode: OrderingMode.desc),
        OrderingTerm(expression: _db.contacts.displayName.lower()),
        OrderingTerm(
          expression: _db.contactEmails.isPrimary,
          mode: OrderingMode.desc,
        ),
      ]);

    if (term != null) {
      query.where(
        _db.contacts.displayName.lower().contains(term) |
            _db.contactEmails.email.lower().contains(term),
      );
    }
    return query;
  }

  /// Collapses joined rows (one per address) into contacts, keeping order.
  List<Contact> _groupJoinedRows(List<TypedResult> rows) {
    final contacts = <String, ContactRow>{};
    final emails = <String, List<ContactEmailRow>>{};

    for (final row in rows) {
      final contact = row.readTable(_db.contacts);
      contacts[contact.id] = contact;
      final email = row.readTableOrNull(_db.contactEmails);
      if (email != null) {
        (emails[contact.id] ??= <ContactEmailRow>[]).add(email);
      }
    }

    final result = <Contact>[];
    for (final entry in contacts.entries) {
      final addresses = emails[entry.key] ?? const <ContactEmailRow>[];
      addresses.sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
      result.add(ContactMapper.toEntity(entry.value, addresses));
    }
    return result;
  }

  Future<List<ContactEmailRow>> _emailsFor(String contactId) async {
    final rows = await (_db.select(_db.contactEmails)
          ..where((t) => t.contactId.equals(contactId)))
        .get();
    rows.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    return rows;
  }

  Future<void> _touch(String contactId) async {
    await (_db.update(_db.contacts)..where((t) => t.id.equals(contactId))).write(
      ContactsCompanion(updatedAt: Value(DateTime.now())),
    );
  }
}
