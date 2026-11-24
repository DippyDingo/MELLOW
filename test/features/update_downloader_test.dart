import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mellow/core/utils/update_check.dart';
import 'package:mellow/features/updates/data/update_downloader.dart';

/// Builds a release whose APK URL is whatever the test needs to exercise.
UpdateRelease releaseFor(
  Uri url, {
  int size = 8,
  String tag = 'build-fff0000',
}) {
  return UpdateRelease(
    tag: tag,
    sha: tag.replaceFirst('build-', ''),
    downloadUrl: url,
    sizeBytes: size,
  );
}

/// Serves a fixed body in a few chunks, so progress reporting is exercised.
http.Client fakeServer({
  required List<int> body,
  int status = 200,
  int chunkSize = 4,
}) {
  return _ChunkedClient(body, status: status, chunkSize: chunkSize);
}

class _ChunkedClient extends http.BaseClient {
  _ChunkedClient(this.body, {required this.status, required this.chunkSize});

  final List<int> body;
  final int status;
  final int chunkSize;
  final List<Uri> requests = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final StreamController<List<int>> controller =
        StreamController<List<int>>();
    unawaited(Future<void>(() async {
      for (int i = 0; i < body.length; i += chunkSize) {
        final int end = (i + chunkSize).clamp(0, body.length);
        controller.add(body.sublist(i, end));
        await Future<void>.delayed(Duration.zero);
      }
      await controller.close();
    }));
    return http.StreamedResponse(controller.stream, status);
  }
}

/// A PNG-free four-byte zip header plus payload: what an APK starts with.
List<int> zipBytes(int total) {
  return <int>[0x50, 0x4B, 0x03, 0x04, ...List<int>.filled(total - 4, 0x41)];
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mellow-update-test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('UpdateDownloader', () {
    test('saves a valid APK and reports progress to 100%', () async {
      final List<double> progress = <double>[];
      final UpdateDownloader downloader = UpdateDownloader(
        httpClient: fakeServer(body: zipBytes(8)),
      );

      final DownloadResult result = await downloader.download(
        release: releaseFor(
          Uri.parse(
            'https://github.com/DippyDingo/MELLOW/releases/download/'
            'build-fff0000/mellow-fff0000-debug.apk',
          ),
        ),
        directory: temp,
        freeBytes: 1024 * 1024 * 1024,
        onProgress: (double p, int received, int total) => progress.add(p),
      );

      expect(result.isSuccess, isTrue);
      expect(result.message, 'Загружено');
      expect(await result.file!.readAsBytes(), zipBytes(8));
      expect(result.file!.path, endsWith('mellow-fff0000-debug.apk'));
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
      // The temporary file must not survive a successful download.
      expect(
        await File('${result.file!.path}.part').exists(),
        isFalse,
      );
    });

    test('refuses a host that is not GitHub before any request', () async {
      final _ChunkedClient client = _ChunkedClient(
        zipBytes(8),
        status: 200,
        chunkSize: 4,
      );
      final UpdateDownloader downloader = UpdateDownloader(httpClient: client);

      final DownloadResult result = await downloader.download(
        release: releaseFor(Uri.parse('https://evil.example/mellow.apk')),
        directory: temp,
        freeBytes: 1024 * 1024 * 1024,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure, DownloadFailure.untrustedHost);
      expect(result.message, contains('не на GitHub'));
      expect(client.requests, isEmpty);
    });

    test('does not start when free space is below file plus reserve', () async {
      final _ChunkedClient client = _ChunkedClient(
        zipBytes(8),
        status: 200,
        chunkSize: 4,
      );
      final UpdateDownloader downloader = UpdateDownloader(httpClient: client);

      final DownloadResult result = await downloader.download(
        release: releaseFor(
          Uri.parse('https://github.com/x/mellow-debug.apk'),
          size: 200 * 1024 * 1024,
        ),
        directory: temp,
        freeBytes: 200 * 1024 * 1024,
      );

      expect(result.failure, DownloadFailure.noSpace);
      expect(result.message, contains('места'));
      expect(client.requests, isEmpty);
    });

    test('a short body is rejected as corrupt and leaves no file', () async {
      final UpdateDownloader downloader = UpdateDownloader(
        httpClient: fakeServer(body: zipBytes(4)),
      );

      final DownloadResult result = await downloader.download(
        release: releaseFor(
          Uri.parse('https://github.com/x/mellow-debug.apk'),
          size: 100,
        ),
        directory: temp,
        freeBytes: 1024 * 1024 * 1024,
      );

      expect(result.failure, DownloadFailure.corrupt);
      expect(result.message, contains('повреждён'));
      expect(temp.listSync(), isEmpty);
    });

    test('an HTML error page of the right size is still rejected', () async {
      final List<int> html = '<?xml version="1.0"?>not a zip'.codeUnits;
      final UpdateDownloader downloader = UpdateDownloader(
        httpClient: fakeServer(body: html, chunkSize: html.length),
      );

      final DownloadResult result = await downloader.download(
        release: releaseFor(
          Uri.parse('https://github.com/x/mellow-debug.apk'),
          size: html.length,
        ),
        directory: temp,
        freeBytes: 1024 * 1024 * 1024,
      );

      expect(result.failure, DownloadFailure.corrupt);
      expect(temp.listSync(), isEmpty);
    });

    test('a 404 is reported as a network problem', () async {
      final UpdateDownloader downloader = UpdateDownloader(
        httpClient: fakeServer(body: zipBytes(8), status: 404),
      );

      final DownloadResult result = await downloader.download(
        release: releaseFor(Uri.parse('https://github.com/x/mellow-debug.apk')),
        directory: temp,
        freeBytes: 1024 * 1024 * 1024,
      );

      expect(result.failure, DownloadFailure.network);
      expect(result.message, contains('прервана'));
    });

    test('cancel stops the transfer and deletes the part file', () async {
      final Completer<void> cancel = Completer<void>();
      final UpdateDownloader downloader = UpdateDownloader(
        httpClient: fakeServer(body: zipBytes(64), chunkSize: 8),
      );

      final Future<DownloadResult> pending = downloader.download(
        release: releaseFor(
          Uri.parse('https://github.com/x/mellow-debug.apk'),
          size: 64,
        ),
        directory: temp,
        freeBytes: 1024 * 1024 * 1024,
        cancel: cancel.future,
      );
      cancel.complete();

      final DownloadResult result = await pending;
      expect(result.cancelled, isTrue);
      expect(result.message, 'Загрузка отменена');
      expect(temp.listSync(), isEmpty);
    });
  });
}
