# Настройка CashRadar

## Окружения

Облачный проект **Cash Radar** (`mawljmoijqhcdbmszglq`) создан владельцем в регионе `ap-northeast-1` (Токио). Он использует PostgreSQL 17 и Supabase Auth. Миграции проверки соединения и основы данных этапа 3 применены к локальной и облачной БД. Сейчас это единственный облачный проект: не использовать его как изолированную тестовую среду.

Для разработки подготовлен отдельный локальный Supabase через Docker; он использует искусственные данные, а почта перехватывается Mailpit и не отправляется получателям. Не загружайте реальные выписки до реализации RLS, закрытого Storage и проверки восстановления резервных копий.

Нужны Flutter 3.44.9 stable, Dart 3.12.2, Node.js и Supabase CLI 3 (`npx --yes supabase@3`), Docker Desktop, а также Chrome для Web, Android SDK и Xcode для мобильных сборок. Минимальная версия iOS проекта — 15.0. Точные версии Dart-зависимостей приложения — в `app/pubspec.lock`.

## Запуск локального Supabase

В Docker Desktop на macOS выберите **Settings → Resources → Network → Port binding behavior → Localhost by default**. Эта настройка влияет на публикацию портов других контейнеров по умолчанию. Ограничение только через сеть Docker на macOS может не защитить порты на хосте; после старта проверяйте их через `lsof`.

```sh
# Из корня репозитория; Docker Desktop должен быть запущен.
docker network inspect cash-radar-loopback >/dev/null 2>&1 || \
  docker network create -o com.docker.network.bridge.host_binding_ipv4=127.0.0.1 cash-radar-loopback
SUPABASE_EXPERIMENTAL_STACK=0 npx --yes supabase@3 start --network-id cash-radar-loopback
lsof -nP -iTCP:54321 -iTCP:54322 -iTCP:54323 -iTCP:54324 -iTCP:54327 -sTCP:LISTEN
python3 scripts/configure_local_supabase.py
```

На хосте должны отображаться только `127.0.0.1` и `::1`, не `*`. Скрипт создаёт игнорируемый файл `app/config/local-supabase.json` с локальным URL и публичным ключом, не перезаписывая существующий файл. Если локальные ключи изменились, обновите конфигурацию вручную. Локальный Studio — `http://127.0.0.1:54323`, перехваченные письма — `http://127.0.0.1:54324`. Обычная остановка сохраняет данные:

```sh
SUPABASE_EXPERIMENTAL_STACK=0 npx --yes supabase@3 stop
```

Не используйте `--no-backup` и `db reset`, если локальные данные нужно сохранить.

## Запуск приложения

Для локального тестирования:

```sh
cd app
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 3000 \
  --dart-define-from-file=config/local-supabase.json
```

Создайте тестовый аккаунт с адресом `example.test`, откройте письмо в Mailpit и перейдите по ссылке. Для проверки восстановления пароля запросите письмо через «Забыли пароль?». Подтверждение и восстановление используют PKCE: открывайте ссылку в том же браузере и на том же устройстве, где отправили запрос.

Для облачного проекта в `app/config/local.json` укажите `https://mawljmoijqhcdbmszglq.supabase.co` и **publishable key** из Supabase Dashboard → Connect → API Keys. Файл исключён из Git. Для запуска с облаком используйте ту же команду Flutter, заменив `config/local-supabase.json` на `config/local.json`. Разрешённые URL возврата: `http://localhost:3000/**`, `http://127.0.0.1:3000/**` и `io.cashradar.app://auth-callback/**`. После публикации Web на этапе 4 нужно добавить HTTPS-адрес опубликованного приложения в список Supabase Auth Redirect URLs и проверить возврат из писем.

