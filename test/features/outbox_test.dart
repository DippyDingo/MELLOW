import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/config/app_config.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/attachment.dart';
import 'package:mellow/domain/repositories/account_repository.dart';
import 'package:mellow/domain/repositories/thread_repository.dart';
import 'package:mellow/domain/security/secure_token_storage.dart';
import 'package:mellow/features/composer/application/outbox.dart';
import 'package:mellow/providers/contracts/mail_provider.dart';
import 'package:mellow/providers/provider_factory.dart';

/// The outbox is what makes «отправил без сети» not a failure. These tests pin
/// the two decisions that matter: a transient error keeps the message waiting,
/// a refusal stops pretending and asks the user.
void main() {
  late _FakeThreads threads;
  late _FakeAccounts accounts;
  late _FakeProvider provider;
  late DateTime now;

  Outbox buildOutbox() {
    return Outbox(
      factory: _FakeFactory(provider),
      threads: threads,
      accounts: accounts,
      clock: () => now,
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 5, 1, 12);
    threads = _FakeThreads();
    accounts = _FakeAccounts();
    provider = _FakeProvider();
  });

  test('a queued message is sent and marked sent', () async {
    threads.queued.add(_queuedMessage());

    final sent = await buildOutbox().flush();

    expect(sent, 1);
    expect(provider.sent, hasLength(1));
    expect(threads.statuses['m-1'], DeliveryStatus.sent);
  });

  test('a transient failure keeps the message queued', () async {
    threads.queued.add(_queuedMessage());
    provider.failure = const MailProviderException(
      'Gmail временно недоступен',
      statusCode: 503,
    );

    final sent = await buildOutbox().flush();

    expect(sent, 0);
    expect(threads.statuses.containsKey('m-1'), isFalse);
  });

  test('a refusal marks the message failed so the user can decide', () async {
    threads.queued.add(_queuedMessage());
    provider.failure = const MailProviderException(
      'Некорректный адрес',
      statusCode: 400,
    );

    await buildOutbox().flush();

    expect(threads.statuses['m-1'], DeliveryStatus.failed);
  });

  test('a revoked token is not retried behind the user’s back', () async {
    threads.queued.add(_queuedMessage());
    provider.failure = const AccountAuthException('Требуется повторный вход');

    await buildOutbox().flush();

    expect(threads.statuses['m-1'], DeliveryStatus.failed);
  });

  test('retries back off instead of hammering the network', () async {
    threads.queued.add(_queuedMessage());
    provider.failure = const MailProviderException('Нет связи', statusCode: 502);
    final outbox = buildOutbox();

    await outbox.flush();
    expect(provider.attempts, 1);

    // Still inside the first minute: no second attempt is made.
    await outbox.flush();
    expect(provider.attempts, 1);

    // After the backoff elapsed the message is tried again.
    now = now.add(const Duration(minutes: 2));
    await outbox.flush();
    expect(provider.attempts, 2);
  });

  test('a message whose account disappeared is not stuck forever', () async {
    threads.queued.add(_queuedMessage());
    accounts.accounts.clear();

    final sent = await buildOutbox().flush();

    expect(sent, 0);
    expect(threads.statuses['m-1'], DeliveryStatus.failed);
  });

  test('hasPending reflects the queue', () async {
    final outbox = buildOutbox();
    expect(await outbox.hasPending(), isFalse);
    threads.queued.add(_queuedMessage());
    expect(await outbox.hasPending(), isTrue);
  });
}

Message _queuedMessage() {
  return Message(
    id: 'm-1',
    threadId: 'th-1',
    accountId: 'acc-1',
    from: const EmailAddress(address: 'warmfarm109@gmail.com'),
    to: <EmailAddress>[const EmailAddress(address: 'friend@example.com')],
    subject: 'Письмо',
    bodyText: 'текст без сети',
    sentAt: DateTime.utc(2026, 5, 1, 11),
    isOutgoing: true,
    deliveryStatus: DeliveryStatus.queued,
  );
}

class _FakeFactory implements MailProviderFactory {
  _FakeFactory(this.provider);

  final MailProvider provider;

  @override
  AppConfig get config => AppConfig.empty;

  @override
  SecureTokenStorage get tokenStorage => _NoStorage();

  @override
  MailProvider create(Account account) => provider;

  @override
  bool canSync(MailProviderKind kind) => true;
}

class _NoStorage implements SecureTokenStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeThreads implements ThreadRepository {
  final List<Message> queued = <Message>[];
  final Map<String, DeliveryStatus> statuses = <String, DeliveryStatus>{};

  @override
  Future<List<Message>> queuedOutgoing() async => List<Message>.of(queued);

  @override
  Future<void> setDeliveryStatus(
    String messageId,
    DeliveryStatus status, {
    String? threadId,
  }) async {
    statuses[messageId] = status;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccounts implements AccountRepository {
  final Map<String, Account> accounts = <String, Account>{
    'acc-1': const Account(
      id: 'acc-1',
      email: 'warmfarm109@gmail.com',
      provider: MailProviderKind.gmail,
      status: AccountStatus.connected,
      isPrimary: true,
    ),
  };

  @override
  Future<Account?> getAccount(String id) async => accounts[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProvider extends BaseMailProvider {
  final List<OutgoingMessage> sent = <OutgoingMessage>[];
  AppException? failure;
  int attempts = 0;

  @override
  String get id => 'fake';

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
  Future<void> connect(Account account) async {
    attempts++;
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendMessage(OutgoingMessage message) async {
    sent.add(message);
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
  Future<void> replyToMessage(
    String providerMessageId,
    OutgoingMessage reply,
  ) async {}

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
}
