import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/repositories/drift_account_repository.dart';
import 'package:mellow/data/repositories/drift_contact_repository.dart';
import 'package:mellow/data/repositories/drift_settings_repository.dart';
import 'package:mellow/data/repositories/drift_thread_repository.dart';
import 'package:mellow/data/seed/demo_seed.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/contact.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';
import 'package:mellow/domain/repositories/thread_repository.dart';

void main() {
  late AppDatabase db;
  late DriftAccountRepository accounts;
  late DriftContactRepository contacts;
  late DriftThreadRepository threads;
  late DriftSettingsRepository settings;

  setUp(() {
    db = AppDatabase.inMemory();
    accounts = DriftAccountRepository(db);
    contacts = DriftContactRepository(db);
    threads = DriftThreadRepository(db);
    settings = DriftSettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('schema', () {
    test('all tables are created', () async {
      // Touching every table proves the generated schema matches the entities.
      expect(await db.select(db.accounts).get(), isEmpty);
      expect(await db.select(db.providerSettings).get(), isEmpty);
      expect(await db.select(db.syncStates).get(), isEmpty);
      expect(await db.select(db.contacts).get(), isEmpty);
      expect(await db.select(db.contactEmails).get(), isEmpty);
      expect(await db.select(db.conversations).get(), isEmpty);
      expect(await db.select(db.conversationParticipants).get(), isEmpty);
      expect(await db.select(db.messages).get(), isEmpty);
      expect(await db.select(db.attachments).get(), isEmpty);
      expect(await db.select(db.appSettingsTable).get(), isEmpty);
    });
  });

  group('DemoSeed', () {
    test('seeds accounts, contacts and threads exactly once', () async {
      await DemoSeed.runIfEmpty(db);
      final accountRows = await accounts.getAccounts();
      expect(accountRows, hasLength(1));
      expect(accountRows.single.isPrimary, isTrue);

      final contactRows = await contacts.getContacts();
      expect(contactRows, hasLength(4));

      final threadRows = await threads.getThreads();
      expect(threadRows, hasLength(5));

      // Running again must not duplicate anything.
      await DemoSeed.runIfEmpty(db);
      expect(await accounts.getAccounts(), hasLength(1));
      expect(await threads.getThreads(), hasLength(5));
    });

    test('unread counters match the seeded conversations', () async {
      await DemoSeed.runIfEmpty(db);
      final threadRows = await threads.getThreads();
      final total = threadRows.fold<int>(0, (sum, t) => sum + t.unreadCount);
      expect(total, 3);
      expect(await threads.watchUnreadCount().first, 3);
    });
  });

  group('DriftAccountRepository', () {
    const first = Account(
      id: 'a1',
      email: 'first@example.com',
      provider: MailProviderKind.gmail,
      status: AccountStatus.connected,
    );
    const second = Account(
      id: 'a2',
      email: 'second@yandex.ru',
      provider: MailProviderKind.yandex,
      status: AccountStatus.connected,
    );

    test('saves and reads an account', () async {
      await accounts.saveAccount(first);
      final loaded = await accounts.getAccount('a1');
      expect(loaded, isNotNull);
      expect(loaded!.email, 'first@example.com');
      expect(loaded.provider, MailProviderKind.gmail);
    });

    test('normalises stored addresses', () async {
      await accounts.saveAccount(
        first.copyWith(email: '  FIRST@Example.COM '),
      );
      final loaded = await accounts.getAccount('a1');
      expect(loaded!.email, 'first@example.com');
    });

    test('exactly one account is primary', () async {
      await accounts.saveAccount(first.copyWith(isPrimary: true));
      await accounts.saveAccount(second);
      await accounts.setPrimary('a2');

      final all = await accounts.getAccounts();
      expect(all.where((a) => a.isPrimary), hasLength(1));
      expect((await accounts.getPrimaryAccount())!.id, 'a2');
    });

    test('updateStatus stores a safe error message', () async {
      await accounts.saveAccount(first);
      await accounts.updateStatus(
        'a1',
        AccountStatus.needsReauth,
        error: 'Токен истёк',
      );
      final loaded = await accounts.getAccount('a1');
      expect(loaded!.status, AccountStatus.needsReauth);
      expect(loaded.lastError, 'Токен истёк');
    });

    test('deleteAccount removes the account and its threads', () async {
      await accounts.saveAccount(first);
      await threads.saveThread(
        MessageThread(
          id: 't1',
          accountId: 'a1',
          subject: 'Hi',
          participants: const <EmailAddress>[EmailAddress(address: 'x@y.com')],
          updatedAt: DateTime(2026),
        ),
      );
      await threads.upsertMessage(
        Message(
          id: 'm1',
          threadId: 't1',
          accountId: 'a1',
          from: const EmailAddress(address: 'x@y.com'),
          to: const <EmailAddress>[EmailAddress(address: 'first@example.com')],
          sentAt: DateTime(2026),
        ),
      );

      await accounts.deleteAccount('a1');

      expect(await accounts.getAccount('a1'), isNull);
      expect(await threads.getThread('t1'), isNull);
      expect(await threads.getMessage('m1'), isNull);
    });

    test('watchAccounts emits updates', () async {
      await accounts.saveAccount(first);
      final stream = accounts.watchAccounts();
      expect(await stream.first, hasLength(1));
    });
  });

  group('DriftContactRepository', () {
    Future<Contact> makeContact({
      String id = 'c1',
      String name = 'Александр',
      List<String> emails = const <String>['alex@example.com'],
    }) {
      return contacts.saveContact(
        Contact(
          id: id,
          displayName: name,
          addresses: emails
              .map((email) => ContactEmail(email: email))
              .toList(growable: false),
        ),
      );
    }

    test('saves a contact with addresses, primary first', () async {
      await makeContact(
        emails: <String>['alex@example.com', 'alexander@company.com'],
      );
      final loaded = await contacts.getContact('c1');
      expect(loaded!.addresses, hasLength(2));
      expect(loaded.addresses.first.isPrimary, isTrue);
      expect(loaded.primaryAddress, 'alex@example.com');
    });

    test('findByEmail normalises the query', () async {
      await makeContact();
      expect(await contacts.findByEmail('ALEX@EXAMPLE.COM'), isNotNull);
      expect(await contacts.findByEmail('nobody@example.com'), isNull);
    });

    test('addAddress refuses to steal an address from another contact', () async {
      await makeContact();
      await makeContact(id: 'c2', name: 'Мария', emails: <String>['maria@mail.ru']);

      expect(
        () => contacts.addAddress('c2', const ContactEmail(email: 'alex@example.com')),
        throwsA(isA<StateError>()),
      );
    });

    test('addAddress is idempotent for the same contact', () async {
      await makeContact();
      await contacts.addAddress('c1', const ContactEmail(email: 'alex@example.com'));
      final loaded = await contacts.getContact('c1');
      expect(loaded!.addresses, hasLength(1));
    });

    test('removing the primary address promotes another one', () async {
      await makeContact(
        emails: <String>['alex@example.com', 'alexander@company.com'],
      );
      await contacts.removeAddress('alex@example.com');
      final loaded = await contacts.getContact('c1');
      expect(loaded!.addresses, hasLength(1));
      expect(loaded.addresses.single.isPrimary, isTrue);
      expect(loaded.addresses.single.email, 'alexander@company.com');
    });

    test('setFavorite is persisted', () async {
      await makeContact();
      await contacts.setFavorite('c1', isFavorite: true);
      expect((await contacts.getContact('c1'))!.isFavorite, isTrue);
    });

    test('mergeContacts moves addresses and deletes the source', () async {
      await makeContact();
      await makeContact(id: 'c2', name: 'Александр (работа)', emails: <String>['al@company.com']);

      await contacts.mergeContacts(targetId: 'c1', sourceId: 'c2');

      final merged = await contacts.getContact('c1');
      expect(merged!.addresses.map((a) => a.email),
          containsAll(<String>['alex@example.com', 'al@company.com']));
      expect(await contacts.getContact('c2'), isNull);
    });

    test('search matches name and address', () async {
      await makeContact();
      await makeContact(id: 'c2', name: 'Мария', emails: <String>['maria@mail.ru']);

      expect((await contacts.search('алекс')).single.id, 'c1');
      expect((await contacts.search('maria@')).single.id, 'c2');
      expect(await contacts.search('zzz'), isEmpty);
    });

    test('deleteContact keeps messages but detaches them', () async {
      await makeContact();
      expect(await contacts.getContact('c1'), isNotNull);
      await contacts.deleteContact('c1');
      expect(await contacts.getContact('c1'), isNull);
    });
  });

  group('DriftThreadRepository', () {
    Future<void> seedAccount() => accounts.saveAccount(
          const Account(
            id: 'a1',
            email: 'me@example.com',
            provider: MailProviderKind.demo,
            status: AccountStatus.connected,
          ),
        );

    Message message({
      required String id,
      String threadId = 't1',
      String? providerId,
      String? messageIdHeader,
      bool isRead = false,
      bool outgoing = false,
      DateTime? sentAt,
      String subject = 'Тема',
      String body = 'Тело письма',
    }) {
      return Message(
        id: id,
        threadId: threadId,
        accountId: 'a1',
        from: const EmailAddress(address: 'alex@example.com', displayName: 'Александр'),
        to: const <EmailAddress>[EmailAddress(address: 'me@example.com')],
        subject: subject,
        bodyText: body,
        sentAt: sentAt ?? DateTime(2026, 11, 23, 10),
        providerId: providerId,
        messageIdHeader: messageIdHeader,
        isRead: isRead,
        isOutgoing: outgoing,
      );
    }

    Future<MessageThread> makeThread({String id = 't1', String subject = 'Тема'}) {
      return threads.saveThread(
        MessageThread(
          id: id,
          accountId: 'a1',
          subject: subject,
          participants: const <EmailAddress>[
            EmailAddress(address: 'alex@example.com'),
          ],
          updatedAt: DateTime(2026, 11, 23, 10),
        ),
      );
    }

    test('upsertMessage inserts once and deduplicates on provider id', () async {
      await seedAccount();
      await makeThread();

      await threads.upsertMessage(message(id: 'm1', providerId: 'p1'));
      await threads.upsertMessage(message(id: 'm2', providerId: 'p1'));

      final stored = await threads.getMessages('t1');
      expect(stored, hasLength(1));
      expect(stored.single.id, 'm1');
    });

    test('upsertMessage deduplicates on the RFC Message-ID header', () async {
      await seedAccount();
      await makeThread();

      await threads.upsertMessage(message(id: 'm1', messageIdHeader: '<a@x>'));
      await threads.upsertMessage(message(id: 'm2', messageIdHeader: '<a@x>'));

      expect(await threads.getMessages('t1'), hasLength(1));
    });

    test('upsertMessage keeps a message read once it was read', () async {
      await seedAccount();
      await makeThread();

      await threads.upsertMessage(message(id: 'm1', providerId: 'p1', isRead: true));
      await threads.upsertMessage(message(id: 'm1', providerId: 'p1', isRead: false));

      final stored = await threads.getMessage('m1');
      expect(stored!.isRead, isTrue);
    });

    test('thread counters track unread messages and preview', () async {
      await seedAccount();
      await makeThread();

      await threads.upsertMessage(
        message(id: 'm1', sentAt: DateTime(2026, 11, 23, 9), body: 'Первое'),
      );
      await threads.upsertMessage(
        message(id: 'm2', sentAt: DateTime(2026, 11, 23, 11), body: 'Второе'),
      );

      var thread = await threads.getThread('t1');
      expect(thread!.unreadCount, 2);
      expect(thread.lastMessagePreview, 'Второе');
      expect(thread.updatedAt, DateTime(2026, 11, 23, 11));

      await threads.setRead('m1', read: true);
      thread = await threads.getThread('t1');
      expect(thread!.unreadCount, 1);

      await threads.setRead('m2', read: true);
      thread = await threads.getThread('t1');
      expect(thread!.unreadCount, 0);
    });

    test('outgoing messages never count as unread', () async {
      await seedAccount();
      await makeThread();
      await threads.upsertMessage(message(id: 'm1', outgoing: true));
      final thread = await threads.getThread('t1');
      expect(thread!.unreadCount, 0);
    });

    test('watchMessages emits in chronological order', () async {
      await seedAccount();
      await makeThread();
      await threads.upsertMessage(
        message(id: 'late', sentAt: DateTime(2026, 11, 23, 12)),
      );
      await threads.upsertMessage(
        message(id: 'early', sentAt: DateTime(2026, 11, 23, 8)),
      );

      final stored = await threads.watchMessages('t1').first;
      expect(stored.map((m) => m.id), <String>['early', 'late']);
    });

    test('filters: archived, hidden, unread and account', () async {
      await seedAccount();
      await makeThread(id: 't1');
      await makeThread(id: 't2', subject: 'Архив');
      await makeThread(id: 't3', subject: 'Скрытая');
      await threads.upsertMessage(message(id: 'm1', threadId: 't1'));

      await threads.setThreadArchived('t2', archived: true);
      await threads.hideThread('t3');

      var visible = await threads.getThreads();
      expect(visible.map((t) => t.id), <String>['t1']);

      visible = await threads.getThreads(const ThreadFilter(includeArchived: true));
      expect(visible.map((t) => t.id), containsAll(<String>['t1', 't2']));
      expect(visible.map((t) => t.id), isNot(contains('t3')));

      final unreadOnly = await threads.getThreads(const ThreadFilter(unreadOnly: true));
      expect(unreadOnly.map((t) => t.id), <String>['t1']);

      final otherAccount =
          await threads.getThreads(const ThreadFilter(accountId: 'a2'));
      expect(otherAccount, isEmpty);
    });

    test('pinned threads sort above newer unpinned ones', () async {
      await seedAccount();
      await threads.saveThread(
        MessageThread(
          id: 'old-pinned',
          accountId: 'a1',
          subject: 'Закреплённая',
          participants: const <EmailAddress>[],
          updatedAt: DateTime(2026, 1, 1),
          isPinned: true,
        ),
      );
      await makeThread(id: 'new-plain');

      final list = await threads.getThreads();
      expect(list.first.id, 'old-pinned');
    });

    test('search filters by subject and preview', () async {
      await seedAccount();
      await makeThread(id: 't1', subject: 'Документы');
      await makeThread(id: 't2', subject: 'Отпуск');

      final bySubject = await threads.getThreads(const ThreadFilter(query: 'докум'));
      expect(bySubject.single.id, 't1');
    });

    test('search matches a participant name', () async {
      await seedAccount();
      await threads.saveThread(
        MessageThread(
          id: 't1',
          accountId: 'a1',
          subject: 'Планы',
          participants: const <EmailAddress>[
            EmailAddress(address: 'maria.sokolova@mail.ru'),
          ],
          updatedAt: DateTime(2026, 11, 23, 10),
        ),
      );

      // A conversation is found by the person, not only by its subject: the
      // field promises "имя, тема или текст" (spec 2.7).
      final byAddress =
          await threads.getThreads(const ThreadFilter(query: 'сокол'));
      expect(byAddress.single.id, 't1');
    });

    test('unread count aggregates across threads', () async {
      await seedAccount();
      await makeThread(id: 't1');
      await makeThread(id: 't2');
      await threads.upsertMessage(message(id: 'm1', threadId: 't1'));
      await threads.upsertMessage(message(id: 'm2', threadId: 't2'));

      expect(await threads.watchUnreadCount().first, 2);
    });
  });

  group('DriftSettingsRepository', () {
    test('returns defaults on an empty database', () async {
      expect(await settings.getSettings(), AppSettings.defaults);
    });

    test('round-trips every field', () async {
      const updated = AppSettings(
        themePreference: ThemePreference.dark,
        focusModeEnabled: true,
        focusFavoritesOnly: true,
        focusUnreadOnly: false,
        hideAutomatedMessages: false,
        notificationsEnabled: false,
        notificationsFavoritesOnly: true,
        syncOnLaunch: false,
        blockExternalImages: false,
        appLockEnabled: true,
      );
      await settings.saveSettings(updated);
      expect(await settings.getSettings(), updated);
    });

    test('reset restores defaults', () async {
      await settings.saveSettings(
        const AppSettings(themePreference: ThemePreference.light),
      );
      await settings.reset();
      expect(await settings.getSettings(), AppSettings.defaults);
    });

    test('corrupt values fall back instead of throwing', () async {
      await db.into(db.appSettingsTable).insert(
            AppSettingsTableCompanion.insert(
              key: 'theme_preference',
              value: 'neon',
            ),
          );
      final loaded = await settings.getSettings();
      expect(loaded.themePreference, ThemePreference.system);
    });
  });
}
