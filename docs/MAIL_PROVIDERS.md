# Почтовые провайдеры

## 1. Контракт

Все адаптеры реализуют `lib/providers/contracts/mail_provider.dart`:

```dart
abstract interface class MailProvider {
  String get id;
  ProviderCapabilities get capabilities;

  Future<void> connect(Account account);
  Future<void> disconnect();
  Future<MessagePage> fetchMessages({String? cursor, int limit, String? folder});
  Future<Message?> getMessage(String providerMessageId);
  Future<void> sendMessage(OutgoingMessage message);
  Future<void> replyToMessage(String providerMessageId, OutgoingMessage reply);
  Future<void> markAsRead(String providerMessageId, {bool read});
  Future<void> archiveMessage(String providerMessageId);
  Future<void> deleteMessage(String providerMessageId);
  Future<List<int>> downloadAttachment(Attachment attachment);
  Future<Attachment> uploadAttachment(String messageId, String filePath);
}
```

Правила:

* ошибки — только `MailProviderException` / `AccountAuthException` /
  `UnsupportedException`, без утечки типов SDK;
* списки никогда не `null`;
* `disconnect()` не удаляет данные;
* `deleteMessage` вызывается только по явному действию пользователя.

`ProviderCapabilities` описывает **возможности протокола**, а не гарантии
доставки. `supportsReadReceipts == true` не значит, что получатель подтвердит
прочтение.

## 2. Матрица возможностей (план)

| Возможность | Gmail API | Яндекс IMAP | Mail.ru IMAP | Outlook Graph |
| --- | --- | --- | --- | --- |
| OAuth 2.0 | да | нет | нет | да |
| Пароль приложения | нет | да | да | нет |
| Нативные цепочки | да (`threadId`) | нет | нет | да (`conversationId`) |
| Инкрементальная синхронизация | да (`historyId`) | да (`UIDVALIDITY`/`UID`) | да | да (`deltaLink`) |
| Push | `watch` + Pub/Sub | IMAP IDLE (нестабильно на мобильных) | IMAP IDLE | webhooks (нужен сервер) |
| Серверный поиск | да | да | да | да |
| Метки/папки | labels | folders | folders | categories |
| Вложения | да | да | да | да |

Мгновенные уведомления без серверной инфраструктуры для IMAP-провайдеров не
гарантируются. Это ограничение платформы, а не реализации.

## 3. Определение провайдера

`ProviderDiscovery.guess(email)` — чистая функция без сети:

* `gmail.com`, `googlemail.com` → Gmail;
* `yandex.ru/.com/.by/.kz`, `ya.ru` → Яндекс (`imap.yandex.ru:993`,
  `smtp.yandex.ru:465`);
* `mail.ru`, `inbox.ru`, `list.ru`, `bk.ru` → Mail.ru
  (`imap.mail.ru:993`, `smtp.mail.ru:465`);
* `outlook.com`, `hotmail.com`, `live.com`, `*.onmicrosoft.com` → Outlook;
* всё остальное → `MailProviderKind.imap` с низкой уверенностью: экран
  предлагает ручную настройку хостов.

## 4. Порты и шифрование

Только защищённые соединения: IMAP 993 (implicit TLS), SMTP 465 (implicit TLS).
STARTTLS-варианты (587/143) проектируются позже и только с проверкой сертификата.

## 5. Авторизация

* **Gmail:** OAuth 2.0, PKCE, scopes минимальны:
  `gmail.readonly`, `gmail.send`, `gmail.modify`, `userinfo.email`.
  Refresh-токен — в защищённом хранилище.
* **Outlook:** Microsoft Graph, delegated permissions `Mail.ReadWrite`,
  `Mail.Send`, `offline_access`.
* **Яндекс / Mail.ru / произвольный IMAP:** пароль приложения (не основной
  пароль). Хранится только в защищённом хранилище, никогда в SQLite или логах.

Истёкший токен переводит аккаунт в `needsReauth`; UI показывает «Войти заново».

### 5.1. Как устроен Gmail-адаптер

| Файл | Ответственность |
| --- | --- |
| `providers/gmail/gmail_endpoints.dart` | URL-ы, scopes, id ярлыков — без логики |
| `providers/oauth/pkce.dart` | verifier/challenge (S256), `state` |
| `providers/oauth/oauth_client.dart` | обмен кода и refresh, `http.Client` инъектируется |
| `providers/gmail/gmail_api.dart` | REST-вызовы, пагинация, повтор после 401 через refresh |
| `providers/gmail/gmail_message_parser.dart` | чистая функция: JSON → `Message`, MIME-дерево, RFC 2047 |
| `providers/gmail/gmail_mail_provider.dart` | `MailProvider` + `IncrementalMailProvider` |
| `providers/mime/mime_builder.dart` | RFC 5322 для `raw` и будущего SMTP |

Правила, которые нельзя нарушать при правках:

* `state` из redirect сравнивается с ожидаемым — иначе `AccountAuthException`;
  так же ведёт себя отказ пользователя (`error=access_denied`).
* Refresh-токен сохраняется только в `SecureTokenStorage` и никогда не
  логируется; `OAuthTokens.toString()` не печатает токен.
* `401` от API — один повтор после refresh, не бесконечный цикл.
* `404/410` на `history.list` — это «курсор устарел», а не «писем нет»;
  вызывающий обязан перейти к полной сверке.
* `supportsPush: false`: Gmail push требует Cloud Pub/Sub, которого у Mellow
  пока нет. Обещать push в UI — значит врать про скорость доставки.
* `Message.threadId` из адаптера — **провайдерский** thread id (временное
  значение); движок синхронизации заменяет его на локальный id диалога до
  записи в базу.
* Bcc попадает только в SMTP-конверт (`MimePayload.envelopeBcc`), в заголовки —
  никогда.
* Парсер не бросает исключений на кривых письмах: пустые поля, отсутствие
  `payload`, неизвестная кодировка → безопасные значения по умолчанию.

Регистрация URL-схемы `com.googleusercontent.apps.<id>` для возврата из
браузера описана в [`VERIFY.md`](VERIFY.md#5-подключение-реального-gmail).

## 6. Статус реализации

| Адаптер | Статус |
| --- | --- |
| Контракт + capabilities | готово (Sprint 01) |
| Определение провайдера | готово (Sprint 01) |
| Gmail | **готово (Sprint 03)** — OAuth 2.0 + PKCE, Gmail API, historyId, MIME |
| IMAP / SMTP (Яндекс, Mail.ru) | Sprint 06 |
| Outlook | Sprint 06 |
