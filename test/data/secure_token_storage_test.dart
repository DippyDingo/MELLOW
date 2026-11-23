import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/data/security/flutter_secure_token_storage.dart';
import 'package:mellow/domain/security/secure_token_storage.dart';

void main() {
  late InMemoryTokenStorage storage;

  setUp(() {
    storage = InMemoryTokenStorage();
  });

  group('AccountSecrets', () {
    test('namespaces every key by account id', () async {
      final secrets = AccountSecrets(storage, 'acc-1');
      await secrets.saveOAuth(accessToken: 'token-1');

      expect(secrets.accessTokenKey, 'account.acc-1.access_token');
      expect(storage.debugValues.keys, <String>['account.acc-1.access_token']);
    });

    test('two accounts never see each other’s tokens', () async {
      final first = AccountSecrets(storage, 'acc-1');
      final second = AccountSecrets(storage, 'acc-2');

      await first.saveOAuth(accessToken: 'first', refreshToken: 'r1');
      await second.saveOAuth(accessToken: 'second');

      expect(await first.accessToken(), 'first');
      expect(await second.accessToken(), 'second');
      expect(await second.refreshToken(), isNull);
    });

    test('expiry round-trips as UTC', () async {
      final secrets = AccountSecrets(storage, 'acc-1');
      final expiry = DateTime.utc(2026, 12, 1, 12, 0);
      await secrets.saveOAuth(accessToken: 't', expiresAt: expiry);

      final stored = await secrets.expiresAt();
      expect(stored, expiry);
      expect(stored!.isUtc, isTrue);
    });

    test('a corrupt expiry value is treated as unknown, not fatal', () async {
      final secrets = AccountSecrets(storage, 'acc-1');
      await storage.write(secrets.expiresAtKey, 'not-a-date');
      expect(await secrets.expiresAt(), isNull);
    });

    test('a missing refresh token keeps the previous one', () async {
      final secrets = AccountSecrets(storage, 'acc-1');
      await secrets.saveOAuth(accessToken: 'a', refreshToken: 'keep-me');
      // Google omits refresh_token when refreshing.
      await secrets.saveOAuth(accessToken: 'b');

      expect(await secrets.accessToken(), 'b');
      expect(await secrets.refreshToken(), 'keep-me');
    });

    test('app password is stored under a dedicated key', () async {
      final secrets = AccountSecrets(storage, 'acc-imap');
      await secrets.saveAppPassword('app-password');

      expect(await secrets.appPassword(), 'app-password');
      expect(
        storage.debugValues.containsKey(secrets.accessTokenKey),
        isFalse,
        reason: 'IMAP accounts must not get OAuth keys',
      );
    });

    test('clear() removes every secret of one account only', () async {
      final first = AccountSecrets(storage, 'acc-1');
      final second = AccountSecrets(storage, 'acc-2');
      await first.saveOAuth(accessToken: 'a', refreshToken: 'r');
      await second.saveOAuth(accessToken: 'b');

      await first.clear();

      expect(storage.debugValues.keys, <String>['account.acc-2.access_token']);
      expect(await second.accessToken(), 'b');
    });
  });

  test('isAvailable is true for the in-memory implementation', () async {
    expect(await storage.isAvailable(), isTrue);
  });

  test('delete removes a single key', () async {
    await storage.write('k', 'v');
    await storage.delete('k');
    expect(await storage.read('k'), isNull);
  });

  test('read of an unknown key returns null instead of throwing', () async {
    expect(await storage.read('nothing'), isNull);
  });

  test('StorageException is an AppException so the UI can render it', () {
    const error = StorageException('keystore broken');
    expect(error, isA<AppException>());
    expect(error.message, 'keystore broken');
  });
}
