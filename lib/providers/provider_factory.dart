import 'package:mellow/core/config/app_config.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/security/secure_token_storage.dart';
import 'package:mellow/providers/contracts/mail_provider.dart';
import 'package:mellow/providers/gmail/gmail_mail_provider.dart';

/// Creates the mail adapter for an account.
///
/// This is the single place that maps a stored [MailProviderKind] onto a
/// concrete implementation, so adding IMAP or Graph later touches one switch
/// and nothing else.
class MailProviderFactory {
  const MailProviderFactory({required this.config, required this.tokenStorage});

  final AppConfig config;
  final SecureTokenStorage tokenStorage;

  /// Builds an adapter, or throws [UnsupportedException] when the provider is
  /// not implemented in this build yet.
  MailProvider create(Account account) {
    switch (account.provider) {
      case MailProviderKind.gmail:
        return GmailMailProvider(
          config: config,
          tokenStorage: tokenStorage,
          accountId: account.id,
        );
      case MailProviderKind.yandex:
      case MailProviderKind.mailRu:
      case MailProviderKind.imap:
        throw const UnsupportedException(
          'Другие почтовые сервисы Mellow пока не подключает. Сейчас '
          'работает только Gmail.',
        );
      case MailProviderKind.outlook:
        throw const UnsupportedException(
          'Outlook Mellow пока не подключает. Сейчас работает только Gmail.',
        );
      case MailProviderKind.demo:
        throw const UnsupportedException('Демо-аккаунт не синхронизируется.');
    }
  }

  /// True when the account can be synced in this build.
  bool canSync(MailProviderKind provider) => provider == MailProviderKind.gmail;
}
