import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/providers/discovery/provider_discovery.dart';

void main() {
  group('ProviderDiscovery.guess', () {
    test('detects Gmail domains', () {
      expect(ProviderDiscovery.guess('someone@gmail.com').provider, MailProviderKind.gmail);
      expect(
        ProviderDiscovery.guess('someone@googlemail.com').provider,
        MailProviderKind.gmail,
      );
    });

    test('detects Yandex domains with server settings', () {
      final guess = ProviderDiscovery.guess('person@yandex.ru');
      expect(guess.provider, MailProviderKind.yandex);
      expect(guess.isCertain, isTrue);
      expect(guess.imapHost, 'imap.yandex.ru');
      expect(guess.smtpHost, 'smtp.yandex.ru');
    });

    test('detects Mail.ru family domains', () {
      for (final domain in <String>['mail.ru', 'inbox.ru', 'bk.ru', 'list.ru']) {
        expect(
          ProviderDiscovery.guess('user@$domain').provider,
          MailProviderKind.mailRu,
          reason: domain,
        );
      }
    });

    test('detects Outlook family domains', () {
      for (final domain in <String>['outlook.com', 'hotmail.com', 'live.com']) {
        expect(
          ProviderDiscovery.guess('user@$domain').provider,
          MailProviderKind.outlook,
          reason: domain,
        );
      }
    });

    test('is case and whitespace tolerant', () {
      expect(
        ProviderDiscovery.guess('  User@YANDEX.RU ').provider,
        MailProviderKind.yandex,
      );
    });

    test('falls back to manual IMAP with low confidence', () {
      final guess = ProviderDiscovery.guess('user@some-company.dev');
      expect(guess.provider, MailProviderKind.imap);
      expect(guess.isCertain, isFalse);
      expect(guess.confidence, lessThan(0.5));
      expect(guess.imapHost, isNull);
    });

    test('recognises Microsoft 365 custom tenants as a hint only', () {
      final guess = ProviderDiscovery.guess('user@contoso.onmicrosoft.com');
      expect(guess.provider, MailProviderKind.outlook);
      expect(guess.isCertain, isFalse);
    });
  });

  test('providerLabel returns human names', () {
    expect(ProviderDiscovery.providerLabel(MailProviderKind.gmail), 'Gmail');
    expect(ProviderDiscovery.providerLabel(MailProviderKind.yandex), 'Яндекс Почта');
  });
}
