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

  /// Hosts a download may touch, checked again after every redirect.
  ///
  /// `github.com` answers a release download with a 302 to a CDN; those CDN
  /// hosts are part of the same delivery, not a substitution, so they are
  /// allowed by name instead of trusting any `Location` header.
  static const Set<String> downloadHosts = <String>{
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
  };

  /// True when this build knows where to look for updates.
  static bool get isConfigured => repository.isNotEmpty;

  /// Page with the CI runs that carry the downloadable APK.
  static String get actionsUrl =>
      'https://github.com/$repository/actions/workflows/build-apk.yml';

  /// Page listing every published build, used when the check cannot run.
  static String get releasesUrl => 'https://github.com/$repository/releases';
}

/// One published build: what it is, where its APK lives, what changed.
class UpdateRelease {
  const UpdateRelease({
    required this.tag,
    required this.sha,
    required this.downloadUrl,
    required this.sizeBytes,
    this.title,
    this.notes = '',
    this.publishedAt,
  });

  /// Release tag, `build-<sha7>`.
  final String tag;

  /// Commit the APK was built from, lower-case hex.
  final String sha;

  /// Direct link to the `.apk` asset.
  final Uri downloadUrl;

  /// Size GitHub reports for the asset, used to verify the download.
  final int sizeBytes;

  /// Human title, e.g. «Сборка 6807756».
  final String? title;

  /// Release notes as written by CI (Markdown, shown as plain text).
  final String? notes;

  final DateTime? publishedAt;

  /// Size in whole megabytes, for a label a person can read.
  int get sizeMb => (sizeBytes / (1024 * 1024)).round();

  /// `build-6807756` → `6807756`; anything else → the tag as-is.
  String get shortSha => tag.startsWith('build-') ? tag.substring(6) : tag;
}

/// Result of asking GitHub for the newest build of the channel.
class UpdateStatus {
  const UpdateStatus({
    required this.currentSha,
    this.release,
    this.error,
    this.usedFallback = false,
  });

  final String currentSha;

  /// The newest build the channel offers, when one was found.
  final UpdateRelease? release;

  /// Human-readable reason the check could not run; never a raw exception.
  final String? error;

  /// True when the release list was unusable and commits were used instead:
  /// the user can then only be sent to the releases page, not downloaded to.
  final bool usedFallback;

  String? get latestSha => release?.sha;

  DateTime? get publishedAt => release?.publishedAt;

  /// True when a newer build exists *and* it can be downloaded from here.
  bool get isNewer {
    final remote = release?.sha;
    if (remote == null) return false;
    return isNewerThan(currentSha, remote);
  }

  /// True when the channel answered but offered no usable APK, so the app can
  /// only point at the releases page.
  bool get canOnlyOpenPage => release == null && error == null;

  /// Compares two short or full commit ids by prefix.
  ///
  /// Equal ids and ids that are prefixes of each other count as the same
  /// build: `build-abc1234` and an `abc1234…` build sha are one commit.
  static bool isNewerThan(String current, String remote) {
    if (current.isEmpty || remote.isEmpty) return false;
    final String a = current.toLowerCase();
    final String b = remote.toLowerCase();
    return !b.startsWith(a) && !a.startsWith(b);
  }
}

