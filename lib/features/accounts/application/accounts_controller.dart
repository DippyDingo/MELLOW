import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/domain/entities/account.dart';

/// Live list of connected accounts.
final accountsProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(accountRepositoryProvider).watchAccounts();
});

/// The account new mail is sent from (falls back to the first account).
final primaryAccountProvider = Provider<Account?>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
  if (accounts.isEmpty) return null;
  return accounts.firstWhere(
    (account) => account.isPrimary,
    orElse: () => accounts.first,
  );
});
