import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/core/config/app_config.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/repositories/drift_account_repository.dart';
import 'package:mellow/data/repositories/drift_thread_repository.dart';
import 'package:mellow/data/security/flutter_secure_token_storage.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/attachment.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/security/secure_token_storage.dart';
import 'package:mellow/features/composer/application/send_controller.dart';
import 'package:mellow/providers/contracts/incremental_mail_provider.dart';
import 'package:mellow/providers/contracts/mail_provider.dart';
import 'package:mellow/providers/provider_factory.dart';

/// Records what the controller asked the adapter to do, and can refuse.
class RecordingProvider extends BaseMailProvider
    implements IncrementalMailProvider {
  final List<OutgoingMessage> sent = <OutgoingMessage>[];
  final List<OutgoingMessage> replies = <OutgoingMessage>[];
  final List<String> replyTargets = <String>[];

  /// Set to make the next send fail, the way a real provider would.
  AppException? failure;

  @override
  String get id => 'recording';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsThreads: true,
        supportsPush: false,
        supportsSearch: true,
        supportsLabels: true,
        supportsReadReceipts: false,
        supportsAttachments: false,
      );

  @override
  Future<void> connect(Account account) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendMessage(OutgoingMessage message) async {
    if (failure != null) throw failure!;
    sent.add(message);
  }

  @override
  Future<void> replyToMessage(
    String providerMessageId,
    OutgoingMessage reply,
  ) async {
    if (failure != null) throw failure!;
    replyTargets.add(providerMessageId);
    replies.add(reply);
  }

  @override
  Future<MessagePage> fetchMessages({
    String? cursor,
    int limit = 50,
    String? folder,
  }) async =>
      const MessagePage(messages: <Message>[]);

  @override
  Future<Message?> getMessage(String providerMessageId) async => null;

  @override
  Future<void> markAsRead(String providerMessageId, {bool read = true}) async {}

  @override
  Future<void> archiveMessage(String providerMessageId) async {}

  @override
  Future<void> deleteMessage(String providerMessageId) async {}

  @override
  Future<List<int>> downloadAttachment(Attachment attachment) async => <int>[];

  @override
  Future<Attachment> uploadAttachment(String messageId, String filePath) async =>
      throw const UnsupportedException('no upload');

  @override
  Future<String?> currentCursor() async => 'cursor-1';

  @override
  Future<List<String>?> changedMessageIds(String cursor) async => null;
}

/// Hands out the recording adapter instead of the real Gmail one.
class FakeFactory implements MailProviderFactory {
  FakeFactory(this.provider);

  final RecordingProvider provider;

  @override
  AppConfig get config => throw UnimplementedError();

  @override
  SecureTokenStorage get tokenStorage => throw UnimplementedError();

  @override
  MailProvider create(Account account) => provider;

  @override
  bool canSync(MailProviderKind kind) => true;
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late RecordingProvider provider;
  late Account account;

  setUp(() async {
    db = AppDatabase.inMemory();
    account = const Account(
      id: 'acc-1',
      email: 'me@example.com',
      provider: MailProviderKind.gmail,
      status: AccountStatus.connected,
      isPrimary: true,
    );
    await DriftAccountRepository(db).saveAccount(account);

    provider = RecordingProvider();
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        mailProviderFactoryProvider.overrideWithValue(FakeFactory(provider)),
        secureTokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  OutgoingDraft draft({
    String? threadId,
    String? inReplyTo,
    String? replyToProviderMessageId,
  }) {
    return OutgoingDraft(
      accountId: account.id,
      from: account.email,
      to: const <String>['alex@example.com'],
      subject: 'Тема',
      bodyText: 'Привет',
      threadId: threadId,
      inReplyTo: inReplyTo,
      replyToProviderMessageId: replyToProviderMessageId,
    );
  }

  test('a new message is stored, sent, and marked as sent', () async {
    await container.read(sendControllerProvider.notifier).send(draft());

    final state = container.read(sendControllerProvider);
    expect(state.error, isNull);
    expect(state.sentMessageId, isNotNull);
    expect(provider.sent, hasLength(1));
    expect(provider.sent.single.bodyText, 'Привет');

    final threads = DriftThreadRepository(db);
    final storedThreads = await threads.getThreads();
    expect(storedThreads, hasLength(1), reason: 'thread created for the message');

    final messages = await threads.getMessages(storedThreads.single.id);
    expect(messages, hasLength(1));
    expect(messages.single.deliveryStatus, DeliveryStatus.sent);
    expect(messages.single.isOutgoing, isTrue);
    expect(storedThreads.single.subject, 'Тема');
  });

  test('a failed send keeps the text and marks the message failed', () async {
    provider.failure = const MailProviderException('SMTP недоступен');

    await container.read(sendControllerProvider.notifier).send(draft());

    final state = container.read(sendControllerProvider);
    expect(state.error, 'SMTP недоступен');
    expect(state.isSent, isFalse);

    final threads = DriftThreadRepository(db);
    final stored = await threads.getThreads();
    final messages = await threads.getMessages(stored.single.id);
    expect(messages, hasLength(1), reason: 'the text is never lost');
    expect(messages.single.deliveryStatus, DeliveryStatus.failed);
    expect(messages.single.bodyText, 'Привет');
  });

  test('a retry after a failure ends up as one sent message', () async {
    provider.failure = const MailProviderException('обрыв');
    await container.read(sendControllerProvider.notifier).send(draft());

    provider.failure = null;
    final failedId = container.read(sendControllerProvider);
    expect(failedId.isSent, isFalse);

    // Retry the same draft: the second attempt replaces the failed copy
    // instead of creating a second message.
    await container.read(sendControllerProvider.notifier).send(draft());

    final threads = DriftThreadRepository(db);
    final stored = await threads.getThreads();
    final messages = await threads.getMessages(stored.single.id);
    expect(messages, hasLength(1));
    expect(messages.single.deliveryStatus, DeliveryStatus.sent);
  });

  test('a reply keeps the thread and links through In-Reply-To', () async {
    final threads = DriftThreadRepository(db);
    await container.read(sendControllerProvider.notifier).send(draft());
    final threadId = (await threads.getThreads()).single.id;

    await container.read(sendControllerProvider.notifier).send(
          draft(
            threadId: threadId,
            inReplyTo: '<root@example.com>',
            replyToProviderMessageId: 'gmail-1',
          ),
        );

    expect(provider.replyTargets, <String>['gmail-1']);
    expect(provider.replies.single.inReplyTo, '<root@example.com>');

    final messages = await threads.getMessages(threadId);
    expect(messages, hasLength(2), reason: 'the reply joins the conversation');
    expect(messages.every((m) => m.deliveryStatus == DeliveryStatus.sent), isTrue);
  });

  test('an account that cannot send yet explains itself', () async {
    final imap = const Account(
      id: 'acc-imap',
      email: 'me@yandex.ru',
      provider: MailProviderKind.yandex,
      status: AccountStatus.connected,
    );
    await DriftAccountRepository(db).saveAccount(imap);

    await container.read(sendControllerProvider.notifier).send(
          const OutgoingDraft(
            accountId: 'acc-imap',
            from: 'me@yandex.ru',
            to: <String>['alex@example.com'],
            subject: 'Тема',
            bodyText: 'Привет',
          ),
        );

    final state = container.read(sendControllerProvider);
    expect(state.error, contains('спринте 06'));
    expect(provider.sent, isEmpty);
  });
}
