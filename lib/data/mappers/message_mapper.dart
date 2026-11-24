import 'package:drift/drift.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/message_thread.dart';

/// Translates between message/thread rows and domain entities.
abstract final class MessageMapper {
  static Message toEntity(MessageRow row) {
    return Message(
      id: row.id,
      threadId: row.conversationId,
      accountId: row.accountId,
      from: EmailAddress(
        address: row.fromAddress,
        displayName: row.fromName,
      ),
      to: _parseList(row.toAddresses),
      cc: _parseList(row.ccAddresses),
      bcc: _parseList(row.bccAddresses),
      subject: row.subject,
      bodyText: row.bodyText,
      bodyHtml: row.bodyHtml,
      messageIdHeader: row.messageIdHeader,
      inReplyTo: row.inReplyTo,
      references: row.references.isEmpty
          ? const <String>[]
          : row.references.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      sentAt: row.sentAt,
      providerId: row.providerMessageId,
      isRead: row.isRead,
      isDraft: row.isDraft,
      isOutgoing: row.isOutgoing,
      deliveryStatus: _statusFromName(row.deliveryStatus),
      hasAttachments: row.hasAttachments,
    );
  }

  static MessagesCompanion toCompanion(Message message) {
    return MessagesCompanion.insert(
      id: message.id,
      conversationId: message.threadId,
      accountId: message.accountId,
      providerMessageId: Value(message.providerId),
      messageIdHeader: Value(message.messageIdHeader),
      subject: Value(message.subject),
      fromAddress: message.from.address,
      fromName: Value(message.from.displayName),
      toAddresses: Value(_joinList(message.to)),
      ccAddresses: Value(_joinList(message.cc)),
      bccAddresses: Value(_joinList(message.bcc)),
      bodyText: Value(message.bodyText),
      bodyHtml: Value(message.bodyHtml),
      inReplyTo: Value(message.inReplyTo),
      references: Value(message.references.join(',')),
      sentAt: message.sentAt,
      isRead: Value(message.isRead),
      isOutgoing: Value(message.isOutgoing),
      isDraft: Value(message.isDraft),
      hasAttachments: Value(message.hasAttachments),
      deliveryStatus: Value(message.deliveryStatus.name),
    );
  }

  /// [displayNames] maps a normalised address to the person's name, so a
  /// conversation can show (and be searched by) "Мария Соколова" rather than
  /// only her address.
  static MessageThread threadToEntity(
    ConversationRow row,
    List<ParticipantRow> participants, {
    Map<String, String> displayNames = const <String, String>{},
  }) {
    return MessageThread(
      id: row.id,
      accountId: row.accountId,
      subject: row.subject,
      participants: participants
          .map(
            (p) => EmailAddress(
              address: p.email,
              displayName: displayNames[p.email.toLowerCase()],
            ),
          )
          .toList(growable: false),
      updatedAt: row.updatedAt,
      lastMessagePreview: row.lastMessagePreview,
      unreadCount: row.unreadCount,
      isPinned: row.isPinned,
      isArchived: row.isArchived,
      isMuted: row.isMuted,
      contactId: row.contactId,
      providerThreadId: row.providerThreadId,
    );
  }

  static ConversationsCompanion threadToCompanion(MessageThread thread) {
    return ConversationsCompanion.insert(
      id: thread.id,
      accountId: thread.accountId,
      contactId: Value(thread.contactId),
      subject: Value(thread.subject),
      providerThreadId: Value(thread.providerThreadId),
      updatedAt: Value(thread.updatedAt),
      lastMessagePreview: Value(thread.lastMessagePreview),
      unreadCount: Value(thread.unreadCount),
      isPinned: Value(thread.isPinned),
      isArchived: Value(thread.isArchived),
      isMuted: Value(thread.isMuted),
    );
  }

  /// Address lists are stored comma separated (addresses cannot contain `,`).
  static String _joinList(List<EmailAddress> addresses) =>
      addresses.map((a) => a.address).join(',');

  static List<EmailAddress> _parseList(String raw) {
    if (raw.trim().isEmpty) return const <EmailAddress>[];
    return raw
        .split(',')
        .map((part) => parseEmailAddress(part))
        .whereType<EmailAddress>()
        .toList(growable: false);
  }

  static DeliveryStatus _statusFromName(String name) {
    return DeliveryStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => DeliveryStatus.received,
    );
  }
}
