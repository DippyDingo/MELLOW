import 'dart:convert';

import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/core/utils/html_text.dart';
import 'package:mellow/domain/entities/attachment.dart';
import 'package:mellow/domain/entities/message.dart';

/// Attachment description extracted from a Gmail part tree.
class ParsedAttachment {
  const ParsedAttachment({
    required this.providerId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String providerId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  Attachment toEntity(String messageId) => Attachment(
        id: '$messageId:$providerId',
        messageId: messageId,
        fileName: fileName,
        sizeBytes: sizeBytes,
        mimeType: mimeType,
        providerAttachmentId: providerId,
      );
}

/// Bilingual text extracted from a Gmail payload.
class ParsedBodies {
  const ParsedBodies({required this.text, this.html});

  final String text;
  final String? html;
}

/// Converts Gmail API JSON into Mellow entities.
///
/// This is a pure function set: no HTTP, no database, no logging. That is what
/// makes the tricky parts (MIME trees, base64url, header casing) unit-testable
/// against captured fixtures.
abstract final class GmailMessageParser {
  /// Builds a [Message] from `users.messages.get` (format=full).
  ///
  /// [accountId] and [localId] are supplied by the caller: Gmail ids are never
  /// used as Mellow primary keys.
  ///
  /// [threadId] is the **provider** thread id. It travels inside
  /// `Message.threadId` as a transient placeholder and is replaced with the
  /// local conversation id by `MailSyncService` before the message is stored —
  /// adapters cannot know the local conversation id, and inventing one here
  /// would make conversation routing untestable.
  static Message toMessage(
    Map<String, dynamic> json, {
    required String accountId,
    required String localId,
    required String threadId,
    required String ownAddress,
  }) {
    final payload = _asMap(json['payload']);
    final headers = _headers(payload);

    final from = parseEmailAddress(headers['from'] ?? '') ??
        EmailAddress(address: ownAddress);
    final to = parseAddressList(headers['to'] ?? '');
    final cc = parseAddressList(headers['cc'] ?? '');
    final bcc = parseAddressList(headers['bcc'] ?? '');

    final labelIds = _asStringList(json['labelIds']);
    final internalDate = _asInt(json['internalDate']);
    final sentAt = internalDate == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(internalDate, isUtc: true);

    final bodies = extractBodies(payload);
    final attachments = extractAttachments(payload);

    return Message(
      id: localId,
      threadId: threadId,
      accountId: accountId,
      from: from,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: _decodeHeader(headers['subject'] ?? ''),
      bodyText: bodies.text,
      bodyHtml: bodies.html,
      messageIdHeader: headers['message-id'],
      inReplyTo: headers['in-reply-to'],
      references: _splitReferences(headers['references']),
      sentAt: sentAt,
      providerId: json['id'] as String?,
      isRead: !labelIds.contains(GmailLabelNames.unread),
      isDraft: labelIds.contains(GmailLabelNames.draft),
      isOutgoing: from.address == normalizeEmail(ownAddress) ||
          labelIds.contains(GmailLabelNames.sent),
      deliveryStatus: DeliveryStatus.received,
      hasAttachments: attachments.isNotEmpty,
    );
  }

  /// Walks a MIME tree and returns the best text and HTML bodies.
  ///
  /// Gmail may split a message into `multipart/alternative` (text+html) or
  /// `multipart/mixed` (body+attachments); both are handled by recursion.
  static ParsedBodies extractBodies(Map<String, dynamic>? payload) {
    if (payload == null) return const ParsedBodies(text: '');

    String? text;
    String? html;
    String? htmlFallback;

    void visit(Map<String, dynamic> part) {
      final mimeType = (part['mimeType'] as String? ?? '').toLowerCase();
      final body = _asMap(part['body']);
      final data = body['data'] as String?;

      // The declared charset lives in the part's own Content-Type header. Mail
      // from older Russian clients still arrives as cp1251/koi8-r, and decoding
      // that as UTF-8 would turn the body into replacement characters.
      final charset = _charsetOf(part);

      if (data != null && data.isNotEmpty) {
        if (mimeType == 'text/plain' && text == null) {
          text = _decodeBody(data, charset: charset);
        } else if (mimeType == 'text/html') {
          final decoded = _decodeBody(data, charset: charset);
          if (html == null || decoded.length > html!.length) html = decoded;
        } else if (mimeType.isEmpty && htmlFallback == null) {
          htmlFallback = _decodeBody(data, charset: charset);
        }
      }

      for (final child in _asList(part['parts'])) {
        final map = _asMap(child);
        if (map != null) visit(map);
      }
    }

    visit(payload);

    final resolvedHtml = html ?? htmlFallback;
    return ParsedBodies(
      text: text ?? (resolvedHtml == null ? '' : htmlToPlainText(resolvedHtml)),
      html: resolvedHtml,
    );
  }

  /// Collects real attachments (parts with a filename and an attachment id).
  static List<ParsedAttachment> extractAttachments(Map<String, dynamic>? payload) {
    if (payload == null) return const <ParsedAttachment>[];

    final result = <ParsedAttachment>[];

    void visit(Map<String, dynamic> part) {
      final body = _asMap(part['body']);
      final attachmentId = body?['attachmentId'] as String?;
      final fileName = part['filename'] as String?;
      final mimeType = part['mimeType'] as String? ?? '';

      final isAttachment = attachmentId != null &&
          fileName != null &&
          fileName.isNotEmpty &&
          !mimeType.startsWith('text/');

      if (isAttachment) {
        result.add(
          ParsedAttachment(
            providerId: attachmentId,
            fileName: fileName,
            mimeType: mimeType.isEmpty ? 'application/octet-stream' : mimeType,
            sizeBytes: _asInt(body?['size']) ?? 0,
          ),
        );
      }

      for (final child in _asList(part['parts'])) {
        final map = _asMap(child);
        if (map != null) visit(map);
      }
    }

    visit(payload);
    return List<ParsedAttachment>.unmodifiable(result);
  }

  /// Compact snippet used for the conversation list.
  static String snippetOf(Map<String, dynamic> json) {
    final snippet = json['snippet'] as String? ?? '';
    return _decodeHeader(snippet);
  }

  /// Gmail encodes headers and bodies with RFC 2047 / base64url.
  static String _decodeHeader(String raw) {
    if (raw.isEmpty) return raw;
    var value = raw;

    final encodedWord = RegExp(r'=\?([^?]+)\?([BbQq])\?([^?]*)\?=');
    value = value.replaceAllMapped(encodedWord, (match) {
      final charset = match.group(1) ?? 'utf-8';
      final encoding = (match.group(2) ?? 'b').toUpperCase();
      final payload = match.group(3) ?? '';
      try {
        if (encoding == 'B') {
          return _decodeBytes(base64.decode(base64Url.normalize(payload)), charset);
        }
        final bytes = <int>[];
        for (var i = 0; i < payload.length; i++) {
          if (payload[i] == '_') {
            bytes.add(0x20);
          } else if (payload[i] == '=' && i + 2 < payload.length) {
            bytes.add(int.parse(payload.substring(i + 1, i + 3), radix: 16));
            i += 2;
          } else {
            bytes.add(payload.codeUnitAt(i));
          }
        }
        return _decodeBytes(bytes, charset);
      } catch (_) {
        return match.group(0) ?? '';
      }
    });

    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _decodeBody(String data, {String? charset}) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(data));
      return _decodeBytes(bytes, charset ?? 'utf-8');
    } catch (_) {
      return '';
    }
  }

