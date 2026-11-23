# Mellow

**Email, который ощущается как мессенджер.** Мобильное приложение (Flutter,
Android + iOS), которое подключается к существующим почтовым ящикам и превращает
переписку в аккуратные диалоги.

> **Статус: Sprint 01 — Foundation.**
> Работают архитектура, локальная база (SQLite/Drift), темы, навигация и
> интерфейс на демонстрационных данных. Подключение реальной почты — следующий
> этап (см. [`docs/ROADMAP.md`](docs/ROADMAP.md)).

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
| Провайдеры | Контракт `MailProvider` + `ProviderCapabilities`, определение провайдера по домену |
| UI | 4 раздела, экран диалога, профиль человека, Smart Composer, настройки, Focus Mode |
| Темы | Светлая/тёмная/системная, дизайн-токены, проверенный контраст, масштабирование текста |
| Состояние | Riverpod: настройки, аккаунты, диалоги, контакты, поиск |
| Тесты | unit/widget/repository-тесты: адреса, даты, темы, контракты, дедупликация, настройки, навигация |

Чего **сознательно нет** (и почему — честно):

* реальной авторизации Gmail/Яндекс/Mail.ru/Outlook — этап 03 и 06;
* отправки писем — Composer честно говорит, что отправка ещё не подключена;
* фоновой синхронизации и уведомлений — этап 07.

---

## Структура

```
lib/
├── app/            # bootstrap, DI, навигация, корневой виджет
├── core/           # темы, ошибки, константы, утилиты, общие виджеты
├── domain/         # сущности и контракты репозиториев (без Flutter-зависимостей UI)
├── data/           # Drift-схема, мапперы, реализации репозиториев, демо-данные
├── providers/      # контракт MailProvider и определение провайдера
├── features/       # accounts, conversations, contacts, favorites, composer,
│                   # messages, settings, onboarding
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
