/// Immutable product-wide constants.
abstract final class AppConstants {
  /// How many messages a single provider page returns by default.
  static const int defaultPageSize = 50;

  /// Hard ceiling for a single outgoing message (most providers accept ~25 MB).
  static const int maxAttachmentBytes = 20 * 1024 * 1024;

  /// Local cache budget before the app asks the user to free space.
  static const int localCacheBudgetBytes = 512 * 1024 * 1024;

  /// Delay before the first retry of a failed network operation.
  static const Duration retryBaseDelay = Duration(seconds: 2);

  /// Maximum number of retries for a transient provider error.
  static const int maxRetries = 3;

  /// App-wide route paths, kept in one place so navigation stays testable.
  static const String routeConversations = '/conversations';
  static const String routeContacts = '/contacts';
  static const String routeFavorites = '/favorites';
  static const String routeSettings = '/settings';
}
