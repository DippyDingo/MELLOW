import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mellow/core/utils/update_check.dart';

/// Records which URLs a check touched, so tests can assert both the request
/// and the "no fallback happened" behaviour.
class _Recorder {
  final List<Uri> urls = <Uri>[];

  UpdateChecker checker({
    required Object body,
    int status = 200,
    String repository = 'DippyDingo/MELLOW',
    String currentSha = 'abc1234',
    Object? fallbackBody,
    int fallbackStatus = 200,
  }) {
    return UpdateChecker(
      repository: repository,
      currentSha: currentSha,
      httpClient: MockClient((http.Request request) async {
        urls.add(request.url);
        final bool isCommits = request.url.path.endsWith('/commits');
        return http.Response(
          jsonEncode(isCommits && fallbackBody != null ? fallbackBody : body),
          isCommits && fallbackBody != null ? fallbackStatus : status,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );
  }
}

const String _apkUrl =
    'https://github.com/DippyDingo/MELLOW/releases/download/build-fff0000/'
    'mellow-fff0000-debug.apk';

/// A release exactly as the API returns it, trimmed to the fields used.
Map<String, dynamic> release({
  String tag = 'build-fff0000',
  String createdAt = '2026-11-23T10:00:00Z',
  bool draft = false,
  bool prerelease = false,
  List<Map<String, dynamic>>? assets,
  String body = 'Сборка fff0000\nИзменения: см. историю коммитов.',
}) {
  return <String, dynamic>{
    'tag_name': tag,
    'name': 'Сборка ${tag.replaceFirst('build-', '')}',
    'body': body,
    'draft': draft,
    'prerelease': prerelease,
    'created_at': createdAt,
    'published_at': createdAt,
    'assets': assets ?? <Map<String, dynamic>>[apk(tag)],
  };
}

Map<String, dynamic> apk(
  String tag, {
  String? name,
  int size = 202591784,
  String? url,
}) {
  final String sha = tag.replaceFirst('build-', '');
  return <String, dynamic>{
    'name': name ?? 'mellow-$sha-debug.apk',
    'size': size,
    'browser_download_url': url ??
        'https://github.com/DippyDingo/MELLOW/releases/download/$tag/'
            'mellow-$sha-debug.apk',
  };
}

void main() {
  group('UpdateChecker: release list', () {
    test('reads the newest release and its APK link', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[release()],
      ).check();

      expect(status.error, isNull);
      expect(status.isNewer, isTrue);
      expect(status.release?.tag, 'build-fff0000');
      expect(status.release?.sha, 'fff0000');
      expect(status.release?.downloadUrl.toString(), _apkUrl);
      expect(status.release?.sizeBytes, 202591784);
      expect(status.release?.sizeMb, 193);
      expect(status.publishedAt, DateTime.utc(2026, 11, 23, 10));
      expect(status.usedFallback, isFalse);
    });

    test('asks for the release list, not /releases/latest', () async {
      final _Recorder recorder = _Recorder();
      await recorder.checker(body: <Map<String, dynamic>>[release()]).check();

      expect(recorder.urls, hasLength(1));
      expect(recorder.urls.single.host, 'api.github.com');
      expect(recorder.urls.single.path, '/repos/DippyDingo/MELLOW/releases');
      expect(recorder.urls.single.queryParameters['per_page'], '10');
    });

    test('picks by created_at, the order the channel is built on', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[
          // Published later but created earlier: /releases/latest picked this
          // one on the live repo, which is exactly what must not happen.
          <String, dynamic>{
            ...release(tag: 'build-9ca485a', createdAt: '2026-11-23T21:17:24Z'),
            'published_at': '2026-11-23T21:40:00Z',
          },
          <String, dynamic>{
            ...release(tag: 'build-45163e0', createdAt: '2026-11-23T21:26:46Z'),
            'published_at': '2026-11-23T21:32:14Z',
          },
        ],
      ).check();

      expect(status.release?.tag, 'build-45163e0');
    });

    test('picks the newest even when GitHub returns the oldest first', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[
          release(tag: 'build-9ca485a', createdAt: '2026-11-23T21:17:24Z'),
          release(tag: 'build-45163e0', createdAt: '2026-11-23T21:26:46Z'),
          release(tag: 'build-6807756', createdAt: '2026-11-23T21:48:48Z'),
        ],
      ).check();

      expect(status.release?.tag, 'build-6807756');
    });

    test('skips drafts', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[
          release(tag: 'build-aaaa111', draft: true, createdAt: '2026-11-24T00:00:00Z'),
          release(tag: 'build-bbbb222', createdAt: '2026-11-23T00:00:00Z'),
        ],
      ).check();

      expect(status.release?.tag, 'build-bbbb222');
    });

    test('a pre-release is still a valid build', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[release(prerelease: true)],
      ).check();

      expect(status.release?.tag, 'build-fff0000');
      expect(status.isNewer, isTrue);
    });

    test('ignores tags that are not build-<sha>', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[
          release(tag: 'v1.0.0', createdAt: '2026-11-24T00:00:00Z'),
          release(tag: 'build-ffffffffffff', createdAt: '2026-11-23T00:00:00Z'),
        ],
      ).check();

      expect(status.release?.tag, 'build-ffffffffffff');
      expect(status.release?.sha, 'ffffffffffff');
    });

    test('ignores a release whose only asset is not an APK', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[
          release(
            tag: 'build-ccc3333',
            createdAt: '2026-11-24T00:00:00Z',
            assets: <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'checksums.txt',
                'size': 12,
                'browser_download_url': 'https://github.com/x/checksums.txt',
              },
            ],
          ),
          release(tag: 'build-ddd4444', createdAt: '2026-11-23T00:00:00Z'),
        ],
      ).check();

      expect(status.release?.tag, 'build-ddd4444');
    });

    test('refuses an APK link that is not https or not a GitHub host', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[
          release(
            tag: 'build-eee5555',
            createdAt: '2026-11-24T00:00:00Z',
            assets: <Map<String, dynamic>>[
              apk('build-eee5555', url: 'https://evil.example/mellow.apk'),
            ],
          ),
          release(
            tag: 'build-fff6666',
            createdAt: '2026-11-24T00:00:00Z',
            assets: <Map<String, dynamic>>[
              apk('build-fff6666', url: 'http://github.com/mellow.apk'),
            ],
          ),
          release(tag: 'build-aaa7777', createdAt: '2026-11-23T00:00:00Z'),
        ],
      ).check();

      expect(status.release?.tag, 'build-aaa7777');
    });

    test('a missing sha inside the tag is rejected', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[release(tag: 'build-abc')],
      ).check();

      // Nothing usable → fallback path explains itself instead of pretending.
      expect(status.release, isNull);
      expect(status.error, isNotNull);
    });
  });

  group('UpdateChecker: up to date', () {
    test('the release of this very build is not an update', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[release()],
        currentSha: 'fff0000',
      ).check();

      expect(status.release?.tag, 'build-fff0000');
      expect(status.isNewer, isFalse);
    });

    test('a short sha that prefixes the release sha is the same build', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[release(tag: 'build-fff0000abc')],
        currentSha: 'fff0000',
      ).check();

      expect(status.isNewer, isFalse);
    });

    test('a build without a sha never claims an update', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <Map<String, dynamic>>[release()],
        currentSha: '',
      ).check();

      expect(status.isNewer, isFalse);
    });
  });

  group('UpdateChecker: errors', () {
    test('a missing channel is explained, not hidden', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: const <Map<String, dynamic>>[],
        repository: '',
      ).check();

      expect(status.error, contains('не настроен'));
      expect(status.release, isNull);
      // No request at all: an unconfigured build stays silent on the network.
      expect(recorder.urls, isEmpty);
    });

    test('403 is reported as a rate limit, not as "no updates"', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <String, dynamic>{'message': 'rate limit'},
        status: 403,
      ).check();

      expect(status.error, contains('Слишком много проверок'));
      expect(status.isNewer, isFalse);
    });

    test('5xx becomes a readable message', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <String, dynamic>{'message': 'Oops'},
        status: 502,
      ).check();

      expect(status.error, contains('502'));
    });

    test('a malformed answer does not crash', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: <String, dynamic>{'unexpected': 1},
      ).check();

      expect(status.error, isNotNull);
      expect(status.release, isNull);
    });
  });

  group('UpdateChecker: fallback to commits (§3.2)', () {
    test('empty release list asks for commits and offers no download', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: const <Map<String, dynamic>>[],
        fallbackBody: <Map<String, dynamic>>[
          <String, dynamic>{'sha': 'fff0000999'},
        ],
      ).check();

      expect(recorder.urls, hasLength(2));
      expect(recorder.urls.last.path, endsWith('/commits'));
      expect(status.release, isNull);
      expect(status.usedFallback, isTrue);
      expect(status.isNewer, isFalse);
      expect(status.error, contains('страницу релизов'));
    });

    test('fallback that matches the current build says nothing is wrong', () async {
      final _Recorder recorder = _Recorder();
      final UpdateStatus status = await recorder.checker(
        body: const <Map<String, dynamic>>[],
        fallbackBody: <Map<String, dynamic>>[
          <String, dynamic>{'sha': 'abc1234fff'},
        ],
      ).check();

      expect(status.usedFallback, isTrue);
      expect(status.error, isNull);
      expect(status.canOnlyOpenPage, isTrue);
    });
  });

  group('UpdateStatus', () {
    UpdateStatus withSha(String current, String remote) {
      return UpdateStatus(
        currentSha: current,
        release: UpdateRelease(
          tag: 'build-$remote',
          sha: remote,
          downloadUrl: Uri.parse(_apkUrl),
          sizeBytes: 1,
        ),
      );
    }

    test('short and long shas are compared by prefix', () {
      expect(withSha('abc1234', 'abc1234fff').isNewer, isFalse);
      expect(withSha('abc1234fff', 'abc1234').isNewer, isFalse);
    });

    test('a different sha is an update', () {
      expect(withSha('abc1234', 'ddd9999').isNewer, isTrue);
    });

    test('no release means no update', () {
      const UpdateStatus status = UpdateStatus(currentSha: 'abc1234');
      expect(status.isNewer, isFalse);
      expect(status.canOnlyOpenPage, isTrue);
    });
  });
}
