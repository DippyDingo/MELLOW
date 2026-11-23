import 'package:drift/drift.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/domain/entities/contact.dart';

/// Translates between `contacts` / `contact_emails` rows and [Contact].
abstract final class ContactMapper {
  /// Builds a contact from its row plus its address rows (primary first).
  static Contact toEntity(ContactRow row, List<ContactEmailRow> emails) {
    final addresses = emails
        .map(
          (email) => ContactEmail(
            email: email.email,
            label: email.label,
            displayName: email.displayName,
            isPrimary: email.isPrimary,
          ),
        )
        .toList(growable: false);

    return Contact(
      id: row.id,
      displayName: row.displayName,
      addresses: addresses,
      isFavorite: row.isFavorite,
      updatedAt: row.updatedAt,
    );
  }

  static ContactsCompanion toCompanion(Contact contact, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return ContactsCompanion.insert(
      id: contact.id,
      displayName: contact.displayName,
      isFavorite: Value(contact.isFavorite),
      createdAt: Value(timestamp),
      updatedAt: Value(timestamp),
    );
  }

  static ContactEmailsCompanion emailToCompanion({
    required String id,
    required String contactId,
    required ContactEmail email,
  }) {
    return ContactEmailsCompanion.insert(
      id: id,
      contactId: contactId,
      email: email.email,
      displayName: Value(email.displayName),
      label: Value(email.label),
      isPrimary: Value(email.isPrimary),
    );
  }
}
