import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/repositories/drift_account_repository.dart';
import 'package:mellow/data/repositories/drift_contact_repository.dart';
import 'package:mellow/data/repositories/drift_thread_repository.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/attachment.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/providers/contracts/incremental_mail_provider.dart';
import 'package:mellow/providers/contracts/mail_provider.dart';
import 'package:mellow/services/sync/mail_sync_service.dart';
import 'package:mellow/services/sync/sync_state_store.dart';

/// Scriptable provider: the test decides what each call returns.
class FakeMailProvider extends BaseMailProvider implements IncrementalMailProvider {
  FakeMailProvider({this.ownAddress = 'me@example.com'});

  final String ownAddress;

  final List<Message> pages = <Message>[];

  /// Ids reported by the incremental endpoint; `null` simulates a stale cursor.
  List<String>? incrementalIds;
  int currentCursorCalls = 0;
  String? savedCursor;
  int fetchCalls = 0;
  int disconnectCalls = 0;
  AppException? failure;

  @override
  String get id => 'fake';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsThreads: true,
        supportsPush: false,
        supportsSearch: true,
        supportsLabels: false,
        supportsReadReceipts: false,
        supportsAttachments: true,
        supportsIncrementalSync: true,
      );

  @override
  Future<void> connect(Account account) async {}

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  Future<MessagePage> fetchMessages({
    String? cursor,
    int limit = 50,
    String? folder,
  }) async {
    if (failure != null) throw failure!;
    fetchCalls++;
    final from = cursor == null ? 0 : int.parse(cursor);
    final slice = pages.skip(from).take(limit).toList();
    final next = from + slice.length;
    return MessagePage(
      messages: slice,
      nextCursor: next < pages.length ? '$next' : null,
      hasMore: next < pages.length,
    );
  }

  @override
  Future<Message?> getMessage(String providerMessageId) async {
    for (final message in pages) {
      if (message.providerId == providerMessageId) return message;
    }
    return null;
  }

  @override
  Future<void> sendMessage(OutgoingMessage message) async {}

  @override
  Future<void> replyToMessage(String providerMessageId, OutgoingMessage reply) async {}

  @override
  Future<void> markAsRead(String providerMessageId, {bool read = true}) async {}

  @override
  Future<void> deleteMessage(String providerMessageId) async {}

  @override
  Future<List<int>> downloadAttachment(Attachment attachment) async => <int>[];

  @override
  Future<Attachment> uploadAttachment(String messageId, String filePath) async =>
      throw const UnsupportedException('no upload in fake');

  @override
  Future<String?> currentCursor() async {
    if (failure != null) throw failure!;
    currentCursorCalls++;
    return savedCursor ?? 'cursor-1';
  }

  @override
  Future<List<String>?> changedMessageIds(String cursor) async {
    if (failure != null) throw failure!;
    return incrementalIds;
  }
}

Message incoming({
  required String providerId,
  String messageId = '<m@example.com>',
  String from = 'alex@example.com',
  String? fromName = 'Александр Петров',
  String subject = 'Тема',
  String providerThread = 'thread-1',
  String? inReplyTo,
  List<String> references = const <String>[],
  DateTime? sentAt,
  bool read = false,
}) {
  return Message(
    id: 'local-$providerId',
    threadId: providerThread,
    accountId: 'acc-1',
    from: EmailAddress(address: from, displayName: fromName),
    to: const <EmailAddress>[EmailAddress(address: 'me@example.com')],
    subject: subject,
    bodyText: 'Тело $providerId',
    sentAt: sentAt ?? DateTime(2026, 11, 23, 10),
    providerId: providerId,
    messageIdHeader: messageId,
    inReplyTo: inReplyTo,
    references: references,
    isRead: read,
  );
}

