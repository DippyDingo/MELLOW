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
    this.updateCheckEnabled = true,
    this.updateOnMobileData = true,
    this.updateNotificationsEnabled = true,
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

  /// Ask GitHub for a newer build at startup and every few hours.
  final bool updateCheckEnabled;

  /// Allow downloading a build over mobile data; otherwise Wi-Fi only.
  final bool updateOnMobileData;

  /// Show a system notification when a new build is found.
  final bool updateNotificationsEnabled;

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
    bool? updateCheckEnabled,
    bool? updateOnMobileData,
    bool? updateNotificationsEnabled,
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
      updateCheckEnabled: updateCheckEnabled ?? this.updateCheckEnabled,
      updateOnMobileData: updateOnMobileData ?? this.updateOnMobileData,
      updateNotificationsEnabled:
          updateNotificationsEnabled ?? this.updateNotificationsEnabled,
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
          other.appLockEnabled == appLockEnabled &&
          other.updateCheckEnabled == updateCheckEnabled &&
          other.updateOnMobileData == updateOnMobileData &&
          other.updateNotificationsEnabled == updateNotificationsEnabled;

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
        updateCheckEnabled,
        updateOnMobileData,
        updateNotificationsEnabled,
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
