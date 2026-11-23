import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/attachment.dart';
import 'package:mellow/domain/entities/message.dart';

/// What a concrete mail service can actually do.
///
/// Capabilities are advertised by adapters and consumed by the UI/engines.
/// They describe protocol possibilities only — `supportsReadReceipts` does not
/// mean a read receipt is ever guaranteed by ordinary email.
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.supportsThreads,
    required this.supportsPush,
    required this.supportsSearch,
    required this.supportsLabels,
    required this.supportsReadReceipts,
    required this.supportsAttachments,
    this.supportsIncrementalSync = false,
    this.maxAttachmentBytes,
  });

  /// Provider exposes native thread/conversation ids.
  final bool supportsThreads;

  /// Provider can notify about new mail without polling (e.g. Gmail Watch).
  /// Requires extra infrastructure; never assumed to be available offline.
  final bool supportsPush;

  /// Server-side search is available.
  final bool supportsSearch;

  /// Labels/folders are supported.
  final bool supportsLabels;

  final bool supportsReadReceipts;
  final bool supportsAttachments;

  /// Provider can return only changes since a cursor (Gmail history, IMAP UID).
  final bool supportsIncrementalSync;

  /// Optional hard limit enforced by the service.
  final int? maxAttachmentBytes;

  static const ProviderCapabilities none = ProviderCapabilities(
    supportsThreads: false,
    supportsPush: false,
    supportsSearch: false,
    supportsLabels: false,
    supportsReadReceipts: false,
    supportsAttachments: false,
  );
}

/// A page of messages plus the cursor needed to fetch the next/older page.
///
/// [cursor] is opaque to callers and is persisted in `sync_state`.
class MessagePage {
  const MessagePage({
    required this.messages,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<Message> messages;
  final String? nextCursor;
  final bool hasMore;
}

/// A message the user is about to send. Kept separate from [Message] because it
/// has no provider id yet and its identity is created locally.
class OutgoingMessage {
  const OutgoingMessage({
    required this.from,
    required this.to,
    required this.subject,
    required this.bodyText,
    this.bodyHtml,
    this.cc = const [],
    this.bcc = const [],
    this.inReplyTo,
    this.references = const [],
    this.attachments = const [],
  });

  final String from;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String bodyText;
  final String? bodyHtml;

  /// RFC 5322 `In-Reply-To` header of the answered message.
  final String? inReplyTo;

  /// Full `References` chain, oldest first.
  final List<String> references;

  final List<Attachment> attachments;
}

/// The only way Mellow talks to a mail service.
///
/// Adapters (Gmail REST, IMAP/SMTP, Microsoft Graph) implement this interface;
/// domain and application code depend on it, never on a concrete adapter.
///
/// Contract rules:
/// * Every method throws [MailProviderException] (or [AccountAuthException])
///   on failure and never leaks provider-specific types.
/// * Lists may be empty but are never null.
abstract interface class MailProvider {
  /// Stable identifier used for persistence and logs, e.g. `gmail`.
  String get id;

  ProviderCapabilities get capabilities;

  /// Validates that the stored credentials/tokens still work.
  Future<void> connect(Account account);

  /// Releases sockets / cancels background watchers. Must not delete data.
  Future<void> disconnect();

  /// Fetches one page of messages, newest first.
  Future<MessagePage> fetchMessages({
    String? cursor,
    int limit = 50,
    String? folder,
  });

  /// Fetches a single message by provider id.
  Future<Message?> getMessage(String providerMessageId);

  Future<void> sendMessage(OutgoingMessage message);

  /// Sends [reply] and links it to [providerMessageId] via headers.
  Future<void> replyToMessage(String providerMessageId, OutgoingMessage reply);

  Future<void> markAsRead(String providerMessageId, {bool read = true});

  Future<void> archiveMessage(String providerMessageId);

  /// Moves a message to trash on the server. Never called implicitly.
  Future<void> deleteMessage(String providerMessageId);

  /// Downloads attachment bytes; implementations may cache.
  Future<List<int>> downloadAttachment(Attachment attachment);

  /// Uploads a local file and returns the provider handle for [OutgoingMessage].
  Future<Attachment> uploadAttachment(String messageId, String filePath);
}

/// Base class for adapters that only implement a subset of the contract.
///
/// Every capability the adapter lacks must throw [UnsupportedException] rather
/// than silently doing nothing.
abstract class BaseMailProvider implements MailProvider {
  const BaseMailProvider();

  @override
  Future<List<int>> downloadAttachment(Attachment attachment) =>
      throw UnimplementedError('downloadAttachment is not implemented for $id');

  @override
  Future<Attachment> uploadAttachment(String messageId, String filePath) =>
      throw UnimplementedError('uploadAttachment is not implemented for $id');

  @override
  Future<void> archiveMessage(String providerMessageId) =>
      throw UnimplementedError('archiveMessage is not implemented for $id');
}
