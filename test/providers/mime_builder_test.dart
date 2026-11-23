import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/providers/mime/mime_builder.dart';

void main() {
  final date = DateTime.utc(2026, 11, 23, 10, 30);

  MimeBuilder builder({
    String subject = 'Hello',
    String bodyText = 'Body',
    String? bodyHtml,
    String? inReplyTo,
    List<String> references = const <String>[],
    List<String> bcc = const <String>[],
    String? messageId = '<fixed@mellow.local>',
  }) {
    return MimeBuilder(
      from: 'me@example.com',
      to: <String>['alex@example.com'],
      bcc: bcc,
      subject: subject,
      bodyText: bodyText,
      bodyHtml: bodyHtml,
      inReplyTo: inReplyTo,
      references: references,
      messageId: messageId,
      date: date,
      boundary: 'boundary-1',
    );
  }

  group('headers', () {
    test('produces mandatory headers in order', () {
      final raw = builder().build();
      final headers = raw.split('\r\n\r\n').first.split('\r\n');

      expect(headers.first, 'From: me@example.com');
      expect(headers, contains('To: alex@example.com'));
      expect(headers, contains('Subject: Hello'));
      expect(headers, contains('Message-ID: <fixed@mellow.local>'));
      expect(headers, contains('MIME-Version: 1.0'));
      expect(
        headers,
        contains('Date: Mon, 23 Nov 2026 10:30:00 +0000'),
      );
    });

    test('uses CRLF line endings', () {
      final raw = builder().build();
      expect(raw, contains('\r\n'));
      expect(raw.split('\r\n\r\n').length, greaterThan(1));
    });

    test('encodes a Russian subject as an RFC 2047 word', () {
      final raw = builder(subject: 'Привет').build();
      final subjectLine =
          raw.split('\r\n').firstWhere((line) => line.startsWith('Subject:'));
      expect(subjectLine, startsWith('Subject: =?UTF-8?B?'));
      expect(subjectLine, endsWith('?='));

      final encoded = subjectLine
          .replaceFirst('Subject: =?UTF-8?B?', '')
          .replaceFirst('?=', '');
      expect(utf8.decode(base64.decode(encoded)), 'Привет');
    });

    test('leaves ASCII subjects readable', () {
      expect(builder(subject: 'Re: hello').build(), contains('Subject: Re: hello'));
    });

    test('writes In-Reply-To only when replying', () {
      expect(builder().build(), isNot(contains('In-Reply-To:')));
      final reply = builder(inReplyTo: '<parent@example.com>').build();
      expect(reply, contains('In-Reply-To: <parent@example.com>'));
    });

    test('builds a References chain ending with the parent', () {
      final raw = builder(
        inReplyTo: '<parent@example.com>',
        references: <String>['<root@example.com>', '<parent@example.com>'],
      ).build();
      final line = raw
          .split('\r\n')
          .firstWhere((l) => l.startsWith('References:'));
      expect(
        line,
        'References: <root@example.com> <parent@example.com>',
      );
    });

    test('never leaks Bcc into the message', () {
      final raw = builder(bcc: <String>['secret@example.com']).build();
      expect(raw, isNot(contains('Bcc:')));
      expect(raw, isNot(contains('secret@example.com')));

      // …but the envelope keeps it for SMTP.
      final parts = builder(bcc: <String>['secret@example.com']).buildParts();
      expect(parts.envelopeBcc, <String>['secret@example.com']);
    });

    test('normalises bare Message-IDs with angle brackets', () {
      final raw = builder(inReplyTo: 'parent@example.com').build();
      expect(raw, contains('In-Reply-To: <parent@example.com>'));
    });
  });

  group('bodies', () {
    test('plain text body is base64 encoded', () {
      final parts = builder(bodyText: 'Тело письма').buildParts();
      expect(parts.headers, contains('Content-Type: text/plain; charset="utf-8"'));

      final encoded = parts.body
          .split('\r\n\r\n')
          .last
          .replaceAll('\r\n', '')
          .trim();
      expect(utf8.decode(base64.decode(encoded)), 'Тело письма');
    });

    test('html body becomes multipart/alternative with both parts', () {
      final raw = builder(bodyText: 'text', bodyHtml: '<b>html</b>').build();
      expect(raw, contains('multipart/alternative; boundary="boundary-1"'));
      expect(raw, contains('Content-Type: text/plain'));
      expect(raw, contains('Content-Type: text/html'));
      expect(raw, contains('--boundary-1--'));
    });

    test('base64url encoding round-trips', () {
      final encoded = builder().toBase64Url();
      expect(encoded, isNot(contains('=')));
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
      );
      expect(decoded, contains('Subject: Hello'));
    });

    test('folds long base64 bodies at 76 characters', () {
      final parts = builder(bodyText: 'x' * 400).buildParts();
      final lines = parts.body.split('\r\n').where((l) => l.isNotEmpty);
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(76));
      }
    });
  });

  test('generated Message-ID is unique per call', () {
    final a = builder(messageId: null).build();
    final b = builder(messageId: null).build();
    final id = (String raw) => raw
        .split('\r\n')
        .firstWhere((line) => line.startsWith('Message-ID:'))
        .replaceFirst('Message-ID: ', '');
    expect(id(a), isNot(id(b)));
    expect(id(a), startsWith('<'));
    expect(id(a), endsWith('@mellow.local>'));
  });
}
