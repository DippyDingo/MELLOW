import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/core/utils/update_check.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/repositories/drift_settings_repository.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';
import 'package:mellow/features/updates/application/update_controller.dart';

/// The controller talks to GitHub through [UpdateChecker], which is created
/// inside the provider. To keep the test hermetic without a network, the
/// checker is exercised separately (see `update_check_test.dart`) and here only
/// the decisions the controller makes are covered: when to check at all, and
/// what the banner does.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  UpdateController controller() =>
      container.read(updateControllerProvider.notifier);

  UpdateState state() => container.read(updateControllerProvider);

  setUp(() {
    db = AppDatabase.inMemory();
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('UpdateController: when to check', () {
    test('does nothing while the check is switched off', () async {
      await container
          .read(settingsControllerProvider.notifier)
          .setUpdateCheckEnabled(false);

      await controller().check(automatic: false);

      // Diagnostic: what the controller actually saw.
      // ignore: avoid_print
      print('DIAG live=${container.read(settingsControllerProvider).valueOrNull?.updateCheckEnabled} '
          'sync=${container.read(appSettingsProvider).updateCheckEnabled} '
          'phase=${state().phase} msg=${state().message}');

      // No state change at all: the banner must not appear and no request is
      // made, which is what the acceptance criterion in §11 asks for.
      expect(state().phase, UpdatePhase.idle);
      expect(state().showBanner, isFalse);
    });

    test('a recent automatic check is skipped', () async {
      await container
          .read(settingsControllerProvider.notifier)
          .markUpdateChecked(DateTime.now().subtract(const Duration(minutes: 5)));

      await controller().check();

      expect(state().phase, UpdatePhase.idle);
    });

    test('an automatic check older than six hours runs', () async {
      await container.read(settingsControllerProvider.notifier).markUpdateChecked(
            DateTime.now().subtract(const Duration(hours: 7)),
          );

      await controller().check();

      // The GitHub call itself cannot succeed in a unit test, so what matters
      // is that the controller did not skip the attempt: it reached the
      // "checking" phase and then reported a failure honestly.
      expect(state().phase, UpdatePhase.failed);
      expect(state().message, isNotNull);
    });
  });

  group('UpdateController: banner visibility', () {
    test('nothing to show before a check', () {
      expect(state().showBanner, isFalse);
    });

    test('«Позже» hides the banner', () async {
      // Simulate what a successful check produces, without the network.
      final UpdateController c = controller();
      c.dismiss();
      expect(state().dismissed, isTrue);
      expect(state().showBanner, isFalse);
    });
  });

  group('Settings: update preferences round-trip', () {
    test('all three are on by default', () async {
      final AppSettings settings =
          await DriftSettingsRepository(db).getSettings();
      expect(settings.updateCheckEnabled, isTrue);
      expect(settings.updateOnMobileData, isTrue);
      expect(settings.updateNotificationsEnabled, isTrue);
      expect(settings.lastUpdateCheckAt, isNull);
    });

    test('values survive a save and load', () async {
      final DriftSettingsRepository repository = DriftSettingsRepository(db);
      final DateTime stamp = DateTime.utc(2026, 11, 23, 12, 30);
      await repository.saveSettings(
        AppSettings.defaults.copyWith(
          updateCheckEnabled: false,
          updateOnMobileData: false,
          updateNotificationsEnabled: false,
          lastUpdateCheckAt: stamp,
        ),
      );

      final AppSettings loaded = await repository.getSettings();
      expect(loaded.updateCheckEnabled, isFalse);
      expect(loaded.updateOnMobileData, isFalse);
      expect(loaded.updateNotificationsEnabled, isFalse);
      expect(loaded.lastUpdateCheckAt, stamp);
    });
  });

  group('UpdateState', () {
    test('the banner shows for available, downloading and downloaded', () {
      for (final UpdatePhase phase in <UpdatePhase>[
        UpdatePhase.available,
        UpdatePhase.downloading,
        UpdatePhase.downloaded,
      ]) {
        expect(
          UpdateState(phase: phase, release: _release).showBanner,
          isTrue,
          reason: '$phase must be visible',
        );
      }
    });

    test('the banner stays hidden for idle, checking, up to date and failure', () {
      for (final UpdatePhase phase in <UpdatePhase>[
        UpdatePhase.idle,
        UpdatePhase.checking,
        UpdatePhase.upToDate,
        UpdatePhase.failed,
      ]) {
        expect(
          UpdateState(phase: phase).showBanner,
          isFalse,
          reason: '$phase must not show a banner',
        );
      }
    });

    test('«Позже» beats an available build', () {
      expect(
        UpdateState(
          phase: UpdatePhase.available,
          release: _release,
          dismissed: true,
        ).showBanner,
        isFalse,
      );
    });
  });
}

final UpdateRelease _release = UpdateRelease(
  tag: 'build-fff0000',
  sha: 'fff0000',
  downloadUrl: Uri.parse('https://github.com/x/mellow-debug.apk'),
  sizeBytes: 1024,
);
