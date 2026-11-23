# Как проверить Mellow самостоятельно

Этот файл — пошаговая инструкция для человека, который хочет убедиться, что код
действительно работает, а не только «написан». Все шаги выполняются на вашей
машине: в среде, где готовился код, Flutter/Dart не был установлен, поэтому
`flutter analyze` и `flutter test` там ни разу не запускались.

> Время: ~10 минут до запуска приложения, ~2 минуты на все проверки, если SDK
> уже установлен.

---

## 0. Что понадобится

| Инструмент | Версия | Проверка |
| --- | --- | --- |
| Flutter | 3.24+ (Dart 3.5+) | `flutter --version` |
| Android Studio / Android SDK | API 34+ | `flutter doctor` |
| Xcode (только для iOS) | 15+ | `flutter doctor` |
| Git | любая | `git --version` |

`flutter doctor` должен быть зелёным для вашей платформы. Java для Gradle
ставится вместе с Android Studio.

---

## 1. Код генерируется один раз

Drift генерирует `*.g.dart`, которые **не хранятся в git** (это осознанное
решение: сгенерированный код не рецензируется). Без этого шага проект не
скомпилируется — это ожидаемо, а не ошибка.

```bash
git clone https://github.com/DippyDingo/MELLOW.git
cd MELLOW
git checkout arena/ef9ea789-mellow     # ветка со спринтами 01–03

flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Ожидаемый результат: в `lib/data/database/` появились файлы `*.g.dart`,
сборка завершилась сообщением `Succeeded after ...`.

Альтернатива — один скрипт, который делает всё сразу (включая создание
платформенных папок):

```bash
bash tool/bootstrap.sh
```

---

## 2. Платформенные папки

`android/` и `ios/` в репозитории намеренно отсутствуют: они генерируются под
вашу версию Flutter и содержат машинно-зависимые файлы. Создаются один раз:

```bash
flutter create --platforms=android,ios --org app.mellow --project-name mellow .
```

Команда не перезапишет `lib/`, `pubspec.yaml` и документацию.

---

## 3. Автоматические проверки

```bash
flutter analyze                 # ожидаемо: No issues found!
flutter test                    # ожидаемо: All tests passed!
bash tool/check_structure.sh    # ожидаемо: ✓ architecture rules hold
```

`tool/check_structure.sh` не требует Dart SDK и проверяет архитектурные
ограничения из `AGENTS.md` (домен без Flutter, фичи не лезут друг другу в
`presentation/`, цвета только из темы).

Проверить только новые модули Sprint 03:

```bash
flutter test test/services test/providers
```

---

## 4. Запуск приложения

```bash
flutter run                                   # debug: демо-данные засеиваются сами
flutter run --dart-define=MELLOW_DEMO_SEED=true   # демо-данные и в release
```

Что должно быть видно сразу:

1. Запуск без падения, сплэш → список диалогов с демо-перепиской.
2. Четыре таба: **Диалоги**, **Люди**, **Избранное**, **Настройки**.
3. Настройки → **Оформление**: светлая / тёмная / системная тема; выбор
   сохраняется после перезапуска приложения.
4. Настройки → **Размер текста**: список диалогов перестраивается.
5. Перезапуск: демо-данные не дублируются (дедупликация по `provider_id`).

---

## 5. Подключение реального Gmail

Без своих OAuth-ключей кнопка подключения честно скажет, что Gmail не настроен
в этой сборке — приложение не притворяется, что авторизация прошла.

### 5.1. Создать OAuth-клиент

1. [Google Cloud Console](https://console.cloud.google.com/) → новый проект.
2. **APIs & Services → Library** → включить **Gmail API**.
3. **OAuth consent screen** → тип **External**, добавьте себя в *Test users*.
4. **Credentials → Create credentials → OAuth client ID** → тип
   **Android** (или **iOS**).
   * Для Android нужны имя пакета `app.mellow.mellow` и SHA-1 отпечаток
     debug-ключа:
     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore \
       -alias androiddebugkey -storepass android -keypass android | grep SHA1
     ```
   * Для iOS — bundle id `app.mellow.mellow`.
5. Скопируйте **Client ID**. Redirect URI для мобильного клиента Google
   выдаёт сам: `com.googleusercontent.apps.<ID>:/oauth2redirect`.

### 5.2. Запустить с ключами

```bash
flutter run \
  --dart-define=GOOGLE_CLIENT_ID=1234567890-abcdef.apps.googleusercontent.com \
  --dart-define=GOOGLE_REDIRECT_URI=com.googleusercontent.apps.1234567890-abcdef:/oauth2redirect
```

