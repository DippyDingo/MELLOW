import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.inMemory();
    container = ProviderContainer(
      overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('starts from defaults', () async {
    final settings = await container.read(settingsControllerProvider.future);
    expect(settings, AppSettings.defaults);
  });

  test('writes are persisted and survive a new container', () async {
    final controller = container.read(settingsControllerProvider.notifier);
    await controller.setThemePreference(ThemePreference.dark);
    await controller.setFocusModeEnabled(true);
    await controller.setFocusUnreadOnly(true);

    final stored = await container.read(settingsRepositoryProvider).getSettings();
    expect(stored.themePreference, ThemePreference.dark);
    expect(stored.focusModeEnabled, isTrue);
    expect(stored.focusUnreadOnly, isTrue);

    // A fresh container over the same database reads the same values.
    final second = ProviderContainer(
      overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(second.dispose);
    final reloaded = await second.read(settingsControllerProvider.future);
    expect(reloaded, stored);
  });

  test('the state stream reflects writes from elsewhere', () async {
    await container.read(settingsControllerProvider.future);

    await container
        .read(settingsRepositoryProvider)
        .saveSettings(const AppSettings(appLockEnabled: true));

    // Streams are asynchronous; give the Drift query stream a turn.
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(settingsControllerProvider).valueOrNull?.appLockEnabled,
      isTrue,
    );
  });

  test('reset restores defaults in state and storage', () async {
    final controller = container.read(settingsControllerProvider.notifier);
    await controller.setThemePreference(ThemePreference.light);

    await controller.reset();

    expect(
      container.read(settingsControllerProvider).valueOrNull,
      AppSettings.defaults,
    );
    expect(
      await container.read(settingsRepositoryProvider).getSettings(),
      AppSettings.defaults,
    );
  });

  test('appSettingsProvider falls back to defaults while loading', () {
    expect(container.read(appSettingsProvider), AppSettings.defaults);
  });
}
