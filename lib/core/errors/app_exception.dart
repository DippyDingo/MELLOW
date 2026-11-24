/// Base error type for every failure Mellow surfaces to the user.
///
/// Rules of the house:
/// * UI never catches raw platform/plugin exceptions — repositories translate
///   them into one of these types.
/// * Messages here are developer-facing and must never contain credentials,
///   tokens or full message bodies.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause, this.stackTrace});

  /// Short, safe description. Never contains secrets.
  final String message;

  /// Original error, kept for logging/diagnostics inside the app only.
  final Object? cause;

  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// Local database failed (open, migration, query).
final class StorageException extends AppException {
  const StorageException(super.message, {super.cause, super.stackTrace});
}

/// Account setup/authorisation problem: expired token, revoked access, etc.
final class AccountAuthException extends AppException {
  const AccountAuthException(super.message, {super.cause, super.stackTrace});
}

/// Remote mail provider refused or failed the operation.
///
/// [statusCode] keeps the HTTP status when there was one, so callers can make
/// protocol decisions (Gmail's 404 on an outdated `historyId`, 429 for rate
/// limits) without subclassing the hierarchy — the hierarchy stays `sealed` and
/// every adapter shares one error vocabulary.
final class MailProviderException extends AppException {
  const MailProviderException(
    super.message, {
    this.statusCode,
    super.cause,
    super.stackTrace,
  });

  /// HTTP status of the failed request, when applicable.
  final int? statusCode;

  /// Worth retrying later with backoff (rate limit or server-side outage).
  bool get isTransient {
    final code = statusCode;
    if (code == null) return false;
    return code == 429 || code >= 500;
  }

  /// The provider no longer knows the cursor we hold.
  bool get isCursorExpired => statusCode == 404 || statusCode == 410;
}

/// The device could not reach the provider: no network, DNS failure, timeout.
///
/// Kept separate from [MailProviderException] because the reaction differs: a
/// mail that failed to go out because of this is retried by the outbox, while a
/// refusal from the server is shown to the user.
final class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause, super.stackTrace});
}

/// Invalid user input (email address, subject limits, ...).
final class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// Provider or feature is not available in the current build/version.
final class UnsupportedException extends AppException {
  const UnsupportedException(super.message);
}
