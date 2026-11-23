import 'package:flutter/foundation.dart';

/// How the app picks a colour scheme.
enum ThemePreference {
  system,
  light,
  dark,
}

/// User-visible application settings. Immutable value object.
@immutable
class AppSettings {
  const AppSettings({
    this.themePreference = ThemePreference.system,
    this.focusModeEnabled = false,
    this.focusFavoritesOnly = false,
    this.focusUnreadOnly = false,
    this.hideAutomatedMessages = true,
    this.notificationsEnabled = true,
    this.notificationsFavoritesOnly = false,
    this.syncOnLaunch = true,
    this.blockExternalImages = true,
    this.appLockEnabled = false,
  });

  final ThemePreference themePreference;
  final bool focusModeEnabled;
  final bool focusFavoritesOnly;
  final bool focusUnreadOnly;
  final bool hideAutomatedMessages;
  final bool notificationsEnabled;
  final bool notificationsFavoritesOnly;
  final bool syncOnLaunch;

  /// Never fetch remote images in HTML mail automatically (privacy).
  final bool blockExternalImages;

  final bool appLockEnabled;

  AppSettings copyWith({
    ThemePreference? themePreference,
    bool? focusModeEnabled,
    bool? focusFavoritesOnly,
    bool? focusUnreadOnly,
    bool? hideAutomatedMessages,
    bool? notificationsEnabled,
    bool? notificationsFavoritesOnly,
    bool? syncOnLaunch,
    bool? blockExternalImages,
    bool? appLockEnabled,
  }) {
    return AppSettings(
      themePreference: themePreference ?? this.themePreference,
      focusModeEnabled: focusModeEnabled ?? this.focusModeEnabled,
      focusFavoritesOnly: focusFavoritesOnly ?? this.focusFavoritesOnly,
      focusUnreadOnly: focusUnreadOnly ?? this.focusUnreadOnly,
      hideAutomatedMessages: hideAutomatedMessages ?? this.hideAutomatedMessages,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notificationsFavoritesOnly:
          notificationsFavoritesOnly ?? this.notificationsFavoritesOnly,
      syncOnLaunch: syncOnLaunch ?? this.syncOnLaunch,
      blockExternalImages: blockExternalImages ?? this.blockExternalImages,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
    );
  }

  static const AppSettings defaults = AppSettings();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.themePreference == themePreference &&
          other.focusModeEnabled == focusModeEnabled &&
          other.focusFavoritesOnly == focusFavoritesOnly &&
          other.focusUnreadOnly == focusUnreadOnly &&
          other.hideAutomatedMessages == hideAutomatedMessages &&
          other.notificationsEnabled == notificationsEnabled &&
          other.notificationsFavoritesOnly == notificationsFavoritesOnly &&
          other.syncOnLaunch == syncOnLaunch &&
          other.blockExternalImages == blockExternalImages &&
          other.appLockEnabled == appLockEnabled;

  @override
  int get hashCode => Object.hash(
        themePreference,
        focusModeEnabled,
        focusFavoritesOnly,
        focusUnreadOnly,
        hideAutomatedMessages,
        notificationsEnabled,
        notificationsFavoritesOnly,
        syncOnLaunch,
        blockExternalImages,
        appLockEnabled,
      );
}

/// Persistence contract for `app_settings` (simple key/value rows).
abstract interface class SettingsRepository {
  Stream<AppSettings> watchSettings();

  Future<AppSettings> getSettings();

  Future<void> saveSettings(AppSettings settings);

  /// Clears every stored preference, restoring [AppSettings.defaults].
  Future<void> reset();
}
