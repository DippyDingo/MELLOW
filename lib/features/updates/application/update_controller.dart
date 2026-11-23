import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';
import 'package:mellow/core/utils/update_check.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';
import 'package:mellow/features/updates/data/update_downloader.dart';
import 'package:path_provider/path_provider.dart';

/// Where the update flow currently stands.
enum UpdatePhase {
  /// Not checked yet, or the check said nothing.
  idle,

  /// Asking GitHub.
  checking,

  /// A newer build exists and is waiting for the user.
  available,

  /// Bytes are arriving.
  downloading,

  /// The APK is on the phone, waiting for the installer.
  downloaded,

  /// This build is the newest one, or the channel has nothing newer.
  upToDate,

  /// The check or the download failed; [UpdateState.message] says why.
  failed,
}

/// Everything the banner and the sheet need, in one immutable value.
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.release,
    this.message,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.filePath,
    this.dismissed = false,
  });

  final UpdatePhase phase;
  final UpdateRelease? release;

  /// A sentence for the user; null when there is nothing to say.
  final String? message;

  /// `0..1` while downloading.
  final double progress;
  final int receivedBytes;
  final int totalBytes;

  /// Local APK once downloading finished.
  final String? filePath;

  /// The user pressed «Позже»: the banner hides until a newer build appears.
  final bool dismissed;

  /// The banner is shown only for a build the user has not waved away.
  bool get showBanner =>
      (phase == UpdatePhase.available ||
          phase == UpdatePhase.downloading ||
          phase == UpdatePhase.downloaded) &&
      !dismissed;

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateRelease? release,
    String? message,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? filePath,
    bool? dismissed,
    bool clearMessage = false,
  }) {
    return UpdateState(
      phase: phase ?? this.phase,
      release: release ?? this.release,
      message: clearMessage ? null : (message ?? this.message),
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      filePath: filePath ?? this.filePath,
      dismissed: dismissed ?? this.dismissed,
    );
  }
}

/// Drives the update flow: when to check, what to show, when to download.
///
/// Deliberately does **not** install anything: Android requires the user to
/// confirm an APK, so the last step is handing the file to the system
/// installer from the UI layer.
class UpdateController extends Notifier<UpdateState> {
  static const Duration autoCheckInterval = Duration(hours: 6);

  UpdateChecker? _checker;
  UpdateDownloader? _downloader;
  Completer<void>? _cancelDownload;

  @override
  UpdateState build() {
    ref.onDispose(() {
      _checker?.close();
      _downloader?.close();
    });
    return const UpdateState();
  }

  UpdateChecker get _client =>
      _checker ??= UpdateChecker();

  UpdateDownloader get _transfer =>
      _downloader ??= UpdateDownloader();

  /// Runs a check unless the user turned checking off.
  ///
  /// [automatic] applies the six-hour rule from the ТЗ: an automatic check is
  /// skipped when the previous one is recent, while a manual one always runs.
  Future<void> check({bool automatic = true}) async {
    // Awaited, not read: while settings are still loading the synchronous
    // provider answers with defaults, and «проверять обновления выключено»
    // would be ignored on the very first launch after the user turned it off.
    final AppSettings settings;
    try {
      settings = await ref.read(settingsControllerProvider.future);
    } on Exception {
      return;
    }
    if (!settings.updateCheckEnabled) {
      state = const UpdateState(phase: UpdatePhase.idle);
      return;
    }

    if (automatic) {
      final DateTime? last = settings.lastUpdateCheckAt;
      if (last != null && DateTime.now().difference(last) < autoCheckInterval) {
        return;
      }
    }

    if (!UpdateChannel.isConfigured) {
      state = const UpdateState(
        phase: UpdatePhase.failed,
        message: 'Канал обновлений не настроен в этой сборке',
      );
      return;
    }

    state = state.copyWith(phase: UpdatePhase.checking, clearMessage: true);

    final UpdateStatus status = await _client.check();
    await ref.read(settingsControllerProvider.notifier).markUpdateChecked(
          DateTime.now(),
        );

    if (status.error != null && status.release == null) {
      state = UpdateState(phase: UpdatePhase.failed, message: status.error);
      return;
    }

    if (!status.isNewer) {
      state = UpdateState(phase: UpdatePhase.upToDate, release: status.release);
      return;
    }

    state = UpdateState(phase: UpdatePhase.available, release: status.release);
  }

  /// Hides the banner for the current build. A newer build shows it again.
  void dismiss() => state = state.copyWith(dismissed: true);

  /// Downloads the available APK, reporting progress to the UI.
  Future<void> download() async {
    final UpdateRelease? release = state.release;
    if (release == null) return;
    if (state.phase == UpdatePhase.downloading) return;

    final Directory directory = await _updatesDirectory();
    final Completer<void> cancel = Completer<void>();
    _cancelDownload = cancel;

    state = state.copyWith(
      phase: UpdatePhase.downloading,
      progress: 0,
      receivedBytes: 0,
      totalBytes: release.sizeBytes,
      clearMessage: true,
      dismissed: false,
    );

    final DownloadResult result = await _transfer.download(
      release: release,
      directory: directory,
      cancel: cancel.future,
      onProgress: (double progress, int received, int total) {
        if (state.phase != UpdatePhase.downloading) return;
        state = state.copyWith(
          progress: progress,
          receivedBytes: received,
          totalBytes: total,
        );
      },
    );

    _cancelDownload = null;

    if (result.isSuccess) {
      state = state.copyWith(
        phase: UpdatePhase.downloaded,
        progress: 1,
        filePath: result.file!.path,
        message: 'Обновление скачано, можно устанавливать',
      );
      return;
    }

    if (result.cancelled) {
      state = state.copyWith(
        phase: UpdatePhase.available,
        progress: 0,
        receivedBytes: 0,
        message: result.message,
      );
      return;
    }

    state = state.copyWith(
      phase: UpdatePhase.failed,
      message: result.message,
      progress: 0,
    );
  }

  /// Stops a running download; the partial file is deleted by the downloader,
  /// which then reports [DownloadResult.cancelled] and moves the UI back.
  void cancelDownload() {
    final Completer<void>? cancel = _cancelDownload;
    if (cancel == null || cancel.isCompleted) return;
    cancel.complete();
  }

  /// After a successful install the app restarts; this keeps the UI honest
  /// when the install was cancelled instead.
  void markInstalled() {
    state = const UpdateState(phase: UpdatePhase.upToDate);
  }

  Future<Directory> _updatesDirectory() async {
    final Directory base = await getTemporaryDirectory();
    return Directory('${base.path}/updates');
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
