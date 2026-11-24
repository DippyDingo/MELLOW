import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/core/config/app_config.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/features/accounts/application/accounts_controller.dart';
import 'package:mellow/providers/gmail/gmail_mail_provider.dart';
import 'package:mellow/services/sync/mail_sync_service.dart';
import 'package:uuid/uuid.dart';

/// Steps of the Gmail connection flow, mirrored by the UI.
enum GmailConnectStep {
  idle,
  awaitingConsent,
  exchangingCode,
  verifying,
  syncing,
  done,
  failed,
}

/// State of the "connect Gmail" flow.
class GmailConnectState {
  const GmailConnectState({
    this.step = GmailConnectStep.idle,
    this.authorizationUri,
    this.message,
    this.error,
    this.accountEmail,
    this.syncedMessages = 0,
  });

  final GmailConnectStep step;
  final Uri? authorizationUri;

  /// Short, user-facing status («Проверяем доступ…»).
  final String? message;

  final String? error;
  final String? accountEmail;
  final int syncedMessages;

  bool get isBusy =>
      step == GmailConnectStep.awaitingConsent ||
      step == GmailConnectStep.exchangingCode ||
      step == GmailConnectStep.verifying ||
      step == GmailConnectStep.syncing;

  /// Keeps the address and the consent URL while the flow advances, so the
  /// screen can still offer "open the browser again".
  GmailConnectState copyWith({
    GmailConnectStep? step,
    Uri? authorizationUri,
    String? message,
    String? error,
    String? accountEmail,
    int? syncedMessages,
    bool clearError = false,
  }) {
    return GmailConnectState(
      step: step ?? this.step,
      authorizationUri: authorizationUri ?? this.authorizationUri,
      message: message ?? this.message,
      error: clearError ? null : (error ?? this.error),
      accountEmail: accountEmail ?? this.accountEmail,
      syncedMessages: syncedMessages ?? this.syncedMessages,
    );
  }
}

/// Drives the real OAuth 2.0 + PKCE flow for Gmail and the first sync.
///
/// The controller owns no protocol details: it asks the adapter for the consent
/// URL, hands the redirect back to it, persists the account and triggers one
/// sync. Everything network-related stays in `providers/gmail`.
class GmailConnectController extends StateNotifier<GmailConnectState> {
  GmailConnectController(this._ref) : super(const GmailConnectState());

  final Ref _ref;

  GmailMailProvider? _provider;
  String? _expectedState;
  String? _codeVerifier;
  String? _pendingAccountId;

  /// Key for the PKCE secret that survives the browser trip.
  ///
  /// Android may kill Mellow while the consent screen is open (the browser is
  /// a heavy foreground app). Keeping the verifier and the requested address in
  /// the keystore means the redirect can still be finished afterwards instead
  /// of dead-ending on «Поток авторизации не был начат».
  static const String _flowKey = 'gmail.pending_flow';

  AppConfig get _config => AppConfig.fromEnvironment;

  bool get isConfigured => _config.isGoogleConfigured;

  /// Builds the consent URL for [email] and remembers the PKCE secret.
  Future<void> start(String email) async {
    if (!isConfigured) {
      state = const GmailConnectState(
        step: GmailConnectStep.failed,
        error: 'В этой сборке подключение Gmail недоступно. Это ограничение '
            'сборки: она собрана без доступа к Google.',
      );
      return;
    }

    final parsed = parseEmailAddress(email);
    if (parsed == null) {
      state = const GmailConnectState(
        step: GmailConnectStep.failed,
        error: 'Проверьте адрес почты',
      );
      return;
    }

    // The account id is minted up front: it is the key under which tokens are
    // stored, so it must exist before the consent screen opens.
    final accountId = const Uuid().v4();
    _pendingAccountId = accountId;
    final provider = GmailMailProvider(
      config: _config,
      tokenStorage: _ref.read(secureTokenStorageProvider),
      accountId: accountId,
    );

    final request = provider.buildAuthRequest(loginHint: parsed.address);
    _provider = provider;
    _expectedState = request.state;
    _codeVerifier = request.codeVerifier;

    state = GmailConnectState(
      step: GmailConnectStep.awaitingConsent,
      authorizationUri: request.authorizationUri,
      accountEmail: parsed.address,
      message: 'Подтвердите доступ в браузере',
    );

    await _saveFlow(
      accountId: accountId,
      state: request.state,
      verifier: request.codeVerifier,
      email: parsed.address,
      authorizationUri: request.authorizationUri.toString(),
    );
  }

  /// Writes the in-flight consent flow to the keystore.
  ///
  /// Best effort: a device with a broken keystore must still be able to try,
  /// just without surviving being killed by the system.
  Future<void> _saveFlow({
    required String accountId,
    required String state,
    required String verifier,
    required String email,
    required String authorizationUri,
  }) async {
    try {
      await _ref.read(secureTokenStorageProvider).write(
            _flowKey,
            jsonEncode(<String, String>{
              'accountId': accountId,
              'state': state,
              'verifier': verifier,
              'email': email,
              'authorizationUri': authorizationUri,
            }),
          );
    } on AppException {
      // Nothing to show: the flow still works while the app stays alive.
    }
  }