С запрошенными правами: `gmail.readonly`, `gmail.send`, `gmail.modify`,
`openid`, `email`, `profile` (см. `lib/providers/gmail/gmail_endpoints.dart`).

Важно: `com.googleusercontent.apps...` — это **схема** URL. Чтобы система
вернула вас в приложение, эта схема должна быть зарегистрирована в
`android/app/src/main/AndroidManifest.xml` (`<intent-filter>` с
`android:scheme`) и в `ios/Runner/Info.plist` (`CFBundleURLTypes`). Пока
платформенных папок нет, добавьте их после `flutter create` — это единственное
место, где нужна ручная правка.

### 5.3. Пройти поток

1. Настройки → **Аккаунты** → **Добавить**.
2. Введите адрес Gmail → **Продолжить** → откроется браузер.
3. Выдайте доступ; браузер вернётся в приложение (или вставьте URL из адресной
   строки в поле на экране — предусмотрен ручной путь).
4. Экран показывает реальные стадии: обмен кода → проверка доступа → первая
   синхронизация.
5. Готово: диалоги появились в списке, в **Настройки → Синхронизация** видно
   время последней синхронизации.

Что проверить отдельно:

* **Токен не в логах**: `flutter logs` не должен содержать `ya29.` или
  `1//0`.
* **Токен в Keychain/Keystore**: перезапустите приложение — повторной
  авторизации не требуется.
* **Отмена доступа**: в браузере нажмите «Отмена» — аккаунт не создаётся,
  появляется понятное сообщение.
* **Повторная синхронизация**: Настройки → Синхронизация → «Синхронизировать
  сейчас»; в списке не появляются дубликаты.
* **Полная сверка**: кнопка ↻ в шапке того же экрана.

---

## 6. Проверка ключевых сценариев вручную

| Что проверить | Как | Ожидаемо |
| --- | --- | --- |
| Персистентность | добавить контакт в избранное, перезапустить | избранное на месте |
| Дедупликация писем | «Синхронизировать сейчас» 3 раза | число диалогов не растёт |
| Группировка | ответ на письмо в Gmail | письмо попадает в тот же диалог |
| Кодировка | письмо с русской темой | тема читается, без «=??UTF-8?B?» |
| Безопасный HTML | письмо с внешней картинкой | картинка не загружается автоматически |
| Тема | переключить тему, закрыть приложение | выбор сохранён |
| Масштаб текста | увеличить шрифт системы | вёрстка не ломается |
| Ошибка сети | включить авиарежим → «Синхронизировать» | понятная ошибка, данные не теряются |

---

## 7. Сборка релиза

```bash
flutter build apk --debug                      # Android, проверка компиляции
flutter build appbundle --release              # Android release (нужен keystore)
flutter build ios --no-codesign                # iOS, только macOS
```

---

## 8. Если что-то не работает

| Симптом | Причина | Решение |
| --- | --- | --- |
| `Target of URI doesn't exist: '*.g.dart'` | не запускался build_runner | шаг 1 |
| `No issues found!` не появляется, ошибки в `data/database` | устаревший кэш генерации | `dart run build_runner build --delete-conflicting-outputs` |
| `Gmail не настроен в этой сборке` | нет `--dart-define=GOOGLE_CLIENT_ID` | шаг 5.2 |
| Браузер не возвращает в приложение | не зарегистрирована URL-схема | шаг 5.2, конец |
| `redirect_uri_mismatch` | тип OAuth-клиента — Web, а не Android/iOS | пересоздайте клиент |
| `Access blocked: app not verified` | вы не в списке Test users | добавьте себя в OAuth consent screen |
| `flutter test` падает на `AppDatabase` | нет `sqlite3_flutter_libs` на десктопе/CI | тесты рассчитаны на `NativeDatabase.memory()`, запускайте на устройстве/эмуляторе или в `flutter test` с установленным SQLite |

---

## 9. Что ещё не работает (честный список)

* Отправка писем и очередь отправки — Sprint 05. Composer это пишет прямо на
  экране.
* Яндекс, Mail.ru, Outlook — Sprint 06. Экран подключения говорит об этом
  вместо мнимой настройки.
* Фоновая синхронизация и уведомления — Sprint 07.
* Полнотекстовый поиск (FTS5), Focus Mode, локализация через ARB, экран
  «Хранилище» — Sprint 08.

Актуальный статус — в [`ROADMAP.md`](ROADMAP.md).

---

## 10. Быстрый чек-лист «всё честно работает»

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze                 # 0 issues
flutter test                    # all green
bash tool/check_structure.sh    # ✓
flutter run                     # приложение стартует, 4 таба, тема сохраняется
```

Если все пять пунктов зелёные — код рабочий, а не «написанный вслепую».
