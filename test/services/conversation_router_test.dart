import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/services/sync/conversation_router.dart';

Message message({
  String inReplyTo = '',
  List<String> references = const <String>[],
  String subject = 'Hello',
  bool outgoing = false,
  bool read = true,
}) {
  return Message(
    id: 'm1',
    threadId: 'provider-thread',
    accountId: 'acc',
    from: EmailAddress(
      address: outgoing ? 'me@example.com' : 'alex@example.com',
      displayName: 'Александр',
    ),
    to: const <EmailAddress>[EmailAddress(address: 'me@example.com')],
    subject: subject,
    bodyText: 'Body',
    sentAt: DateTime(2026, 11, 23, 10),
    inReplyTo: inReplyTo.isEmpty ? null : inReplyTo,
    references: references,
    isOutgoing: outgoing,
    isRead: read,
  );
}

void main() {
  late ConversationRouter router;

  setUp(() {
    router = ConversationRouter(accountId: 'acc');
  });

  group('normalizeSubject', () {
    test('strips one Re:', () {
      expect(ConversationRouter.normalizeSubject('Re: Встреча'), 'Встреча');
    });

    test('strips nested prefixes in any case', () {
      expect(
        ConversationRouter.normalizeSubject('RE: Fwd: Re: Встреча'),
        'Встреча',
      );
    });

    test('strips Russian reply prefixes', () {
      expect(
        ConversationRouter.normalizeSubject('Ответ: Пересл: Отчёт'),
        'Отчёт',
      );
    });

    test('strips numbering used by some clients', () {
      expect(ConversationRouter.normalizeSubject('Re[2]: Тема'), 'Тема');
    });

    test('keeps legitimate colons in the subject', () {
      expect(
        ConversationRouter.normalizeSubject('План: квартал 4'),
        'План: квартал 4',
      );
    });

    test('collapses whitespace', () {
      expect(ConversationRouter.normalizeSubject('  Re:   Тема  '), 'Тема');
    });
  });

  test('isReplySubject', () {
    expect(ConversationRouter.isReplySubject('Re: hi'), isTrue);
    expect(ConversationRouter.isReplySubject('Ответ: привет'), isTrue);
    expect(ConversationRouter.isReplySubject('Привет'), isFalse);
  });

  group('resolve', () {
    test('prefers the provider thread id', () {
      final id = router.resolve(
        message: message(inReplyTo: '<parent@x>'),
        providerThreadId: 'provider-thread',
        knownConversationOfProviderThread: 'conv-provider',
        conversationOfMessage: (_) => 'conv-references',
      );
      expect(id, 'conv-provider');
    });

    test('falls back to the References chain when the thread is unknown', () {
      final id = router.resolve(
        message: message(
          inReplyTo: '<parent@x>',
          references: <String>['<root@x>', '<parent@x>'],
        ),
        providerThreadId: 'provider-thread',
        knownConversationOfProviderThread: null,
        conversationOfMessage: (header) =>
            header == '<parent@x>' ? 'conv-parent' : null,
      );
      expect(id, 'conv-parent');
    });

    test('prefers the closest ancestor (newest reference)', () {
      final id = router.resolve(
        message: message(
          inReplyTo: '<newest@x>',
          references: <String>['<oldest@x>', '<middle@x>', '<newest@x>'],
        ),
        providerThreadId: null,
        knownConversationOfProviderThread: null,
        conversationOfMessage: (header) {
          if (header == '<middle@x>') return 'conv-middle';
          if (header == '<newest@x>') return 'conv-newest';
          return null;
        },
      );
      expect(id, 'conv-newest');
    });

    test('creates a new id when nothing is known', () {
      final first = router.resolve(
        message: message(),
        providerThreadId: null,
        knownConversationOfProviderThread: null,
        conversationOfMessage: (_) => null,
      );
      final second = router.resolve(
        message: message(),
        providerThreadId: null,
        knownConversationOfProviderThread: null,
        conversationOfMessage: (_) => null,
      );
      expect(first, isNotEmpty);
      expect(first, isNot(second));
    });

    test('identical subjects alone never merge conversations', () {
      final a = router.resolve(
        message: message(subject: 'Счёт'),
        providerThreadId: null,
        knownConversationOfProviderThread: null,
        conversationOfMessage: (_) => null,
      );
      final b = router.resolve(
        message: message(subject: 'Счёт'),
        providerThreadId: null,
        knownConversationOfProviderThread: null,
        conversationOfMessage: (_) => null,
      );
      expect(a, isNot(b));
    });
  });

  group('newThread', () {
    test('builds a thread with deduplicated participants', () {
      final thread = router.newThread(
        message: message(),
        conversationId: 'conv-1',
        providerThreadId: 'provider-thread',
        contactId: 'contact-1',
      );

      expect(thread.id, 'conv-1');
      expect(thread.accountId, 'acc');
      expect(thread.providerThreadId, 'provider-thread');
      expect(thread.contactId, 'contact-1');
      expect(thread.participants.map((p) => p.address), <String>[
        'alex@example.com',
        'me@example.com',
      ]);
    });

    test('normalises the subject', () {
      final thread = router.newThread(
        message: message(subject: 'Re: Re: Встреча'),
        conversationId: 'conv-1',
        providerThreadId: null,
        contactId: '',
      );
      expect(thread.subject, 'Встреча');
    });

    test('counts an unread incoming message', () {
      final thread = router.newThread(
        message: message(read: false),
        conversationId: 'c',
        providerThreadId: null,
        contactId: '',
      );
      expect(thread.unreadCount, 1);
    });
  });

  group('touch', () {
    test('advances updatedAt and adds new participants', () {
      final original = router.newThread(
        message: message(),
        conversationId: 'c',
        providerThreadId: null,
        contactId: '',
      );

      final later = Message(
        id: 'm2',
        threadId: 'provider-thread',
        accountId: 'acc',
        from: const EmailAddress(address: 'maria@mail.ru'),
        to: const <EmailAddress>[EmailAddress(address: 'me@example.com')],
        sentAt: DateTime(2026, 11, 24, 9),
        isRead: false,
      );

      final updated = router.touch(original, later);
      expect(updated.updatedAt, DateTime(2026, 11, 24, 9));
      expect(
        updated.participants.map((p) => p.address),
        contains('maria@mail.ru'),
      );
      expect(updated.participants, hasLength(3));
    });

    test('never moves updatedAt backwards', () {
      final original = router.newThread(
        message: message(),
        conversationId: 'c',
        providerThreadId: null,
        contactId: '',
      );
      final older = Message(
        id: 'm0',
        threadId: 't',
        accountId: 'acc',
        from: const EmailAddress(address: 'alex@example.com'),
        to: const <EmailAddress>[],
        sentAt: DateTime(2020),
        isRead: true,
      );
      expect(router.touch(original, older).updatedAt, original.updatedAt);
    });
  });
}
