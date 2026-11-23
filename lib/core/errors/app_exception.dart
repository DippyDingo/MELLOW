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
final class MailProviderException extends AppException {
  const MailProviderException(super.message, {super.cause, super.stackTrace});
}

/// Invalid user input (email address, subject limits, ...).
final class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// Provider or feature is not available in the current build/version.
final class UnsupportedException extends AppException {
  const UnsupportedException(super.message);
}
