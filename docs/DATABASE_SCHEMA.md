# Схема базы данных

Движок: SQLite через Drift. Файл `mellow.sqlite` в application support
directory. Версия схемы: **1**.

## 1. Общие правила

* Первичные ключи — UUID Mellow (`text`). Идентификаторы провайдера хранятся
  отдельными колонками и никогда не становятся ключами.
* Все адреса нормализуются (`normalizeEmail`: trim + lower-case) до записи.
* Внешние ключи включены (`PRAGMA foreign_keys = ON` в `beforeOpen`).
* Удаление локальных данных не затрагивает сервер. Флаги `is_hidden`,
  `is_archived` — только локальное представление.
* Даты — `dateTime` (UTC в store, локальное время в UI).
* `*.g.dart` генерируется: `dart run build_runner build
  --delete-conflicting-outputs`.

## 2. Таблицы

### `accounts`
| Колонка | Тип | Примечание |
| --- | --- | --- |
| id | text PK | UUID Mellow |
| email | text, unique | нормализованный адрес |
| provider | text | `MailProviderKind.name` |
| status | text | `AccountStatus.name` |
| display_name | text? | имя для переключателя |
| provider_account_id | text? | `sub` Gmail / Graph id |
| is_primary | bool | по умолчанию false |
| last_sync_at | datetime? | |
| last_error | text? | безопасный текст ошибки |
| created_at | datetime | |

Уникальность: `email` (адрес — реальная идентичность ящика). `provider_account_id`
не входит в ключ: SQLite считает NULL-ы различными.

### `provider_settings`
Не секретные параметры подключения: `imap_host/port`, `smtp_host/port`,
`options_json`. PK — `account_id`. **Токены и пароли здесь не хранятся.**

### `sync_state`
`account_id` PK, `cursor` (непрозрачная строка: Gmail `historyId`, IMAP
`UIDVALIDITY:UID`), `last_sync_at`, `last_full_sync_at`,
`consecutive_failures`, `last_error`.

Инварианты (реализованы в `SyncStateStore`):

* `cursor` обновляется только после того, как пачка писем закоммичена;
* инкрементальный проход не затирает `last_full_sync_at`;
* сбой пишет `last_error` и увеличивает `consecutive_failures`, но сохраняет
  последний рабочий курсор — повтор не теряет письма.

### `contacts`
`id` PK, `display_name`, `avatar_path?`, `is_favorite`, `created_at`,
`updated_at`.

### `contact_emails`
`id` PK, `contact_id` FK → `contacts.id`, `email` (**уникален глобально**),
`display_name?`, `label?`, `is_primary`, `created_at`.

Инвариант: адрес принадлежит максимум одному контакту. Объединение — только
через `mergeContacts`.

### `conversations`
| Колонка | Примечание |
| --- | --- |
| id | UUID |
| account_id | FK, диалог привязан к аккаунту |
| contact_id | FK?, заполняется, когда все участники — один контакт |
| subject | тема, без «Re:» |
| provider_thread_id | threadId Gmail / Graph |
| created_at, updated_at | `updated_at` = время последнего письма |
| last_message_preview | до 140 символов |
| unread_count | пересчитывается репозиторием |
| is_pinned, is_archived, is_muted | пользовательские флаги |
| is_hidden | скрыт локально (soft delete) |

Уникальность: `(account_id, provider_thread_id)`.

### `conversation_participants`
`id` PK, `conversation_id` FK, `email`, `contact_id?`, `is_own_address`.
Уникальность: `(conversation_id, email)`.

Пишется только через `ThreadRepository.replaceParticipants` (идемпотентно,
в одной транзакции). `contact_id` заполняется **по адресу**, а не по позиции в
письме: у группового диалога несколько человек, и привязка всех к контакту
отправителя была бы молчаливым искажением данных. Адреса без контакта остаются
`null` до первого письма от них.

### `messages`
| Колонка | Примечание |
| --- | --- |
| id | UUID |
| conversation_id | FK |
| account_id | FK |
| provider_message_id | id у провайдера |
| message_id_header | RFC 5322 `Message-ID`, **индексирован** |
| subject, from_address, from_name | |
| to_addresses, cc_addresses, bcc_addresses | через запятую |
| body_text, body_html? | HTML только для санитайзера |
| in_reply_to, references | заголовки цепочки |
| sent_at, received_at | |
| is_read, is_outgoing, is_draft | |
| has_attachments | |
| delivery_status | `DeliveryStatus.name` |
| created_at | |

Уникальность: `(account_id, provider_message_id)`.

### `attachments`
`id` PK, `message_id` FK, `file_name`, `mime_type`, `size_bytes`,
`local_path?`, `provider_attachment_id?`, `is_downloaded`, `created_at`.
Байты в SQLite не хранятся — только путь в кеше.

### `app_settings`
`key` PK, `value` (text). Все значения — строки; парсинг с безопасным фолбэком
к дефолтам (`DriftSettingsRepository._mapRows`).

Ключи: `theme_preference`, `focus_mode_enabled`, `focus_favorites_only`,
`focus_unread_only`, `hide_automated_messages`, `notifications_enabled`,
`notifications_favorites_only`, `sync_on_launch`, `block_external_images`,
`app_lock_enabled`.

## 3. Индексы

```sql
CREATE INDEX idx_messages_message_id    ON messages(message_id_header);
CREATE INDEX idx_messages_conversation  ON messages(conversation_id, sent_at);
CREATE INDEX idx_conversations_account  ON conversations(account_id, updated_at);
CREATE INDEX idx_contact_emails_contact ON contact_emails(contact_id);
```

## 4. Дедупликация сообщений

`DriftThreadRepository.upsertMessage`:

1. поиск по `(account_id, provider_message_id)`;
2. если не найдено — поиск по `messages.message_id_header`;
3. найденное обновляется (README-статус «прочитано» не откатывается обратно);
4. иначе — вставка.

Повторная синхронизация того же окна не создаёт дубликатов — это покрыто
тестами.

## 5. Миграции

`MigrationStrategy` в `app_database.dart`: `onCreate` создаёт таблицы и индексы,
`onUpgrade` — пошаговые `fromNToM`. При добавлении колонки:

```dart
if (from < 2) await m.addColumn(messages, messages.snippet);
```

и `schemaVersion = 2`. Данные пользователя не удаляются; при необходимости
несовместимого изменения — новая таблица + перенос, не `DROP`.

## 6. Будущее (не реализовано)

* `labels`, `conversation_labels` — этап 06;
* `sync_log` — диагностика этапа 07;
* FTS5-таблица `messages_fts` для полнотекстового поиска — этап 08.
