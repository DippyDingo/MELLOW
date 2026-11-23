import 'package:mellow/providers/contracts/mail_provider.dart';

/// Optional protocol extension for providers that can sync incrementally.
///
/// Kept separate from [MailProvider] so adapters that cannot do incremental
/// sync (e.g. a plain IMAP server without UIDVALIDITY) are not forced to
/// pretend. The sync engine checks `provider is IncrementalMailProvider`.
abstract interface class IncrementalMailProvider implements MailProvider {
  /// Current cursor to persist after a successful sync (Gmail `historyId`,
  /// IMAP `UIDVALIDITY:UIDNEXT`, Graph `deltaLink`).
  Future<String?> currentCursor();

  /// Ids changed since [cursor].
  ///
  /// Returns `null` when the provider no longer knows that cursor — the caller
  /// must run a full reconciliation instead of trusting it.
  Future<List<String>?> changedMessageIds(String cursor);
}
