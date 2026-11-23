import 'package:drift/drift.dart';
import 'package:mellow/core/utils/email_address.dart';
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
    // The search term is applied in Dart below: SQLite's `lower()` folds ASCII
    // only, so `lower(subject) LIKE '%докум%'` never matches Russian text.
    final term = filter.query?.trim().toLowerCase();

    query.orderBy([
      (t) => OrderingTerm(expression: t.isPinned, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
    ]);

    final rows = await query.get();
    if (rows.isEmpty) return const <MessageThread>[];

    final List<MessageThread> threads;
    if (filter.favoritesOnly) {
      threads = await _filterFavorites(rows);
    } else {
      final participants =
          await _participantsFor(rows.map((r) => r.id).toList());
      threads = rows
          .map((row) =>
              MessageMapper.threadToEntity(row, participants[row.id] ?? const []))
          .toList(growable: false);
    }

    if (term == null || term.isEmpty) return threads;
    return threads
        .where(
          (thread) =>
              thread.subject.toLowerCase().contains(term) ||
              thread.lastMessagePreview.toLowerCase().contains(term),
        )
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
  Future<void> deleteAccountThreads(String accountId) async {
    // One transaction: a half-deleted mailbox would break the counters and the
    // participant rows that reference the conversations.
    await _db.transaction(() async {
      final threadIds = await (_db.selectOnly(_db.conversations)
            ..addColumns(<Expression<Object>>[_db.conversations.id])
            ..where(_db.conversations.accountId.equals(accountId)))
          .map((row) => row.read<String>(_db.conversations.id)!)
          .get();

      // Children first: attachments reference messages, participants
      // reference conversations, and foreign keys are enforced.
      await (_db.delete(_db.attachments)
            ..where(
              (t) => t.messageId.isInQuery(
                _db.selectOnly(_db.messages)
                  ..addColumns(<Expression<Object>>[_db.messages.id])
                  ..where(_db.messages.accountId.equals(accountId)),
              ),
            ))
          .go();
      await (_db.delete(_db.messages)
            ..where((t) => t.accountId.equals(accountId)))
          .go();
      await (_db.delete(_db.conversationParticipants)
            ..where((t) => t.conversationId.isIn(threadIds)))
          .go();
      await (_db.delete(_db.conversations)
            ..where((t) => t.accountId.equals(accountId)))
          .go();
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
  Future<MessageThread> createThreadForOutgoing({
    required Message message,
    required String subject,
  }) async {
    final normalizedSubject = subject.trim();
    final thread = MessageThread(
      id: message.threadId,
      accountId: message.accountId,
      subject: normalizedSubject,
      participants: <EmailAddress>[
        message.from,
        ...message.to,
        ...message.cc,
      ],
      updatedAt: message.sentAt,
      lastMessagePreview: message.preview,
      // Own message: nothing unread in it.
      unreadCount: 0,
    );
    return saveThread(thread);
  }

  @override
  Future<void> updateOutgoingMessage(Message message) async {
    final row = await (_db.select(_db.messages)
          ..where((t) => t.id.equals(message.id)))
        .getSingleOrNull();
    if (row == null) {
      await _db.into(_db.messages).insert(MessageMapper.toCompanion(message));
      await _refreshThreadCounters(message.threadId);
      return;
    }
    await (_db.update(_db.messages)..where((t) => t.id.equals(message.id))).write(
      _companionWithId(message, message.id),
    );
    await _refreshThreadCounters(message.threadId);
  }

  @override
  Future<void> setDeliveryStatus(
    String messageId,
    DeliveryStatus status, {
    String? threadId,
  }) async {
    final row = await (_db.select(_db.messages)
          ..where((t) => t.id.equals(messageId)))
        .getSingleOrNull();
    if (row == null) return;

    final movesThread = threadId != null && threadId != row.conversationId;
    await (_db.update(_db.messages)..where((t) => t.id.equals(messageId))).write(
      MessagesCompanion(
        deliveryStatus: Value(status.name),
        isOutgoing: const Value(true),
        conversationId: movesThread ? Value(threadId) : const Value.absent(),
      ),
    );

    await _refreshThreadCounters(row.conversationId);
    if (movesThread) {
      await _refreshThreadCounters(threadId);
      await _dropThreadIfEmpty(row.conversationId);
    }
  }

  /// Removes a conversation that holds no messages.
  ///
  /// The composer stores an outgoing message against a placeholder thread id
  /// before the real conversation exists; once the message moves out, the
  /// placeholder must not linger in the list.
  Future<void> _dropThreadIfEmpty(String threadId) async {
    final remaining = await (_db.selectOnly(_db.messages)
          ..addColumns(<Expression<Object>>[_db.messages.id])
          ..where(_db.messages.conversationId.equals(threadId)))
        .get();
    if (remaining.isNotEmpty) return;
    await (_db.delete(_db.conversationParticipants)
          ..where((t) => t.conversationId.equals(threadId)))
        .go();
    await (_db.delete(_db.conversations)..where((t) => t.id.equals(threadId))).go();
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
