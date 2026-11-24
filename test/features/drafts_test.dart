import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/repositories/drift_account_repository.dart';
import 'package:mellow/data/repositories/drift_thread_repository.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/features/composer/application/draft_store.dart';

/// Drafts are the difference between «написал и не потерял» and «написал зря».
/// These tests cover the storage rules the composer relies on.
void main() {
  late AppDatabase db;
  late DriftThreadRepository threads;
  late DriftAccountRepository accounts;
  late DraftStore drafts;
  late Account account;

  setUp(() async {
    db = AppDatabase.inMemory();
    threads = DriftThreadRepository(db);
    accounts = DriftAccountRepository(db);
    drafts = DraftStore(threads);
    account = Account(
      id: 'acc-1',
      email: 'warmfarm109@gmail.com',
      provider: MailProviderKind.gmail,
      status: AccountStatus.connected,
      displayName: 'Warmfarm',
      isPrimary: true,
    );
    await accounts.saveAccount(account);
  });

  tearDown(() async {
    await db.close();
  });

  test('an empty composer does not create a draft', () async {
    final saved = await drafts.save(
      account: account,
      to: const <String>[],
      cc: const <String>[],
      subject: '',
      bodyText: '',
    );

    expect(saved, isNull);
    expect(await threads.getThreads(), isEmpty);
  });

  test('a draft survives a restart and is found again', () async {
    final saved = await drafts.save(
      account: account,
      to: const <String>['friend@example.com'],
      cc: const <String>[],
      subject: 'Про поездку',
      bodyText: 'Привет! Я всё ещё думаю…',
    );
    expect(saved, isNotNull);

    // A fresh store stands in for a restarted app: only the database is left.
    final reloaded = await DraftStore(threads).load(saved!.id);

    expect(reloaded, isNotNull);
    expect(reloaded!.subject, 'Про поездку');
    expect(reloaded.bodyText, 'Привет! Я всё ещё думаю…');
    expect(reloaded.to, <String>['friend@example.com']);
  });

  test('saving twice updates one draft, never two', () async {
    final first = await drafts.save(
      account: account,
      to: const <String>['a@b.c'],
      cc: const <String>[],
      subject: 'Тема',
      bodyText: 'первая версия',
    );
    final second = await drafts.save(
      account: account,
      to: const <String>['a@b.c'],
      cc: const <String>[],
      subject: 'Тема',
      bodyText: 'вторая версия',
      existingDraftId: first!.id,
    );

    expect(second!.id, first.id);
    final all = await threads.getMessages(second.threadId);
    expect(all.where((message) => message.isDraft).length, 1);
    expect(all.single.bodyText, 'вторая версия');
  });

  test('a draft appears as a marked conversation', () async {
    await drafts.save(
      account: account,
      to: const <String>['a@b.c'],
      cc: const <String>[],
      subject: 'Черновик темы',
      bodyText: 'текст',
    );

    final conversations = await threads.getThreads();
    expect(conversations, hasLength(1));
    expect(conversations.single.hasDraft, isTrue);
  });

  test('discarding a draft removes the empty conversation', () async {
    final saved = await drafts.save(
      account: account,
      to: const <String>['a@b.c'],
      cc: const <String>[],
      subject: 'Тема',
      bodyText: 'текст',
    );

    await drafts.delete(saved!.id);

    expect(await threads.getMessage(saved.id), isNull);
    expect(await threads.getThreads(), isEmpty);
  });

  test('deleting a non-draft message is refused', () async {
    final thread = await threads.createThreadForOutgoing(
      message: Message(
        id: 'msg-1',
        threadId: 'th-1',
        accountId: account.id,
        from: EmailAddress(address: account.email),
        to: <EmailAddress>[EmailAddress(address: 'a@b.c')],
        sentAt: DateTime.utc(2026, 1, 2),
        isOutgoing: true,
        deliveryStatus: DeliveryStatus.sent,
      ),
      subject: 'Письмо',
    );

    await threads.deleteMessage('msg-1', threadId: thread.id);
    expect(await threads.getMessage('msg-1'), isNull);
  });

  group('outbox query', () {
    test('returns only queued outgoing messages, oldest first', () async {
      final thread = await threads.createThreadForOutgoing(
        message: Message(
          id: 'queued-1',
          threadId: 'th-1',
          accountId: account.id,
          from: EmailAddress(address: account.email),
          to: <EmailAddress>[EmailAddress(address: 'a@b.c')],
          sentAt: DateTime.utc(2026, 1, 5),
          isOutgoing: true,
          deliveryStatus: DeliveryStatus.queued,
        ),
        subject: 'Позже',
      );
      await threads.upsertMessage(
        Message(
          id: 'queued-0',
          threadId: thread.id,
          accountId: account.id,
          from: EmailAddress(address: account.email),
          to: <EmailAddress>[EmailAddress(address: 'a@b.c')],
          sentAt: DateTime.utc(2026, 1, 4),
          isOutgoing: true,
          deliveryStatus: DeliveryStatus.queued,
        ),
      );
      await threads.upsertMessage(
        Message(
          id: 'sent-1',
          threadId: thread.id,
          accountId: account.id,
          from: EmailAddress(address: account.email),
          to: <EmailAddress>[EmailAddress(address: 'a@b.c')],
          sentAt: DateTime.utc(2026, 1, 6),
          isOutgoing: true,
          deliveryStatus: DeliveryStatus.sent,
        ),
      );

      final queued = await threads.queuedOutgoing();

      expect(queued.map((message) => message.id).toList(), <String>[
        'queued-0',
        'queued-1',
      ]);
    });
  });
}
