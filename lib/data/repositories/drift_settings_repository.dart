import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';

/// Drift-backed [SettingsRepository] over the `app_settings` key/value table.
///
/// Unknown or corrupt values fall back to defaults instead of throwing, so a
/// bad row can never prevent the app from starting.
class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  static const String _themeKey = 'theme_preference';
  static const String _focusEnabledKey = 'focus_mode_enabled';
  static const String _focusFavoritesKey = 'focus_favorites_only';
  static const String _focusUnreadKey = 'focus_unread_only';
  static const String _hideAutomatedKey = 'hide_automated_messages';
  static const String _notificationsKey = 'notifications_enabled';
  static const String _notificationsFavoritesKey = 'notifications_favorites_only';
  static const String _syncOnLaunchKey = 'sync_on_launch';
  static const String _blockImagesKey = 'block_external_images';
  static const String _appLockKey = 'app_lock_enabled';
  static const String _updateCheckKey = 'update_check_enabled';
  static const String _updateMobileKey = 'update_on_mobile_data';
  static const String _updateNotifyKey = 'update_notifications_enabled';
  static const String _updateCheckedKey = 'update_last_check_at';

  @override
  Stream<AppSettings> watchSettings() {
    return _db.select(_db.appSettingsTable).watch().map(_mapRows);
  }

  @override
  Future<AppSettings> getSettings() async {
    final rows = await _db.select(_db.appSettingsTable).get();
    return _mapRows(rows);
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final entries = <String, String>{
      _themeKey: settings.themePreference.name,
      _focusEnabledKey: settings.focusModeEnabled.toString(),
      _focusFavoritesKey: settings.focusFavoritesOnly.toString(),
      _focusUnreadKey: settings.focusUnreadOnly.toString(),
      _hideAutomatedKey: settings.hideAutomatedMessages.toString(),
      _notificationsKey: settings.notificationsEnabled.toString(),
      _notificationsFavoritesKey: settings.notificationsFavoritesOnly.toString(),
      _syncOnLaunchKey: settings.syncOnLaunch.toString(),
      _blockImagesKey: settings.blockExternalImages.toString(),
      _appLockKey: settings.appLockEnabled.toString(),
      _updateCheckKey: settings.updateCheckEnabled.toString(),
      _updateMobileKey: settings.updateOnMobileData.toString(),
      _updateNotifyKey: settings.updateNotificationsEnabled.toString(),
      if (settings.lastUpdateCheckAt != null)
        _updateCheckedKey: settings.lastUpdateCheckAt!.toIso8601String(),
    };

    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _db.appSettingsTable,
        entries.entries
            .map((e) => AppSettingsTableCompanion.insert(key: e.key, value: e.value))
            .toList(growable: false),
      );
    });
  }

  @override
  Future<void> reset() async {
    await _db.delete(_db.appSettingsTable).go();
  }

  AppSettings _mapRows(List<AppSettingRow> rows) {
    final values = <String, String>{
      for (final row in rows) row.key: row.value,
    };
    const defaults = AppSettings.defaults;

    return AppSettings(
      themePreference: _theme(values[_themeKey]) ?? defaults.themePreference,
      focusModeEnabled:
          _bool(values[_focusEnabledKey]) ?? defaults.focusModeEnabled,
      focusFavoritesOnly:
          _bool(values[_focusFavoritesKey]) ?? defaults.focusFavoritesOnly,
      focusUnreadOnly: _bool(values[_focusUnreadKey]) ?? defaults.focusUnreadOnly,
      hideAutomatedMessages:
          _bool(values[_hideAutomatedKey]) ?? defaults.hideAutomatedMessages,
      notificationsEnabled:
          _bool(values[_notificationsKey]) ?? defaults.notificationsEnabled,
      notificationsFavoritesOnly: _bool(values[_notificationsFavoritesKey]) ??
          defaults.notificationsFavoritesOnly,
      syncOnLaunch: _bool(values[_syncOnLaunchKey]) ?? defaults.syncOnLaunch,
      blockExternalImages:
          _bool(values[_blockImagesKey]) ?? defaults.blockExternalImages,
      appLockEnabled: _bool(values[_appLockKey]) ?? defaults.appLockEnabled,
      updateCheckEnabled:
          _bool(values[_updateCheckKey]) ?? defaults.updateCheckEnabled,
      updateOnMobileData:
          _bool(values[_updateMobileKey]) ?? defaults.updateOnMobileData,
      updateNotificationsEnabled: _bool(values[_updateNotifyKey]) ??
          defaults.updateNotificationsEnabled,
      lastUpdateCheckAt: _date(values[_updateCheckedKey]),
    );
  }

  ThemePreference? _theme(String? raw) {
    if (raw == null) return null;
    for (final value in ThemePreference.values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  DateTime? _date(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw);

  bool? _bool(String? raw) {
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return null;
  }
}
