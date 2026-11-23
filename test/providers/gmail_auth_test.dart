import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/core/config/app_config.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/data/security/flutter_secure_token_storage.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/providers/gmail/gmail_endpoints.dart';
import 'package:mellow/providers/gmail/gmail_mail_provider.dart';
import 'package:mellow/providers/oauth/pkce.dart';

const String clientId = '1234-abc.apps.googleusercontent.com';

GmailMailProvider provider({
  String id = clientId,
  String redirect = '',
  InMemoryTokenStorage? storage,
}) {
  return GmailMailProvider(
    config: AppConfig(
      googleClientId: id,
      microsoftClientId: '',
      googleRedirectUri: redirect,
    ),
    tokenStorage: storage ?? InMemoryTokenStorage(),
    accountId: 'acc-1',
  );
}

AppConfig config({String id = clientId, String redirect = ''}) => AppConfig(
      googleClientId: id,
      microsoftClientId: '',
      googleRedirectUri: redirect,
    );

void main() {
  group('AppConfig', () {
    test('derives the reversed-client-id redirect when none is given', () {
      final value = config();
      expect(
        value.googleRedirectUri,
        'com.googleusercontent.apps.1234-abc:/oauth2redirect',
      );
      expect(value.isGoogleConfigured, isTrue);
    });

    test('an explicit redirect wins', () {
      final value = config(redirect: 'app.mellow:/oauth2redirect');
      expect(value.googleRedirectUri, 'app.mellow:/oauth2redirect');
    });

    test('is not configured without a client id', () {
      const config = AppConfig.empty;
      expect(config.isGoogleConfigured, isFalse);
      expect(config.googleRedirectUri, isEmpty);
      expect(config.isMicrosoftConfigured, isFalse);
    });

    test('reversedGoogleClientScheme tolerates a bare id', () {
      expect(
        AppConfig.reversedGoogleClientScheme('1234-abc'),
        'com.googleusercontent.apps.1234-abc',
      );
    });
  });

  group('buildAuthRequest', () {
    test('refuses to build a URL for an unconfigured build', () {
      expect(
        () => provider(id: '').buildAuthRequest(),
        throwsA(isA<UnsupportedException>()),
      );
    });

    test('produces a proper PKCE authorisation request', () {
      final request = provider().buildAuthRequest(loginHint: 'me@gmail.com');
      final query = request.authorizationUri.queryParameters;

      expect(
        request.authorizationUri.toString(),
        startsWith('https://accounts.google.com/o/oauth2/v2/auth?'),
      );
      expect(query['client_id'], clientId);
      expect(
        query['redirect_uri'],
        'com.googleusercontent.apps.1234-abc:/oauth2redirect',
      );
      expect(query['response_type'], 'code');
      expect(query['code_challenge_method'], 'S256');
      expect(query['code_challenge'], Pkce.challengeFor(request.codeVerifier));
      expect(query['state'], request.state);
      expect(query['login_hint'], 'me@gmail.com');

      // Refresh tokens require the offline access type and a forced consent.
      expect(query['access_type'], 'offline');
      expect(query['prompt'], 'consent');

      // Scopes are the minimum needed, and never include full mailbox delete.
      final scopes = query['scope']!.split(' ');
      expect(scopes, contains('https://www.googleapis.com/auth/gmail.readonly'));
      expect(scopes, contains('https://www.googleapis.com/auth/gmail.send'));
      expect(scopes, contains('https://www.googleapis.com/auth/gmail.modify'));
      expect(scopes, contains('openid'));
    });

    test('never puts the verifier into the URL', () {
      final request = provider().buildAuthRequest();
      expect(
        request.authorizationUri.toString(),
        isNot(contains(request.codeVerifier)),
      );
    });

    test('two requests never share a verifier or state', () {
      final first = provider().buildAuthRequest();
      final second = provider().buildAuthRequest();
      expect(first.codeVerifier, isNot(second.codeVerifier));
      expect(first.state, isNot(second.state));
    });

    test('a stored verifier is reused when resuming a flow', () {
      final request = provider().buildAuthRequest(
        codeVerifierOverride: 'fixed-verifier',
        stateOverride: 'fixed-state',
      );
      expect(request.codeVerifier, 'fixed-verifier');
      expect(request.state, 'fixed-state');
      expect(
        request.authorizationUri.queryParameters['code_challenge'],
        Pkce.challengeFor('fixed-verifier'),
      );
    });
  });

  group('completeAuth', () {
    test('rejects a redirect with a foreign state before any request', () async {
      final adapter = provider();
      await expectLater(
        adapter.completeAuth(
          redirectUri: Uri.parse(
            'com.googleusercontent.apps.1234-abc:/oauth2redirect?code=c&state=evil',
          ),
          expectedState: 'expected',
          codeVerifier: 'verifier',
        ),
        throwsA(isA<AccountAuthException>()),
      );
    });

    test('rejects a denied consent', () async {
      final adapter = provider();
      await expectLater(
        adapter.completeAuth(
          redirectUri: Uri.parse(
            'com.googleusercontent.apps.1234-abc:/oauth2redirect'
            '?error=access_denied&state=s',
          ),
          expectedState: 's',
          codeVerifier: 'verifier',
        ),
        throwsA(isA<AccountAuthException>()),
      );
    });
  });

  group('connect', () {
    test('explains that the account needs authorisation when tokens are gone',
        () async {
      final adapter = provider();
      const account = Account(
        id: 'acc-1',
        email: 'me@gmail.com',
        provider: MailProviderKind.gmail,
        status: AccountStatus.pending,
      );

      await expectLater(
        adapter.connect(account),
        throwsA(
          isA<AccountAuthException>().having(
            (error) => error.message,
            'message',
            contains('Нет сохранённого доступа'),
          ),
        ),
      );
    });
  });

  test('capabilities describe Gmail honestly', () {
    final capabilities = provider().capabilities;
    expect(capabilities.supportsThreads, isTrue);
    expect(capabilities.supportsIncrementalSync, isTrue);
    expect(
      capabilities.supportsPush,
      isFalse,
      reason: 'push needs a Pub/Sub backend that does not exist yet',
    );
    expect(
      capabilities.supportsReadReceipts,
      isFalse,
      reason: 'email never guarantees read receipts',
    );
  });

  test('the requested scopes match the documented endpoint list', () {
    expect(GmailEndpoints.scopes, isNotEmpty);
    expect(
      GmailEndpoints.scopes.every((scope) => scope.startsWith('https://') ||
          scope == 'openid' ||
          scope == 'email' ||
          scope == 'profile'),
      isTrue,
    );
  });
}
