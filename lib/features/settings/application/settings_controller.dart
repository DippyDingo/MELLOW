import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';

/// Streams stored settings and exposes typed mutators.
///
/// The controller never holds a mutable copy: every change is written to the
/// repository and flows back through the stream, so multiple screens stay in
/// sync and a crash cannot leave the UI showing unsaved state.
class SettingsController extends AsyncNotifier<AppSettings> {
  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  @override
  Future<AppSettings> build() async {
    final subscription = _repository.watchSettings().listen(
      (settings) => state = AsyncData(settings),
      onError: (Object error, StackTrace stackTrace) =>
          state = AsyncError<AppSettings>(error, stackTrace),
    );
    ref.onDispose(subscription.cancel);
    return _repository.getSettings();
  }

  /// Applies a change optimistically, then persists it.
  ///
  /// If the write fails the previous value is restored and the error is
  /// rethrown, so the UI never claims a setting was saved when it was not.
  Future<void> _update(AppSettings Function(AppSettings current) transform) async {
    final previous = state.valueOrNull ?? AppSettings.defaults;
    final next = transform(previous);
    if (next == previous) return;
    state = AsyncData(next);
    try {
      await _repository.saveSettings(next);
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

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

  Future<void> reset() async {
    await _repository.reset();
    state = AsyncData(await _repository.getSettings());
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Convenience synchronous access with defaults while loading.
final appSettingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(settingsControllerProvider).valueOrNull ??
      AppSettings.defaults;
});
