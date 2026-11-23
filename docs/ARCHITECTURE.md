# Архитектура Mellow

## 1. Принципы

1. **Clean Architecture.** Зависимости направлены внутрь: UI → Application →
   Domain; Data и Providers реализуют доменные контракты.
2. **Feature-first.** Код группируется по функциям продукта, а не по типам
   файлов. Внутри фичи — `application/`, `presentation/`, при необходимости
   `widgets/`.
3. **Dependency Inversion.** Бизнес-логика знает только абстракции
   (`MailProvider`, `ThreadRepository`, …). Gmail, IMAP и Graph — адаптеры.
4. **Локальная база — источник истины для UI.** Экраны читают из SQLite, а не из
   сети. Сеть только наполняет базу.
5. **Честность интерфейса.** Неработающая функция сообщает об этом, а не
   имитирует результат.

## 2. Слои

```
┌──────────────────────────────────────────────┐
│ presentation  features/*/presentation        │  виджеты, без логики
├──────────────────────────────────────────────┤
│ application   features/*/application         │  Riverpod: состояние и сценарии
├──────────────────────────────────────────────┤
│ domain        entities, repositories         │  модель и контракты, без I/O
├──────────────────────────────────────────────┤
│ data          database, mappers, repos       │  Drift + реализации
├──────────────────────────────────────────────┤
│ providers     contracts, gmail, imap, …      │  адаптеры почтовых сервисов
├──────────────────────────────────────────────┤
│ services      sync, delivery, notifications  │  фоновые процессы (этапы 03, 07)
└──────────────────────────────────────────────┘
```

Правила импорта:

| Из | Можно | Нельзя |
| --- | --- | --- |
| `domain/` | ничего из `lib/` | `flutter/material.dart`, `drift`, `features/`, `data/` |
| `data/` | `domain/`, `core/` | `features/` |
| `providers/` | `domain/`, `core/` | `features/`, `data/` |
| `services/` | `domain/`, `providers/contracts`, `core/` | `features/`, `flutter/material`, `flutter/widgets` |
| `features/` | всё ниже себя | другая фича (кроме общедоступных контроллеров) |
| `app/` | всё | — |

## 3. Структура каталогов

```
lib/
├── app/
│   ├── bootstrap/bootstrap.dart   # единственное место создания AppDatabase
│   ├── di/providers.dart          # Provider-граф (БД → репозитории)
│   ├── navigation/                # routes.dart, router.dart, app_shell.dart
│   └── mellow_app.dart            # MaterialApp.router, темы, локализация
├── core/
│   ├── constants/app_constants.dart
│   ├── errors/app_exception.dart  # sealed иерархия ошибок
│   ├── theme/                     # токены, темы, резолвер ThemeMode
│   ├── utils/                     # email_address.dart, date_format.dart
│   └── widgets/                   # MellowScaffold, MellowAvatar, ContactList,
│                                  # ContactTile, AccountSwitcherButton, empty state
├── domain/
│   ├── entities/                  # account, contact, message, thread, attachment
│   └── repositories/              # 5 контрактов
├── data/
│   ├── database/                  # tables.dart, app_database.dart
│   ├── mappers/                   # Row ⇄ Entity
│   ├── repositories/              # Drift-реализации
│   └── seed/demo_seed.dart        # демонстрационные данные для UI-прототипа
├── providers/
│   ├── contracts/mail_provider.dart, incremental_mail_provider.dart
│   ├── gmail/                     # endpoints, api, parser, adapter
│   ├── oauth/                     # pkce.dart, oauth_client.dart
│   ├── mime/mime_builder.dart     # RFC 5322 для отправки
│   ├── provider_factory.dart      # MailProviderKind → адаптер
│   └── discovery/provider_discovery.dart
├── services/
│   └── sync/                      # mail_sync_service, sync_state_store,
│                                  # conversation_router
└── features/
    ├── accounts/       # состояние аккаунтов (application/)
    ├── conversations/  ├── contacts/  ├── favorites/
    ├── composer/       ├── messages/  ├── settings/  └── onboarding/
```

Каталоги `services/delivery` и `services/notifications` появятся на этапах 05 и
07 — пустыми они не создаются.

### 3.1. Границы модулей Sprint 03

```
features/onboarding  → providers/gmail, services/sync      (экраны входа)
features/sync        → services/sync, providers/factory     (кнопка синхронизации)
services/sync        → domain/repositories, providers/contracts
providers/gmail      → providers/oauth, providers/mime, core
providers/oauth      ↔ core/errors, http
```

* Ни один слой выше не знает про `googleapis.com`: URL-ы живут в
  `gmail_endpoints.dart`.
* `MailSyncService` принимает `MailProvider`, поэтому фейковый провайдер в
  тестах — это тот же код, что работает с Gmail.
* `ConversationRouter` — чистая функция от «что уже в базе», поэтому правила
  группировки тестируются без БД.

## 4. DI и запуск

