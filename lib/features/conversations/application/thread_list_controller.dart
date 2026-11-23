import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:mellow/domain/repositories/thread_repository.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';

/// Search text of the conversation screen.
final threadSearchQueryProvider = StateProvider<String>((ref) => '');

/// Account currently being viewed; `null` means "all accounts".
final selectedAccountIdProvider = StateProvider<String?>((ref) => null);

/// Builds the repository filter from search, account selection and Focus Mode.
final threadFilterProvider = Provider<ThreadFilter>((ref) {
  final query = ref.watch(threadSearchQueryProvider);
  final accountId = ref.watch(selectedAccountIdProvider);
  final settings = ref.watch(appSettingsProvider);
  final focusActive = settings.focusModeEnabled;
  return ThreadFilter(
    accountId: accountId,
    query: query.trim().isEmpty ? null : query.trim(),
    favoritesOnly: focusActive && settings.focusFavoritesOnly,
    unreadOnly: focusActive && settings.focusUnreadOnly,
  );
});

/// Live conversation list.
final threadListProvider = StreamProvider<List<MessageThread>>((ref) {
  final filter = ref.watch(threadFilterProvider);
  return ref.watch(threadRepositoryProvider).watchThreads(filter);
});

/// Unread badge for the bottom navigation.
final unreadCountProvider = StreamProvider<int>((ref) {
  return ref.watch(threadRepositoryProvider).watchUnreadCount();
});

/// Sorts pinned threads first, then by recency (repository already does this;
/// re-applied here so the UI stays correct with hand-made thread objects).
List<MessageThread> sortForDisplay(List<MessageThread> threads) {
  final sorted = List<MessageThread>.of(threads);
  sorted.sort((a, b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  });
  return sorted;
}