Облачный Supabase требует подтверждения email. Встроенная почта предназначена для тестирования: отправляет письма только участникам организации и ограничена двумя письмами в час. Для других адресов нужна настройка собственного SMTP; тариф и условия выбранного провайдера нужно проверить отдельно. Не отключайте подтверждение адреса ради обхода ограничения. [Документация Supabase](https://supabase.com/docs/guides/auth/auth-smtp).

Публичный ключ попадает в клиентскую сборку и не является секретом. Не помещайте в приложение `service_role`, secret key, токен доступа, пароль БД или другие секреты. Приложение принимает HTTP только для явно включённой локальной конфигурации и адресов localhost, 127.0.0.1 или Android emulator 10.0.2.2; для облака требуется HTTPS.

## Сборка для Cloudflare Pages

Корень проекта — корень Git-репозитория, команда сборки — `bash scripts/build_cloudflare_pages.sh`, каталог результата — `app/build/web`. Скрипт проверяет публичные переменные `SUPABASE_URL` и `SUPABASE_PUBLISHABLE_KEY`, устанавливает Flutter 3.44.9 с проверкой ревизии и собирает приложение. Укажите обе переменные в настройках сборки Pages; ключ попадёт в публичный JavaScript, поэтому использовать можно только publishable/anon key. Секреты и локальные конфигурационные файлы в Git не добавляются.

Для прямых переходов и обновления защищённых страниц используется стандартный SPA fallback Cloudflare Pages; файл верхнего уровня `404.html` добавлять не следует. Регистрации и восстановлению пароля нужен адрес сайта в разрешённых Supabase Auth Redirect URLs. Если preview-сборки используют тот же облачный Supabase, это общее окружение с рабочими данными, а не изолированный тестовый backend; адрес каждой preview-сборки также требует отдельного разрешения для возврата из письма.

В Supabase Dashboard → Table Editor можно проверить наличие таблиц `profiles`, `banks`, `accounts`, `categories`: существующему пользователю созданы профиль и 16 категорий, в справочнике три банка. Dashboard работает с административными правами, поэтому отображение записей там само по себе не проверяет RLS; изоляцию проверяют локальные тесты ниже. Интерфейс управления счетами и категориями появится на последующих этапах.

На Android и iOS используются защищённые средства хранения системы, а браузер хранит сессию через Supabase SDK в локальном хранилище сайта: это требует защиты приложения от XSS и HTTPS на опубликованном сайте. Пароль в приложении не сохраняется. Перед публикацией заменить примерные идентификаторы пакета `com.example.cash_radar` на принадлежащие проекту и перепроверить mobile deep links.

## Миграции

Из корня репозитория:

```sh
npx --yes supabase@3 login
npx --yes supabase@3 link --project-ref mawljmoijqhcdbmszglq
npx --yes supabase@3 migration list --remote
npx --yes supabase@3 db push --dry-run --remote
npx --yes supabase@3 db push --remote
```

Перед подтверждением проверяйте целевой проект и точный список миграций. Удалённую БД не сбрасывать; применённые миграции не переписывать. Не передавайте токены или пароли в чат и не коммитьте их.

## Проверки

```sh
cd app
flutter analyze
flutter test
flutter build web
# Только изолированный локальный Supabase; создаёт и удаляет тестовых пользователей и таблицу.
flutter test --dart-define-from-file=config/local-supabase.json \
  --dart-define=RUN_LOCAL_AUTH_TESTS=true test/local_auth_integration_test.dart
# Реальные таблицы и два локальных пользователя; фикстуры удаляются после теста.
flutter test --dart-define-from-file=config/local-supabase.json \
  --dart-define=RUN_LOCAL_FOUNDATION_TESTS=true test/local_foundation_integration_test.dart
# Проверка доступности облачной БД с публичным ключом.
flutter test --dart-define-from-file=config/local.json \
  --dart-define=RUN_SUPABASE_INTEGRATION_TESTS=true test/connection_integration_test.dart
```

Интеграционные тесты отключены в обычном запуске. Тест этапа 3 проверяет настоящие профили, банки, счета и категории через API двух тестовых пользователей; тестовые пользователи и созданные ими строки удаляются после завершения. Операций и их RLS пока нет.

Для SQL-проверок и конкурентных изменений категорий из корня репозитория:

```sh
docker exec -i supabase_db_Cash-Radar psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 < supabase/tests/foundation.sql
python3 supabase/tests/category_concurrency.py
```

SQL-тест откатывает свои фикстуры; конкурентный тест создаёт и удаляет только собственного тестового пользователя. Запускать их только на локальном Supabase.
