import 'package:drift/drift.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/mappers/account_mapper.dart';
import 'package:mellow/data/mappers/contact_mapper.dart';
import 'package:mellow/data/mappers/message_mapper.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/contact.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/domain/entities/message_thread.dart';
import 'package:uuid/uuid.dart';

/// Fills the database with a small, believable demo mailbox.
///
/// Used by the UI prototype (roadmap step 2) and by widget tests. It writes
/// through the real mappers, so the seed exercises the same code paths that
/// synchronisation will. It never runs when the database already has data.
abstract final class DemoSeed {
  static const Uuid _uuid = Uuid();

  static const String demoAccountId = 'demo-account-gmail';
  static const String demoEmail = 'mellow.demo@gmail.com';

  static Future<void> runIfEmpty(AppDatabase db) async {
    final existing = await db.select(db.accounts).get();
    if (existing.isNotEmpty) return;
    await run(db);
  }

  /// Seeds the demo mailbox unconditionally (tests call this directly).
  static Future<void> run(AppDatabase db, {DateTime? now}) async {
    final reference = now ?? DateTime.now();

    const account = Account(
      id: demoAccountId,
      email: demoEmail,
      provider: MailProviderKind.gmail,
      status: AccountStatus.connected,
      displayName: 'Mellow Demo',
      isPrimary: true,
    );
    await db.into(db.accounts).insert(AccountMapper.toCompanion(account));

    final people = <_Person>[
      const _Person(
        name: 'Александр Петров',
        emails: <String>['alex@example.com', 'alexander@company.com'],
        isFavorite: true,
      ),
      const _Person(
        name: 'Мария Соколова',
        emails: <String>['maria.sokolova@mail.ru'],
        isFavorite: true,
      ),
      const _Person(
        name: 'Design Weekly',
        emails: <String>['news@designweekly.io'],
      ),
      const _Person(
        name: 'Иван Кузнецов',
        emails: <String>['ivan.kuznetsov@yandex.ru'],
      ),
    ];

    final contactIds = <String, String>{};
    for (final person in people) {
      final id = _uuid.v4();
      contactIds[person.name] = id;
      await db.into(db.contacts).insert(
            ContactMapper.toCompanion(
              Contact(
                id: id,
                displayName: person.name,
                addresses: person.emails
                    .map(
                      (email) => ContactEmail(
                        email: email,
                        displayName: person.name,
                        label: person.emails.length > 1 && email.endsWith('company.com')
                            ? 'работа'
                            : null,
                      ),
                    )
                    .toList(growable: false),
                isFavorite: person.isFavorite,
              ),
            ),
          );
      for (var i = 0; i < person.emails.length; i++) {
        await db.into(db.contactEmails).insert(
              ContactMapper.emailToCompanion(
                id: _uuid.v4(),
                contactId: id,
                email: ContactEmail(
                  email: person.emails[i],
                  displayName: person.name,
                  isPrimary: i == 0,
                ),
              ),
            );
      }
    }

    final threads = <_SeedThread>[
      _SeedThread(
        subject: 'Разработка приложения',
        contactName: 'Александр Петров',
        participantEmail: 'alex@example.com',
        unread: 1,
        isPinned: true,
        messages: <_SeedMessage>[
          _SeedMessage(
            fromMe: false,
            minutesAgo: 190,
            text: 'Привет! Посмотрел макеты — выглядит спокойно и по делу. '
                'Можно начинать с экрана диалогов.',
          ),
          _SeedMessage(
            fromMe: true,
            minutesAgo: 120,
            text: 'Отлично. Начинаю с архитектуры и локальной базы, '
                'потом покажу первый экран.',
          ),
          _SeedMessage(
            fromMe: false,
            minutesAgo: 12,
            text: 'Супер. Ещё вопрос: сможем ли мы показывать письма '
                'в одном диалоге, даже если темы немного отличаются?',
          ),
        ],
      ),
      _SeedThread(
        subject: 'Документы по проекту',
        contactName: 'Александр Петров',
        participantEmail: 'alexander@company.com',
        messages: <_SeedMessage>[
          _SeedMessage(
            fromMe: false,
            minutesAgo: 320,
            text: 'Отправил договор и приложение со сроками. '
                'Посмотри, пожалуйста, до пятницы.',
          ),
        ],
      ),
      _SeedThread(
        subject: 'Планы на выходные',
        contactName: 'Мария Соколова',
        participantEmail: 'maria.sokolova@mail.ru',
        unread: 2,
        messages: <_SeedMessage>[
          _SeedMessage(
            fromMe: true,
            minutesAgo: 1500,
            text: 'Привет! Может, сходим в тот новый парк в субботу?',
          ),
          _SeedMessage(
            fromMe: false,
            minutesAgo: 1480,
            text: 'Давай! Часам к одиннадцати?',
          ),
          _SeedMessage(
            fromMe: false,
            minutesAgo: 1400,
            text: 'И возьми, пожалуйста, термос — обещают прохладу.',
          ),
        ],
      ),
      _SeedThread(
        subject: 'Лучшие статьи недели',
        contactName: 'Design Weekly',
        participantEmail: 'news@designweekly.io',
        messages: <_SeedMessage>[
          _SeedMessage(
            fromMe: false,
            minutesAgo: 2900,
            text: 'В этом выпуске: как сделать интерфейс спокойным, '
                'не потеряв выразительность, и подборка шрифтов для мобильных.',
          ),
        ],
      ),
      _SeedThread(
        subject: 'Встреча по API',
        contactName: 'Иван Кузнецов',
        participantEmail: 'ivan.kuznetsov@yandex.ru',
        messages: <_SeedMessage>[
          _SeedMessage(
            fromMe: true,
            minutesAgo: 5800,
            text: 'Спасибо за созвон. Скидываю итоги: контракт провайдера '
                'делаем независимым от Gmail.',
          ),
          _SeedMessage(
            fromMe: false,
            minutesAgo: 5760,
            text: 'Согласен. И давай сразу заложим курсоры синхронизации, '
                'чтобы не тянуть всё заново.',
          ),
        ],
      ),
    ];

    final ownAddress = EmailAddress(address: demoEmail, displayName: 'Я');

    for (final seed in threads) {
      final threadId = _uuid.v4();
      final contactId = contactIds[seed.contactName];
      final peer = parseEmailAddress(seed.participantEmail)!;
      final lastSentAt = reference.subtract(Duration(minutes: seed.messages.last.minutesAgo));

      await db.into(db.conversations).insert(
            MessageMapper.threadToCompanion(
              MessageThread(
                id: threadId,
                accountId: demoAccountId,
                subject: seed.subject,
                participants: <EmailAddress>[peer, ownAddress],
                updatedAt: lastSentAt,
                lastMessagePreview: seed.messages.last.text,
                unreadCount: seed.unread,
                isPinned: seed.isPinned,
                contactId: contactId,
              ),
            ),
          );

      for (final participant in <_Participant>[
        _Participant(address: peer, contactId: contactId, isOwn: false),
        _Participant(address: ownAddress, contactId: null, isOwn: true),
      ]) {
        await db.into(db.conversationParticipants).insert(
              ConversationParticipantsCompanion.insert(
                id: _uuid.v4(),
                conversationId: threadId,
                email: participant.address.address,
                contactId: Value(participant.contactId),
                isOwnAddress: Value(participant.isOwn),
              ),
            );
      }

      // The last `unread` received messages stay unread, exactly as a sync would
      // leave them.
      final receivedIndexes = <int>[
        for (var i = 0; i < seed.messages.length; i++)
          if (!seed.messages[i].fromMe) i,
      ];
      final unreadFromIndex = receivedIndexes.length - seed.unread;

      for (var i = 0; i < seed.messages.length; i++) {
        final message = seed.messages[i];
        final receivedPosition = receivedIndexes.indexOf(i);
        final isRead = message.fromMe || receivedPosition < unreadFromIndex;
        final sentAt = reference.subtract(Duration(minutes: message.minutesAgo));

        await db.into(db.messages).insert(
              MessageMapper.toCompanion(
                Message(
                  id: _uuid.v4(),
                  threadId: threadId,
                  accountId: demoAccountId,
                  from: message.fromMe ? ownAddress : peer,
                  to: message.fromMe ? <EmailAddress>[peer] : <EmailAddress>[ownAddress],
                  subject: seed.subject,
                  bodyText: message.text,
                  sentAt: sentAt,
                  isRead: isRead,
                  isOutgoing: message.fromMe,
                  deliveryStatus: DeliveryStatus.received,
                  messageIdHeader: '<demo-${_uuid.v4()}@mellow.local>',
                ),
              ),
            );
      }
    }
  }
}

class _Person {
  const _Person({
    required this.name,
    required this.emails,
    this.isFavorite = false,
  });

  final String name;
  final List<String> emails;
  final bool isFavorite;
}

class _SeedThread {
  const _SeedThread({
    required this.subject,
    required this.contactName,
    required this.participantEmail,
    required this.messages,
    this.unread = 0,
    this.isPinned = false,
  });

  final String subject;
  final String contactName;
  final String participantEmail;
  final List<_SeedMessage> messages;
  final int unread;
  final bool isPinned;
}

class _SeedMessage {
  const _SeedMessage({
    required this.fromMe,
    required this.minutesAgo,
    required this.text,
  });

  final bool fromMe;
  final int minutesAgo;
  final String text;
}

class _Participant {
  const _Participant({
    required this.address,
    required this.contactId,
    required this.isOwn,
  });

  final EmailAddress address;
  final String? contactId;
  final bool isOwn;
}
