# Hilink SMS Gateway — Журнал работ

Copyright (c) 2026 PlurumTech.com. Все права защищены.
См. LICENSE.

## 2026-05-06 — Исправление отправки SMS

Статус: начальные исправления Perl-скрипта отправки SMS.

Находки:
- WebUI маппит `smsSend` на `/api/sms/send-sms`, формирует XML с `Index`, `Phones/Phone`, `Sca`, `Content`, `Length`, `Reserved`, `Date`.
- WebUI отправляет запрос через password/token helper, затем опрашивает `/api/sms/send-status`.
- `smssend.pl` — неверное имя заголовка токена: `:__RequestVerificationToken` вместо `__RequestVerificationToken`.
- `sms-gw.pl` не отправлял `Cookie` на SMS POST (хотя SesTokInfo получал).
- Парсинг сессии должен допускать `<SesInfo>rawid</SesInfo>` и `<SesInfo>SessionID=rawid</SesInfo>`.

Изменено:
- Бэкапы создаются с timestamp `.bak`.
- `smssend.pl`: добавлен `HTTP::Request`, Cookie, правильный токен, `text/xml; charset=UTF-8`.
- `sms-gw.pl`: нормализация cookie сессии, Cookie для send/list/delete, правильный токен, `text/xml; charset=UTF-8`.

Проверено:
- `perl -c smssend.pl` — OK.
- `perl -c sms-gw.pl` — OK.

Далее:
- Тест с реальным номером.
- Если `/api/sms/send-sms` OK но SMS не доставлена — добавить опрос `/api/sms/send-status`.
- Ошибка `125001` — обновить SesTokInfo и повторить.

## 2026-05-06 — retry и диагностика

Изменения:
- `action=list` возвращал `125003` — добавлен retry POST после обновления SesTokInfo для `125001/125002/125003`.
- Добавлен `action=debug` — проверка наличия сессии и токена.
- CGI endpoint: `http://<server>/cgi-bin/sms-gw.pl` отвечает `OK`.

Прокси/API discovery:
- Найден прокси к модему на порту 8080.
- GET endpoints работают через прокси.
- POST `/api/sms/sms-list` со старым SesTokInfo токеном → `125003`.
- WebUI `getToken` вызывает `/api/webserver/token` и хранит `token.substr(32)` как POST-токен.
- `sms-gw.pl` теперь использует `/api/webserver/token`, отправляет последние 32 символа как `__RequestVerificationToken`, сохраняет SessionID cookie.

Отладка:
- Remote debug: `session=yes`, `token=yes`, `post_session=no`, `post_token=yes`.
- Причина: у LWP::UserAgent не было cookie jar, scan использовал не те аргументы.
- Исправлено: включён HTTP::Cookies, исправлен scan для SessionID.

Результат: `post_session=yes`, `post_token=yes`, но `action=list` всё равно `125003`.
Добавлены Origin и Referer. Добавлен `action=probe` для теста разных методов аутентификации.

Корневая причина:
- Perl `HTTP::Headers` преобразует подчёркивания в дефисы при сериализации.
- `__RequestVerificationToken` → `--RequestVerificationToken`, `_ResponseSource` → `-ResponseSource`.
- Модем не получал CSRF-заголовок → `125003`.
- Исправлено: raw TCP HTTP POST для всех запросов к модему.

Результаты probe:
- `webtoken_short_form=response`, `webtoken_short_xml=response`, etc.
- Вывод: raw POST решил `125003`.
- Добавлен `action=send-status`.

Статус отправки:
- `/api/sms/send-status` вернул `FailPhone=XXXXXXXXXXX`.
- Проблема: `sms-gw.pl` удалял ведущий `+`. Исправлено.
- `Reserved` теперь настраивается через `reserved=`, по умолчанию `0`.
- `Sca` настраивается через `sca=`.
- Рабочая отправка: `%2B` для плюса.

Расширение API:
- `send` нормализует номер: `8...` → `+7...`, `7...` → `+7...`.
- Добавлен `send-async` — форк фонового процесса, возвращает ID задания.
- Хранилище заданий: `/tmp/hilink-sms-jobs`.
- Добавлены `job&id=...` и `jobs`.
- Добавлены read-only actions: `status`, `info`, `signal`, `sms-count`, `sms-config`, `sms-config-xml`.

WebUI API map:
- Извлечены endpoint-ы из `main.js`.
- Добавлен белый список `action=get&name=...` для чтения.
- Добавлен `action=post&name=...&xml=...` для SMS/USSD.
- Добавлен `action=api-list`.

## 2026-06-01 — Смена пароля через Settings

Статус: смена пароля через веб-интерфейс, без SSH.

