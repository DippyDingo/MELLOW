import 'package:http/http.dart' as http;
import 'package:mellow/core/config/app_config.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/attachment.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/security/secure_token_storage.dart';
import 'package:mellow/providers/contracts/incremental_mail_provider.dart';
import 'package:mellow/providers/contracts/mail_provider.dart';
import 'package:mellow/providers/gmail/gmail_api.dart';
import 'package:mellow/providers/gmail/gmail_endpoints.dart';
import 'package:mellow/providers/gmail/gmail_message_parser.dart';
import 'package:mellow/providers/mime/mime_builder.dart';
import 'package:mellow/providers/oauth/oauth_client.dart';
import 'package:mellow/providers/oauth/pkce.dart';
import 'package:uuid/uuid.dart';

/// Result of starting the OAuth flow: the URL to open plus the secret that must
/// be kept until the redirect comes back.
class GmailAuthRequest {
  const GmailAuthRequest({
    required this.authorizationUri,
    required this.state,
    required this.codeVerifier,
  });

  final Uri authorizationUri;

  /// Must be compared with the `state` of the redirect.
  final String state;

  /// PKCE verifier kept on the device (never sent in the browser).
  final String codeVerifier;
}

/// Gmail through the official REST API and OAuth 2.0 (PKCE).
///
/// Layer boundary: this class talks HTTP and the OS keystore only. It returns
/// domain entities and never touches SQLite — persistence is the sync engine's
/// job (see `services/sync/mail_sync_service.dart`).
class GmailMailProvider extends BaseMailProvider
    implements IncrementalMailProvider {
  GmailMailProvider({
    required this.config,
    required this.tokenStorage,
    required this.accountId,
    http.Client? httpClient,
    OAuthClient? oauthClient,
    Uri? apiBaseUri,
    Uri? tokenEndpoint,
  })  : _http = httpClient ?? http.Client(),
        _oauth = oauthClient ?? OAuthClient(httpClient: httpClient),
        _apiBase = apiBaseUri,
        _tokenEndpoint = tokenEndpoint ?? Uri.parse(GmailEndpoints.token),
        _secrets = AccountSecrets(tokenStorage, accountId);

  final AppConfig config;
  final SecureTokenStorage tokenStorage;
  final String accountId;

  final http.Client _http;
  final OAuthClient _oauth;
  final Uri? _apiBase;
  final Uri _tokenEndpoint;
  final AccountSecrets _secrets;
  final Uuid _uuid = const Uuid();

  GmailApi? _api;
  OAuthTokens? _tokens;

  /// The address of the connected mailbox, needed to distinguish own messages.
  String _ownAddress = '';

  @override
  String get id => 'gmail';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsThreads: true,
        // Gmail push needs a Cloud Pub/Sub backend that Mellow does not have
        // yet, so the honest capability is "no": sync is pull-based.
        supportsPush: false,
        supportsSearch: true,
        supportsLabels: true,
        supportsReadReceipts: false,
        supportsAttachments: true,
        supportsIncrementalSync: true,
        // Gmail rejects messages above 25 MB, encoded size included.
        maxAttachmentBytes: 25 * 1024 * 1024,
      );

  /// Builds the consent URL. The caller opens it (url_launcher) and keeps
  /// [GmailAuthRequest.codeVerifier] until the redirect arrives.
  GmailAuthRequest buildAuthRequest({String? loginHint, String? stateOverride, String? codeVerifierOverride}) {
    if (!config.isGoogleConfigured) {
      throw const UnsupportedException(
        'В этой сборке подключение Gmail недоступно: она собрана без '
        'доступа к Google.',
      );
    }

    final pkce = codeVerifierOverride == null
        ? Pkce.generate()
        : PkcePair(
            verifier: codeVerifierOverride,
            challenge: Pkce.challengeFor(codeVerifierOverride),
          );
    final state = stateOverride ?? Pkce.state();

    final uri = Uri.parse(GmailEndpoints.authorization).replace(
      queryParameters: <String, String>{
        'client_id': config.googleClientId,
        'redirect_uri': config.googleRedirectUri,
        'response_type': 'code',
        'scope': GmailEndpoints.scopes.join(' '),
        'code_challenge': pkce.challenge,
        'code_challenge_method': PkcePair.method,
        'state': state,
        'access_type': 'offline',
        // Forces the consent screen so a refresh token is actually issued.
        'prompt': 'consent',
        if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint,
      },
    );

    return GmailAuthRequest(
      authorizationUri: uri,
      state: state,
      codeVerifier: pkce.verifier,
    );
  }

  /// Completes the flow: validates `state`, exchanges the code, stores tokens.
  Future<void> completeAuth({
    required Uri redirectUri,
    required String expectedState,
    required String codeVerifier,
  }) async {
    final code = parseAuthorizationCode(redirectUri, expectedState: expectedState);

    final tokens = await _oauth.exchangeCode(
      tokenEndpoint: _tokenEndpoint,
      clientId: config.googleClientId,
      code: code,
      redirectUri: config.googleRedirectUri,
      codeVerifier: codeVerifier,
    );

    await _secrets.saveOAuth(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
    );
    _tokens = tokens;
  }

  /// Validates stored credentials and resolves the mailbox address.
  @override
  Future<void> connect(Account account) async {
    _ownAddress = account.email;
    final accessToken = await _secrets.accessToken();
    if (accessToken == null) {
      throw const AccountAuthException('Нет сохранённого доступа к Gmail');
    }

    if (await _secrets.expiresAt() != null &&
        DateTime.now().isAfter(
          (await _secrets.expiresAt())!.subtract(const Duration(minutes: 1)),
        )) {
      await _refresh();
    } else {
      _tokens = OAuthTokens(accessToken: accessToken);
    }

    final profile = await _client.getProfile();
    if (profile.emailAddress.isNotEmpty) _ownAddress = profile.emailAddress;
  }

  @override
  Future<void> disconnect() async {
    _api?.close();
    _api = null;
  }

  /// Revokes locally stored credentials (server-side revoke is user-facing and
  /// intentionally not automatic).
  Future<void> forgetCredentials() => _secrets.clear();

  @override
  Future<MessagePage> fetchMessages({
    String? cursor,
    int limit = 50,
    String? folder,
  }) async {
    final refs = await _client.listMessageRefs(
      pageToken: cursor,
      maxResults: limit,
      labelId: folder ?? GmailEndpoints.labelInbox,
    );

    final messages = <Message>[];
    for (final ref in refs) {
      final json = await _client.getMessage(ref.id);
      messages.add(_toMessage(json, threadId: ref.threadId));
    }

    return MessagePage(
      messages: messages,
      nextCursor: refs.isEmpty ? null : refs.last.nextPageToken,
      hasMore: refs.isNotEmpty && refs.last.nextPageToken != null,
    );
  }

  @override
  Future<Message?> getMessage(String providerMessageId) async {
    final json = await _client.getMessage(providerMessageId);
    final threadId = json['threadId'] as String?;
    return _toMessage(json, threadId: threadId);
  }

  /// `historyId` to persist as the incremental cursor.
  @override
  Future<String?> currentCursor() async {
    final profile = await _client.getProfile();
    return profile.historyId;
  }

  /// Message ids added since [startHistoryId].
  ///
  /// Returns `null` when Google dropped that history window — the sync engine
  /// must then do a full reconciliation instead of trusting the cursor.
  @override
  Future<List<String>?> changedMessageIds(String cursor) async {
    // A message can appear in several history records (added, then labelled),
    // so ids are de-duplicated while keeping the provider's order.
    final ids = <String>{};
    String? pageToken;

    do {
      final page = await _client.listHistory(
        startHistoryId: cursor,
        pageToken: pageToken,
      );
      if (page == null) return null;
      ids.addAll(page.messageIdsAdded);
      pageToken = page.nextPageToken;
    } while (pageToken != null);

    return ids.toList(growable: false);
  }

  @override
  Future<void> sendMessage(OutgoingMessage message) async {
    final mime = MimeBuilder(
      from: message.from,
      to: message.to,
      cc: message.cc,
      bcc: message.bcc,
      subject: message.subject,
      bodyText: message.bodyText,
      bodyHtml: message.bodyHtml,
      inReplyTo: message.inReplyTo,
      references: message.references,
    );
    await _client.sendRaw(mime.toBase64Url());
  }

  @override
  Future<void> replyToMessage(String providerMessageId, OutgoingMessage reply) async {
    final original = await _client.getMessage(
      providerMessageId,
      format: 'metadata',
    );
    final threadId = original['threadId'] as String?;
    final payload = original['payload'];
    final headers = <String, String>{};
    if (payload is Map<String, dynamic> && payload['headers'] is List) {
      for (final header in payload['headers'] as List) {
        if (header is Map<String, dynamic>) {
          final name = (header['name'] as String?)?.toLowerCase();
          final value = header['value'] as String?;
          if (name != null && value != null) headers[name] = value;
        }
      }
    }

    final mime = MimeBuilder(
      from: reply.from,
      to: reply.to,
      cc: reply.cc,
      bcc: reply.bcc,
      subject: reply.subject,
      bodyText: reply.bodyText,
      bodyHtml: reply.bodyHtml,
      inReplyTo: headers['message-id'],
      references: <String>[
        ...?_referencesOf(headers['references']),
        if (headers['message-id'] != null) headers['message-id']!,
      ],
    );

    await _client.sendRaw(mime.toBase64Url(), threadId: threadId);
  }

  @override
  Future<void> markAsRead(String providerMessageId, {bool read = true}) async {
    await _client.modifyLabels(
      providerMessageId,
      removeLabelIds: read ? <String>[GmailEndpoints.labelUnread] : const [],
      addLabelIds: read ? const [] : <String>[GmailEndpoints.labelUnread],
    );
  }

  @override
  Future<void> archiveMessage(String providerMessageId) async {
    // Gmail "archive" = remove the INBOX label. The message stays searchable.
    await _client.modifyLabels(
      providerMessageId,
      removeLabelIds: <String>[GmailEndpoints.labelInbox],
    );
  }

  @override
  Future<void> deleteMessage(String providerMessageId) async {
    // Trash, never permanent delete: recoverable in Gmail for 30 days.
    await _client.modifyLabels(
      providerMessageId,
      addLabelIds: <String>[GmailEndpoints.labelTrash],
      removeLabelIds: <String>[GmailEndpoints.labelInbox],
    );
  }

  @override
  Future<List<int>> downloadAttachment(Attachment attachment) async {
    final providerId = attachment.providerAttachmentId;
    if (providerId == null) {
      throw const MailProviderException('У вложения нет идентификатора Gmail');
    }
    return _client.getAttachment(attachment.messageId, providerId);
  }

  @override
  Future<Attachment> uploadAttachment(String messageId, String filePath) {
    // Gmail accepts attachments only as part of the sent MIME message; an
    // out-of-band upload does not exist in the API.
    throw const UnsupportedException(
      'Gmail не поддерживает загрузку вложений отдельно от отправки',
    );
  }

  /// Parses one Gmail message.
  ///
  /// `Message.threadId` here is the provider thread id (a transient value):
  /// the sync engine maps it to a local conversation id before persisting.
  Message _toMessage(Map<String, dynamic> json, {String? threadId}) {
    return GmailMessageParser.toMessage(
      json,
      accountId: accountId,
      localId: _uuid.v4(),
      threadId: threadId ?? (json['threadId'] as String? ?? ''),
      ownAddress: _ownAddress,
    );
  }

  GmailApi get _client {
    final existing = _api;
    if (existing != null) return existing;
    final tokens = _tokens;
    if (tokens == null) {
      throw const AccountAuthException('Gmail не авторизован');
    }
    final api = GmailApi(
      accessToken: tokens.accessToken,
      baseUri: _apiBase,
      httpClient: _http,
      onTokenRefreshed: (refreshed) {
        _tokens = refreshed;
      },
    );
    api.refreshCallback = _refresh;
    _api = api;
    return api;
  }

  Future<OAuthTokens> _refresh() async {
    final refreshToken = await _secrets.refreshToken();
    if (refreshToken == null) {
      throw const AccountAuthException(
        'Срок доступа истёк. Войдите в Gmail заново',
      );
    }

    final tokens = await _oauth.refresh(
      tokenEndpoint: _tokenEndpoint,
      clientId: config.googleClientId,
      refreshToken: refreshToken,
    );
    await _secrets.saveOAuth(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
    );
    _tokens = tokens;
    return tokens;
  }

  static List<String>? _referencesOf(String? raw) {
    if (raw == null) return null;
    final matches = RegExp(r'<[^<>]+>').allMatches(raw);
    if (matches.isEmpty) return null;
    return matches.map((match) => match.group(0)!).toList(growable: false);
  }
}
