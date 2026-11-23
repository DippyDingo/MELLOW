import 'package:mellow/core/utils/email_address.dart';

/// A thematic conversation ("thread") between the user and a set of people.
///
/// Grouping rules (spec 2.3) are implemented by the conversation engine, not by
/// this entity. A thread is identified locally by [id]; provider thread ids are
/// stored in [providerThreadId] and are only a hint.
class MessageThread {
  const MessageThread({
    required this.id,
    required this.accountId,
    required this.subject,
    required this.participants,
    required this.updatedAt,
    this.lastMessagePreview = '',
    this.unreadCount = 0,
    this.isPinned = false,
    this.isArchived = false,
    this.isMuted = false,
    this.contactId,
    this.providerThreadId,
  });

  final String id;

  /// Account the thread was synced from. Threads are account-scoped so that the
  /// same person mailing two mailboxes produces two conversations.
  final String accountId;

  final String subject;
  final List<EmailAddress> participants;

  /// Timestamp of the newest message (used for sorting).
  final DateTime updatedAt;
  final String lastMessagePreview;
  final int unreadCount;

  final bool isPinned;
  final bool isArchived;
  final bool isMuted;

  /// Set when all participants resolve to a single known contact.
  final String? contactId;

  /// Gmail threadId / Graph conversationId when the provider supports threads.
  final String? providerThreadId;

  bool get hasUnread => unreadCount > 0;

  /// Address shown in the conversation list: the first participant that is not
  /// one of the user's own accounts. Resolution happens in the application
  /// layer; this is the raw fallback.
  String get primaryParticipantAddress =>
      participants.isEmpty ? '' : participants.first.address;

  MessageThread copyWith({
    String? subject,
    List<EmailAddress>? participants,
    DateTime? updatedAt,
    String? lastMessagePreview,
    int? unreadCount,
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
    String? contactId,
    String? providerThreadId,
  }) {
    return MessageThread(
      id: id,
      accountId: accountId,
      subject: subject ?? this.subject,
      participants: participants ?? this.participants,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isMuted: isMuted ?? this.isMuted,
      contactId: contactId ?? this.contactId,
      providerThreadId: providerThreadId ?? this.providerThreadId,
    );
  }

  @override
  String toString() => 'MessageThread($id, "$subject", ${participants.length})';
}