void main() {
  late AppDatabase db;
  late DriftThreadRepository threads;
  late DriftContactRepository contacts;
  late DriftAccountRepository accounts;
  late SyncStateStore syncState;
  late FakeMailProvider provider;
  late MailSyncService service;

  const account = Account(
    id: 'acc-1',
    email: 'me@example.com',
    provider: MailProviderKind.gmail,
    status: AccountStatus.connected,
  );

  setUp(() async {
    db = AppDatabase.inMemory();
    threads = DriftThreadRepository(db);
    contacts = DriftContactRepository(db);
    accounts = DriftAccountRepository(db);
    syncState = SyncStateStore(db);
    provider = FakeMailProvider();
    service = MailSyncService(
      threads: threads,
      contacts: contacts,
      syncState: syncState,
      accountId: account.id,
      ownAddress: account.email,
    );
    await accounts.saveAccount(account);
  });

  tearDown(() async {
    await db.close();
  });

  group('first sync', () {
    test('stores messages, creates the contact and one thread', () async {
      provider.pages.addAll(<Message>[
        incoming(providerId: 'p1'),
        incoming(
          providerId: 'p2',
          messageId: '<m2@example.com>',
          subject: 'Re: Тема',
          inReplyTo: '<m@example.com>',
          sentAt: DateTime(2026, 11, 23, 11),
        ),
      ]);

      final result = await service.sync(account: account, provider: provider);

      expect(result.created, 2);
      expect(result.fetched, 2);
      expect(result.wasFullSync, isTrue);

      final stored = await threads.getThreads();
      expect(stored, hasLength(1), reason: 'both messages share a thread');
      expect(stored.single.subject, 'Тема');

      final messages = await threads.getMessages(stored.single.id);
      expect(messages, hasLength(2));
      expect(messages.map((m) => m.providerId), <String>['p1', 'p2']);
    });

    test('auto-creates the contact by address, keeping the header name',
        () async {
      provider.pages.add(incoming(providerId: 'p1'));

      await service.sync(account: account, provider: provider);

      final contact = await contacts.findByEmail('alex@example.com');
      expect(contact, isNotNull);
      expect(contact!.displayName, 'Александр Петров');
      expect(contact.addresses.single.email, 'alex@example.com');
    });

    test('never creates a contact for our own address', () async {
      provider.pages.add(
        incoming(
          providerId: 'p1',
          from: 'me@example.com',
          messageId: '<sent@example.com>',
        ),
      );

      await service.sync(account: account, provider: provider);

      expect(await contacts.findByEmail('me@example.com'), isNull);
      final stored = await threads.getThreads();
      expect(stored.single.participants
          .where((p) => p.address == 'me@example.com'), hasLength(1));
    });

    test('records the cursor and marks the account as synced', () async {
      provider.pages.add(incoming(providerId: 'p1'));

      await service.sync(account: account, provider: provider);

      final state = await syncState.read(account.id);
      expect(state, isNotNull);
      expect(state!.cursor, isNotEmpty);
      expect(state.consecutiveFailures, 0);

      final synced = await accounts.getAccount(account.id);
      expect(synced!.lastSyncAt, isNotNull);
      expect(synced.status, AccountStatus.connected);
    });

    test('separate subjects stay in separate conversations', () async {
      provider.pages.addAll(<Message>[
        incoming(providerId: 'p1', providerThread: 'thread-a', subject: 'Счёт'),
        incoming(
          providerId: 'p2',
          providerThread: 'thread-b',
          subject: 'Счёт',
          messageId: '<b@example.com>',
        ),
      ]);

      await service.sync(account: account, provider: provider);

      final stored = await threads.getThreads();
      expect(stored, hasLength(2), reason: 'same subject, different threads');
    });
  });

  group('deduplication', () {
    test('a repeated sync does not duplicate anything', () async {
      provider.pages.add(incoming(providerId: 'p1'));
      await service.sync(account: account, provider: provider);

      // Force a full pass again, as a manual "resync" would.
      final second = await service.sync(
        account: account,
        provider: provider,
        fullSync: true,
      );

      expect(second.created, 0);
      expect(second.updated, 1);

      final stored = await threads.getThreads();
      expect(stored, hasLength(1));
      expect(await threads.getMessages(stored.single.id), hasLength(1));
      expect(await contacts.getContacts(), hasLength(1));
    });

    test('a message with the same Message-ID under a new provider id is not duplicated',
        () async {
      provider.pages.add(incoming(providerId: 'p1'));
      await service.sync(account: account, provider: provider);

      provider.pages
        ..clear()
        ..add(incoming(providerId: 'p1-other-system', messageId: '<m@example.com>'));

      await service.sync(
        account: account,
        provider: provider,
        fullSync: true,
      );

      final stored = await threads.getThreads();
      expect(await threads.getMessages(stored.single.id), hasLength(1));
    });
  });

  group('threading', () {
    test('a reply links through References even without a provider thread',
        () async {
      provider.pages.add(
        incoming(providerId: 'p1', providerThread: '', messageId: '<root@example.com>'),
      );
      await service.sync(account: account, provider: provider);

      provider.pages.add(
        incoming(
          providerId: 'p2',
          providerThread: '',
          messageId: '<reply@example.com>',
          subject: 'Re: Тема',
          inReplyTo: '<root@example.com>',
          references: <String>['<root@example.com>'],
          sentAt: DateTime(2026, 11, 23, 12),
        ),
      );
      await service.sync(
        account: account,
        provider: provider,
        fullSync: true,
      );

      final stored = await threads.getThreads();
      expect(stored, hasLength(1));

      final messages = await threads.getMessages(stored.single.id);
      expect(messages, hasLength(2));
    });

    test('participants accumulate across the conversation', () async {
      provider.pages.add(incoming(providerId: 'p1'));
      await service.sync(account: account, provider: provider);

      provider.pages.add(
        incoming(
          providerId: 'p2',
          messageId: '<m2@example.com>',
          from: 'maria@mail.ru',
          fromName: 'Мария',
          inReplyTo: '<m@example.com>',
          sentAt: DateTime(2026, 11, 23, 13),
        ),
      );
      await service.sync(
        account: account,
        provider: provider,
        fullSync: true,
      );

      final stored = await threads.getThreads();
      final addresses = stored.single.participants.map((p) => p.address);
      expect(addresses, containsAll(<String>['alex@example.com', 'maria@mail.ru']));
      expect(await contacts.getContacts(), hasLength(2));
    });
  });

  group('incremental sync', () {
    test('uses the stored cursor on the second run', () async {
      provider.pages.add(incoming(providerId: 'p1'));
      await service.sync(account: account, provider: provider);
      final fetchCallsAfterFirst = provider.fetchCalls;

      provider.incrementalIds = <String>['p2'];
      provider.pages.add(
        incoming(
          providerId: 'p2',
          messageId: '<m2@example.com>',
          inReplyTo: '<m@example.com>',
          sentAt: DateTime(2026, 11, 23, 15),
        ),
      );

      final second = await service.sync(account: account, provider: provider);

      expect(second.wasFullSync, isFalse);
      expect(second.created, 1);
      expect(
        provider.fetchCalls,
        fetchCallsAfterFirst,
        reason: 'incremental path must not page through the mailbox again',
      );
    });

    test('ids that no longer resolve are skipped, not counted as fetched',
        () async {
      provider.pages.add(incoming(providerId: 'p1'));
      await service.sync(account: account, provider: provider);

      // Google reports deleted messages in history as well.
      provider.incrementalIds = <String>['deleted-id'];

      final result = await service.sync(account: account, provider: provider);

      expect(result.fetched, 0);
      expect(result.created, 0);
      expect(result.wasFullSync, isFalse);
    });

    test('falls back to a full pass when the cursor is stale', () async {
      provider.pages.add(incoming(providerId: 'p1'));
      await service.sync(account: account, provider: provider);

      provider.incrementalIds = null; // provider says "history too old"
      final result = await service.sync(account: account, provider: provider);

      expect(result.wasFullSync, isTrue);
      expect(result.cursorWasStale, isFalse, reason: 'the fallback completed');
      expect(result.fetched, 1);
      final stored = await threads.getThreads();
      expect(await threads.getMessages(stored.single.id), hasLength(1));
    });
  });

  group('failures', () {
    test('an auth error flips the account to needsReauth', () async {
      provider.failure = const AccountAuthException('Токен истёк');

      await expectLater(
        service.sync(account: account, provider: provider),
        throwsA(isA<AccountAuthException>()),
      );

      final stored = await accounts.getAccount(account.id);
      expect(stored!.status, AccountStatus.needsReauth);
      expect(stored.lastError, 'Токен истёк');

      final state = await syncState.read(account.id);
      expect(state!.consecutiveFailures, 1);
    });

    test('a provider error keeps the previous cursor intact', () async {
      provider.pages.add(incoming(providerId: 'p1'));
      await service.sync(account: account, provider: provider);
      final cursorBefore = (await syncState.read(account.id))!.cursor;

      provider.failure = const MailProviderException('Gmail недоступен', statusCode: 503);
      await expectLater(
        service.sync(account: account, provider: provider),
        throwsA(isA<MailProviderException>()),
      );

      final state = await syncState.read(account.id);
      expect(state!.cursor, cursorBefore);
      expect(state.lastError, 'Gmail недоступен');
    });
  });

  group('pagination', () {
    test('walks pages until the provider says there is no more', () async {
      provider.pages.addAll(
        List<Message>.generate(
          7,
          (index) => incoming(
            providerId: 'p$index',
            messageId: '<m$index@example.com>',
            providerThread: 'thread-$index',
            subject: 'Тема $index',
          ),
        ),
      );

      final result = await service.sync(
        account: account,
        provider: provider,
        pageSize: 3,
        maxPages: 10,
      );

      expect(result.created, 7);
      expect(provider.fetchCalls, 3);
      expect(await threads.getThreads(), hasLength(7));
    });

    test('stops at maxPages so one sync cannot run forever', () async {
      provider.pages.addAll(
        List<Message>.generate(
          20,
          (index) => incoming(
            providerId: 'p$index',
            messageId: '<m$index@example.com>',
            providerThread: 'thread-$index',
          ),
        ),
      );

      final result = await service.sync(
        account: account,
        provider: provider,
        pageSize: 5,
        maxPages: 2,
      );

      expect(result.fetched, 10);
      expect(provider.fetchCalls, 2);
    });
  });

  test('participants are stored with the own address flagged', () async {
    provider.pages.add(incoming(providerId: 'p1'));
    await service.sync(account: account, provider: provider);

    final stored = await threads.getThreads();
    final own = stored.single.participants
        .where((participant) => participant.address == 'me@example.com');
    expect(own, hasLength(1));
  });

  test('a message we sent does not create a contact for ourselves', () async {
    provider.pages.add(
      incoming(providerId: 'p1', from: 'me@example.com', messageId: '<x@example.com>'),
    );
    await service.sync(account: account, provider: provider);
    expect(await contacts.getContacts(), isEmpty);
  });
}