/// Asks GitHub whether a newer build exists, and where to get it.
///
/// Reads the release list rather than `/releases/latest`: the latter answers
/// 404 whenever the newest release is a draft or a pre-release, and it once
/// pointed at an older build than the channel actually had. The list is
/// explicit about order, so it cannot silently go backwards.
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

  static const String _apiHost = 'api.github.com';
  static const int _assetLimit = 10;

  Future<UpdateStatus> check({String branch = 'main'}) async {
    if (_repository.isEmpty) {
      return UpdateStatus(
        currentSha: _currentSha,
        error: 'Канал обновлений не настроен в этой сборке',
      );
    }

    final Uri uri = Uri.https(
      _apiHost,
      '/repos/$_repository/releases',
      <String, String>{'per_page': '$_assetLimit'},
    );

    final http.Response response;
    try {
      response = await _http.get(
        uri,
        headers: const <String, String>{'Accept': 'application/vnd.github+json'},
      ).timeout(timeout);
    } on Exception {
      return UpdateStatus(currentSha: _currentSha, error: 'Нет связи с GitHub');
    }

    if (response.statusCode == 403) {
      return UpdateStatus(
        currentSha: _currentSha,
        error: 'Слишком много проверок, попробуйте позже',
      );
    }
    if (response.statusCode != 200) {
      return UpdateStatus(
        currentSha: _currentSha,
        error: 'GitHub ответил ${response.statusCode}',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return UpdateStatus(
        currentSha: _currentSha,
        error: 'Не удалось прочитать список сборок',
      );
    }
    if (decoded is! List) {
      return UpdateStatus(
        currentSha: _currentSha,
        error: 'Не удалось прочитать список сборок',
      );
    }

    final UpdateRelease? newest = _newestRelease(decoded);
    if (newest == null) {
      // The channel exists but offers nothing installable; fall back so the
      // user is still told a build exists and can open the releases page.
      return _checkCommits(branch: branch);
    }

    return UpdateStatus(currentSha: _currentSha, release: newest);
  }

  /// Picks the newest release that is not a draft and carries an APK.
  ///
  /// Sorted by `created_at` explicitly instead of trusting the order GitHub
  /// happens to return, because that order is what once made
  /// `/releases/latest` point at an older build.
  static UpdateRelease? _newestRelease(List<dynamic> releases) {
    final List<UpdateRelease> parsed = <UpdateRelease>[];
    for (final Object? raw in releases) {
      if (raw is! Map<String, dynamic>) continue;
      final UpdateRelease? release = _parseRelease(raw);
      if (release != null) parsed.add(release);
    }
    if (parsed.isEmpty) return null;
    parsed.sort((UpdateRelease a, UpdateRelease b) {
      final DateTime x = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime y = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return y.compareTo(x);
    });
    return parsed.first;
  }

  static UpdateRelease? _parseRelease(Map<String, dynamic> raw) {
    if (raw['draft'] == true) return null;

    final Object? tag = raw['tag_name'];
    if (tag is! String || !tag.startsWith('build-')) return null;
    final String sha = tag.substring(6);
    if (sha.length < 7) return null;

    final Object? assets = raw['assets'];
    if (assets is! List) return null;

    for (final Object? asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final Object? name = asset['name'];
      final Object? url = asset['browser_download_url'];
      final Object? size = asset['size'];
      if (name is! String || !name.endsWith('-debug.apk')) continue;
      if (url is! String || size is! int) continue;
      final Uri? parsed = Uri.tryParse(url);
      if (parsed == null || parsed.scheme != 'https') continue;
      if (!UpdateChannel.downloadHosts.contains(parsed.host)) continue;

      return UpdateRelease(
        tag: tag,
        sha: sha.toLowerCase(),
        downloadUrl: parsed,
        sizeBytes: size,
        title: raw['name'] is String ? raw['name'] as String : null,
        notes: raw['body'] is String ? raw['body'] as String : '',
        publishedAt: _date(raw['published_at']) ?? _date(raw['created_at']),
      );
    }
    return null;
  }

  /// Last resort from the ТЗ §3.2: newest commit of the branch.
  ///
  /// Gives no download link, only proof that a newer build was pushed, so the
  /// UI must send the user to the releases page instead of offering an install.
  Future<UpdateStatus> _checkCommits({required String branch}) async {
    final Uri uri = Uri.https(
      _apiHost,
      '/repos/$_repository/commits',
      <String, String>{'sha': branch, 'per_page': '1'},
    );

    try {
      final http.Response response = await _http.get(
        uri,
        headers: const <String, String>{'Accept': 'application/vnd.github+json'},
      ).timeout(timeout);
      if (response.statusCode == 200) {
        final Object? decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
          final Map<String, dynamic> first = decoded.first as Map<String, dynamic>;
          final Object? sha = first['sha'];
          if (sha is String) {
            return UpdateStatus(
              currentSha: _currentSha,
              usedFallback: true,
              error: UpdateStatus.isNewerThan(_currentSha, sha)
                  ? 'Есть более свежая сборка, но файл пока недоступен: '
                      'откройте страницу релизов'
                  : null,
            );
          }
        }
      }
    } on Exception {
      // Fall through: the caller shows the generic "could not check" state.
    }

    return UpdateStatus(
      currentSha: _currentSha,
      usedFallback: true,
      error: 'Не удалось проверить обновления',
    );
  }

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  void close() => _http.close();
}
