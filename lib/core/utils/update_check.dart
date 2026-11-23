import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where this build comes from and where newer ones can be found.
///
/// Supplied at build time so the repository carries no hard-coded account:
///
/// ```bash
/// flutter build apk --debug \
///   --dart-define=MELLOW_UPDATE_REPO=DippyDingo/MELLOW \
///   --dart-define=MELLOW_BUILD_SHA=abc1234
/// ```
abstract final class UpdateChannel {
  static const String repository = String.fromEnvironment('MELLOW_UPDATE_REPO');
  static const String buildSha = String.fromEnvironment('MELLOW_BUILD_SHA');

  /// True when this build knows where to look for updates.
  static bool get isConfigured => repository.isNotEmpty;

  /// Page with the CI runs that carry the downloadable APK.
  static String get actionsUrl =>
      'https://github.com/$repository/actions/workflows/build-apk.yml';
}

/// Result of asking GitHub for the newest build of a branch.
class UpdateStatus {
  const UpdateStatus({
    required this.currentSha,
    this.latestSha,
    this.publishedAt,
    this.error,
  });

  final String currentSha;
  final String? latestSha;
  final DateTime? publishedAt;

  /// Human-readable reason the check could not run; never a raw exception.
  final String? error;

  bool get isNewer =>
      latestSha != null &&
      currentSha.isNotEmpty &&
      !latestSha!.startsWith(currentSha) &&
      !currentSha.startsWith(latestSha!);
}

/// Asks GitHub whether a newer build exists.
///
/// Informational only: the app never downloads or installs anything by itself.
/// A debug build has no update mechanism it could safely use, so the screen
/// only tells the user where the file is.
class UpdateChecker {
  UpdateChecker({
    http.Client? httpClient,
    String? repository,
    String? currentSha,
    this.timeout = const Duration(seconds: 10),
  })  : _http = httpClient ?? http.Client(),
        _repository = repository ?? UpdateChannel.repository,
        _currentSha = currentSha ?? UpdateChannel.buildSha;

  final http.Client _http;
  final Duration timeout;

  /// `owner/repo`; injectable so the check is testable without a real build.
  final String _repository;
  final String _currentSha;

  Future<UpdateStatus> check({String branch = 'main'}) async {
    if (_repository.isEmpty) {
      return UpdateStatus(
        currentSha: _currentSha,
        error: 'Канал обновлений не настроен в этой сборке',
      );
    }

    final uri = Uri.https(
      'api.github.com',
      '/repos/$_repository/commits',
      <String, String>{'sha': branch, 'per_page': '1'},
    );

    try {
      final response = await _http.get(
        uri,
        headers: const <String, String>{'Accept': 'application/vnd.github+json'},
      ).timeout(timeout);

      if (response.statusCode != 200) {
        return UpdateStatus(
          currentSha: _currentSha,
          error: 'GitHub ответил ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) {
        return UpdateStatus(
          currentSha: _currentSha,
          error: 'Не удалось прочитать список сборок',
        );
      }

      final first = decoded.first;
      if (first is! Map<String, dynamic>) {
        return UpdateStatus(
          currentSha: _currentSha,
          error: 'Не удалось прочитать список сборок',
        );
      }

      return UpdateStatus(
        currentSha: _currentSha,
        latestSha: first['sha'] as String?,
        publishedAt: _commitDate(first['commit']),
      );
    } on Exception {
      return UpdateStatus(
        currentSha: _currentSha,
        error: 'Нет связи с GitHub',
      );
    }
  }

  static DateTime? _commitDate(Object? commit) {
    if (commit is! Map<String, dynamic>) return null;
    final committer = commit['committer'];
    if (committer is! Map<String, dynamic>) return null;
    final raw = committer['date'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  void close() => _http.close();
}