```
main() → bootstrap()
  ├─ WidgetsFlutterBinding
  ├─ AppDatabase.open()                     (path_provider → mellow.sqlite)
  ├─ createContainer(database:)             (overrides appDatabaseProvider)
  ├─ DemoSeed.runIfEmpty()  // debug или MELLOW_DEMO_SEED=true
  └─ runApp(UncontrolledProviderScope(MellowApp))
```

* `appDatabaseProvider` — единственная точка входа к базе. В тестах
  переопределяется на `AppDatabase.inMemory()`.
* `createContainer` используется и в проде, и в тестах, поэтому проводка не
  расходится.
* Настройки читаются асинхронно (`settingsControllerProvider`), но через
  `appSettingsProvider` доступны синхронно с дефолтами — первый кадр не мигает.

## 5. Состояние (Riverpod)

| Провайдер | Тип | Назначение |
| --- | --- | --- |
| `appDatabaseProvider` | `Provider` | экземпляр Drift |
| `*RepositoryProvider` | `Provider` | контракты репозиториев |
| `settingsControllerProvider` | `AsyncNotifierProvider` | настройки + запись |
| `appSettingsProvider` | `Provider` | синхронный доступ с дефолтами |
| `accountsProvider` / `primaryAccountProvider` | `Stream`/`Provider` | аккаунты (`features/accounts/application`) |
| `threadListProvider` | `StreamProvider` | список диалогов |
| `threadFilterProvider` | `Provider` | поиск + аккаунт + Focus Mode |
| `threadByIdProvider` / `threadMessagesProvider` | `Future`/`Stream` | экран диалога |
| `contactsProvider` / `contactByIdProvider` | `Stream`/`Future` | люди |
| `unreadCountProvider` | `StreamProvider` | бейдж навигации |
| `syncControllerProvider` | `StateNotifierProvider` | ручная синхронизация, стадии, итог |
| `syncOnLaunchProvider` | `FutureProvider` | одна попытка синхронизации при старте |
| `gmailConnectControllerProvider` | `StateNotifierProvider` | шаги подключения Gmail |
| `secureTokenStorageProvider` | `Provider` | Keychain/Keystore (в тестах — in-memory) |
| `syncStateStoreProvider` | `Provider` | курсоры и счётчик сбоев |

Правило: контроллер не хранит копию данных, которые есть в потоке из базы.
Запись → база → поток → UI.

Границы фич: фича может импортировать `application/` другой фичи (публичные
провайдеры), но никогда — её `presentation/`. Виджет, нужный двум фичам,
переезжает в `core/widgets` (`ContactList`, `MellowAvatar`,
`AccountSwitcherButton`). Правило проверяется `tool/check_structure.sh`.

## 6. Навигация

GoRouter, пути собраны в `AppRoutes`:

* `ShellRoute` — четыре вкладки (Диалоги, Люди, Избранное, Настройки) с нижней
  панелью и сохранением состояния;
* поверх шелла: `/conversations/:id`, `/contacts/:id`, `/compose`,
  `/settings/accounts`, `/settings/accounts/add`, `/settings/accounts/add/gmail`
  (реальный OAuth-поток), `/settings/sync` (ручная синхронизация),
  `/settings/appearance`, `/settings/privacy`, `/settings/about`.

Никаких строковых путей в виджетах — только `AppRoutes.*`.

## 7. Темизация

* `MellowColors extends ThemeExtension` — семантические токены
  (`surface`, `onSurfaceMuted`, `bubbleOutgoing`, `danger`, …) для светлой и
  тёмной темы.
* `MellowTheme.light()/dark()` собирает `ThemeData` (ColorScheme, AppBar,
  InputDecoration, NavigationBar, SnackBar, Switch) из токенов.
* `resolveThemeMode(settings)` — единственное место перевода предпочтения в
  `ThemeMode`.
* Масштаб текста ограничен 0.85–1.6, чтобы экстремальные системные настройки не
  ломали вёрстку, но оставались доступными.
* Контраст пар токенов проверяется тестом (`test/core/mellow_theme_test.dart`).

## 8. Ошибки

`AppException` — sealed-иерархия: `StorageException`,
`AccountAuthException`, `MailProviderException`, `ValidationException`,
`UnsupportedException`. Репозитории и адаптеры транслируют платформенные
исключения в эти типы. Сообщения безопасны (без тел писем и реквизитов).

## 9. Что появится дальше

| Этап | Изменения в архитектуре |
| --- | --- |
| 03 Mail Core | `providers/gmail`, `services/sync`, `SecureTokenStorage` |
| 04 Conversation Engine | движок группировки `threading/`, правила участников |
| 05 Composer & Attachments | `services/delivery` (очередь, сверка), кеш вложений |
| 06 Universal Providers | `providers/imap`, `providers/smtp`, `providers/outlook` |
| 07 Sync & Notifications | `services/background`, `services/notification` |
| 08 Focus & Polish | FTS5-поиск, оптимизация, релизные сборки |

Ни один этап не меняет направление зависимостей и не переносит логику в виджеты.
