import 'package:drift/drift.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/mappers/account_mapper.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/repositories/account_repository.dart';

/// Drift-backed [AccountRepository].
class DriftAccountRepository implements AccountRepository {
  DriftAccountRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Account>> watchAccounts() {
    final query = _db.select(_db.accounts)
      ..orderBy([
        (t) => OrderingTerm(expression: t.isPrimary, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt),
      ]);
    return query.watch().map(
          (rows) => rows.map(AccountMapper.toEntity).toList(growable: false),
        );
  }

  @override
  Future<List<Account>> getAccounts() async {
    final rows = await (_db.select(_db.accounts)
          ..orderBy([
            (t) => OrderingTerm(expression: t.isPrimary, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.createdAt),
          ]))
        .get();
    return rows.map(AccountMapper.toEntity).toList(growable: false);
  }

  @override
  Future<Account?> getAccount(String id) async {
    final row = await (_db.select(_db.accounts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : AccountMapper.toEntity(row);
  }

  @override
  Future<Account?> getPrimaryAccount() async {
    final row = await (_db.select(_db.accounts)
          ..where((t) => t.isPrimary.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (row != null) return AccountMapper.toEntity(row);
    final all = await getAccounts();
    return all.isEmpty ? null : all.first;
  }

  @override
  Future<Account> saveAccount(Account account) async {
    await _db.into(_db.accounts).insertOnConflictUpdate(
          AccountMapper.toCompanion(account),
        );
    if (account.isPrimary) await setPrimary(account.id);
    final saved = await getAccount(account.id);
    return saved ?? account;
  }

  @override
  Future<void> updateStatus(
    String id,
    AccountStatus status, {
    String? error,
  }) async {
    await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        status: Value(status.name),
        lastError: Value(error),
      ),
    );
  }

  @override
  Future<void> updateLastSync(String id, DateTime at) async {
    await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(lastSyncAt: Value(at)),
    );
  }

  @override
  Future<void> setPrimary(String id) async {
    await _db.transaction(() async {
      await _db.update(_db.accounts).write(
            const AccountsCompanion(isPrimary: Value(false)),
          );
      await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
        const AccountsCompanion(isPrimary: Value(true)),
      );
    });
  }

  @override
  Future<void> deleteAccount(String id) async {
    await _db.transaction(() async {
      final threadIds = await (_db.selectOnly(_db.conversations)
            ..addColumns([_db.conversations.id])
            ..where(_db.conversations.accountId.equals(id)))
          .map((row) => row.read(_db.conversations.id))
          .get();

      for (final threadId in threadIds.whereType<String>()) {
        final messageIds = await (_db.selectOnly(_db.messages)
              ..addColumns([_db.messages.id])
              ..where(_db.messages.conversationId.equals(threadId)))
            .map((row) => row.read(_db.messages.id))
            .get();
        for (final messageId in messageIds.whereType<String>()) {
          await (_db.delete(_db.attachments)
                ..where((t) => t.messageId.equals(messageId)))
              .go();
        }
        await (_db.delete(_db.messages)
              ..where((t) => t.conversationId.equals(threadId)))
            .go();
        await (_db.delete(_db.conversationParticipants)
              ..where((t) => t.conversationId.equals(threadId)))
            .go();
        await (_db.delete(_db.conversations)..where((t) => t.id.equals(threadId)))
            .go();
      }

      await (_db.delete(_db.syncStates)..where((t) => t.accountId.equals(id))).go();
      await (_db.delete(_db.providerSettings)..where((t) => t.accountId.equals(id)))
          .go();
      await (_db.delete(_db.accounts)..where((t) => t.id.equals(id))).go();
    });
  }
}
