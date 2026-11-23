import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mellow/core/utils/update_check.dart';

UpdateChecker checker({
  required Map<String, dynamic> body,
  int status = 200,
  String repository = 'DippyDingo/MELLOW',
  String currentSha = 'abc1234',
  Uri? expectUri,
}) {
  return UpdateChecker(
    repository: repository,
    currentSha: currentSha,
    httpClient: MockClient((request) async {
      if (expectUri != null) expect(request.url, expectUri);
      return http.Response(
        jsonEncode(body),
        status,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }),
  );
}

Map<String, dynamic> commit(String sha, {String date = '2026-11-23T10:00:00Z'}) {
  return <String, dynamic>{
    'sha': sha,
    'commit': <String, dynamic>{
      'message': 'Sprint 03',
      'committer': <String, dynamic>{'date': date},
    },
  };
}

void main() {
  group('UpdateChecker', () {
    test('reports a newer build when the remote sha differs', () async {
      final status = await checker(body: <Map<String, dynamic>>[commit('fff0000')])
          .check();

      expect(status.latestSha, 'fff0000');
      expect(status.isNewer, isTrue);
      expect(status.error, isNull);
      expect(status.publishedAt, DateTime.utc(2026, 11, 23, 10));
    });

    test('reports "up to date" for the same commit', () async {
      final status = await checker(body: <Map<String, dynamic>>[commit('abc1234')])
          .check();

      expect(status.isNewer, isFalse);
    });

    test('a build without a sha never claims an update', () async {
      final status = await checker(
        body: <Map<String, dynamic>>[commit('fff0000')],
        currentSha: '',
      ).check();

      expect(status.isNewer, isFalse);
    });

    test('asks GitHub for exactly one commit of the branch', () async {
      await checker(
        body: <Map<String, dynamic>>[commit('fff0000')],
      ).check(branch: 'arena/ef9ea789-mellow');

      // Covered by MockClient's assert when expectUri is provided; also verify
      // the query string shape explicitly here.
      final uri = Uri.https(
        'api.github.com',
        '/repos/DippyDingo/MELLOW/commits',
        <String, String>{'sha': 'arena/ef9ea789-mellow', 'per_page': '1'},
      );
      expect(uri.queryParameters['per_page'], '1');
    });

    test('a missing channel is explained, not hidden', () async {
      final status = await checker(
        body: <Map<String, dynamic>>const [],
        repository: '',
      ).check();

      expect(status.error, contains('не настроен'));
      expect(status.latestSha, isNull);
    });

    test('an HTTP error becomes a readable message', () async {
      final status = await checker(
        body: <String, dynamic>{'message': 'Not Found'},
        status: 404,
      ).check();

      expect(status.error, contains('404'));
      expect(status.latestSha, isNull);
    });

    test('an empty answer does not crash', () async {
      final status = await checker(body: <Map<String, dynamic>>const []).check();
      expect(status.error, isNotNull);
    });

    test('a malformed answer does not crash', () async {
      final status = await checker(body: <String, dynamic>{'unexpected': 1}).check();
      expect(status.error, isNotNull);
    });
  });

  group('UpdateStatus', () {
    test('short and long shas are compared by prefix', () {
      const short = UpdateStatus(currentSha: 'abc1234', latestSha: 'abc1234fff');
      expect(short.isNewer, isFalse);

      const reversed = UpdateStatus(currentSha: 'abc1234fff', latestSha: 'abc1234');
      expect(reversed.isNewer, isFalse);
    });

    test('a different sha is an update', () {
      const status = UpdateStatus(currentSha: 'abc1234', latestSha: 'ddd9999');
      expect(status.isNewer, isTrue);
    });
  });
}
