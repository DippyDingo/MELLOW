/// Build-time configuration.
///
/// Everything here is supplied with `--dart-define`, so no client id or secret
/// ever lands in the repository. Values that are missing keep the app fully
/// usable: the affected provider simply reports that it is not configured.
final class AppConfig {
  const AppConfig({
    required this.googleClientId,
    required this.microsoftClientId,
    String? googleRedirectUri,
  }) : _googleRedirectUri = googleRedirectUri;

  final String googleClientId;
  final String microsoftClientId;

  final String? _googleRedirectUri;

  /// Reads configuration from the compile-time environment.
  ///
  /// ```bash
  /// flutter run \
  ///   --dart-define=GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com \
  ///   --dart-define=GOOGLE_REDIRECT_URI=com.googleusercontent.apps.xxxx:/oauth2redirect
  /// ```
  ///
  /// `GOOGLE_REDIRECT_URI` is optional: for an Android/iOS OAuth client Google
  /// expects the reversed client id, so it is derived when omitted.
  static const AppConfig fromEnvironment = AppConfig(
    googleClientId: String.fromEnvironment('GOOGLE_CLIENT_ID'),
    googleRedirectUri: String.fromEnvironment('GOOGLE_REDIRECT_URI'),
    microsoftClientId: String.fromEnvironment('MICROSOFT_CLIENT_ID'),
  );

  /// Redirect URI registered for the mobile OAuth client.
  ///
  /// An explicit `GOOGLE_REDIRECT_URI` wins; otherwise the standard reversed
  /// client id is used, which is what Google's "installed app" flow requires.
  String get googleRedirectUri {
    final override = _googleRedirectUri;
    if (override != null && override.isNotEmpty) return override;
    if (googleClientId.isEmpty) return '';
    return '${reversedGoogleClientScheme(googleClientId)}:/oauth2redirect';
  }

  /// `123-abc.apps.googleusercontent.com` -> `com.googleusercontent.apps.123-abc`.
  ///
  /// Exposed because the platform manifest must register the same scheme; the
  /// value is documented in `docs/VERIFY.md`.
  static String reversedGoogleClientScheme(String clientId) {
    const suffix = '.apps.googleusercontent.com';
    final bare = clientId.endsWith(suffix)
        ? clientId.substring(0, clientId.length - suffix.length)
        : clientId;
    return 'com.googleusercontent.apps.$bare';
  }

  /// True when Gmail can actually be connected on this build.
  bool get isGoogleConfigured =>
      googleClientId.isNotEmpty && googleRedirectUri.isNotEmpty;

  /// True when Outlook can actually be connected on this build.
  bool get isMicrosoftConfigured => microsoftClientId.isNotEmpty;

  static const AppConfig empty = AppConfig(
    googleClientId: '',
    microsoftClientId: '',
  );
}
