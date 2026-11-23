import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/providers/gmail/gmail_message_parser.dart';

/// A realistic `users.messages.get` response (trimmed but structurally exact).
Map<String, dynamic> fixture({
  List<String> labelIds = const <String>['INBOX', 'UNREAD'],
  String subject = 'Привет из Gmail',
  String from = 'Александр Петров <alex@example.com>',
  String to = 'me@example.com',
  String messageId = '<abc123@mail.gmail.com>',
  String? inReplyTo,
  String? references,
  List<Map<String, dynamic>>? parts,
}) {
  return <String, dynamic>{
    'id': '18c1f2a3b4d5e6f7',
    'threadId': '18c1f2a3b4d5e6f0',
    'labelIds': labelIds,
    'snippet': 'Текст письма для превью',
    'internalDate': '1795000000000',
    'payload': <String, dynamic>{
      'mimeType': 'multipart/alternative',
      'headers': <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Subject', 'value': subject},
        <String, dynamic>{'name': 'From', 'value': from},
        <String, dynamic>{'name': 'To', 'value': to},
        <String, dynamic>{'name': 'Message-ID', 'value': messageId},
        if (inReplyTo != null)
          <String, dynamic>{'name': 'In-Reply-To', 'value': inReplyTo},
        if (references != null)
          <String, dynamic>{'name': 'References', 'value': references},
        <String, dynamic>{'name': 'Date', 'value': 'Mon, 23 Nov 2026 10:00:00 +0000'},
      ],
      'parts': parts ??
          <Map<String, dynamic>>[
            <String, dynamic>{
              'mimeType': 'text/plain',
              'body': <String, dynamic>{
                'data': base64Url.encode(utf8.encode('Текст письма')).replaceAll('=', ''),
                'size': 24,
              },
            },
            <String, dynamic>{
              'mimeType': 'text/html',
              'body': <String, dynamic>{
                'data': base64Url
                    .encode(utf8.encode('<p>Текст письма</p>'))
                    .replaceAll('=', ''),
                'size': 30,
              },
            },
          ],
    },
  };
}

Message parse(Map<String, dynamic> json) => GmailMessageParser.toMessage(
      json,
      accountId: 'acc-1',
      localId: 'local-1',
      threadId: 'thread-1',
      ownAddress: 'me@example.com',
    );

