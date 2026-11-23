/// Endpoints and scopes of the Gmail REST API.
///
/// Kept separate from the adapter so tests can point at local fixtures and so
/// that a change of scope is a one-line, reviewable diff.
abstract final class GmailEndpoints {
  static const String authorization = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const String token = 'https://oauth2.googleapis.com/token';
  static const String userInfo = 'https://openidconnect.googleapis.com/v1/userinfo';
  static const String apiBase = 'https://gmail.googleapis.com/gmail/v1/users/me';

  /// Scopes (docs/MAIL_PROVIDERS.md §5). `gmail.modify` is required to mark
  /// messages read and to archive them; nothing broader is requested.
  static const List<String> scopes = <String>[
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.send',
    'https://www.googleapis.com/auth/gmail.modify',
    'openid',
    'email',
    'profile',
  ];

  /// Label ids Mellow cares about.
  static const String labelInbox = 'INBOX';
  static const String labelSent = 'SENT';
  static const String labelTrash = 'TRASH';
  static const String labelUnread = 'UNREAD';
}
