import 'package:mellow/core/utils/email_address.dart';

/// Email services Mellow knows how to talk to.
enum MailProviderKind {
  gmail,
  yandex,
  mailRu,
  outlook,
  imap,

  /// Local-only data used for the UI prototype and demo mode.
  demo;

  /// Providers that need IMAP/SMTP credentials plus app-specific settings.
  bool get isImapBased =>
      this == MailProviderKind.yandex ||
      this == MailProviderKind.mailRu ||
      this == MailProviderKind.imap;
}

/// Lifecycle of a connected mailbox. Mirrors the `accounts.status` column.
enum AccountStatus {
  /// Row exists, but the provider handshake has not succeeded yet.
  pending,

  /// Connected and usable.
  connected,

  /// Token expired / password rejected / app password revoked.
  needsReauth,

  /// User disconnected the account; local data is kept until deleted.
  disabled,

  /// Connection failed for a reason that is worth retrying.
  error;

  bool get isUsable => this == AccountStatus.connected;
}

/// A mailbox connected to Mellow.
///
/// Identity rules:
/// * [id] is Mellow's own stable UUID and never a provider identifier.
/// * Provider identifiers (`providerAccountId`) live beside it, not instead.
class Account {
  const Account({
    required this.id,
    required this.email,
    required this.provider,
    required this.status,
    this.displayName,
    this.providerAccountId,
    this.isPrimary = false,
    this.lastSyncAt,
    this.lastError,
    this.createdAt,
  });

  final String id;

  /// Normalised address (`normalizeEmail`).
  final String email;
  final MailProviderKind provider;
  final AccountStatus status;

  /// Name shown in the account switcher; falls back to the local part.
  final String? displayName;

  /// Provider-side identifier (Gmail `sub`, IMAP user, Graph id). Optional.
  final String? providerAccountId;

  /// Exactly one account is primary; new messages are sent from it by default.
  final bool isPrimary;

  final DateTime? lastSyncAt;

  /// Safe, user-readable error description. Never a token or password.
  final String? lastError;

  final DateTime? createdAt;

  String get label => displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : nameFromAddress(email);

  String get domain => emailDomain(email);

  Account copyWith({
    String? email,
    MailProviderKind? provider,
    AccountStatus? status,
    String? displayName,
    String? providerAccountId,
    bool? isPrimary,
    DateTime? lastSyncAt,
    String? lastError,
    DateTime? createdAt,
  }) {
    return Account(
      id: id,
      email: email ?? this.email,
      provider: provider ?? this.provider,
      status: status ?? this.status,
      displayName: displayName ?? this.displayName,
      providerAccountId: providerAccountId ?? this.providerAccountId,
      isPrimary: isPrimary ?? this.isPrimary,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'Account($id, $email, ${provider.name}, ${status.name})';
}
