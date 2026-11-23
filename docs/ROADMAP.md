# Roadmap Mellow 1.0

Восемь вертикальных этапов. Каждый даёт законченный, проверяемый результат и не
требует переписывать предыдущий.

| # | Этап | Статус |
| --- | --- | --- |
| 01 | Foundation | **готово** |
| 02 | UI Prototype | готово в объёме дизайн-системы и экранов на демо-данных |
| 03 | Mail Core | **готово** |
| 04 | Conversation Engine | ожидает |
| 05 | Composer & Attachments | ожидает |
| 06 | Universal Providers | ожидает |
| 07 | Sync & Notifications | ожидает |
| 08 | Focus & Polish | ожидает |

---

## Sprint 01 — Foundation ✅

**Цель:** запускаемое Android/iOS-приложение с правильной архитектурой,
локальной базой, темами и навигацией.

Сделано:

* Flutter-проект, `pubspec.yaml` с зафиксированными семействами зависимостей
  (Riverpod, go_router, Drift, sqlite3_flutter_libs, uuid), линтер со strict-режимом;
* Clean Architecture + feature-first: `app`, `core`, `domain`, `data`,
  `providers`, `features`;
* Drift: 10 таблиц, индексы, миграционная стратегия, 5 реализаций репозиториев,
  мапперы;
* доменные сущности `Account`, `Contact`, `MessageThread`, `Message`,
  `Attachment`, настройки;
* контракт `MailProvider` + `ProviderCapabilities` + определение провайдера по
  домену (Gmail / Яндекс / Mail.ru / Outlook / прочее);
* дизайн-система: семантические токены, две темы, типографика, отступы, радиусы,
  контраст под тестом;
* навигация: нижняя панель из четырёх разделов + push-маршруты;
* экраны: Диалоги (поиск, Focus Mode, список), Люди, Избранное, профиль
  человека, переписка, Smart Composer, настройки, тема, безопасность, аккаунты,
  добавление аккаунта, о приложении;
* демо-данные через реальные мапперы (идемпотентный сид);
* тесты: unit + repository + state + widget, включая архитектурный guard
  `tool/check_structure.sh`;
* документация: `README`, `AGENTS.md`, 9 документов в `docs/`.

Осознанно не сделано: реальная авторизация, отправка, групповая синхронизация,
push, FTS5. Экраны честно сообщают об этом.

**Критерий приёмки:** `flutter analyze` чистый, `flutter test` зелёный,
приложение открывается и показывает диалоги из локальной базы в обеих темах.

---

## Sprint 02 — UI Prototype

* Довести экраны до финального вида: профиль человека с полной историей,
  вложения в пузыре, предпросмотр письма.
* Локализация: вынести строки в ARB (`ru`/`en`), сейчас строки в коде.
* Анимации переходов, скелетоны вместо спиннеров.

Критерий: любой экран выглядит готовым на демо-данных, без заглушек-«TODO».

## Sprint 03 — Mail Core ✅

Сделано:

* `SecureTokenStorage` (Keychain `first_unlock_this_device` /
  EncryptedSharedPreferences) с проверкой доступности и in-memory реализацией
  для тестов.
* `providers/oauth`: PKCE (S256), `state`, обмен кода и refresh с injectable
  `http.Client`.
* `providers/gmail`: endpoints, `GmailApi` (list/get/history/modify/send/
  attachment, повтор после 401 через refresh), `GmailMessageParser` (MIME-дерево,
  RFC 2047, cp1251/koi8-r), `GmailMailProvider` (контракт + инкрементальный
  курсор).
* `providers/mime`: сборка RFC 5322 с `Message-ID`, `In-Reply-To`,
  `References`; Bcc только в конверте.
* `services/sync`: `MailSyncService` (инкрементально по `historyId`, полная
  сверка, устаревший курсор → реконкайл), `SyncStateStore`,
  `ConversationRouter` (provider thread → `In-Reply-To` → `References` → новый).
* UI: экран подключения Gmail с реальными стадиями, экран «Синхронизация»
  (последняя синхронизация, ошибки, полная сверка), честное поведение для
  провайдеров, которых ещё нет.
* Тесты: `test/providers/{pkce,oauth_client,mime_builder,gmail_parser}_test.dart`,
  `test/services/{conversation_router,mail_sync_service}_test.dart`.

Критерий выполнен по коду: письма из реального Gmail попадают в базу и в список
без дубликатов. Отправка писем сознательно перенесена в Sprint 05.

## Sprint 04 — Conversation Engine

* Группировка: provider threadId → `In-Reply-To`/`References` → участники+тема.
* Автосоздание контактов по адресу, ручное объединение в UI.
* Общая история человека, обработка новых участников.

Критерий: сценарии A–C из спецификации проходят.

## Sprint 05 — Composer & Attachments

* Черновики в базе, очередь отправки (`queued → sending → sent/failed`),
  сверка после обрыва соединения.
* Вложения: скачивание, кеш, белый список типов, лимиты.
* Ответ / ответ всем / пересылка с корректными заголовками.

Критерий: сценарий D (потеря соединения) даёт корректный статус без дубликатов.

## Sprint 06 — Universal Providers

* `providers/imap` + `smtp` (Яндекс, Mail.ru, произвольный), `providers/outlook`
  (Graph, deltaLink).
* Ручная настройка серверов, проверка соединения, повторная авторизация.

Критерий: два IMAP-провайдера и Graph работают так же, как Gmail.

## Sprint 07 — Sync & Notifications

* Фоновая синхронизация (WorkManager / BGTaskScheduler), восстановление.
* Локальные уведомления с переходом в диалог, настройки по контактам.
* Каркас push-архитектуры (без сервера — только интерфейсы).

Критерий: приложение обновляется в фоне в разумных пределах ОС, уведомления
приходят и открывают нужную переписку.

## Sprint 08 — Focus & Polish

* Focus Mode до конца (фильтры рассылок, исключения), FTS5-поиск.
* Оптимизация списков, размеров БД, кеша.
* Сборки Android и iOS, store-метаданные, финальный прогон тестов.

Критерий: кандидат на релиз Mellow 1.0.