void main() {
  group('toMessage', () {
    test('maps identity, subject and addresses', () {
      final message = parse(fixture());

      expect(message.id, 'local-1');
      expect(message.accountId, 'acc-1');
      expect(message.threadId, 'thread-1');
      expect(message.providerId, '18c1f2a3b4d5e6f7');
      expect(message.from.address, 'alex@example.com');
      expect(message.from.displayName, 'Александр Петров');
      expect(message.to.single.address, 'me@example.com');
      expect(message.subject, 'Привет из Gmail');
      expect(message.messageIdHeader, '<abc123@mail.gmail.com>');
    });

    test('reads both body parts', () {
      final message = parse(fixture());
      expect(message.bodyText, 'Текст письма');
      expect(message.bodyHtml, '<p>Текст письма</p>');
    });

    test('unread label means the message is unread', () {
      expect(parse(fixture()).isRead, isFalse);
      expect(parse(fixture(labelIds: <String>['INBOX'])).isRead, isTrue);
    });

    test('SENT label marks the message as outgoing', () {
      final message = parse(
        fixture(
          labelIds: <String>['SENT'],
          from: 'me@example.com',
          to: 'alex@example.com',
        ),
      );
      expect(message.isOutgoing, isTrue);
    });

    test('mail from our own address counts as outgoing', () {
      final message = parse(
        fixture(labelIds: <String>[], from: 'Me <ME@example.com>'),
      );
      expect(message.isOutgoing, isTrue);
    });

    test('parses the References chain into a list', () {
      final message = parse(
        fixture(
          inReplyTo: '<parent@example.com>',
          references: '<root@example.com> <parent@example.com>',
        ),
      );
      expect(message.inReplyTo, '<parent@example.com>');
      expect(
        message.references,
        <String>['<root@example.com>', '<parent@example.com>'],
      );
    });

    test('decodes RFC 2047 encoded subject', () {
      final encoded = '=?UTF-8?B?${base64.encode(utf8.encode('Встреча'))}?=';
      expect(parse(fixture(subject: encoded)).subject, 'Встреча');
    });

    test('converts internalDate (ms epoch) into a UTC timestamp', () {
      expect(
        parse(fixture()).sentAt.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1795000000000, isUtc: true),
      );
    });

    test('falls back safely when headers are missing', () {
      final message = GmailMessageParser.toMessage(
        <String, dynamic>{'id': 'x', 'threadId': 't', 'payload': <String, dynamic>{}},
        accountId: 'a',
        localId: 'l',
        threadId: 't',
        ownAddress: 'me@example.com',
      );
      expect(message.from.address, 'me@example.com');
      expect(message.subject, '');
      expect(message.bodyText, '');
      expect(message.bodyHtml, isNull);
    });
  });

  group('extractBodies', () {
    test('handles multipart/mixed with an attachment', () {
      final payload = <String, dynamic>{
        'mimeType': 'multipart/mixed',
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{
            'mimeType': 'text/plain',
            'body': <String, dynamic>{
              'data': base64Url.encode(utf8.encode('only text')).replaceAll('=', ''),
            },
          },
          <String, dynamic>{
            'mimeType': 'application/pdf',
            'filename': 'report.pdf',
            'body': <String, dynamic>{'attachmentId': 'att-1', 'size': 12345},
          },
        ],
      };

      final bodies = GmailMessageParser.extractBodies(payload);
      expect(bodies.text, 'only text');
      expect(bodies.html, isNull);

      final attachments = GmailMessageParser.extractAttachments(payload);
      expect(attachments, hasLength(1));
      expect(attachments.single.fileName, 'report.pdf');
      expect(attachments.single.providerId, 'att-1');
      expect(attachments.single.sizeBytes, 12345);
    });

    test('falls back to text extracted from html', () {
      final payload = <String, dynamic>{
        'mimeType': 'text/html',
        'body': <String, dynamic>{
          'data': base64Url
              .encode(utf8.encode('<p>Привет</p><p>Мир</p>'))
              .replaceAll('=', ''),
        },
      };
      final bodies = GmailMessageParser.extractBodies(payload);
      expect(bodies.html, '<p>Привет</p><p>Мир</p>');
      expect(bodies.text, contains('Привет'));
      expect(bodies.text, contains('Мир'));
    });

    test('decodes a cp1251 part using the declared charset', () {
      // «Привет» in windows-1251 — exactly what an old desktop client sends.
      final cp1251 = <int>[0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2];
      final payload = <String, dynamic>{
        'mimeType': 'text/plain',
        'headers': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Content-Type',
            'value': 'text/plain; charset=windows-1251',
          },
        ],
        'body': <String, dynamic>{
          'data': base64Url.encode(cp1251).replaceAll('=', ''),
        },
      };
      expect(GmailMessageParser.extractBodies(payload).text, 'Привет');
    });

    test('walks nested multiparts', () {
      final payload = <String, dynamic>{
        'mimeType': 'multipart/mixed',
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{
            'mimeType': 'multipart/alternative',
            'parts': <Map<String, dynamic>>[
              <String, dynamic>{
                'mimeType': 'text/plain',
                'body': <String, dynamic>{
                  'data': base64Url.encode(utf8.encode('nested')).replaceAll('=', ''),
                },
              },
            ],
          },
        ],
      };
      expect(GmailMessageParser.extractBodies(payload).text, 'nested');
    });
  });

  group('extractAttachments', () {
    test('ignores inline text parts and empty filenames', () {
      final payload = <String, dynamic>{
        'mimeType': 'multipart/mixed',
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{
            'mimeType': 'text/plain',
            'filename': '',
            'body': <String, dynamic>{'attachmentId': 'inline', 'size': 10},
          },
          <String, dynamic>{
            'mimeType': 'image/png',
            'filename': 'photo.png',
            'body': <String, dynamic>{'attachmentId': 'att-2', 'size': 2048},
          },
        ],
      };
      final attachments = GmailMessageParser.extractAttachments(payload);
      expect(attachments.single.fileName, 'photo.png');

      final entity = attachments.single.toEntity('msg-1');
      expect(entity.id, 'msg-1:att-2');
      expect(entity.mimeType, 'image/png');
    });

    test('returns an empty list when there is no payload', () {
      expect(GmailMessageParser.extractAttachments(null), isEmpty);
    });
  });

  test('snippetOf keeps the snippet readable', () {
    expect(
      GmailMessageParser.snippetOf(<String, dynamic>{'snippet': 'Короткий текст'}),
      'Короткий текст',
    );
  });
}
