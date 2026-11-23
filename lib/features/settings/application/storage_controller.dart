import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/core/errors/app_exception.dart';
import 'package:mellow/domain/entities/account.dart';

/// What the local database currently holds, in numbers a person can judge.
class StorageSummary {
  const StorageSummary({
    required this.threads,
    required this.messages,
    required this.contacts,
    required this.accounts,
    this.databaseBytes,
    this.fileBytes,
  });

  final int threads;
  final int messages;
  final int contacts;
  final int accounts;

  /// Size of `mellow.sqlite` on disk, when the platform reports it.
  final int? databaseBytes;

  /// Size of everything Mellow keeps in its app-support directory.
  final int? fileBytes;

  bool get isEmpty => threads == 0 && messages == 0 && contacts == 0;

  /// Short human size: «812 КБ», «3,4 МБ», «—».
  static String formatBytes(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes Б';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} КБ';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1).replaceAll('.', ',')} МБ';
    return '${(mb / 1024).toStringAsFixed(2).replaceAll('.', ',')} ГБ';
  }
}

/// Reads and clears local storage.
///
/// Deletion is deliberately local: `clearAll` never talks to a mail server, so
/// removing data on the phone cannot remove anything from the mailbox itself.
class StorageController extends AsyncNotifier<StorageSummary> {
  @override
  Future<StorageSummary> build() async {
    return _measure();
  }

  Future<StorageSummary> _measure() async {
    final db = ref.watch(appDatabaseProvider);
    final threads = await ref.watch(threadRepositoryProvider).getThreads();
    final contacts = await ref.watch(contactRepositoryProvider).search('');
    final accounts = await ref.watch(accountRepositoryProvider).getAccounts();

    var messages = 0;
    for (final thread in threads) {
      messages += await db.countMessages(thread.id);
    }

    final usage = await db.usage();
    return StorageSummary(
      threads: threads.length,
      messages: messages,
      contacts: contacts.length,
      accounts: accounts.length,
      databaseBytes: usage.databaseBytes,
      fileBytes: usage.fileBytes,
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue<StorageSummary>.loading();
    state = await AsyncValue.guard(_measure);
  }

  /// Deletes every synced message, thread and contact for [accountId].
  ///
  /// The account row is kept so the user can sync again; credentials are kept
  /// too — disconnecting an account is a separate, explicit action.
  Future<void> clearAccount(Account account) async {
    state = const AsyncValue<StorageSummary>.loading();
    try {
      await ref.read(threadRepositoryProvider).deleteAccountThreads(account.id);
      await ref.read(accountRepositoryProvider).updateStatus(
            account.id,
            AccountStatus.connected,
          );
      await refresh();
    } on AppException catch (error, stackTrace) {
      state = AsyncValue<StorageSummary>.error(error, stackTrace);
    }
  }

  /// Deletes all synced mail of every account (settings and accounts stay).
  Future<void> clearAll() async {
    state = const AsyncValue<StorageSummary>.loading();
    try {
      final accounts = await ref.read(accountRepositoryProvider).getAccounts();
      for (final account in accounts) {
        await ref.read(threadRepositoryProvider).deleteAccountThreads(account.id);
      }
      await refresh();
    } on AppException catch (error, stackTrace) {
      state = AsyncValue<StorageSummary>.error(error, stackTrace);
    }
  }
}

final storageControllerProvider =
    AsyncNotifierProvider<StorageController, StorageSummary>(StorageController.new);
