import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/data/security/flutter_secure_token_storage.dart';
import 'package:mellow/features/onboarding/application/gmail_connect_controller.dart';

/// The consent flow crosses two apps, and Android is free to kill Mellow while
/// the browser is in front. These tests pin the recovery path: without it the
/// redirect lands on a screen that no longer knows the PKCE secret and simply
/// fails, which is exactly the «просит вставить ссылку, ничего не открывается»
/// report.
void main() {
  late InMemoryTokenStorage storage;
  late ProviderContainer container;

  setUp(() {
    storage = InMemoryTokenStorage();
    container = ProviderContainer(
      overrides: <Override>[
        secureTokenStorageProvider.overrideWithValue(storage),
      ],
    );
  });

  tearDown(() => container.dispose());

  GmailConnectController controller() =>
      container.read(gmailConnectControllerProvider.notifier);

  test('a fresh controller has nothing to restore', () async {
    expect(await controller().restorePending(), isFalse);
    expect(
      container.read(gmailConnectControllerProvider).step,
      GmailConnectStep.idle,
    );
  });

  test('a stored flow comes back with its consent link', () async {
    // Shape written by `start()`: the verifier never leaves the keystore.
    await storage.write(
      'gmail.pending_flow',
      '{"accountId":"acc-1","state":"st-1","verifier":"ve-1",'
          '"email":"warmfarm109@gmail.com",'
          '"authorizationUri":"https://accounts.google.com/o/oauth2/v2/auth?x=1"}',
    );

    expect(await controller().restorePending(), isTrue);

    final state = container.read(gmailConnectControllerProvider);
    expect(state.step, GmailConnectStep.awaitingConsent);
    expect(state.accountEmail, 'warmfarm109@gmail.com');
    expect(state.authorizationUri.toString(), contains('accounts.google.com'));
  });

  test('a corrupted record is ignored, not fatal', () async {
    await storage.write('gmail.pending_flow', 'not json at all');

    expect(await controller().restorePending(), isFalse);
    expect(
      container.read(gmailConnectControllerProvider).step,
      GmailConnectStep.idle,
    );
  });

  test('restoring twice is stable', () async {
    await storage.write(
      'gmail.pending_flow',
      '{"accountId":"acc-1","state":"st-1","verifier":"ve-1",'
          '"email":"a@b.c","authorizationUri":"https://example.com/auth"}',
    );

    expect(await controller().restorePending(), isTrue);
    expect(await controller().restorePending(), isTrue);
  });

  test('reset forgets the stored flow', () async {
    await storage.write(
      'gmail.pending_flow',
      '{"accountId":"acc-1","state":"st-1","verifier":"ve-1",'
          '"email":"a@b.c","authorizationUri":"https://example.com/auth"}',
    );
    await controller().restorePending();

    controller().reset();
    // `reset` clears the keystore without awaiting; give it a turn.
    await Future<void>.delayed(Duration.zero);

    expect(await storage.read('gmail.pending_flow'), isNull);
    expect(
      container.read(gmailConnectControllerProvider).step,
      GmailConnectStep.idle,
    );
  });

  test('completing without a started flow still fails honestly', () async {
    await controller().complete('app.mellow:/oauth2redirect?code=abc');

    final state = container.read(gmailConnectControllerProvider);
    expect(state.step, GmailConnectStep.failed);
    expect(state.error, 'Поток авторизации не был начат');
  });
}
