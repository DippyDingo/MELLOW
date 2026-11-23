import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:uuid/uuid.dart';

/// Decides which conversation a fetched message belongs to (spec 2.3).
///
/// Strategy, in priority order:
/// 1. **Provider thread id** — authoritative when the service exposes it.
/// 2. **`In-Reply-To` / `References`** — the RFC headers that actually link
///    messages, independent of the provider.
/// 3. **Provider thread id of a message in the same References chain.**
/// 4. A new conversation.
///
/// Subject alone is *never* a grouping signal: two unrelated conversations can
/// share a subject, and merging them would be user-visible data corruption.
class ConversationRouter {
  ConversationRouter({required this.accountId, Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final String accountId;
  final Uuid _uuid;

  /// Normalises an RFC subject: strips any number of `Re:`, `Fwd:`, `Ответ:`
  /// prefixes and collapses whitespace.
  static String normalizeSubject(String subject) {
    var value = subject.trim();
    final prefix = RegExp(
      r'^((re|fw|fwd|aw|sv|отв|ответ|пересл)\s*(\[\d+\])?\s*:\s*)',
      caseSensitive: false,
    );
    while (prefix.hasMatch(value)) {
      value = value.replaceFirst(prefix, '').trim();
    }
    return value.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// True when the subject looks like a reply or a forward.
  static bool isReplySubject(String subject) =>
      RegExp(r'^\s*(re|aw|отв|ответ)\s*:', caseSensitive: false)
          .hasMatch(subject);

  /// Routes a message when the caller has already resolved the lookups.
  ///
  /// Kept next to [normalizeSubject] so the priority order lives in one file
  /// and is unit-testable without a database.
  String resolve({
    required Message message,
    required String? providerThreadId,
    required String? knownConversationOfProviderThread,
    required String? Function(String messageIdHeader) conversationOfMessage,
  }) {
    if (providerThreadId != null && providerThreadId.isNotEmpty) {
      final known = knownConversationOfProviderThread;
      if (known != null) return known;
    }

    for (final parent in <String>[
      if (message.inReplyTo != null) message.inReplyTo!,
      ...message.references.reversed,
    ]) {
      final known = conversationOfMessage(parent);
      if (known != null) return known;
    }

    return _uuid.v4();
  }

  /// Builds a fresh conversation for [message].
  MessageThread newThread({
    required Message message,
    required String conversationId,
    required String? providerThreadId,
    required String? contactId,
    DateTime? now,
  }) {
    final participants = <EmailAddress>[];
    final seen = <String>{};
    for (final address in <EmailAddress>[message.from, ...message.to, ...message.cc]) {
      final normalized = normalizeEmail(address.address);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      participants.add(EmailAddress(address: normalized, displayName: address.displayName));
    }

    return MessageThread(
      id: conversationId,
      accountId: accountId,
      subject: normalizeSubject(message.subject),
      participants: participants,
      updatedAt: message.sentAt,
      lastMessagePreview: message.preview,
      unreadCount: message.isRead || message.isOutgoing ? 0 : 1,
      providerThreadId: providerThreadId,
      contactId: contactId,
    );
  }

  /// Refreshes the denormalised fields after a new message lands.
  ///
  /// Only advances `updated_at` — the repository recomputes unread counters and
  /// the preview from the stored rows, so this cannot drift.
  MessageThread touch(MessageThread thread, Message message) {
    final participants = <EmailAddress>[...thread.participants];
    final known = participants.map((a) => a.address).toSet();
    for (final address in <EmailAddress>[message.from, ...message.to, ...message.cc]) {
      final normalized = normalizeEmail(address.address);
      if (normalized.isEmpty || !known.add(normalized)) continue;
      participants.add(EmailAddress(address: normalized, displayName: address.displayName));
    }

    return thread.copyWith(
      participants: participants,
      updatedAt: message.sentAt.isAfter(thread.updatedAt)
          ? message.sentAt
          : thread.updatedAt,
      providerThreadId: thread.providerThreadId,
    );
  }
}
