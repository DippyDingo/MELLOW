import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/contact.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:mellow/domain/repositories/contact_repository.dart';
import 'package:mellow/domain/repositories/thread_repository.dart';
import 'package:mellow/providers/contracts/incremental_mail_provider.dart';
import 'package:mellow/providers/contracts/mail_provider.dart';
import 'package:mellow/services/sync/conversation_router.dart';
import 'package:mellow/services/sync/sync_state_store.dart';
import 'package:uuid/uuid.dart';

/// What one sync run did. Rendered on the sync screen and asserted in tests.
class SyncResult {
  const SyncResult({
    required this.fetched,
    required this.created,
    required this.updated,
    required this.threads,
    this.cursor,
    this.wasFullSync = false,
    this.cursorWasStale = false,
  });

  final int fetched;
  final int created;
  final int updated;
  final int threads;
  final String? cursor;

  /// True when a reconciliation pass ran (first sync or forced refresh).
  final bool wasFullSync;

  /// True when the stored cursor was rejected by the provider.
  final bool cursorWasStale;

  int get changed => created + updated;

  @override
  String toString() =>
      'SyncResult(fetched: $fetched, new: $created, updated: $updated, '
      'threads: $threads, full: $wasFullSync, staleCursor: $cursorWasStale)';
}

/// Synchronises one mailbox into the local database (spec 3.5).
///
/// Provider-agnostic: works with any [MailProvider] and uses cursors when the
/// adapter implements [IncrementalMailProvider]. No Flutter imports, so it can
/// later run inside a background isolate unchanged.
///
/// Order of operations for every message:
/// 1. resolve contact of the sender (by address, never by name);
/// 2. route to a conversation (provider thread → References → new);
/// 3. upsert the message (deduplication lives in the repository);
/// 4. refresh participants and denormalised counters.
class MailSyncService {
  MailSyncService({
    required this.threads,
    required this.contacts,
    required this.syncState,
    required this.accountId,
    required this.ownAddress,
    Uuid? uuid,
  })  : _uuid = uuid ?? const Uuid(),
        _router = ConversationRouter(accountId: accountId, uuid: uuid);

  final ThreadRepository threads;
  final ContactRepository contacts;
  final SyncStateStore syncState;
  final String accountId;

  /// The address of the mailbox being synced, so own messages are recognised.
  final String ownAddress;

  final Uuid _uuid;
  final ConversationRouter _router;

  /// Runs one sync pass.
  ///
  /// [fullSync] ignores the stored cursor. [onProgress] receives short,
  /// user-safe stage descriptions for the sync screen.
  Future<SyncResult> sync({
    required Account account,
    required MailProvider provider,
    bool fullSync = false,
    int pageSize = 25,
    int maxPages = 4,
    void Function(String stage)? onProgress,
  }) async {
    final state = await syncState.read(accountId);
    final incremental = provider is IncrementalMailProvider ? provider : null;
    final storedCursor = state?.cursor;
    final canUseCursor = incremental != null &&
        !fullSync &&
        storedCursor != null &&
        storedCursor.isNotEmpty;

    try {
      var result = canUseCursor
          ? await _incrementalSync(
              provider: provider,
              incremental: incremental,
              cursor: storedCursor,
              onProgress: onProgress,
            )
          : await _fullSync(
              provider: provider,
              pageSize: pageSize,
              maxPages: maxPages,
              onProgress: onProgress,
            );

      // Fall back to a full pass when the provider dropped our cursor window.
      if (result.cursorWasStale) {
        onProgress?.call('Курсор устарел, полная сверка');
        result = await _fullSync(
          provider: provider,
          pageSize: pageSize,
          maxPages: maxPages,
          onProgress: onProgress,
        );
      }

      onProgress?.call('Сохранение состояния');
      final cursor = incremental == null ? null : await incremental.currentCursor();
      await syncState.saveCursor(
        accountId: accountId,
        cursor: cursor ?? result.cursor ?? storedCursor,
        fullSync: result.wasFullSync,
      );
      await syncState.markAccountSynced(accountId, DateTime.now());
      return result;
    } on AccountAuthException catch (error) {
      // Re-auth is a user action, not a retry.
      await syncState.markAccountFailed(
        accountId,
        AccountStatus.needsReauth,
        error.message,
      );
      await syncState.recordFailure(accountId, error.message);
      rethrow;
    } on AppException catch (error) {
      await syncState.markAccountFailed(
        accountId,
        AccountStatus.error,
        error.message,
      );
      await syncState.recordFailure(accountId, error.message);
      rethrow;
    }
  }

