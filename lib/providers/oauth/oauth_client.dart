import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mellow/core/errors/app_exception.dart';

/// Tokens returned by an OAuth 2.0 token endpoint.
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.scopes = const <String>[],
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final List<String> scopes;

  /// Treats a token as expired one minute early to avoid a race with the API.
  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 1)));
  }

  @override
  String toString() =>
      'OAuthTokens(expiresAt: $expiresAt, scopes: ${scopes.length})';
}

/// Turns the query string of the redirect URI into an authorisation code.
///
/// Throws [AccountAuthException] when the user denied access or the `state`
/// does not match — never silently continues.
String parseAuthorizationCode(
  Uri redirect, {
  required String expectedState,
}) {
  final error = redirect.queryParameters['error'];
  if (error != null) {
    final description = redirect.queryParameters['error_description'];
    throw AccountAuthException(
      description == null || description.isEmpty
          ? 'Доступ не предоставлен ($error)'
          : 'Доступ не предоставлен: $description',
    );
  }

  final state = redirect.queryParameters['state'];
  if (state != expectedState) {
    throw const AccountAuthException(
      'Ответ авторизации не совпадает с запросом (state)',
    );
  }

  final code = redirect.queryParameters['code'];
  if (code == null || code.isEmpty) {
    throw const AccountAuthException('Провайдер не вернул код авторизации');
  }
  return code;
}

/// Minimal OAuth 2.0 client: authorisation-code exchange and refresh.
///
/// The HTTP client is injected so the whole flow is testable with `MockClient`
/// and no network access.
class OAuthClient {
  OAuthClient({http.Client? httpClient, this.timeout = const Duration(seconds: 30)})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;

  /// Exchanges an authorisation code for tokens (public client, no secret).
  Future<OAuthTokens> exchangeCode({
    required Uri tokenEndpoint,
    required String clientId,
    required String code,
    required String redirectUri,
    required String codeVerifier,
  }) async {
    return _post(
      tokenEndpoint,
      <String, String>{
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      },
    );
  }

  /// Refreshes an access token.
  ///
  /// A rejected refresh token (400/401) surfaces as [AccountAuthException]: the
  /// account must be re-authorised, retrying will not help.
  Future<OAuthTokens> refresh({
    required Uri tokenEndpoint,
    required String clientId,
    required String refreshToken,
  }) async {
    return _post(
      tokenEndpoint,
      <String, String>{
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'refresh_token': refreshToken,
      },
    );
  }

  Future<OAuthTokens> _post(Uri endpoint, Map<String, String> body) async {
    http.Response response;
    try {
      response = await _http
          .post(
            endpoint,
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);
    } on Exception catch (error) {
      throw MailProviderException(
        'Нет связи с сервером авторизации',
        cause: error,
      );
    }

    if (response.statusCode == 200) {
      return _parseTokens(response.body);
    }

    if (response.statusCode == 400 || response.statusCode == 401) {
      throw AccountAuthException(
        'Сервер отклонил авторизацию: ${_errorCode(response.body)}',
      );
    }

    throw MailProviderException(
      'Сервер авторизации ответил ${response.statusCode}',
    );
  }

  OAuthTokens _parseTokens(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const MailProviderException('Некорректный ответ сервера авторизации');
    }

    final accessToken = decoded['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const AccountAuthException('Провайдер не выдал access token');
    }

    final expiresIn = decoded['expires_in'];
    final scope = decoded['scope'];

    return OAuthTokens(
      accessToken: accessToken,
      refreshToken: decoded['refresh_token'] as String?,
      expiresAt: expiresIn is int
          ? DateTime.now().add(Duration(seconds: expiresIn))
          : null,
      scopes: scope is String && scope.isNotEmpty ? scope.split(' ') : const [],
    );
  }

  /// Extracts `error` from a JSON error body without leaking the body itself.
  String _errorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String) return error;
      }
    } catch (_) {
      // Fall through to a generic message.
    }
    return 'unknown_error';
  }

  void close() => _http.close();
}
