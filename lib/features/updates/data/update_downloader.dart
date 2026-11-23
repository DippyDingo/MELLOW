import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mellow/core/utils/update_check.dart';

/// How a download ended. Every case has a sentence the UI can show as-is.
enum DownloadFailure {
  /// The device has less free space than the file plus a safety margin.
  noSpace,

  /// The server refused or the connection broke; retry is reasonable.
  network,

  /// The host is not the one the ТЗ allows.
  untrustedHost,

  /// The file that arrived is not the APK the release announced.
  corrupt,
}

/// Result of a finished or aborted download.
class DownloadResult {
  const DownloadResult._({
    this.file,
    this.failure,
    this.cancelled = false,
    this.receivedBytes = 0,
  });

  const DownloadResult.success(File file, int size)
      : this._(file: file, receivedBytes: size);

  const DownloadResult.failed(DownloadFailure failure, {int receivedBytes = 0})
      : this._(failure: failure, receivedBytes: receivedBytes);

  const DownloadResult.cancelled({int receivedBytes = 0})
      : this._(cancelled: true, receivedBytes: receivedBytes);

  final File? file;
  final DownloadFailure? failure;
  final bool cancelled;
  final int receivedBytes;

  bool get isSuccess => file != null;

  /// A sentence for the user; never a raw exception.
  String get message {
    if (isSuccess) return 'Загружено';
    if (cancelled) return 'Загрузка отменена';
    return switch (failure) {
      DownloadFailure.noSpace =>
        'Не хватает места: нужно освободить около 50 МБ',
      DownloadFailure.network => 'Загрузка прервана. Проверьте связь',
      DownloadFailure.untrustedHost =>
        'Ссылка ведёт не на GitHub — загрузка отменена',
      DownloadFailure.corrupt =>
        'Файл повреждён: размер или формат не совпали',
      null => 'Не удалось скачать обновление',
    };
  }
}

/// Downloads a release APK into the app's temporary directory.
///
/// Written as a stream so a 194 MB file never sits in memory and the progress
/// bar moves as bytes arrive. The download is validated before it is handed to
/// the installer: exact size, `.apk` name, and a zip header (`PK`), because an
/// HTML error page saved as `x.apk` would otherwise reach Android.
class UpdateDownloader {
  UpdateDownloader({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Free space kept free on top of the file, so a phone that fills up stops
  /// being able to take photos *during* an update instead of after.
  static const int reserveBytes = 50 * 1024 * 1024;

  /// Streams [release] into [directory] and reports progress as a fraction.
  ///
  /// [onProgress] is called with a value in `0..1` at most a few hundred times;
  /// [cancel] stops the transfer and leaves no partial file behind.
  Future<DownloadResult> download({
    required UpdateRelease release,
    required Directory directory,
    void Function(double progress, int received, int total)? onProgress,
    Future<void>? cancel,
    int? freeBytes,
  }) async {
    final Uri url = release.downloadUrl;
    if (url.scheme != 'https' || !UpdateChannel.downloadHosts.contains(url.host)) {
      return const DownloadResult.failed(DownloadFailure.untrustedHost);
    }

    final int needed = release.sizeBytes + reserveBytes;
    final int available = freeBytes ?? await _freeBytes(directory);
    if (available > 0 && available < needed) {
      return const DownloadResult.failed(DownloadFailure.noSpace);
    }

    await directory.create(recursive: true);
    final File target = File('${directory.path}/${_fileName(release)}');
    final File partial = File('${target.path}.part');
    final IOSink sink = partial.openWrite();

    bool cancelled = false;
    int received = 0;
    bool cancelRequested = false;

    // A plain flag set by the caller's signal: the stream is already awaited
    // below, so a completion signal only has to be visible to that loop.
    if (cancel != null) {
      unawaited(cancel.then((_) => cancelRequested = true));
    }

    try {
      final http.StreamedResponse response = await _http.send(
        http.Request('GET', url),
      );

      if (response.statusCode != 200) {
        await _closeQuietly(sink);
        await _delete(partial);
        return const DownloadResult.failed(DownloadFailure.network);
      }

      await for (final List<int> chunk in response.stream) {
        if (cancelRequested) {
          cancelled = true;
          break;
        }
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && release.sizeBytes > 0) {
          onProgress(
            (received / release.sizeBytes).clamp(0.0, 1.0),
            received,
            release.sizeBytes,
          );
        }
      }

      await sink.flush();
      await sink.close();

      if (cancelled) {
        await _delete(partial);
        return DownloadResult.cancelled(receivedBytes: received);
      }

      if (received != release.sizeBytes) {
        await _delete(partial);
        return DownloadResult.failed(
          DownloadFailure.corrupt,
          receivedBytes: received,
        );
      }

      if (!await _looksLikeZip(partial)) {
        await _delete(partial);
        return const DownloadResult.failed(DownloadFailure.corrupt);
      }

      await partial.rename(target.path);
      return DownloadResult.success(target, received);
    } on IOException {
      await _closeQuietly(sink);
      await _delete(partial);
      return DownloadResult.failed(DownloadFailure.network, receivedBytes: received);
    } on http.ClientException {
      await _closeQuietly(sink);
      await _delete(partial);
      return DownloadResult.failed(DownloadFailure.network, receivedBytes: received);
    } on Exception {
      await _closeQuietly(sink);
      await _delete(partial);
      return DownloadResult.failed(DownloadFailure.network, receivedBytes: received);
    }
  }

  /// File name taken from the release, so the installer shows a sane label.
  static String _fileName(UpdateRelease release) {
    final String segment = release.downloadUrl.pathSegments.isEmpty
        ? ''
        : release.downloadUrl.pathSegments.last;
    if (segment.endsWith('.apk')) return segment;
    return 'mellow-${release.shortSha}-debug.apk';
  }

  /// A zip (and therefore an APK) starts with `PK\x03\x04`.
  static Future<bool> _looksLikeZip(File file) async {
    final RandomAccessFile handle = await file.open();
    try {
      final List<int> head = await handle.read(2);
      return head.length == 2 && head[0] == 0x50 && head[1] == 0x4B;
    } finally {
      await handle.close();
    }
  }

  /// Free bytes on the volume holding [directory].
  ///
  /// Flutter has no cross-platform API for this, so the check is best-effort:
  /// on an unexpected platform it returns `0`, which means "unknown" and lets
  /// the download proceed to fail honestly later instead of blocking it.
  static Future<int> _freeBytes(Directory directory) async {
    try {
      final ProcessResult result = await Process.run('df', <String>['-k', directory.path]);
      if (result.exitCode != 0) return 0;
      final List<String> lines = (result.stdout as String).trim().split('\n');
      if (lines.length < 2) return 0;
      final List<String> parts = lines[1].split(RegExp(r'\s+'));
      if (parts.length < 4) return 0;
      final int? kilobytes = int.tryParse(parts[3]);
      return kilobytes == null ? 0 : kilobytes * 1024;
    } on Exception {
      return 0;
    }
  }

  static Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on IOException {
      // A leftover `.part` file is harmless: the next run overwrites it.
    }
  }

  static Future<void> _closeQuietly(IOSink sink) async {
    try {
      await sink.close();
    } on IOException {
      // Already closed by the failure path.
    }
  }

  void close() => _http.close();
}