  /// Incremental path: the provider tells us which ids changed.
  Future<SyncResult> _incrementalSync({
    required MailProvider provider,
    required IncrementalMailProvider incremental,
    required String cursor,
    void Function(String stage)? onProgress,
  }) async {
    onProgress?.call('Получение изменений');
    final changedIds = await incremental.changedMessageIds(cursor);
    if (changedIds == null) {
      // Signal the caller to reconcile; nothing was written.
      return const SyncResult(
        fetched: 0,
        created: 0,
        updated: 0,
        threads: 0,
        cursorWasStale: true,
      );
    }

    var created = 0;
    var updated = 0;
    var fetched = 0;
    final touchedThreads = <String>{};

    for (final providerId in changedIds) {
      // History reports deleted and moved messages too; `null` means "nothing
      // to store", not an error, so it is skipped quietly.
      final message = await provider.getMessage(providerId);
      if (message == null) continue;
      fetched++;
      final outcome = await _persist(message);
      if (outcome.isNew) {
        created++;
      } else {
        updated++;
      }
      touchedThreads.add(outcome.threadId);
      onProgress?.call('Обработано писем: ${created + updated}');
    }

    return SyncResult(
      // Not `changedIds.length`: ids that no longer resolve are not messages.
      fetched: fetched,
      created: created,
      updated: updated,
      threads: touchedThreads.length,
    );
  }

  /// Reconciliation path: walk the newest pages, stop on an empty page.
  Future<SyncResult> _fullSync({
    required MailProvider provider,
    required int pageSize,
    required int maxPages,
    void Function(String stage)? onProgress,
  }) async {
    var fetched = 0;
    var created = 0;
    var updated = 0;
    final touchedThreads = <String>{};

    String? cursor;
    var page = 0;

    while (page < maxPages) {
      final result = await provider.fetchMessages(cursor: cursor, limit: pageSize);
      if (result.messages.isEmpty) break;

      for (final message in result.messages) {
        fetched++;
        final outcome = await _persist(message);
        if (outcome.isNew) {
          created++;
        } else {
          updated++;
        }
        touchedThreads.add(outcome.threadId);
      }

      page++;
      cursor = result.nextCursor;
      onProgress?.call('Загружено писем: $fetched');
      if (cursor == null || !result.hasMore) break;
    }

    return SyncResult(
      fetched: fetched,
      created: created,
      updated: updated,
      threads: touchedThreads.length,
      cursor: cursor,
      wasFullSync: true,
    );
  }