  Future<void> _clearFlow() async {
    try {
      await _ref.read(secureTokenStorageProvider).delete(_flowKey);
    } on AppException {
      // A stale record is replaced by the next `start()` anyway.
    }
  }

  /// Restores a flow interrupted by the app being killed.
  ///
  /// Returns true when there was something to restore, so the screen knows a
  /// redirect can still be completed without opening the browser again.
  Future<bool> restorePending() async {
    if (_codeVerifier != null) return true;
    try {
      final raw = await _ref.read(secureTokenStorageProvider).read(_flowKey);
      if (raw == null || raw.isEmpty) return false;
      final data = jsonDecode(raw);
      if (data is! Map) return false;

      final accountId = data['accountId'];
      final state = data['state'];
      final verifier = data['verifier'];
      final email = data['email'];
      if (accountId is! String ||
          state is! String ||
          verifier is! String ||
          email is! String) {
        return false;
      }

      final authUri = Uri.tryParse('${data['authorizationUri']}');
      _pendingAccountId = accountId;
      _expectedState = state;
      _codeVerifier = verifier;
      _provider = GmailMailProvider(
        config: _config,
        tokenStorage: _ref.read(secureTokenStorageProvider),
        accountId: accountId,
      );
      this.state = GmailConnectState(
        step: GmailConnectStep.awaitingConsent,
        authorizationUri: authUri,
        accountEmail: email,
        message: 'Подтвердите доступ в браузере',
      );
      return true;
    } catch (_) {
      // A corrupted record is not worth an error screen: start over instead.
      return false;
    }
  }

  /// Called with the redirect URI the browser came back with.
  ///
  /// Accepts the raw URL (`com.googleusercontent...:/oauth2redirect?code=...`).
  Future<void> complete(String redirectUrl) async {
    final provider = _provider;
    final expectedState = _expectedState;
    final verifier = _codeVerifier;
    final accountId = _pendingAccountId;

    if (provider == null || expectedState == null || verifier == null || accountId == null) {
      state = const GmailConnectState(
        step: GmailConnectStep.failed,
        error: 'Поток авторизации не был начат',
      );
      return;
    }

    try {
      state = state.copyWith(
        step: GmailConnectStep.exchangingCode,
        message: 'Обмениваем код на токен доступа',
        clearError: true,
      );

      await provider.completeAuth(
        redirectUri: Uri.parse(redirectUrl),
        expectedState: expectedState,
        codeVerifier: verifier,
      );

      state = state.copyWith(
        step: GmailConnectStep.verifying,
        message: 'Проверяем доступ к ящику',
      );

      // The account row is created only now, after the token exchange worked,
      // so a cancelled consent never leaves a phantom account behind.
      final email = normalizeEmail(state.accountEmail ?? '');
      final account = Account(
        id: accountId,
        email: email,
        provider: MailProviderKind.gmail,
        status: AccountStatus.connected,
        displayName: email,
        createdAt: DateTime.now(),
      );

      await provider.connect(account);
      await _ref.read(accountRepositoryProvider).saveAccount(account);
      await _ref.read(accountRepositoryProvider).setPrimary(account.id);

      state = state.copyWith(
        step: GmailConnectStep.syncing,
        message: 'Загружаем последние письма',
      );

      final service = MailSyncService(
        threads: _ref.read(threadRepositoryProvider),
        contacts: _ref.read(contactRepositoryProvider),
        syncState: _ref.read(syncStateStoreProvider),
        accountId: account.id,
        ownAddress: account.email,
      );

      final result = await service.sync(account: account, provider: provider);
      _ref.invalidate(accountsProvider);

      state = GmailConnectState(
        step: GmailConnectStep.done,
        accountEmail: account.email,
        syncedMessages: result.created,
        message: result.created == 0
            ? 'Готово. Новых писем нет.'
            : 'Готово. Загружено писем: ${result.created}',
      );
    } on AccountAuthException catch (error) {
      _failed(error.message);
    } on AppException catch (error) {
      _failed(error.message);
    } finally {
      // The adapter is a short-lived object: the account row and the cursor are
      // persisted, so the next sync builds a fresh one. Releasing here keeps
      // sockets and watchers from leaking after a failed handshake.
      await provider.disconnect();
      _provider = null;
      // The code can only be redeemed once, so the stored flow is spent whether
      // the exchange succeeded or not.
      _codeVerifier = null;
      _expectedState = null;
      await _clearFlow();
    }
  }

  void _failed(String message) {
    state = GmailConnectState(
      step: GmailConnectStep.failed,
      accountEmail: state.accountEmail,
      error: message,
    );
  }

  void reset() {
    _provider = null;
    _expectedState = null;
    _codeVerifier = null;
    _pendingAccountId = null;
    state = const GmailConnectState();
    unawaited(_clearFlow());
  }
}

final gmailConnectControllerProvider =
    StateNotifierProvider<GmailConnectController, GmailConnectState>(
  GmailConnectController.new,
);
