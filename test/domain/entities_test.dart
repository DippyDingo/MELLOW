import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/attachment.dart';
import 'package:mellow/domain/entities/contact.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';

void main() {
  group('Account', () {
    const account = Account(
      id: 'a1',
      email: 'demo@gmail.com',
      provider: MailProviderKind.gmail,
      status: AccountStatus.connected,
    );

    test('label falls back to a name derived from the address', () {
      expect(account.label, 'Demo');
    });

    test('label prefers the stored display name', () {
      expect(account.copyWith(displayName: 'Mellow Demo').label, 'Mellow Demo');
    });

    test('domain is the part after @', () {
      expect(account.domain, 'gmail.com');
    });

    test('status usability', () {
      expect(AccountStatus.connected.isUsable, isTrue);
      expect(AccountStatus.needsReauth.isUsable, isFalse);
      expect(AccountStatus.error.isUsable, isFalse);
    });

    test('copyWith keeps the identity', () {
      final updated = account.copyWith(status: AccountStatus.needsReauth);
      expect(updated.id, 'a1');
      expect(updated.status, AccountStatus.needsReauth);
      expect(updated.email, account.email);
    });
  });

  group('Contact', () {
    test('initial is safe for empty names', () {
      const contact = Contact(id: 'c1', displayName: '', addresses: <ContactEmail>[]);
      expect(contact.initial, '?');
      expect(contact.primaryAddress, '');
    });

    test('primaryAddress is the first address', () {
      const contact = Contact(
        id: 'c1',
        displayName: 'Александр',
        addresses: <ContactEmail>[
          ContactEmail(email: 'alex@example.com', isPrimary: true),
          ContactEmail(email: 'a@company.com'),
        ],
      );
      expect(contact.primaryAddress, 'alex@example.com');
      expect(contact.initial, 'А');
    });

    test('contactNameFromAddresses prefers a header name', () {
      expect(
        contactNameFromAddresses(const <ContactEmail>[
          ContactEmail(email: 'ivan.petrov@x.com', displayName: 'Иван'),
        ]),
        'Иван',
      );
    });

    test('contactNameFromAddresses falls back to the address', () {
      expect(
        contactNameFromAddresses(const <ContactEmail>[
          ContactEmail(email: 'ivan.petrov@x.com'),
        ]),
        'Ivan Petrov',
      );
      expect(contactNameFromAddresses(const <ContactEmail>[]), 'Unknown');
    });
  });

  group('Message', () {
    final message = Message(
      id: 'm1',
      threadId: 't1',
      accountId: 'a1',
      from: const EmailAddress(address: 'alex@example.com'),
      to: const <EmailAddress>[EmailAddress(address: 'me@example.com')],
      subject: 'Hello',
      bodyText: 'Line one\n\nLine   two',
      sentAt: DateTime(2026, 11, 23),
    );

    test('preview collapses whitespace', () {
      expect(message.preview, 'Line one Line two');
    });

    test('preview truncates long bodies with an ellipsis', () {
      final long = message.copyWith(bodyText: 'a' * 300);
      expect(long.preview.length, 141);
      expect(long.preview.endsWith('…'), isTrue);
    });

    test('preview of an empty body is empty', () {
      expect(message.copyWith(bodyText: '   ').preview, '');
    });

    test('delivery status helpers', () {
      expect(DeliveryStatus.sent.isTerminal, isTrue);
      expect(DeliveryStatus.failed.isTerminal, isTrue);
      expect(DeliveryStatus.queued.isTerminal, isFalse);
      expect(DeliveryStatus.sending.isOutgoing, isTrue);
      expect(DeliveryStatus.received.isOutgoing, isFalse);
    });
  });

  group('Attachment', () {
    test('readableSize uses sensible units', () {
      const small = Attachment(
        id: 'x',
        messageId: 'm',
        fileName: 'a.txt',
        sizeBytes: 900,
        mimeType: 'text/plain',
      );
      const medium = Attachment(
        id: 'y',
        messageId: 'm',
        fileName: 'b.pdf',
        sizeBytes: 1536 * 1024,
        mimeType: 'application/pdf',
      );
      expect(small.readableSize, '900 B');
      expect(medium.readableSize, '1.5 MB');
    });

    test('extension is lower-cased', () {
      const file = Attachment(
        id: 'z',
        messageId: 'm',
        fileName: 'Report.PDF',
        sizeBytes: 1,
        mimeType: 'application/pdf',
      );
      expect(file.extension, 'pdf');
    });
  });

  group('MessageThread', () {
    test('hasUnread reflects the unread count', () {
      final thread = MessageThread(
        id: 't',
        accountId: 'a',
        subject: 's',
        participants: const <EmailAddress>[EmailAddress(address: 'a@b.com')],
        updatedAt: DateTime(2026),
        unreadCount: 2,
      );
      expect(thread.hasUnread, isTrue);
      expect(thread.primaryParticipantAddress, 'a@b.com');
      expect(thread.copyWith(unreadCount: 0).hasUnread, isFalse);
    });
  });

  group('AppSettings', () {
    test('defaults are calm and privacy-first', () {
      const defaults = AppSettings.defaults;
      expect(defaults.themePreference, ThemePreference.system);
      expect(defaults.blockExternalImages, isTrue);
      expect(defaults.focusModeEnabled, isFalse);
    });

    test('copyWith changes a single field and equality holds', () {
      const defaults = AppSettings.defaults;
      final dark = defaults.copyWith(themePreference: ThemePreference.dark);
      expect(dark.themePreference, ThemePreference.dark);
      expect(dark.focusModeEnabled, defaults.focusModeEnabled);
      expect(dark == defaults, isFalse);
      expect(defaults.copyWith() == defaults, isTrue);
    });
  });
}
