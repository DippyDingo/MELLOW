import 'package:drift/drift.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/domain/entities/account.dart';

/// Translates between the `accounts` table and [Account].
abstract final class AccountMapper {
  static Account toEntity(AccountRow row) {
    return Account(
      id: row.id,
      email: row.email,
      provider: _providerFromName(row.provider),
      status: _statusFromName(row.status),
      displayName: row.displayName,
      providerAccountId: row.providerAccountId,
      isPrimary: row.isPrimary,
      lastSyncAt: row.lastSyncAt,
      lastError: row.lastError,
      createdAt: row.createdAt,
    );
  }

  static AccountsCompanion toCompanion(Account account) {
    return AccountsCompanion.insert(
      id: account.id,
      email: normalizeEmail(account.email),
      provider: account.provider.name,
      status: account.status.name,
      displayName: Value(account.displayName),
      providerAccountId: Value(account.providerAccountId),
      isPrimary: Value(account.isPrimary),
      lastSyncAt: Value(account.lastSyncAt),
      lastError: Value(account.lastError),
      createdAt: Value(account.createdAt ?? DateTime.now()),
    );
  }

  static MailProviderKind _providerFromName(String name) {
    return MailProviderKind.values.firstWhere(
      (kind) => kind.name == name,
      orElse: () => MailProviderKind.imap,
    );
  }

  static AccountStatus _statusFromName(String name) {
    return AccountStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => AccountStatus.error,
    );
  }
}
