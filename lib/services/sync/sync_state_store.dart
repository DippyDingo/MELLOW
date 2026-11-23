import 'package:drift/drift.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/domain/entities/account.dart';

/// Persistence for `sync_state` rows.
///
/// Kept out of the sync engine so the engine can be tested with a fake store
/// and so cursor semantics live in exactly one place.
class SyncStateStore {
  SyncStateStore(this._db);

  final AppDatabase _db;

  Future<SyncStateRow?> read(String accountId) {
    return (_db.select(_db.syncStates)
          ..where((t) => t.accountId.equals(accountId)))
        .getSingleOrNull();
  }

  /// Saves the cursor **after** a batch has been committed.
  ///
  /// [fullSync] marks the completion of a reconciliation, which resets the
  /// failure counter.
  Future<void> saveCursor({
    required String accountId,
    required String? cursor,
    required bool fullSync,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    // An incremental pass must not erase the date of the last reconciliation.
    final previous = await read(accountId);
    await _db.into(_db.syncStates).insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            accountId: accountId,
            cursor: Value(cursor),
            lastSyncAt: Value(timestamp),
            lastFullSyncAt: Value(
              fullSync ? timestamp : previous?.lastFullSyncAt,
            ),
            consecutiveFailures: const Value(0),
            lastError: const Value(null),
          ),
        );
  }

  /// Records a failure without losing the last good cursor.
  Future<void> recordFailure(String accountId, String message) async {
    final existing = await read(accountId);
    final failures = (existing?.consecutiveFailures ?? 0) + 1;
    await _db.into(_db.syncStates).insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            accountId: accountId,
            cursor: Value(existing?.cursor),
            lastSyncAt: Value(existing?.lastSyncAt),
            consecutiveFailures: Value(failures),
            lastError: Value(message),
          ),
        );
  }

  Future<void> clear(String accountId) async {
    await (_db.delete(_db.syncStates)..where((t) => t.accountId.equals(accountId)))
        .go();
  }

  /// Reflects a successful sync on the account row itself.
  Future<void> markAccountSynced(String accountId, DateTime at) async {
    await (_db.update(_db.accounts)..where((t) => t.id.equals(accountId))).write(
      AccountsCompanion(
        lastSyncAt: Value(at),
        status: Value(AccountStatus.connected.name),
        lastError: const Value(null),
      ),
    );
  }

  /// Reflects a failed sync on the account row (used by the accounts screen).
  Future<void> markAccountFailed(
    String accountId,
    AccountStatus status,
    String message,
  ) async {
    await (_db.update(_db.accounts)..where((t) => t.id.equals(accountId))).write(
      AccountsCompanion(
        status: Value(status.name),
        lastError: Value(message),
      ),
    );
  }
}
