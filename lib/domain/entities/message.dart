import 'package:mellow/core/utils/email_address.dart';

/// A single message inside a [MessageThread].
///
/// [id] is Mellow's UUID. [providerId] is whatever the mail service calls the
/// message (Gmail id, IMAP UID, Graph id) and is only used by adapters.
class Message {
  const Message({
    required this.id,
    required this.threadId,
    required this.accountId,
    required this.from,
    required this.to,
    required this.sentAt,
    this.cc = const <EmailAddress>[],
    this.bcc = const <EmailAddress>[],
    this.subject = '',
    this.bodyText = '',
    this.bodyHtml,
    this.messageIdHeader,
    this.inReplyTo,
    this.references = const <String>[],
    this.providerId,
    this.isRead = false,
    this.isDraft = false,
    this.isOutgoing = false,
    this.deliveryStatus = DeliveryStatus.received,
    this.hasAttachments = false,
  });

  final String id;
  final String threadId;
  final String accountId;

  final EmailAddress from;
  final List<EmailAddress> to;
  final List<EmailAddress> cc;
  final List<EmailAddress> bcc;

  final String subject;
  final String bodyText;

  /// Raw HTML from the sender. Must only be rendered through the sanitiser.
  final String? bodyHtml;

  /// RFC 5322 `Message-ID` (with angle brackets, as received).
  final String? messageIdHeader;
  final String? inReplyTo;
  final List<String> references;

  final DateTime sentAt;

  final String? providerId;
  final bool isRead;
  final bool isDraft;

  /// True when the message was sent from one of the user's accounts.
  final bool isOutgoing;

  final DeliveryStatus deliveryStatus;
  final bool hasAttachments;

  /// Short preview for list rows. Never shows HTML markup.
  String get preview {
    final normalized = bodyText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return '';
    return normalized.length <= 140 ? normalized : '${normalized.substring(0, 140)}…';
  }

  Message copyWith({
    String? subject,
    String? bodyText,
    String? bodyHtml,
    bool? isRead,
    bool? isOutgoing,
    DeliveryStatus? deliveryStatus,
    String? providerId,
    bool? hasAttachments,
  }) {
    return Message(
      id: id,
      threadId: threadId,
      accountId: accountId,
      from: from,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject ?? this.subject,
      bodyText: bodyText ?? this.bodyText,
      bodyHtml: bodyHtml ?? this.bodyHtml,
      messageIdHeader: messageIdHeader,
      inReplyTo: inReplyTo,
      references: references,
      sentAt: sentAt,
      providerId: providerId ?? this.providerId,
      isRead: isRead ?? this.isRead,
      isDraft: isDraft,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      hasAttachments: hasAttachments ?? this.hasAttachments,
    );
  }

  @override
  String toString() => 'Message($id, from=${from.address}, at=$sentAt)';
}

/// Delivery state of an outgoing message (section 2.4 of the spec).
///
/// `sent` means "the mail server accepted the message", not "the recipient
/// read it". Email provides no delivery or read guarantee.
enum DeliveryStatus {
  /// Incoming message already delivered by the provider.
  received,
  draft,
  queued,
  sending,
  sent,
  failed;

  bool get isOutgoing =>
      this == DeliveryStatus.queued ||
      this == DeliveryStatus.sending ||
      this == DeliveryStatus.sent;

  bool get isTerminal =>
      this == DeliveryStatus.sent ||
      this == DeliveryStatus.failed ||
      this == DeliveryStatus.received;
}
