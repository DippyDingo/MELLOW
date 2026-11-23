import 'package:drift/drift.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/mappers/message_mapper.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:mellow/domain/repositories/thread_repository.dart';

/// Drift-backed [ThreadRepository].
///
/// Deduplication is enforced twice:
/// * unique index on `(account_id, provider_message_id)`;
/// * an explicit lookup by RFC `Message-ID` before insert, because some
///   providers return the same RFC message under different ids.
class DriftThreadRepository implements ThreadRepository {
  DriftThreadRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<MessageThread>> watchThreads([
    ThreadFilter filter = const ThreadFilter(),
  ]) {
    // Watch both tables: any message or conversation change refreshes the list.
    final trigger = _db
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM conversations) AS c, '
          '(SELECT COUNT(*) FROM messages) AS m, '
          '(SELECT COALESCE(SUM(unread_count), 0) FROM conversations) AS u',
          readsFrom: {_db.conversations, _db.messages},
        )
        .watch();

    return trigger.asyncMap((_) => getThreads(filter));
  }

  @override
  Future<List<MessageThread>> getThreads([
    ThreadFilter filter = const ThreadFilter(),
  ]) async {
    final query = _db.select(_db.conversations);
    if (filter.accountId != null) {
      query.where((t) => t.accountId.equals(filter.accountId!));
    }
    if (!filter.includeArchived) {
      query.where((t) => t.isArchived.equals(false));
    }
    query.where((t) => t.isHidden.equals(false));
    if (filter.unreadOnly) {
      query.where((t) => t.unreadCount.isBiggerThanValue(0));
    }
    if (filter.contactId != null) {
      query.where((t) => t.contactId.equals(filter.contactId!));
    }
    final term = filter.query?.trim().toLowerCase();
    if (term != null && term.isNotEmpty) {
      query.where(
        (t) => t.subject.lower().contains(term) |
            t.lastMessagePreview.lower().contains(term),
      );
    }

    query.orderBy([
      (t) => OrderingTerm(expression: t.isPinned, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
    ]);

    final rows = await query.get();
    if (rows.isEmpty) return const <MessageThread>[];

    if (filter.favoritesOnly) return _filterFavorites(rows);

    final participants = await _participantsFor(rows.map((r) => r.id).toList());
    return rows
        .map((row) => MessageMapper.threadToEntity(row, participants[row.id] ?? const []))
        .toList(growable: false);
  }

  /// Keeps only threads whose contact is a favourite.
  ///
  /// Done in a second query because the favourite flag lives on `contacts`, and
  /// a join would drop threads whose participants are not yet resolved.
  Future<List<MessageThread>> _filterFavorites(List<ConversationRow> rows) async {
    final favoriteContacts = await (_db.select(_db.contacts)
          ..where((t) => t.isFavorite.equals(true)))
        .get();
    final ids = favoriteContacts.map((c) => c.id).toSet();
    final favorites = rows.where((row) => ids.contains(row.contactId)).toList();
    if (favorites.isEmpty) return const <MessageThread>[];
    final participants =
        await _participantsFor(favorites.map((r) => r.id).toList());
    return favorites
        .map((row) => MessageMapper.threadToEntity(row, participants[row.id] ?? const []))
        .toList(growable: false);
  }

  @override
  Future<MessageThread?> getThread(String id) async {
    final row = await (_db.select(_db.conversations)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    final participants = await _participantsFor(<String>[id]);
    return MessageMapper.threadToEntity(row, participants[id] ?? const []);
  }

  @override
  Stream<List<Message>> watchMessages(String threadId) {
    final query = _db.select(_db.messages)
      ..where((t) => t.conversationId.equals(threadId))
      ..orderBy([(t) => OrderingTerm(expression: t.sentAt)]);
    return query.watch().map(
          (rows) => rows.map(MessageMapper.toEntity).toList(growable: false),
        );
  }

  @override
  Future<List<Message>> getMessages(String threadId) async {
    final rows = await (_db.select(_db.messages)
          ..where((t) => t.conversationId.equals(threadId))
          ..orderBy([(t) => OrderingTerm(expression: t.sentAt)]))
        .get();
    return rows.map(MessageMapper.toEntity).toList(growable: false);
  }

  @override
  Future<Message?> getMessage(String id) async {
    final row = await (_db.select(_db.messages)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : MessageMapper.toEntity(row);
  }

  @override
  Future<Message?> findByMessageIdHeader(String messageIdHeader) async {
    if (messageIdHeader.trim().isEmpty) return null;
    final row = await (_db.select(_db.messages)
          ..where((t) => t.messageIdHeader.equals(messageIdHeader.trim()))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : MessageMapper.toEntity(row);
  }

  @override
  Future<Message?> findByProviderMessageId(
    String accountId,
    String providerMessageId,
  ) async {
    if (providerMessageId.isEmpty) return null;
    final row = await (_db.select(_db.messages)
          ..where(
            (t) => t.accountId.equals(accountId) &
                t.providerMessageId.equals(providerMessageId),
          )
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : MessageMapper.toEntity(row);
  }

  @override
  Future<MessageThread?> findByProviderThreadId(
    String accountId,
    String providerThreadId,
  ) async {
    if (providerThreadId.isEmpty) return null;
    final row = await (_db.select(_db.conversations)
          ..where(
            (t) => t.accountId.equals(accountId) &
                t.providerThreadId.equals(providerThreadId),
          )
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    final participants = await _participantsFor(<String>[row.id]);
    return MessageMapper.threadToEntity(row, participants[row.id] ?? const []);
  }

  @override
  Future<void> replaceParticipants(
    String threadId,
    List<ThreadParticipant> participants,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(_db.conversationParticipants)
            ..where((t) => t.conversationId.equals(threadId)))
          .go();
      final seen = <String>{};
      for (final participant in participants) {
        final address = participant.address.trim().toLowerCase();
        if (address.isEmpty || !seen.add(address)) continue;
        await _db.into(_db.conversationParticipants).insert(
              ConversationParticipantsCompanion.insert(
                id: '${threadId}_$address',
                conversationId: threadId,
                email: address,
                contactId: Value(participant.contactId),
                isOwnAddress: Value(participant.isOwnAddress),
              ),
            );
      }
    });
  }

  @override
  Future<MessageThread> saveThread(MessageThread thread) async {
    // Upsert, never REPLACE: REPLACE deletes and re-inserts the row, which would
    // trip the foreign keys of `messages` and `conversation_participants`.
    await _db.into(_db.conversations).insertOnConflictUpdate(
          MessageMapper.threadToCompanion(thread),
        );
    return (await getThread(thread.id)) ?? thread;
  }

  @override
  Future<Message> upsertMessage(Message message) async {
    return _db.transaction(() async {
      var existing = await _findExisting(message);
      if (existing != null) {
        final id = existing.id;
        final updated = message.copyWith(isRead: existing.isRead || message.isRead);
        await (_db.update(_db.messages)..where((t) => t.id.equals(id))).write(
          _companionWithId(updated, id),
        );
        final stored = await getMessage(id);
        if (stored == null) {
          throw StateError('Message $id vanished during update');
        }
        await _refreshThreadCounters(stored.threadId);
        return stored;
      }

      await _db.into(_db.messages).insert(MessageMapper.toCompanion(message));
      await _refreshThreadCounters(message.threadId);
      return (await getMessage(message.id)) ?? message;
    });
  }

  /// Finds a stored copy of [message] by provider id, then by RFC Message-ID.
  Future<MessageRow?> _findExisting(Message message) async {
    if (message.providerId != null) {
      final byProvider = await (_db.select(_db.messages)
            ..where(
              (t) => t.accountId.equals(message.accountId) &
                  t.providerMessageId.equals(message.providerId!),
            )
            ..limit(1))
          .getSingleOrNull();
      if (byProvider != null) return byProvider;
    }
    if (message.messageIdHeader != null) {
      return (_db.select(_db.messages)
            ..where((t) => t.messageIdHeader.equals(message.messageIdHeader!))
            ..limit(1))
          .getSingleOrNull();
    }
    return null;
  }

  @override
  Future<void> setRead(String messageId, {required bool read}) async {
    await _db.transaction(() async {
      final message = await getMessage(messageId);
      if (message == null) return;
      await (_db.update(_db.messages)..where((t) => t.id.equals(messageId))).write(
        MessagesCompanion(isRead: Value(read)),
      );
      await _refreshThreadCounters(message.threadId);
    });
  }

  @override
  Future<void> setThreadPinned(String threadId, {required bool pinned}) async {
    await _setThreadFlag(
      threadId,
      ConversationsCompanion(isPinned: Value(pinned)),
    );
  }

  @override
  Future<void> setThreadArchived(String threadId, {required bool archived}) async {
    await _setThreadFlag(
      threadId,
      ConversationsCompanion(isArchived: Value(archived)),
    );
  }

  @override
  Future<void> setThreadMuted(String threadId, {required bool muted}) async {
    await _setThreadFlag(
      threadId,
      ConversationsCompanion(isMuted: Value(muted)),
    );
  }

  @override
  Future<void> hideThread(String threadId) async {
    await _setThreadFlag(threadId, const ConversationsCompanion(isHidden: Value(true)));
  }

  @override
  Stream<int> watchUnreadCount() {
    final query = _db.customSelect(
      'SELECT COALESCE(SUM(unread_count), 0) AS total FROM conversations '
      'WHERE is_hidden = 0',
      readsFrom: {_db.conversations},
    );
    return query.watchSingle().map(
          (row) => row.read<int>('total'),
        );
  }

  Future<Map<String, List<ParticipantRow>>> _participantsFor(
    List<String> threadIds,
  ) async {
    if (threadIds.isEmpty) return const {};
    final rows = await (_db.select(_db.conversationParticipants)
          ..where((t) => t.conversationId.isIn(threadIds)))
        .get();
    final grouped = <String, List<ParticipantRow>>{};
    for (final row in rows) {
      (grouped[row.conversationId] ??= <ParticipantRow>[]).add(row);
    }
    return grouped;
  }

  Future<void> _setThreadFlag(String threadId, ConversationsCompanion patch) async {
    await (_db.update(_db.conversations)..where((t) => t.id.equals(threadId)))
        .write(patch);
  }

  /// Recomputes unread count, preview and `updated_at` for a thread.
  Future<void> _refreshThreadCounters(String threadId) async {
    final messages = await getMessages(threadId);
    if (messages.isEmpty) return;
    final unread = messages
        .where((m) => !m.isRead && !m.isOutgoing && !m.isDraft)
        .length;
    final last = messages.last;
    await (_db.update(_db.conversations)..where((t) => t.id.equals(threadId))).write(
      ConversationsCompanion(
        unreadCount: Value(unread),
        updatedAt: Value(last.sentAt),
        lastMessagePreview: Value(last.preview),
      ),
    );
  }

  MessagesCompanion _companionWithId(Message message, String id) {
    final base = MessageMapper.toCompanion(message);
    return base.copyWith(
      id: Value(id),
      conversationId: Value(message.threadId),
      accountId: Value(message.accountId),
    );
  }
}
