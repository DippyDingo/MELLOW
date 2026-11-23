import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/domain/security/secure_token_storage.dart';

/// Production [SecureTokenStorage] backed by the OS keystore.
///
/// iOS: Keychain (`first_unlock_this_device` — not restored from backup to
/// another device). Android: EncryptedSharedPreferences with AES-256.
class FlutterSecureTokenStorage implements SecureTokenStorage {
  FlutterSecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  static const String _accountPrefix = 'account.';

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (error) {
      // A broken keystore must not crash the app; the account goes to re-auth.
      throw StorageException(
        'Не удалось прочитать защищённые данные',
        cause: error,
      );
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (error) {
      throw StorageException(
        'Не удалось сохранить защищённые данные',
        cause: error,
      );
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (error) {
      throw StorageException(
        'Не удалось удалить защищённые данные',
        cause: error,
      );
    }
  }

  @override
  Future<void> deleteAccountSecrets(String accountId) async {
    final all = await _storage.readAll();
    final prefix = '$_accountPrefix$accountId';
    for (final key in all.keys) {
      if (key == prefix || key.startsWith('$prefix.')) {
        await _storage.delete(key: key);
      }
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      // A write/read/delete round-trip is the only reliable probe.
      const probeKey = '__mellow_keystore_probe';
      await _storage.write(key: probeKey, value: '1');
      final value = await _storage.read(key: probeKey);
      await _storage.delete(key: probeKey);
      return value == '1';
    } catch (_) {
      return false;
    }
  }
}

/// Non-persistent implementation for unit and widget tests.
///
/// It never touches a platform channel, which is why tests can run the full
/// account flow on a plain Dart VM.
class InMemoryTokenStorage implements SecureTokenStorage {
  InMemoryTokenStorage([Map<String, String>? initial])
      : _values = <String, String>{...?initial};

  final Map<String, String> _values;

  /// Visible for assertions in tests.
  Map<String, String> get debugValues => Map.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAccountSecrets(String accountId) async {
    final prefix = 'account.$accountId';
    _values.removeWhere(
      (key, _) => key == prefix || key.startsWith('$prefix.'),
    );
  }

  @override
  Future<bool> isAvailable() async => true;
}
