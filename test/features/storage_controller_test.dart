import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/repositories/drift_account_repository.dart';
import 'package:mellow/data/repositories/drift_contact_repository.dart';
import 'package:mellow/data/repositories/drift_thread_repository.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/contact.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/features/settings/application/storage_controller.dart';

void main() {
  late AppDatabase db;
  late DriftThreadRepository threads;
  late DriftAccountRepository accounts;
  late DriftContactRepository contacts;
  late ProviderContainer container;

  const account = Account(
    id: 'acc-1',
    email: 'me@example.com',
    provider: MailProviderKind.gmail,
    status: AccountStatus.connected,
  );

  MessageThread thread(String id, String accountId) => MessageThread(
        id: id,
        accountId: accountId,
        subject: 'Тема $id',
        participants: const <EmailAddress>[EmailAddress(address: 'a@example.com')],
        updatedAt: DateTime(2026, 11, 23),
      );

  Message message(String id, String threadId, String accountId) => Message(
        id: id,
        threadId: threadId,
        accountId: accountId,
        from: const EmailAddress(address: 'a@example.com'),
        to: const <EmailAddress>[EmailAddress(address: 'me@example.com')],
        sentAt: DateTime(2026, 11, 23),
        providerId: 'p-$id',
        messageIdHeader: '<$id@example.com>',
      );

  setUp(() async {
    db = AppDatabase.inMemory();
    threads = DriftThreadRepository(db);
    contacts = DriftContactRepository(db);
    accounts = DriftAccountRepository(db);
    await accounts.saveAccount(account);
    await accounts.saveAccount(
      const Account(
        id: 'acc-2',
        email: 'work@example.com',
        provider: MailProviderKind.gmail,
        status: AccountStatus.connected,
      ),
    );

    container = ProviderContainer(
      overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<StorageSummary> summary() =>
      container.read(storageControllerProvider.future);

  Future<void> seed() async {
    await threads.saveThread(thread('t1', 'acc-1'));
    await threads.saveThread(thread('t2', 'acc-1'));
    await threads.saveThread(thread('t3', 'acc-2'));
    await threads.upsertMessage(message('m1', 't1', 'acc-1'));
    await threads.upsertMessage(message('m2', 't2', 'acc-1'));
    await threads.upsertMessage(message('m3', 't3', 'acc-2'));
    await contacts.saveContact(
      const Contact(
        id: 'c1',
        displayName: 'Александр',
        addresses: <ContactEmail>[ContactEmail(email: 'a@example.com')],
      ),
    );
  }

  group('StorageSummary.formatBytes', () {
    test('renders human sizes with a Russian decimal comma', () {
      expect(StorageSummary.formatBytes(512), '512 Б');
      expect(StorageSummary.formatBytes(2048), '2 КБ');
      expect(StorageSummary.formatBytes(3 * 1024 * 1024), '3,0 МБ');
      expect(StorageSummary.formatBytes(2 * 1024 * 1024 * 1024), '2,00 ГБ');
    });

    test('an unknown size is a dash, not a zero', () {
      expect(StorageSummary.formatBytes(null), '—');
    });
  });

  test('counts threads, messages, contacts and accounts', () async {
    await seed();

    final data = await summary();
    expect(data.threads, 3);
    expect(data.messages, 3);
    expect(data.contacts, 1);
    expect(data.accounts, 2);
    expect(data.isEmpty, isFalse);
  });

  test('an empty database is reported as empty', () async {
    final data = await summary();
    expect(data.isEmpty, isTrue);
    expect(data.threads, 0);
  });

  test('clearAccount removes only that account’s mail', () async {
    await seed();

    await container
        .read(storageControllerProvider.notifier)
        .clearAccount(account);

    final data = await summary();
    expect(data.threads, 1, reason: 'the other account keeps its thread');
    expect(data.messages, 1);
    expect(data.accounts, 2, reason: 'accounts are not deleted');
    expect(data.contacts, 1, reason: 'people survive their mailbox');

    final stored = await threads.getThreads();
    expect(stored.single.id, 't3');
  });

  test('clearAccount leaves the account usable and resets its state', () async {
    await seed();
    await container
        .read(storageControllerProvider.notifier)
        .clearAccount(account);

    final stored = await accounts.getAccount('acc-1');
    expect(stored, isNotNull);
    expect(stored!.status, AccountStatus.connected);
  });

  test('clearAll empties every mailbox but keeps accounts and settings',
      () async {
    await seed();

    await container.read(storageControllerProvider.notifier).clearAll();

    final data = await summary();
    expect(data.threads, 0);
    expect(data.messages, 0);
    expect(data.accounts, 2);
    expect(await threads.getThreads(), isEmpty);
  });

  test('deleting twice is harmless', () async {
    await seed();
    final notifier = container.read(storageControllerProvider.notifier);
    await notifier.clearAll();
    await notifier.clearAll();
    expect((await summary()).threads, 0);
  });
}
