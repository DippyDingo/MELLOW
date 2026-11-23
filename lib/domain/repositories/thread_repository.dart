import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/message_thread.dart';

/// Filter for the conversation list. Focus Mode (spec 2.6) is expressed here.
class ThreadFilter {
  const ThreadFilter({
    this.accountId,
    this.includeArchived = false,
    this.unreadOnly = false,
    this.favoritesOnly = false,
    this.contactId,
    this.query,
  });

  final String? accountId;
  final bool includeArchived;
  final bool unreadOnly;
  final bool favoritesOnly;
  final String? contactId;
  final String? query;

  ThreadFilter copyWith({
    String? accountId,
    bool? includeArchived,
    bool? unreadOnly,
    bool? favoritesOnly,
    String? contactId,
    String? query,
  }) {
    return ThreadFilter(
      accountId: accountId ?? this.accountId,
      includeArchived: includeArchived ?? this.includeArchived,
      unreadOnly: unreadOnly ?? this.unreadOnly,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      contactId: contactId ?? this.contactId,
      query: query ?? this.query,
    );
  }
}

/// Persistence contract for conversations and their messages.
abstract interface class ThreadRepository {
  /// Watches conversations newest-first, honouring [filter].
  Stream<List<MessageThread>> watchThreads([ThreadFilter filter = const ThreadFilter()]);

  Future<List<MessageThread>> getThreads([ThreadFilter filter = const ThreadFilter()]);

  Future<MessageThread?> getThread(String id);

  /// Watches the messages of one thread, oldest first.
  Stream<List<Message>> watchMessages(String threadId);

  Future<List<Message>> getMessages(String threadId);

  Future<Message?> getMessage(String id);

  Future<MessageThread> saveThread(MessageThread thread);

  /// Inserts or updates a message, deduplicating on
  /// (account, provider message id) and on the RFC `Message-ID` header.
  ///
  /// Returns the stored message. A repeated sync with the same data must not
  /// create a second row.
  Future<Message> upsertMessage(Message message);

  Future<void> setRead(String messageId, {required bool read});

  Future<void> setThreadPinned(String threadId, {required bool pinned});

  Future<void> setThreadArchived(String threadId, {required bool archived});

  Future<void> setThreadMuted(String threadId, {required bool muted});

  /// Removes a thread from the local view only (server copy is untouched).
  Future<void> hideThread(String threadId);

  /// Number of unread messages across all accounts.
  Stream<int> watchUnreadCount();
}