  /// Persists one message and returns what happened to it.
  Future<_PersistOutcome> _persist(Message message) async {
    final own = normalizeEmail(ownAddress);
    final sender = normalizeEmail(message.from.address);
    final isOwnSender = sender == own;

    // 1. Contact of the counterpart (skipped for messages we sent ourselves).
    Contact? contact;
    if (!isOwnSender && sender.isNotEmpty) {
      contact = await _ensureContact(sender, message.from.displayName);
    }

    // 2. Conversation: provider thread id -> References chain -> new thread.
    final providerThreadId = message.threadId.isEmpty ? null : message.threadId;
    final knownThread = providerThreadId == null
        ? null
        : await threads.findByProviderThreadId(accountId, providerThreadId);

    // Ancestor lookups are synchronous inside `resolve`, so resolve them here.
    final ancestors = <String>[
      if (message.inReplyTo != null) message.inReplyTo!,
      ...message.references.reversed,
    ];
    final ancestorThreads = <String, String>{};
    for (final ancestor in ancestors) {
      final stored = await threads.findByMessageIdHeader(ancestor);
      if (stored != null && !ancestorThreads.containsKey(ancestor)) {
        ancestorThreads[ancestor] = stored.threadId;
      }
    }

    final conversationId = _router.resolve(
      message: message,
      providerThreadId: providerThreadId,
      knownConversationOfProviderThread: knownThread?.id,
      conversationOfMessage: (header) => ancestorThreads[header],
    );

    final existingThread = await threads.getThread(conversationId);
    if (existingThread == null) {
      final created = _router.newThread(
        message: message,
        conversationId: conversationId,
        providerThreadId: providerThreadId,
        contactId: null,
      );
      // `conversations.contact_id` means "this thread is a conversation with
      // exactly one person". It is set only when a single counterpart is known;
      // group threads stay unlinked instead of pointing at a random contact.
      final counterparts = created.participants
          .map((participant) => normalizeEmail(participant.address))
          .where((address) => address.isNotEmpty && address != own)
          .toSet();
      await threads.saveThread(
        created.copyWith(
          contactId: counterparts.length == 1 ? contact?.id : null,
        ),
      );
    } else {
      await threads.saveThread(_router.touch(existingThread, message));
    }

    // 3. Message itself: the repository deduplicates on provider id and
    //    RFC Message-ID, so a repeated sync cannot create a duplicate.
    final existing = message.providerId == null
        ? null
        : await threads.findByProviderMessageId(accountId, message.providerId!);
    final stored = await threads.upsertMessage(
      message.copyWith(threadId: conversationId),
    );

    // 4. Participants reflect everyone seen so far in this conversation.
    final thread = await threads.getThread(conversationId);
    if (thread != null) {
      await threads.replaceParticipants(
        conversationId,
        await _participantsOf(thread, stored, contact),
      );
    }

    return _PersistOutcome(isNew: existing == null, threadId: conversationId);
  }

  /// Builds the participant rows of a thread.
  ///
  /// Every non-own address is linked to its contact **by address**, never by
  /// position: a group thread has several people, and pointing all of them at
  /// the sender's contact would be silent data corruption.
  Future<List<ThreadParticipant>> _participantsOf(
    MessageThread thread,
    Message message,
    Contact? senderContact,
  ) async {
    final result = <ThreadParticipant>[];
    final seen = <String>{};
    final own = normalizeEmail(ownAddress);
    final sender = normalizeEmail(message.from.address);

    final addresses = <EmailAddress>[
      // Participants found in earlier messages are kept: the thread is the
      // source of truth, and a later message may only list a subset of people.
      ...thread.participants,
      message.from,
      ...message.to,
      ...message.cc,
    ];

    for (final address in addresses) {
      final normalized = normalizeEmail(address.address);
      if (normalized.isEmpty || !seen.add(normalized)) continue;

      final isOwn = normalized == own;
      String? contactId;
      if (!isOwn) {
        final contact = await _findContact(normalized);
        contactId = contact?.id ??
            (normalized == sender ? senderContact?.id : null);
      }

      result.add(
        ThreadParticipant(
          address: normalized,
          contactId: contactId,
          isOwnAddress: isOwn,
        ),
      );
    }

    return result;
  }

  /// Looks up an existing contact without creating one.
  ///
  /// Recipients that were never seen as a sender stay unlinked until they
  /// actually write; the UI shows the raw address until then.
  Future<Contact?> _findContact(String normalized) async {
    if (normalized.isEmpty) return null;
    return contacts.findByEmail(normalized);
  }

  /// Finds or creates a contact by address.
  ///
  /// The name comes from the `From` header when present; the address heuristic
  /// is a display fallback only and never used for matching.
  Future<Contact?> _ensureContact(String address, String? displayName) async {
    final normalized = normalizeEmail(address);
    if (normalized.isEmpty) return null;

    final existing = await contacts.findByEmail(normalized);
    if (existing != null) return existing;

    final name = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : nameFromAddress(normalized);

    return contacts.saveContact(
      Contact(
        id: _uuid.v4(),
        displayName: name,
        addresses: <ContactEmail>[
          ContactEmail(email: normalized, displayName: displayName),
        ],
      ),
    );
  }
}

class _PersistOutcome {
  const _PersistOutcome({required this.isNew, required this.threadId});

  final bool isNew;
  final String threadId;
}