  /// Extracts `charset=` from a MIME part's `Content-Type` header.
  static String? _charsetOf(Map<String, dynamic> part) {
    for (final header in _asList(part['headers'])) {
      final map = _asMap(header);
      if (map == null) continue;
      final name = (map['name'] as String? ?? '').toLowerCase();
      if (name != 'content-type') continue;
      final value = map['value'] as String? ?? '';
      final match = RegExp(
        r'charset\s*=\s*"?([A-Za-z0-9_\-]+)"?',
        caseSensitive: false,
      ).firstMatch(value);
      return match?.group(1);
    }
    return null;
  }

  static String _decodeBytes(List<int> bytes, String charset) {
    final normalized = charset.toLowerCase().replaceAll('_', '-');
    if (normalized.contains('1251')) {
      return _decodeWindows1251(bytes);
    }
    if (normalized.contains('koi8')) {
      return _decodeKoi8R(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static List<String> _splitReferences(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    return RegExp(r'<[^<>]+>')
        .allMatches(raw)
        .map((match) => match.group(0)!)
        .toList(growable: false);
  }

  static Map<String, String> _headers(Map<String, dynamic>? payload) {
    final result = <String, String>{};
    for (final header in _asList(payload?['headers'])) {
      final map = _asMap(header);
      if (map == null) continue;
      final name = (map['name'] as String?)?.toLowerCase();
      final value = map['value'] as String?;
      if (name == null || value == null) continue;
      result[name] = value;
    }
    return result;
  }
}

/// Gmail label ids used by the parser.
abstract final class GmailLabelNames {
  static const String inbox = 'INBOX';
  static const String sent = 'SENT';
  static const String draft = 'DRAFT';
  static const String unread = 'UNREAD';
  static const String trash = 'TRASH';
}

Map<String, dynamic>? _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

List<Object?> _asList(Object? value) => value is List<Object?> ? value : const [];

List<String> _asStringList(Object? value) =>
    value is List ? value.whereType<String>().toList(growable: false) : const [];

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

/// Windows-1251 decoding (Russian mail still carries it in 2026).
String _decodeWindows1251(List<int> bytes) {
  const high = <int, int>{
    0xA8: 0x0401, // Ё
    0xB8: 0x0451, // ё
    0xAA: 0x0404, // Є
    0xBA: 0x0454, // є
    0xAF: 0x040F, // Ї
    0xBF: 0x045F, // ї
    0xB2: 0x0406, // І
    0xB3: 0x0456, // і
    0xB4: 0x0490, // Ґ
    0xB6: 0x0491, // ґ
    0xB7: 0x0407, // Ї
  };
  const cp1251Range = 0x0410;

  final buffer = StringBuffer();
  for (final byte in bytes) {
    if (byte < 0x80) {
      buffer.writeCharCode(byte);
    } else if (byte >= 0xC0) {
      // А-я map directly onto 0xC0-0xFF.
      buffer.writeCharCode(cp1251Range + (byte - 0xC0));
    } else {
      buffer.writeCharCode(high[byte] ?? 0x002E);
    }
  }
  return buffer.toString();
}

/// KOI8-R decoding (older Russian gateways).
String _decodeKoi8R(List<int> bytes) {
  const table = <int, int>{
    0xC1: 0x0430, 0xC2: 0x0431, 0xD7: 0x0432, 0xC7: 0x0433, 0xC4: 0x0434,
    0xC5: 0x0435, 0xD6: 0x0436, 0xD3: 0x0437, 0xD1: 0x0438, 0xD2: 0x0439,
    0xCB: 0x043A, 0xC9: 0x043B, 0xC8: 0x043C, 0xCD: 0x043D, 0xCE: 0x043E,
    0xCF: 0x043F, 0xD0: 0x0440, 0xC0: 0x044E, 0xD5: 0x044F,
  };
  final buffer = StringBuffer();
  for (final byte in bytes) {
    final mapped = table[byte];
    if (mapped != null) {
      buffer.writeCharCode(mapped);
    } else {
      buffer.writeCharCode(byte < 0x80 ? byte : 0x002E);
    }
  }
  return buffer.toString();
}
