import 'package:mellow/domain/entities/account.dart';

/// Persistence contract for connected mailboxes.
///
/// Implementations live in `lib/data/repositories`. The domain never sees Drift
/// types, SQL or JSON.
abstract interface class AccountRepository {
  /// Watches all accounts ordered primary first, then by creation date.
  Stream<List<Account>> watchAccounts();

  Future<List<Account>> getAccounts();

  Future<Account?> getAccount(String id);

  /// Account new messages are sent from.
  Future<Account?> getPrimaryAccount();

  Future<Account> saveAccount(Account account);

  Future<void> updateStatus(String id, AccountStatus status, {String? error});

  Future<void> updateLastSync(String id, DateTime at);

  /// Makes [id] primary and demotes every other account in one transaction.
  Future<void> setPrimary(String id);

  /// Removes the account row and all data that belongs to it locally.
  ///
  /// Nothing is deleted on the mail server — this is a local forget operation.
  Future<void> deleteAccount(String id);
}
