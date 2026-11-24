import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/core/config/app_config.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/features/accounts/application/accounts_controller.dart';
import 'package:mellow/features/composer/application/outbox.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';
import 'package:mellow/providers/contracts/mail_provider.dart';
import 'package:mellow/providers/provider_factory.dart';
import 'package:mellow/services/sync/mail_sync_service.dart';

/// Outcome of a manual "sync now" action, rendered on the sync screen.
class SyncScreenState {
  const SyncScreenState({
    this.isRunning = false,
    this.stage,
    this.result,
    this.error,
  });

  final bool isRunning;

  /// Human-readable stage: «Получение изменений», «Загружено писем: 25», …
  final String? stage;

  final SyncRunSummary? result;
  final String? error;

  SyncScreenState copyWith({
    bool? isRunning,
    String? stage,
    SyncRunSummary? result,
    String? error,
    bool clearStage = false,
    bool clearError = false,
  }) {
    return SyncScreenState(
      isRunning: isRunning ?? this.isRunning,
      stage: clearStage ? null : (stage ?? this.stage),
      result: result ?? this.result,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Aggregated numbers for the UI.
class SyncRunSummary {
  const SyncRunSummary({
    required this.accounts,
    required this.fetched,
    required this.created,
    required this.threads,
    required this.fullSync,
    this.skipped = const <String>[],
  });

  final int accounts;
  final int fetched;
  final int created;
  final int threads;
  final bool fullSync;

  /// Accounts skipped with a reason (not connected, not supported yet).
  final List<String> skipped;

  @override
  String toString() => 'SyncRunSummary(accounts: $accounts, fetched: $fetched)';
}

/// Runs synchronisation for every connected account.
///
/// The controller is intentionally thin: all protocol work lives in
/// [MailSyncService] and the adapters, so this class only coordinates and
/// translates progress into UI state.
class SyncController extends StateNotifier<SyncScreenState> {
  SyncController(this._ref) : super(const SyncScreenState());

  final Ref _ref;

  /// Syncs all accounts (or only [accountId]).
  Future<void> syncNow({String? accountId, bool fullSync = false}) async {
    if (state.isRunning) return;
    state = const SyncScreenState(isRunning: true, stage: 'Подготовка');

    final accounts = _ref.read(accountsProvider).valueOrNull ?? const <Account>[];
    final targets = accounts
        .where((account) => account.status != AccountStatus.disabled)
        // The demo mailbox is local data for the UI prototype: there is nothing
        // to fetch, and reporting it as an error would be noise.
        .where((account) => account.provider != MailProviderKind.demo)
        .where((account) => accountId == null || account.id == accountId)
        .toList(growable: false);

    if (targets.isEmpty) {
      state = SyncScreenState(
        error: accounts.isEmpty
            ? 'Сначала подключите почтовый ящик'
            : 'Нет аккаунтов, которые можно синхронизировать',
      );
      return;
    }

    final factory = MailProviderFactory(
      config: AppConfig.fromEnvironment,
      tokenStorage: _ref.read(secureTokenStorageProvider),
    );

    var fetched = 0;
    var created = 0;
    var threads = 0;
    var synced = 0;
    var full = false;
    final skipped = <String>[];

    for (final account in targets) {
      if (!factory.canSync(account.provider)) {
        skipped.add('${account.email}: провайдер пока не поддерживается');
        continue;
      }

      MailProvider? provider;
      try {
        provider = factory.create(account);
        await provider.connect(account);

        final service = MailSyncService(
          threads: _ref.read(threadRepositoryProvider),
          contacts: _ref.read(contactRepositoryProvider),
          syncState: _ref.read(syncStateStoreProvider),
          accountId: account.id,
          ownAddress: account.email,
        );

        final result = await service.sync(
          account: account,
          provider: provider,
          fullSync: fullSync,
          onProgress: (stage) {
            state = state.copyWith(
              stage: '${account.email}: $stage',
              isRunning: true,
            );
          },
        );

        fetched += result.fetched;
        created += result.created;
        threads += result.threads;
        full = full || result.wasFullSync;
        synced++;
        // `MailSyncService` already stamped `lastSyncAt` and the status: it owns
        // the account row during a sync, so no second write happens here.
      } on AccountAuthException catch (error) {
        skipped.add('${account.email}: ${error.message}');
      } on AppException catch (error) {
        skipped.add('${account.email}: ${error.message}');
      } finally {
        // Adapters own sockets and watchers; always release them.
        await provider?.disconnect();
      }
    }

    // A sync is the natural moment to retry queued mail: the network just
    // proved it works, and the user is not waiting on anything.
    if (synced > 0) {
      try {
        await _ref.read(outboxProvider).flush();
      } catch (_) {
        // The queue keeps the messages; the next sync or launch retries.
      }
    }

    state = SyncScreenState(
      result: SyncRunSummary(
        accounts: synced,
        fetched: fetched,
        created: created,
        threads: threads,
        fullSync: full,
        skipped: skipped,
      ),
    );

    // Refresh derived lists (accounts carry lastSyncAt/status).
    _ref.invalidate(accountsProvider);
  }

  void reset() => state = const SyncScreenState();
}

final syncControllerProvider =
    StateNotifierProvider<SyncController, SyncScreenState>(SyncController.new);

/// Runs one sync at startup when the user enabled «синхронизация при запуске».
///
/// Errors are intentionally swallowed here: the startup path must never block
/// the first frame, and the failure is already recorded on the account row and
/// visible on the sync screen.
final syncOnLaunchProvider = FutureProvider<void>((ref) async {
  final settings = ref.watch(appSettingsProvider);
  if (!settings.syncOnLaunch) return;
  // Yield once before touching the sync controller: a provider may not modify
  // another provider while it is still building, and `syncNow` sets the
  // controller state synchronously on its first line.
  await Future<void>.delayed(Duration.zero);
  try {
    await ref.read(syncControllerProvider.notifier).syncNow();
  } catch (_) {
    // Surfaced by SyncController state; startup stays silent.
  }
});

/// Sends anything that was queued while the phone had no network.
///
/// Runs on launch regardless of the «синхронизация при запуске» setting: a
/// message the user already pressed «Отправить» on must not wait for a setting
/// they never touched. Silent by design — the message simply changes state.
final outboxOnLaunchProvider = FutureProvider<void>((ref) async {
  await Future<void>.delayed(Duration.zero);
  try {
    await ref.read(outboxProvider).flush();
  } catch (_) {
    // Still queued; the next launch or sync retries.
  }
});
