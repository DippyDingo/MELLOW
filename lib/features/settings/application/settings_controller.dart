import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';

/// Streams stored settings and exposes typed mutators.
///
/// Every change is written to the repository and flows back through a stream,
/// so multiple screens stay in sync and a crash cannot leave the UI showing
/// saved state that never reached the database. The only thing kept in memory
/// is the last value written here, which is what the next change is applied to.
class SettingsController extends AsyncNotifier<AppSettings> {
  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  /// Last value written by this controller; the base for the next change.
  ///
  /// The stream below emits the stored value, which lags one write behind while
  /// a save is in flight. Building a change on that lagging copy would silently
  /// undo the change made a moment earlier.
  AppSettings? _lastWritten;

  bool _loaded = false;

  @override
  Future<AppSettings> build() async {
    final subscription = _repository.watchSettings().listen(
      (settings) {
        // The first emission is the table as it was before this provider was
        // read; it may arrive after a write has already been applied.
        if (!_loaded) return;
        state = AsyncData(settings);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_loaded) return;
        state = AsyncError<AppSettings>(error, stackTrace);
      },
    );
    ref.onDispose(subscription.cancel);
    final settings = await _repository.getSettings();
    _loaded = true;
    return settings;
  }

  /// Applies a change optimistically, then persists it.
  ///
  /// If the write fails the previous value is restored and the error is
  /// rethrown, so the UI never claims a setting was saved when it was not.
  Future<void> _update(AppSettings Function(AppSettings current) transform) async {
    // `future` resolves to the value from the *first* load, so it is only a
    // fallback: using it for every write would make a second change revert the
    // first one. The last value this controller wrote wins, then the live
    // state, and only then the initial load.
    final previous = _lastWritten ?? state.valueOrNull ?? await future;
    final next = transform(previous);
    if (next == previous) return;
    state = AsyncData(next);
    try {
      await _repository.saveSettings(next);
      _lastWritten = next;
    } catch (_) {
      state = AsyncData(previous);
      _lastWritten = previous;
      rethrow;
    }
  }

  /// The newest settings this app knows, synchronously.
  ///
  /// The stream behind [state] can lag one write behind while a save is in
  /// flight, so a caller that acts right after a change (the update check runs
  /// on resume, right after the user flips a switch) must read [_lastWritten]
  /// first or it will act on the previous value.
  AppSettings get current =>
      _lastWritten ?? state.valueOrNull ?? AppSettings.defaults;

  Future<void> setThemePreference(ThemePreference preference) =>
      _update((s) => s.copyWith(themePreference: preference));

  Future<void> setFocusModeEnabled(bool enabled) =>
      _update((s) => s.copyWith(focusModeEnabled: enabled));

  Future<void> setFocusFavoritesOnly(bool enabled) =>
      _update((s) => s.copyWith(focusFavoritesOnly: enabled));

  Future<void> setFocusUnreadOnly(bool enabled) =>
      _update((s) => s.copyWith(focusUnreadOnly: enabled));

  Future<void> setNotificationsEnabled(bool enabled) =>
      _update((s) => s.copyWith(notificationsEnabled: enabled));

  Future<void> setNotificationsFavoritesOnly(bool enabled) =>
      _update((s) => s.copyWith(notificationsFavoritesOnly: enabled));

  Future<void> setBlockExternalImages(bool enabled) =>
      _update((s) => s.copyWith(blockExternalImages: enabled));

  Future<void> setAppLockEnabled(bool enabled) =>
      _update((s) => s.copyWith(appLockEnabled: enabled));

  Future<void> setUpdateCheckEnabled(bool enabled) =>
      _update((s) => s.copyWith(updateCheckEnabled: enabled));

  Future<void> setUpdateOnMobileData(bool enabled) =>
      _update((s) => s.copyWith(updateOnMobileData: enabled));

  Future<void> setUpdateNotificationsEnabled(bool enabled) =>
      _update((s) => s.copyWith(updateNotificationsEnabled: enabled));

  Future<void> markUpdateChecked(DateTime at) =>
      _update((s) => s.copyWith(lastUpdateCheckAt: at));

  Future<void> reset() async {
    await _repository.reset();
    final defaults = await _repository.getSettings();
    _lastWritten = defaults;
    state = AsyncData(defaults);
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Convenience synchronous access with defaults while loading.
final appSettingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(settingsControllerProvider).valueOrNull ??
      AppSettings.defaults;
});