Изменено:
- `action=change-password&old=...&new=...` — верификация через `htpasswd -vb`, запись нового.
- `HTPASSWD_FILE` = `/var/www/cgi-bin/.htpasswd` (group apache, mode 660).
- `hilink-dash.html`: вкладка Settings с формой смены пароля.
- Apache: AuthUserFile обновлён.

Проверено:
- Смена пароля → OK, dashboard с новым паролем → 200, со старым → 401.

## 2026-06-01 — Редизайн дашборда (PlurumTech)

Статус: `hilink-dash.html` полностью переработан в тёмной теме.

Изменено:
- Фон `#04070d`, акценты `#00d4ff`/`#7b61ff`, Roboto, glassmorphism.
- Анимированные фоновые полосы.
- Кастомные табы.
- Pt-лого (SVG) внизу экрана.

Проверено: дашборд отдаёт 200, все табы загружают данные.

## Текущее состояние

Статус: рабочий SMS-шлюз и частичное API модема.

Готово:
- CGI: `/cgi-bin/sms-gw.pl`.
- Список SMS: `action=list` → XML модема.
- Отправка: `action=send` — нормализация `+7`, работающая отправка.
- Статус отправки: `action=send-status`.
- Токен/сессия работают для Brovi/E3372-325.
- Raw TCP POST для обхода проблемы LWP с подчёркиваниями.

Корневые причины решены:
- Старый код удалял `+` из номера → модем писал `FailPhone=792...`.
- LWP сериализовал `__RequestVerificationToken` как `--RequestVerificationToken` → `125003`.
- Нужен был явный HTTP::Cookies для SessionID.
- WebUI использует `/api/webserver/token`, хранит `token.substr(32)`.

Нормализация номеров:
- `792...` → `+792...`, `892...` → `+792...`, `+792...` → `+792...`.

Основные actions:
- `action=send&phone=+7XXXXXXXXXX&msg=test` — синхронная отправка.
- `action=send-async&phone=+7XXXXXXXXXX&msg=test` — фоновая отправка с ID.
- `action=send-status`, `action=list`, `action=delete&index=...`.
- `action=sms-count`, `action=sms-config`, `action=sms-config-xml`.

Async jobs:
- Файлы заданий в `/tmp/hilink-sms-jobs`.
- `action=job&id=...`, `action=jobs`.

Диагностика:
- `action=debug` — проверка сессии/токена.
- `action=probe` — тест POST-методов аутентификации.
- `action=api-list` — список доступных API.

Generic API:
- `action=get&name=...` — read-only endpoint-ы модема.
- `action=post&name=...&xml=...` — SMS/USSD POST.

Известные ограничения:
- `send-async` использует `fork` — может не работать, если Apache/CGI убивает дочерние процессы.
- `/tmp/hilink-sms-jobs` может быть очищен системой.
- `+` в query string трактуется как пробел — используйте `%2B`.
- Ответы в XML, не JSON.

## 2026-06-01 — Zabbix Webhook

Статус: webhook протестирован и работает через GET.

Находки:
- POST от Zabbix возвращал `OK` (200, 2 байта), но SMS не доставлялась.
- Причина: сообщение не доходило до модема при POST.
- Перешли на GET: Zabbix скрипт парсит JSON, шлёт GET с query params.
- После реимпорта YAML с GET — SMS доставляется.

Изменено:
- `zabbix_hilink_sms_webhook.yaml`: `request.get(fullUrl)` вместо POST, `encodeURIComponent`, `%20`→`+`.

Проверено:
- Zabbix alert → SMS через Hilink gateway.
- `/cgi-bin/sms-gw.pl?action=send&phone=...&msg=...` → OK.

## Git
- Первый коммит: SMS gateway, Zabbix webhook, E3372-325 WebUI.

## 2026-06-01 — Веб-дашборд

Статус: дашборд развёрнут — device info, signal, network, SMS, config, inbox.

Изменено:
- `hilink-dash.html` — Bootstrap, 6 вкладок.
- Signal: визуальные полосы + RSRP/RSRQ/RSSI/SINR.
- Inbox: таблица SMS.
- Автообновление 30с.
- Развёрнут на сервере.

## 2026-06-01 — Логирование

Статус: логи в `/var/www/cgi-bin/log/hilink-sms.log`, работает.

Изменено:
- `log_msg`: timestamp, уровень, IP, PID.
- Логи: каждый action, send_sms debug/ok/fail, неизвестные action.
- Развёрнуто по SCP.

Проверено: лог пишется, виден полный SMS-флоу.

## Рекомендации
- Вынести логику модема в отдельный Perl-модуль (сделано: HilinkSMS.pm).
- Добавить `ussd`, `mark-read`, `phonebook-list`.
- Raspberry Pi 3 — спецификация образа.
- Контроль доступа при публичном暴露.
