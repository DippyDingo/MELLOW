/// Contract for storing secrets outside the SQLite database.
///
/// Implementations:
/// * `FlutterSecureTokenStorage` — Keychain (iOS) / EncryptedSharedPreferences
///   (Android) in production.
/// * `InMemoryTokenStorage` — tests only, never used by the app.
///
/// Rules (AGENTS.md §2, docs/SECURITY.md):
/// * values never appear in logs, exceptions or analytics;
/// * keys are namespaced by account id so disconnecting one account cannot
///   affect another;
/// * a missing value returns `null` instead of throwing.
abstract interface class SecureTokenStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  /// Removes every secret belonging to one account.
  Future<void> deleteAccountSecrets(String accountId);

  /// True when the platform keystore is usable (some Android devices report
  /// a broken keystore after a factory reset).
  Future<bool> isAvailable();
}

/// Typed access to the small set of secrets Mellow keeps.
///
/// Wrapping the raw key/value store keeps key naming in one place and makes
/// accidental collisions impossible.
class AccountSecrets {
  const AccountSecrets(this._storage, this.accountId);

  final SecureTokenStorage _storage;
  final String accountId;

  String get _prefix => 'account.$accountId';

  String get accessTokenKey => '$_prefix.access_token';
  String get refreshTokenKey => '$_prefix.refresh_token';
  String get expiresAtKey => '$_prefix.expires_at';
  String get appPasswordKey => '$_prefix.app_password';
  String get imapPasswordKey => '$_prefix.imap_password';
  String get smtpPasswordKey => '$_prefix.smtp_password';

  Future<String?> accessToken() => _storage.read(accessTokenKey);

  Future<String?> refreshToken() => _storage.read(refreshTokenKey);

  /// Absolute expiry of the access token, or `null` when unknown.
  Future<DateTime?> expiresAt() async {
    final raw = await _storage.read(expiresAtKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> saveOAuth({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) async {
    await _storage.write(accessTokenKey, accessToken);
    if (refreshToken != null) {
      await _storage.write(refreshTokenKey, refreshToken);
    }
    if (expiresAt != null) {
      await _storage.write(expiresAtKey, expiresAt.toUtc().toIso8601String());
    }
  }

  /// App password for IMAP/SMTP providers (Яндекс, Mail.ru, custom servers).
  Future<String?> appPassword() async =>
      await _storage.read(appPasswordKey) ??
      await _storage.read(imapPasswordKey);

  Future<void> saveAppPassword(String password) =>
      _storage.write(appPasswordKey, password);

  Future<void> clear() => _storage.deleteAccountSecrets(accountId);
}
