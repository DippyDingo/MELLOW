# Синхронизация

Синхронизация — **отдельный сервис** (`lib/services/sync/`, этап 03), а не часть
экрана. Sprint 01 готовит для неё данные и инварианты; сам движок ещё не написан.

## 1. Поток

```
Почтовый сервер
      │  fetchMessages(cursor, limit)
      ▼
Проверка дубликатов      (provider id, затем Message-ID)
      │
      ▼
Нормализация             (адреса, даты, HTML → текст + безопасный HTML)
      │
      ▼
Обновление контактов     (найти по адресу / создать)
      │
      ▼
Обновление диалогов      (threadId провайдера → In-Reply-To/References → участники+тема)
      │
      ▼
Сохранение в SQLite      (upsertMessage + пересчёт счётчиков)
      │
      ▼
UI обновляется автоматически (StreamProvider)
```

## 2. Требования

1. Первичная загрузка — последние N писем (`AppConstants.defaultPageSize = 50`).
2. Далее — только изменения от сохранённого курсора.
3. Курсор пишется в `sync_state` **после** успешного коммита пачки.
4. Прерывание не ломает состояние: следующий запуск продолжает с курсора.
5. Временные ошибки — повтор с экспоненциальной паузой
   (`AppConstants.retryBaseDelay`, `maxRetries`).
6. Повторное добавление сообщения невозможно (см. дедупликацию).
7. Удаление/архив на сервере отражаются в локальной модели, но не удаляют
   историю без подтверждения.
8. Каждый аккаунт синхронизируется независимо: ошибка одного не блокирует
   другие.

## 3. Курсоры

| Провайдер | Курсор | Потеря актуальности |
| --- | --- | --- |
| Gmail | `historyId` | 404 → полная сверка последних страниц |
| IMAP | `UIDVALIDITY:UIDNEXT` | смена `UIDVALIDITY` → пересборка папки |
| Graph | `deltaLink` | 410 Gone → полная сверка |
| Demo | отсутствует | не синхронизируется |

## 4. Дедупликация (реализовано)

`DriftThreadRepository.upsertMessage`:

* поиск по `(account_id, provider_message_id)`;
* иначе поиск по `messages.message_id_header`;
* найденное обновляется, `is_read` не откатывается;
* иначе вставка.

Покрыто тестами `test/data/drift_repositories_test.dart` → группа
`DriftThreadRepository`.

## 5. Счётчики диалога

`unread_count`, `last_message_preview`, `updated_at` пересчитываются в
`_refreshThreadCounters` при каждом изменении сообщений. Формула непрочитанного:
`!isRead && !isOutgoing && !isDraft`.

## 6. Фон и мобильные ограничения

* Android WorkManager и iOS BGTaskScheduler **не гарантируют** расписание.
  Минимальный интервал, отложенные задачи и Doze — вне контроля приложения.
* Поэтому: синхронизация при запуске и при возврате в foreground; фон —
  best-effort.
* Push требует серверной инфраструктуры (Gmail Watch → Pub/Sub, Graph
  subscriptions, IMAP IDLE нестабилен на мобильных). В Sprint 03 push не
  обещается пользователю: `ProviderCapabilities.supportsPush == false` у
  Gmail-адаптера, синхронизация — pull-based (при запуске, по кнопке, дальше —
  Sprint 07).

## 7. Наблюдаемость

`sync_state.consecutive_failures` и `last_error` — для экрана «Синхронизация».
В лог попадают только идентификаторы аккаунта, этап и тип ошибки. Тел писем и
токенов в логах нет.

## 8. Реализация (Sprint 03)

```
MailSyncService.sync(account, provider, {fullSync, pageSize, maxPages})
├── SyncStateStore.read(accountId)         → последний курсор
├── incremental? (provider is IncrementalMailProvider)
│   ├── _incrementalSync: changedMessageIds(cursor)
│   │     null → cursorWasStale → _fullSync() (реконкайл)
│   └── _persist(message) × N
├── _fullSync: fetchMessages(cursor) постранично до maxPages
├── syncState.saveCursor(...)   ← только после коммита пачки
├── syncState.markAccountSynced(now)
└── ошибки: AccountAuthException → needsReauth; AppException → error
```

Порядок `_persist` для каждого письма:

1. контакт отправителя по адресу (не по имени), кроме собственного адреса;
2. диалог: `ConversationRouter.resolve` — provider thread → `In-Reply-To` →
   `References` (от новых к старым) → новый UUID; тема **никогда** не ключ;
3. `upsertMessage` (дедупликация provider id → `Message-ID`);
4. `replaceParticipants` по всем участникам диалога.

Инварианты:

* курсор не сохраняется, если пачка не записалась — повтор не теряет письма;
* `lastFullSyncAt` не затирается инкрементальным проходом;
* `maxPages` ограничивает один проход, чтобы первый запуск не висел вечно;
* сервис не импортирует Flutter и потому может быть вынесен в isolate.

Тесты: `test/services/mail_sync_service_test.dart` (in-memory Drift + фейковый
провайдер), `test/services/conversation_router_test.dart`.

## 9. План

| Этап | Объём |
| --- | --- |
| 03 ✅ | Gmail-адаптер, инкрементальная и полная синхронизация, курсор |
| 04 | ручная коррекция диалогов, объединение контактов, история человека |
| 06 | IMAP/Graph-адаптеры и их курсоры |
| 07 | фон (WorkManager/BGTaskScheduler), восстановление после сбоев, уведомления |
