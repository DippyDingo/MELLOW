import 'dart:convert';

/// Builds RFC 5322 messages for sending (Gmail `raw`, SMTP, Microsoft Graph).
///
/// Kept pure and dependency-free so headers can be asserted character by
/// character in tests: reply-linkage headers (`In-Reply-To`, `References`) are
/// what makes a reply land in the right thread in *every* client, and they are
/// the easiest thing to get subtly wrong.
class MimeBuilder {
  const MimeBuilder({
    required this.from,
    required this.to,
    this.cc = const <String>[],
    this.bcc = const <String>[],
    required this.subject,
    required this.bodyText,
    this.bodyHtml,
    this.inReplyTo,
    this.references = const <String>[],
    this.messageId,
    this.date,
    this.boundary,
  });

  final String from;
  final List<String> to;
  final List<String> cc;

  /// Blind copies. **Never written into the message body or headers** — they
  /// belong to the SMTP envelope only, otherwise every recipient sees them.
  final List<String> bcc;

  final String subject;
  final String bodyText;
  final String? bodyHtml;

  /// `In-Reply-To` of the message being answered.
  final String? inReplyTo;

  /// Full `References` chain, oldest first.
  final List<String> references;

  /// Overrides the generated `Message-ID` (tests rely on this).
  final String? messageId;

  /// Overrides `Date` (tests rely on this).
  final DateTime? date;

  /// Multipart boundary; generated when omitted.
  final String? boundary;

  /// Domain used for generated `Message-ID`s.
  static const String messageIdDomain = 'mellow.local';

  /// Builds the complete message, CRLF-terminated as RFC 5322 requires.
  String build({String? generatedMessageId, DateTime? now}) {
    final when = date ?? now ?? DateTime.now();
    final currentId = _normalizeMessageId(
      messageId ?? generatedMessageId ?? _generateMessageId(when),
    );
    final body = bodyHtml == null ? _singlePart() : _alternativePart();

    final headers = <String>[
      'From: ${_formatAddress(from)}',
      if (to.isNotEmpty) 'To: ${to.map(_formatAddress).join(', ')}',
      if (cc.isNotEmpty) 'Cc: ${cc.map(_formatAddress).join(', ')}',
      'Subject: ${_encodeHeader(subject)}',
      'Date: ${_rfc5322Date(when)}',
      'Message-ID: $currentId',
      'MIME-Version: 1.0',
    ];

    if (inReplyTo != null && inReplyTo!.trim().isNotEmpty) {
      headers.add('In-Reply-To: ${_normalizeMessageId(inReplyTo!)}');
    }
    final chain = _referenceChain(currentId);
    if (chain.isNotEmpty) {
      headers.add('References: ${chain.join(' ')}');
    }
    headers.add(body.contentType);

    return '${headers.join('\r\n')}\r\n\r\n${body.content}\r\n';
  }

  /// Headers (without body) plus the Bcc envelope, for SMTP delivery.
  MimePayload buildParts({String? generatedMessageId, DateTime? now}) {
    final raw = build(generatedMessageId: generatedMessageId, now: now);
    final split = raw.indexOf('\r\n\r\n');
    return MimePayload(
      headers: raw.substring(0, split),
      body: raw.substring(split + 4),
      raw: raw,
      envelopeBcc: List<String>.unmodifiable(bcc),
    );
  }

  /// Base64url (no padding) encoding of the message, as Gmail expects.
  String toBase64Url({String? generatedMessageId, DateTime? now}) {
    final raw = build(generatedMessageId: generatedMessageId, now: now);
    return base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
  }

  _MimePart _singlePart() {
    return _MimePart(
      contentType: 'Content-Type: text/plain; charset="utf-8"',
      content: 'Content-Transfer-Encoding: base64\r\n\r\n'
          '${_wrap(base64.encode(utf8.encode(bodyText)))}',
    );
  }

  _MimePart _alternativePart() {
    final b = boundary ?? 'mellow-${DateTime.now().microsecondsSinceEpoch}';
    final text = _wrap(base64.encode(utf8.encode(bodyText)));
    final html = _wrap(base64.encode(utf8.encode(bodyHtml ?? '')));

    final content = <String>[
      '--$b',
      'Content-Type: text/plain; charset="utf-8"',
      'Content-Transfer-Encoding: base64',
      '',
      text,
      '--$b',
      'Content-Type: text/html; charset="utf-8"',
      'Content-Transfer-Encoding: base64',
      '',
      html,
      '--$b--',
      '',
    ].join('\r\n');

    return _MimePart(
      contentType: 'Content-Type: multipart/alternative; boundary="$b"',
      content: content,
    );
  }

  /// `References` = every ancestor in order, ending with the direct parent.
  List<String> _referenceChain(String currentId) {
    final chain = <String>[];
    void add(String value) {
      final normalized = _normalizeMessageId(value);
      if (normalized == currentId) return;
      if (!chain.contains(normalized)) chain.add(normalized);
    }

    for (final reference in references) {
      add(reference);
    }
    final parent = inReplyTo;
    if (parent != null && parent.isNotEmpty) add(parent);
    return chain;
  }

  static String _normalizeMessageId(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('<') && trimmed.endsWith('>')) return trimmed;
    return '<$trimmed>';
  }

  /// Monotonic counter, because two messages built in the same microsecond
  /// would otherwise receive the same `Message-ID` — and servers reject that.
  static int _sequence = 0;

  static String _generateMessageId(DateTime when) {
    final random = when.microsecondsSinceEpoch.toRadixString(36);
    final seq = (_sequence++).toRadixString(36);
    return '<$random.$seq@$messageIdDomain>';
  }

  /// Passes `Name <addr>` through untouched; bare addresses are used as-is.
  static String _formatAddress(String address) => address.trim();

  /// RFC 2047 encoded-word, required for non-ASCII subjects (Russian).
  static String _encodeHeader(String value) {
    if (value.isEmpty) return '';
    final isAscii = value.runes.every((rune) => rune < 128);
    if (isAscii) return value;
    return '=?UTF-8?B?${base64.encode(utf8.encode(value))}?=';
  }

  /// Folds base64 bodies at 76 characters, as the spec recommends.
  static String _wrap(String value) {
    const width = 76;
    if (value.length <= width) return value;
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i += width) {
      final end = i + width < value.length ? i + width : value.length;
      buffer.write(value.substring(i, end));
      if (end < value.length) buffer.write('\r\n');
    }
    return buffer.toString();
  }

  static const List<String> _weekdays = <String>[
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// `Mon, 23 Nov 2026 10:00:00 +0000`.
  static String _rfc5322Date(DateTime when) {
    final utc = when.toUtc();
    final weekday = _weekdays[utc.weekday - 1];
    final month = _months[utc.month - 1];
    String two(int value) => value.toString().padLeft(2, '0');
    return '$weekday, ${two(utc.day)} $month ${utc.year} '
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} +0000';
  }
}

/// A built message, ready to be handed to a transport.
class MimePayload {
  const MimePayload({
    required this.headers,
    required this.body,
    required this.raw,
    required this.envelopeBcc,
  });

  final String headers;
  final String body;
  final String raw;
  final List<String> envelopeBcc;
}

class _MimePart {
  const _MimePart({required this.contentType, required this.content});

  /// For example `Content-Type: multipart/alternative; boundary="..."`.
  final String contentType;

  /// Body section including its own `Content-Transfer-Encoding` header.
  final String content;
}
