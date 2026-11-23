import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/providers/gmail/gmail_endpoints.dart';
import 'package:mellow/providers/oauth/oauth_client.dart';

/// Thin, typed wrapper over the Gmail REST API.
///
/// Responsibilities kept here (and only here):
/// * bearer-token header and automatic single refresh on 401;
/// * pagination cursors;
/// * mapping HTTP failures onto [AppException] subtypes.
///
/// Everything that shapes domain objects lives in `GmailMessageParser`.
class GmailApi {
  GmailApi({
    required this.accessToken,
    required this.onTokenRefreshed,
    http.Client? httpClient,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 30),
  })  : _http = httpClient ?? http.Client(),
        _base = baseUri ?? Uri.parse(GmailEndpoints.apiBase);

  String accessToken;

  /// Called after a successful refresh so the caller can persist new tokens.
  final void Function(OAuthTokens tokens) onTokenRefreshed;

  final http.Client _http;
  final Uri _base;
  final Duration timeout;

  /// Refreshes the access token; supplied by the adapter that owns credentials.
  Future<OAuthTokens> Function()? refreshCallback;

  /// `users.messages.list` — returns provider message ids, newest first.
  Future<GmailListPage> listMessages({
    String? pageToken,
    int maxResults = 50,
    String? labelId,
    String? query,
  }) async {
    final uri = _uri('messages', <String, String>{
      'maxResults': '$maxResults',
      if (pageToken != null) 'pageToken': pageToken,
      if (labelId != null) 'labelIds': labelId,
      if (query != null && query.isNotEmpty) 'q': query,
    });

    final json = await _getJson(uri);
    return GmailListPage(
      ids: _ids(json['messages']),
      nextPageToken: json['nextPageToken'] as String?,
      estimate: json['resultSizeEstimate'] is int
          ? json['resultSizeEstimate'] as int
          : null,
    );
  }

  /// `users.messages.list` including `threadId`, for initial thread building.
  Future<List<GmailMessageRef>> listMessageRefs({
    String? pageToken,
    int maxResults = 50,
    String? labelId,
    String? query,
  }) async {
    final uri = _uri('messages', <String, String>{
      'maxResults': '$maxResults',
      if (pageToken != null) 'pageToken': pageToken,
      if (labelId != null) 'labelIds': labelId,
      if (query != null && query.isNotEmpty) 'q': query,
    });
    final json = await _getJson(uri);
    final next = json['nextPageToken'] as String?;

    final refs = <GmailMessageRef>[];
    for (final raw in _asList(json['messages'])) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'] as String?;
      if (id == null) continue;
      refs.add(
        GmailMessageRef(
          id: id,
          threadId: raw['threadId'] as String?,
          nextPageToken: next,
        ),
      );
    }
    return refs;
  }

  /// `users.messages.get` with `format=full` — the raw JSON for the parser.
  Future<Map<String, dynamic>> getMessage(
    String id, {
    String format = 'full',
  }) {
    return _getJson(_uri('messages/$id', <String, String>{'format': format}));
  }

  /// `users.threads.list` — used to seed conversations with provider threads.
  Future<GmailListPage> listThreads({
    String? pageToken,
    int maxResults = 50,
    String? labelId,
  }) async {
    final uri = _uri('threads', <String, String>{
      'maxResults': '$maxResults',
      if (pageToken != null) 'pageToken': pageToken,
      if (labelId != null) 'labelIds': labelId,
    });
    final json = await _getJson(uri);
    return GmailListPage(
      ids: _ids(json['threads']),
      nextPageToken: json['nextPageToken'] as String?,
    );
  }

  /// `users.getProfile` — gives `historyId` used as the sync cursor.
  Future<GmailProfile> getProfile() async {
    final json = await _getJson(_uri('profile', const <String, String>{}));
    final email = json['emailAddress'] as String? ?? '';
    final historyId = json['historyId'];
    return GmailProfile(
      emailAddress: email,
      historyId: historyId == null ? null : '$historyId',
    );
  }

  /// `users.history.list` — incremental changes since [startHistoryId].
  ///
  /// Returns `null` when Google says the history is too old (HTTP 404), which
  /// means the caller must fall back to a full reconciliation.
  Future<GmailHistoryPage?> listHistory({
    required String startHistoryId,
    String? pageToken,
    int maxResults = 100,
  }) async {
    final uri = _uri('history', <String, String>{
      'startHistoryId': startHistoryId,
      'maxResults': '$maxResults',
      if (pageToken != null) 'pageToken': pageToken,
    });

    try {
      final json = await _getJson(uri);
      return GmailHistoryPage(
        messageIdsAdded: _historyMessageIds(json['history']),
        newHistoryId: json['historyId'] == null ? null : '${json['historyId']}',
        nextPageToken: json['nextPageToken'] as String?,
      );
    } on MailProviderException catch (error) {
      // 404 means Google dropped the history window: the caller must resync.
      if (error.isCursorExpired) return null;
      rethrow;
    }
  }

  /// `users.messages.modify` — adds/removes labels (read state, archive).
  Future<void> modifyLabels(
    String id, {
    List<String> addLabelIds = const <String>[],
    List<String> removeLabelIds = const <String>[],
  }) async {
    await _postJson(
      _uri('messages/$id/modify', const <String, String>{}),
      <String, Object>{
        'addLabelIds': addLabelIds,
        'removeLabelIds': removeLabelIds,
      },
    );
  }

  /// `users.messages.send` — accepts a base64url RFC 5322 message.
  Future<String> sendRaw(String rawBase64Url, {String? threadId}) async {
    final json = await _postJson(
      _uri('messages/send', const <String, String>{}),
      <String, Object>{
        'raw': rawBase64Url,
        if (threadId != null) 'threadId': threadId,
      },
    );
    return json['id'] as String? ?? '';
  }

  /// `users.messages.attachments.get` — base64url payload bytes.
  Future<List<int>> getAttachment(String messageId, String attachmentId) async {
    final json = await _getJson(
      _uri('messages/$messageId/attachments/$attachmentId', const <String, String>{}),
    );
    final data = json['data'] as String?;
    if (data == null) {
      throw const MailProviderException('Gmail вернул пустое вложение');
    }
    return base64Url.decode(base64Url.normalize(data));
  }

  Uri _uri(String path, Map<String, String> query) {
    final base = _base.toString();
    return Uri.parse('$base/$path').replace(
      queryParameters: query.isEmpty ? null : query,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _send(() => _http.get(uri, headers: _headers()));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, Object> body) async {
    final response = await _send(
      () => _http.post(
        uri,
        headers: <String, String>{
          ..._headers(),
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode(body),
      ),
    );
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    return _decode(response);
  }

  Map<String, String> _headers() => <String, String>{
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      };

  /// Performs the request and retries once after refreshing the token.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    http.Response response;
    try {
      response = await request().timeout(timeout);
    } on Exception catch (error) {
      throw MailProviderException('Нет связи с Gmail', cause: error);
    }

    if (response.statusCode == 401 && refreshCallback != null) {
      final tokens = await refreshCallback!.call();
      accessToken = tokens.accessToken;
      onTokenRefreshed(tokens);
      try {
        response = await request().timeout(timeout);
      } on Exception catch (error) {
        throw MailProviderException('Нет связи с Gmail', cause: error);
      }
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AccountAuthException(
        'Gmail отклонил доступ. Требуется повторный вход',
      );
    }
    if (response.statusCode == 429) {
      throw const MailProviderException(
        'Слишком много запросов к Gmail',
        statusCode: 429,
      );
    }
    if (response.statusCode >= 500) {
      throw MailProviderException(
        'Gmail временно недоступен',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      throw MailProviderException(
        'Gmail вернул ошибку ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    return response;
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      throw const MailProviderException('Неожиданный ответ Gmail');
    } on FormatException catch (error) {
      throw MailProviderException('Не удалось разобрать ответ Gmail', cause: error);
    }
  }

  static List<String> _ids(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((item) => item['id'])
        .whereType<String>()
        .toList(growable: false);
  }

  static List<String> _historyMessageIds(Object? raw) {
    if (raw is! List) return const <String>[];
    final ids = <String>{};
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      for (final message in _asList(entry['messagesAdded'])) {
        if (message is! Map<String, dynamic>) continue;
        final messageMap = message['message'];
        if (messageMap is Map<String, dynamic>) {
          final id = messageMap['id'];
          if (id is String) ids.add(id);
        }
      }
    }
    return ids.toList(growable: false);
  }

  static List<Object?> _asList(Object? value) =>
      value is List ? value : const <Object?>[];

  void close() => _http.close();
}

/// One page of ids from a Gmail list endpoint.
class GmailListPage {
  const GmailListPage({required this.ids, this.nextPageToken, this.estimate});

  final List<String> ids;
  final String? nextPageToken;
  final int? estimate;

  bool get hasMore => nextPageToken != null;
}

/// Message id plus its provider thread id.
class GmailMessageRef {
  const GmailMessageRef({required this.id, this.threadId, this.nextPageToken});

  final String id;
  final String? threadId;
  final String? nextPageToken;
}

class GmailProfile {
  const GmailProfile({required this.emailAddress, this.historyId});

  final String emailAddress;
  final String? historyId;
}

class GmailHistoryPage {
  const GmailHistoryPage({
    required this.messageIdsAdded,
    this.newHistoryId,
    this.nextPageToken,
  });

  final List<String> messageIdsAdded;
  final String? newHistoryId;
  final String? nextPageToken;

  bool get hasMore => nextPageToken != null;
}
