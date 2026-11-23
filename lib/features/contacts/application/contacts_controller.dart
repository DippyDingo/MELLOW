import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/domain/entities/contact.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:mellow/domain/repositories/thread_repository.dart';

final contactsSearchQueryProvider = StateProvider<String>((ref) => '');

/// All contacts, live from the database.
final contactsProvider = StreamProvider<List<Contact>>((ref) {
  final query = ref.watch(contactsSearchQueryProvider).trim();
  final repository = ref.watch(contactRepositoryProvider);
  if (query.isEmpty) return repository.watchContacts();
  // Search is a one-shot query; re-run it whenever contacts change.
  return repository
      .watchContacts()
      .asyncMap((_) => repository.search(query));
});

/// Favourites only, for the "Избранное" tab.
///
/// Derived from the all-contacts provider rather than queried again: the tab
/// renders the resolved list, and loading/error stay in the standard
/// `AsyncValue` wrapper where the screen can handle them.
final favoriteContactsProvider = Provider<AsyncValue<List<Contact>>>((ref) {
  return ref
      .watch(contactsProvider)
      .whenData(
        (contacts) => contacts
            .where((contact) => contact.isFavorite)
            .toList(growable: false),
      );
});

/// One contact, resolved lazily for the profile screen.
final contactByIdProvider =
    FutureProvider.family<Contact?, String>((ref, id) async {
  return ref.watch(contactRepositoryProvider).getContact(id);
});

/// Every thread of a person — their full history across conversations.
final contactThreadsProvider =
    FutureProvider.family<List<MessageThread>, String>((ref, contactId) async {
  return ref.watch(threadRepositoryProvider).getThreads(
        ThreadFilter(contactId: contactId),
      );
});
