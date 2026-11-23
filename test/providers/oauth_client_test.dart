import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/providers/oauth/oauth_client.dart';

final Uri endpoint = Uri.parse('https://oauth2.googleapis.com/token');

OAuthClient clientReturning(
  Map<String, dynamic> body, {
  int status = 200,
  void Function(http.Request request)? onRequest,
}) {
  return OAuthClient(
    httpClient: MockClient((request) async {
      onRequest?.call(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  group('parseAuthorizationCode', () {
    test('returns the code when state matches', () {
      final code = parseAuthorizationCode(
        Uri.parse('com.app:/oauth2redirect?code=abc123&state=xyz'),
        expectedState: 'xyz',
      );
      expect(code, 'abc123');
    });

    test('rejects a mismatching state', () {
      expect(
        () => parseAuthorizationCode(
          Uri.parse('com.app:/oauth2redirect?code=abc&state=other'),
          expectedState: 'xyz',
        ),
        throwsA(isA<AccountAuthException>()),
      );
    });

    test('reports a denial without leaking the whole URL', () {
      try {
        parseAuthorizationCode(
          Uri.parse('com.app:/oauth2redirect?error=access_denied&state=xyz'),
          expectedState: 'xyz',
        );
        fail('should throw');
      } on AccountAuthException catch (error) {
        expect(error.message, contains('access_denied'));
        expect(error.message, isNot(contains('http')));
      }
    });

    test('fails when no code is present', () {
      expect(
        () => parseAuthorizationCode(
          Uri.parse('com.app:/oauth2redirect?state=xyz'),
          expectedState: 'xyz',
        ),
        throwsA(isA<AccountAuthException>()),
      );
    });
  });

  group('exchangeCode', () {
    test('parses tokens and expiry', () async {
      http.Request? captured;
      final client = clientReturning(
        <String, dynamic>{
          'access_token': 'ya29.token',
          'refresh_token': '1//refresh',
          'expires_in': 3599,
          'scope': 'https://www.googleapis.com/auth/gmail.readonly openid',
        },
        onRequest: (request) => captured = request,
      );

      final tokens = await client.exchangeCode(
        tokenEndpoint: endpoint,
        clientId: 'client-id',
        code: 'code',
        redirectUri: 'com.app:/oauth2redirect',
        codeVerifier: 'verifier',
      );

      expect(tokens.accessToken, 'ya29.token');
      expect(tokens.refreshToken, '1//refresh');
      expect(tokens.scopes, hasLength(2));
      expect(tokens.isExpired, isFalse);
      expect(tokens.expiresAt, isNotNull);

      // The request is a form POST carrying the PKCE verifier.
      expect(captured!.headers['Content-Type'],
          contains('application/x-www-form-urlencoded'));
      expect(captured!.bodyFields['grant_type'], 'authorization_code');
      expect(captured!.bodyFields['code_verifier'], 'verifier');
      expect(captured!.bodyFields['client_id'], 'client-id');
    });

    test('maps 400 to AccountAuthException with the error code', () async {
      final client = clientReturning(
        <String, dynamic>{'error': 'invalid_grant'},
        status: 400,
      );

      await expectLater(
        client.exchangeCode(
          tokenEndpoint: endpoint,
          clientId: 'client-id',
          code: 'bad',
          redirectUri: 'com.app:/oauth2redirect',
          codeVerifier: 'verifier',
        ),
        throwsA(
          isA<AccountAuthException>().having(
            (error) => error.message,
            'message',
            contains('invalid_grant'),
          ),
        ),
      );
    });

    test('maps 503 to a retryable provider exception', () async {
      final client = clientReturning(<String, dynamic>{}, status: 503);

      await expectLater(
        client.exchangeCode(
          tokenEndpoint: endpoint,
          clientId: 'client-id',
          code: 'code',
          redirectUri: 'redirect',
          codeVerifier: 'verifier',
        ),
        throwsA(isA<MailProviderException>()),
      );
    });

    test('treats a response without access_token as re-auth', () async {
      final client = clientReturning(<String, dynamic>{'expires_in': 100});

      await expectLater(
        client.exchangeCode(
          tokenEndpoint: endpoint,
          clientId: 'client-id',
          code: 'code',
          redirectUri: 'redirect',
          codeVerifier: 'verifier',
        ),
        throwsA(isA<AccountAuthException>()),
      );
    });
  });

  group('refresh', () {
    test('sends the refresh_token grant', () async {
      http.Request? captured;
      final client = clientReturning(
        <String, dynamic>{'access_token': 'fresh', 'expires_in': 3599},
        onRequest: (request) => captured = request,
      );

      final tokens = await client.refresh(
        tokenEndpoint: endpoint,
        clientId: 'client-id',
        refreshToken: '1//refresh',
      );

      expect(tokens.accessToken, 'fresh');
      expect(captured!.bodyFields['grant_type'], 'refresh_token');
      expect(captured!.bodyFields['refresh_token'], '1//refresh');
      expect(captured!.body, isNot(contains('client_secret')));
    });

    test('a rejected refresh token means the account must re-authorise',
        () async {
      final client = clientReturning(
        <String, dynamic>{'error': 'invalid_grant'},
        status: 400,
      );

      await expectLater(
        client.refresh(
          tokenEndpoint: endpoint,
          clientId: 'client-id',
          refreshToken: 'stale',
        ),
        throwsA(isA<AccountAuthException>()),
      );
    });
  });

  group('OAuthTokens', () {
    test('isExpired respects the one-minute safety margin', () {
      final almostExpired = OAuthTokens(
        accessToken: 't',
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );
      final good = OAuthTokens(
        accessToken: 't',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(almostExpired.isExpired, isTrue);
      expect(good.isExpired, isFalse);
    });

    test('a token without expiry is never considered expired', () {
      expect(const OAuthTokens(accessToken: 't').isExpired, isFalse);
    });

    test('toString never contains the token', () {
      final tokens = OAuthTokens(accessToken: 'super-secret-token');
      expect(tokens.toString(), isNot(contains('super-secret-token')));
    });
  });
}
