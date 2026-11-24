import 'dart:io';

import 'package:flutter/services.dart';

/// How the hand-off to Android's installer ended.
enum InstallOutcome {
  /// The system installer was opened; the user still has to confirm.
  opened,

  /// Android refuses installs from this app until the user allows them.
  permissionRequired,

  /// The file is gone (cleaned up by the system, or never finished).
  missingFile,

  /// This platform has no APK installer (iOS, desktop).
  unsupported,

  /// Anything else, described by [InstallResult.message].
  failed,
}

/// Result of asking Android to install a downloaded APK.
class InstallResult {
  const InstallResult(this.outcome, {this.message});

  const InstallResult.opened() : this(InstallOutcome.opened);

  final InstallOutcome outcome;

  /// Detail for the user; null when [outcome] speaks for itself.
  final String? message;

  bool get isSuccess => outcome == InstallOutcome.opened;
}

/// Hands a downloaded APK to the Android installer.
///
/// Uses a small `MethodChannel` served by `android/app/src/main/java/…/
/// ApkInstallerPlugin.java`, which `tool/platform/prepare_android.py` writes
/// next to the generated project. That keeps the app free of a third-party
/// plugin whose Gradle requirements may not match this Flutter version, and it
/// makes the whole mechanism visible in this repository.
///
/// Nothing here can install silently: Android always shows its own confirmation
/// screen, and without the «Install unknown apps» permission it refuses first.
class ApkInstaller {
  const ApkInstaller({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'app.mellow/apk_installer';

  /// FileProvider authority declared by our own manifest patch. Must match
  /// `tool/platform/prepare_android.py` and the Java side.
  static const String fileProviderAuthority = 'app.mellow.updates';

  final MethodChannel _channel;

  /// True when the platform can install an APK at all.
  bool get isSupported => Platform.isAndroid;

  /// Asks Android to show the install screen for [filePath].
  Future<InstallResult> install(String filePath) async {
    if (!isSupported) return const InstallResult(InstallOutcome.unsupported);

    if (!await File(filePath).exists()) {
      return const InstallResult(
        InstallOutcome.missingFile,
        message: 'Файл обновления не найден. Скачайте его заново',
      );
    }

    try {
      final Object? raw = await _channel.invokeMethod<Object?>(
        'installApk',
        <String, String>{
          'path': filePath,
          'authority': fileProviderAuthority,
        },
      );
      final String code = raw is String ? raw : 'failed';
      return switch (code) {
        'opened' => const InstallResult.opened(),
        'permissionRequired' => const InstallResult(
            InstallOutcome.permissionRequired,
            message: 'Разрешите Mellow установку приложений в настройках '
                'Android и нажмите «Установить» снова',
          ),
        'missingFile' => const InstallResult(
            InstallOutcome.missingFile,
            message: 'Файл обновления не найден. Скачайте его заново',
          ),
        _ => const InstallResult(
            InstallOutcome.failed,
            message: 'Не удалось открыть установщик Android',
          ),
      };
    } on PlatformException catch (error) {
      return InstallResult(
        InstallOutcome.failed,
        message: error.message ?? 'Установщик Android недоступен',
      );
    } on MissingPluginException {
      return const InstallResult(
        InstallOutcome.failed,
        message: 'Эта сборка не умеет устанавливать обновления: '
            'установите APK вручную',
      );
    }
  }

  /// Opens the system screen where the user allows installs from Mellow.
  Future<void> openInstallSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on PlatformException {
      // Nothing better to do: the message on screen already explains the step.
    } on MissingPluginException {
      // Same: an old build without the channel cannot open the screen.
    }
  }
}
