import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/domain/entities/account.dart';

/// Result of guessing how a mailbox should be connected.
class ProviderGuess {
  const ProviderGuess({
    required this.provider,
    required this.confidence,
    this.imapHost,
    this.smtpHost,
  });

  final MailProviderKind provider;

  /// 1.0 for a known domain, lower for pattern-based guesses.
  final double confidence;

  final String? imapHost;
  final String? smtpHost;

  bool get isCertain => confidence >= 1.0;
}

/// Maps an email domain to a provider and its server settings.
///
/// Pure logic, no network: it decides *which flow* to offer, and the account
/// screen always lets the user override the result. Unknown domains fall back to
/// generic IMAP/SMTP, which the user must configure manually.
abstract final class ProviderDiscovery {
  // Plain string keys: `MailProviderKind.x.name` is an extension getter and
  // cannot appear in a constant expression.
  static const Map<String, List<String>> _domains = <String, List<String>>{
    'gmail': <String>['gmail.com', 'googlemail.com'],
    'outlook': <String>[
      'outlook.com',
      'hotmail.com',
      'live.com',
      'msn.com',
    ],
    'yandex': <String>[
      'yandex.ru',
      'yandex.com',
      'ya.ru',
      'yandex.by',
      'yandex.kz',
    ],
    'mailRu': <String>[
      'mail.ru',
      'inbox.ru',
      'list.ru',
      'bk.ru',
      'internet.ru',
    ],
  };

  static const Map<MailProviderKind, String> _imapHosts =
      <MailProviderKind, String>{
    MailProviderKind.yandex: 'imap.yandex.ru',
    MailProviderKind.mailRu: 'imap.mail.ru',
  };

  static const Map<MailProviderKind, String> _smtpHosts =
      <MailProviderKind, String>{
    MailProviderKind.yandex: 'smtp.yandex.ru',
    MailProviderKind.mailRu: 'smtp.mail.ru',
  };

  /// Guesses a provider for [email].
  ///
  /// Domains outside the supported list are *not* forced into a known provider:
  /// they return [MailProviderKind.imap] with low confidence so the UI shows the
  /// manual configuration form.
  static ProviderGuess guess(String email) {
    final domain = emailDomain(email);

    for (final entry in _domains.entries) {
      if (entry.value.contains(domain)) {
        final provider = MailProviderKind.values.firstWhere(
          (kind) => kind.name == entry.key,
        );
        return ProviderGuess(
          provider: provider,
          confidence: 1.0,
          imapHost: _imapHosts[provider],
          smtpHost: _smtpHosts[provider],
        );
      }
    }

    // Google Workspace and Microsoft 365 custom domains cannot be detected from
    // the address alone; the user picks the auth method in the UI.
    if (domain.endsWith('.onmicrosoft.com')) {
      return const ProviderGuess(
        provider: MailProviderKind.outlook,
        confidence: 0.8,
      );
    }

    return ProviderGuess(
      provider: MailProviderKind.imap,
      confidence: 0.2,
      imapHost: _imapHosts[MailProviderKind.imap],
      smtpHost: _smtpHosts[MailProviderKind.imap],
    );
  }

  /// Human readable provider name for settings and account chips.
  static String providerLabel(MailProviderKind provider) {
    switch (provider) {
      case MailProviderKind.gmail:
        return 'Gmail';
      case MailProviderKind.yandex:
        return 'Яндекс Почта';
      case MailProviderKind.mailRu:
        return 'Mail.ru';
      case MailProviderKind.outlook:
        return 'Outlook';
      case MailProviderKind.imap:
        return 'IMAP / SMTP';
      case MailProviderKind.demo:
        return 'Демо';
    }
  }

  /// Secure server ports used by every IMAP/SMTP preset in this version.
  static const int imapPort = 993;
  static const int smtpPort = 465;
}
