import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/repositories/thread_repository.dart';
import 'package:uuid/uuid.dart';

/// A message the user is still writing.
///
/// A draft is a normal stored message with `isDraft: true` and the
/// `DeliveryStatus.draft` state, so it survives an app restart, shows up in its
/// conversation and can be reopened exactly where it was left. Nothing about it
/// is sent anywhere until the user presses «Отправить».
class ComposerDraft {
  const ComposerDraft({
    required this.id,
    required this.threadId,
    required this.accountId,
    required this.to,
    required this.cc,
    required this.subject,
    required this.bodyText,
    required this.updatedAt,
    this.replyToMessageId,
  });

  /// Local message id; also the id the composer edits.
  final String id;
  final String threadId;
  final String accountId;

  final List<String> to;
  final List<String> cc;
  final String subject;
  final String bodyText;
  final DateTime updatedAt;

  /// The message this draft answers, if any.
  final String? replyToMessageId;

  /// One line for the conversation list.
  String get preview {
    if (bodyText.trim().isNotEmpty) return bodyText;
    return subject;
  }
}

/// Where a draft lives: always a message row, never a side table.
///
/// Keeping drafts in `messages` means the conversation list, the card preview
/// and the unread counter all work without a second source of truth, and a
/// draft cannot outlive its conversation.
class DraftStore {
  DraftStore(this._threads);

  final ThreadRepository _threads;
  final Uuid _uuid = const Uuid();

  /// Creates a draft for [account], optionally inside an existing thread.
  ///
  /// The conversation is created only when the first keystroke happens, so an
  /// empty composer never leaves an empty «(без темы)» card behind.
  Future<ComposerDraft?> save({
    required Account account,
    required List<String> to,
    required List<String> cc,
    required String subject,
    required String bodyText,
    String? threadId,
    String? replyToMessageId,
    String? existingDraftId,
  }) async {
    final isEmpty = to.isEmpty &&
        subject.trim().isEmpty &&
        bodyText.trim().isEmpty;
    // An empty composer is not a draft: saving it would litter the list with
    // blank cards every time someone opens the screen and changes their mind.
    if (isEmpty && existingDraftId == null) return null;

    final now = DateTime.now();
    final id = existingDraftId ?? _uuid.v4();
    final targetThread = threadId ?? 'draft-$id';

    final message = Message(
      id: id,
      threadId: targetThread,
      accountId: account.id,
      from: EmailAddress(address: account.email),
      to: to.map((address) => EmailAddress(address: address)).toList(),
      cc: cc.map((address) => EmailAddress(address: address)).toList(),
      subject: subject,
      bodyText: bodyText,
      inReplyTo: null,
      sentAt: now,
      isRead: true,
      isDraft: true,
      // A draft was written here, so it is «outgoing» in the sense that it is
      // not a received message; the unread counter ignores drafts explicitly.
      isOutgoing: false,
      deliveryStatus: DeliveryStatus.draft,
    );

    final stored = await _threads.upsertMessage(message);

    // The conversation has to exist for the card to appear. A brand-new draft
    // gets its own; a reply reuses the conversation it answers.
    final thread = await _threads.getThread(stored.threadId);
    if (thread == null) {
      await _threads.createThreadForOutgoing(
        message: stored,
        subject: subject.trim().isEmpty ? '(без темы)' : subject,
      );
    }

    return ComposerDraft(
      id: stored.id,
      threadId: stored.threadId,
      accountId: account.id,
      to: to,
      cc: cc,
      subject: subject,
      bodyText: bodyText,
      updatedAt: now,
      replyToMessageId: replyToMessageId,
    );
  }

  /// Removes a draft after it was sent or explicitly discarded.
  Future<void> delete(String draftId) async {
    final message = await _threads.getMessage(draftId);
    if (message == null || !message.isDraft) return;
    // `setDeliveryStatus` would keep the row; a discarded draft must go away.
    await _threads.deleteMessage(draftId, threadId: message.threadId);
  }

  Future<ComposerDraft?> load(String draftId) async {
    final message = await _threads.getMessage(draftId);
    if (message == null || !message.isDraft) return null;
    return ComposerDraft(
      id: message.id,
      threadId: message.threadId,
      accountId: message.accountId,
      to: message.to.map((address) => address.address).toList(),
      cc: message.cc.map((address) => address.address).toList(),
      subject: message.subject,
      bodyText: message.bodyText,
      updatedAt: message.sentAt,
      replyToMessageId: message.inReplyTo,
    );
  }

  /// True when [threadId] holds a draft, used by the conversation card.
  Future<bool> threadHasDraft(String threadId) async {
    final messages = await _threads.getMessages(threadId);
    return messages.any((message) => message.isDraft);
  }
}

final draftStoreProvider = Provider<DraftStore>((ref) {
  return DraftStore(ref.watch(threadRepositoryProvider));
});
