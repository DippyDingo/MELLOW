# Mellow

**Email, который ощущается как мессенджер.** Мобильное приложение (Flutter,
Android + iOS), которое подключается к существующим почтовым ящикам и превращает
переписку в аккуратные диалоги.

> **Статус: Sprint 03 — Mail Core.**
> Работают архитектура, локальная база (SQLite/Drift), темы, навигация,
> интерфейс на демо-данных и **реальная синхронизация Gmail**: OAuth 2.0 + PKCE,
> Gmail API, движок синхронизации с курсорами и дедупликацией, сборка диалогов
> по `threadId` / `In-Reply-To` / `References`. Отправка писем — Sprint 05.
> Пошаговая проверка на вашей машине — [`docs/VERIFY.md`](docs/VERIFY.md).

---

## Быстрый старт

```bash
# 1. Зависимости
flutter pub get

# 2. Генерация кода Drift (обязательно, *.g.dart в git не хранятся)
dart run build_runner build --delete-conflicting-outputs

# 3. Платформенные папки (android/, ios/) создаются один раз
flutter create --platforms=android,ios --org app.mellow --project-name mellow .

# 4. Запуск
flutter run            # демо-данные засеиваются автоматически в debug-сборке

# 5. Проверки
flutter analyze
flutter test
bash tool/check_structure.sh   # правила слоёв из AGENTS.md (не требует Dart SDK)
```

Или одной командой: `tool/bootstrap.sh`.

### Подключение своего Gmail

```bash
flutter run \
  --dart-define=GOOGLE_CLIENT_ID=1234-abc.apps.googleusercontent.com \
  --dart-define=GOOGLE_REDIRECT_URI=com.googleusercontent.apps.1234-abc:/oauth2redirect
```

(Подставьте свой client id; форма значения важнее примера.)

Без этих ключей приложение честно сообщает, что Gmail не настроен, и не
изображает успешную авторизацию. Подробности (включая регистрацию URL-схемы) —
[`docs/VERIFY.md`](docs/VERIFY.md#5-подключение-реального-gmail).

Чтобы увидеть демо-данные в release-сборке:

```bash
flutter run --dart-define=MELLOW_DEMO_SEED=true
```

---

## Что уже есть

| Слой | Реализовано |
| --- | --- |
| Архитектура | Clean Architecture + feature-first, Dependency Inversion |
| Домен | `Account`, `Contact`, `MessageThread`, `Message`, `Attachment`, контракты репозиториев |
| Данные | Drift-схема (10 таблиц), индексы, миграционная стратегия, мапперы, 5 репозиториев |
| Провайдеры | Контракт `MailProvider` + `ProviderCapabilities`; **Gmail**: OAuth 2.0 + PKCE, Gmail API (list/get/history/modify/send/attachments), парсер MIME, сборка RFC 5322 |
| Синхронизация | `MailSyncService`: инкрементальная (historyId) и полная сверка, устаревший курсор → реконкайл, дедупликация по provider id и `Message-ID`, сборка диалогов, контакты по адресу |
| Безопасность | Токены только в Keychain / EncryptedSharedPreferences, `state` + PKCE, токены никогда в логах |
| UI | 4 раздела, экран диалога, профиль человека, Smart Composer, настройки, Focus Mode |
| Темы | Светлая/тёмная/системная, дизайн-токены, проверенный контраст, масштабирование текста |
| Состояние | Riverpod: настройки, аккаунты, диалоги, контакты, поиск |
| Тесты | unit/widget/repository-тесты: адреса, даты, темы, контракты, дедупликация, настройки, навигация |

Чего **сознательно нет** (и почему — честно):

* Яндекс, Mail.ru, Outlook — Sprint 06 (экран подключения говорит об этом прямо);
* отправки писем и очереди отправки — Sprint 05 (Composer сообщает это на экране);
* фоновой синхронизации и уведомлений — Sprint 07;
* полнотекстового поиска и Focus Mode — Sprint 08.

Известное состояние среды разработки: код спринтов писался без установленного
Flutter SDK, поэтому `flutter analyze` / `flutter test` **не запускались** —
первый запуск на вашей машине и есть проверка (см. [`docs/VERIFY.md`](docs/VERIFY.md)).

---

## Структура

```
lib/
├── app/            # bootstrap, DI, навигация, корневой виджет
├── core/           # темы, ошибки, константы, утилиты, общие виджеты
├── domain/         # сущности и контракты репозиториев (без Flutter-зависимостей UI)
├── data/           # Drift-схема, мапперы, реализации репозиториев, демо-данные
├── providers/      # контракт MailProvider, Gmail API + OAuth/PKCE, MIME, discovery
├── services/       # движок синхронизации, курсоры, сборка диалогов
├── features/       # accounts, conversations, contacts, favorites, composer,
│                   # messages, settings, onboarding, sync
└── main.dart       # точка входа → app/bootstrap
```

Полное описание — [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Документация

| Документ | О чём |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) | Правила разработки с ИИ-агентом (читать первым) |
| [`docs/PRODUCT_SPEC.md`](docs/PRODUCT_SPEC.md) | Продукт, объём v1.0, ограничения |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Слои, зависимости, структура модулей |
| [`docs/DATABASE_SCHEMA.md`](docs/DATABASE_SCHEMA.md) | Таблицы, индексы, инварианты |
| [`docs/MAIL_PROVIDERS.md`](docs/MAIL_PROVIDERS.md) | Контракт адаптеров и матрица возможностей |
| [`docs/SYNC_ENGINE.md`](docs/SYNC_ENGINE.md) | Синхронизация, курсоры, дедупликация |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Токены, пароли, HTML, приватность |
| [`docs/UI_GUIDELINES.md`](docs/UI_GUIDELINES.md) | Токены, типографика, паттерны экранов |
| [`docs/TESTING.md`](docs/TESTING.md) | Стратегия тестов и критерии готовности |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Спринты 01–08 и их результаты |
| [`docs/VERIFY.md`](docs/VERIFY.md) | Как проверить приложение своими руками (сборка, тесты, Gmail) |
