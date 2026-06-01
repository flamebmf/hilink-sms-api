# Hilink SMS Gateway — Work Log

Copyright (c) 2026 PlurumTech.com. All rights reserved.
See LICENSE for terms.

## 2026-05-06 — Initial SMS Send Fixes

Status: initial Perl SMS send fixes applied.

Findings:
- WebUI maps `smsSend` to `/api/sms/send-sms` and builds XML with `Index`, `Phones/Phone`, `Sca`, `Content`, `Length`, `Reserved`, and `Date`.
- WebUI sends the request through its password/token helper and then polls `/api/sms/send-status`.
- `smssend.pl` had an invalid token header name: `:__RequestVerificationToken` instead of `__RequestVerificationToken`.
- `sms-gw.pl` fetched `SesTokInfo` but did not send the `Cookie` header on SMS POST requests.
- Session parsing must tolerate both `<SesInfo>rawid</SesInfo>` and `<SesInfo>SessionID=rawid</SesInfo>`.

Changed:
- Backups created with timestamped `.bak` suffix.
- `smssend.pl` now imports `HTTP::Request`, sends `Cookie`, correct token header, `text/xml; charset=UTF-8`.
- `sms-gw.pl` now normalizes session cookie, sends `Cookie` for send/list/delete, correct token header, `text/xml; charset=UTF-8`.

Verified:
- `perl -c smssend.pl` passes.
- `perl -c sms-gw.pl` passes.

Next:
- Test against the modem with a real phone number.
- If `/api/sms/send-sms` returns OK but SMS is not delivered, add polling of `/api/sms/send-status`.
- If error `125001` appears, refresh `SesTokInfo` and retry.

## 2026-05-06 — Retry and Diagnostics

Changes:
- `action=list` returned `125003` — added POST retry after SesTokInfo refresh for `125001/125002/125003`.
- Added `action=debug` to report session/token status.
- CGI endpoint `http://<server>/cgi-bin/sms-gw.pl` responds `OK`.

Proxy/API discovery:
- Proxy to modem found on port 8080.
- GET endpoints work through the proxy.
- POST `/api/sms/sms-list` with old SesTokInfo token returns `125003`.
- WebUI `getToken` calls `/api/webserver/token` and stores `token.substr(32)` as POST token.
- `sms-gw.pl` now uses `/api/webserver/token`, sends last 32 chars as `__RequestVerificationToken`, keeps SessionID cookie.

Debug:
- Remote debug: `session=yes`, `token=yes`, `post_session=no`, `post_token=yes`.
- Cause: LWP::UserAgent had no cookie jar; scan used wrong argument positions.
- Fixed: enabled HTTP::Cookies, fixed SessionID extraction.

Result: `post_session=yes`, `post_token=yes`, but `action=list` still `125003`.
Added Origin and Referer. Added `action=probe` to test all auth methods.

Root cause:
- Perl `HTTP::Headers` translates underscores to dashes when serializing headers.
- `__RequestVerificationToken` → `--RequestVerificationToken`, `_ResponseSource` → `-ResponseSource`.
- Modem never received CSRF header → `125003`.
- Fixed: raw TCP HTTP POST for all modem requests.

Probe results:
- `webtoken_short_form=response`, `webtoken_short_xml=response`, etc.
- Conclusion: raw POST fixes `125003`.
- Added `action=send-status`.

Send status:
- `/api/sms/send-status` returned `FailPhone=XXXXXXXXXXX`.
- Issue: `sms-gw.pl` stripped leading `+`. Fixed.
- `Reserved` now configurable via `reserved=`, defaults to `0`.
- `Sca` configurable via `sca=`.
- Working send URL uses `%2B` for leading plus.

API expansion:
- `send` normalizes phone: `8...` → `+7...`, `7...` → `+7...`.
- Added `send-async` — forks background process, returns job ID.
- Job storage: `/tmp/hilink-sms-jobs`.
- Added `job&id=...` and `jobs`.
- Added read-only actions: `status`, `info`, `signal`, `sms-count`, `sms-config`, `sms-config-xml`.

WebUI API map:
- Extracted endpoints from `main.js`.
- Added allowlist: `action=get&name=...` (read-only).
- Added `action=post&name=...&xml=...` (SMS/USSD).
- Added `action=api-list`.

## 2026-06-01 — Password Change via Settings Tab

Status: password change via web UI, no SSH needed.

Changed:
- `action=change-password&old=...&new=...` — verifies via `htpasswd -vb`, writes new hash.
- `HTPASSWD_FILE` = `/var/www/cgi-bin/.htpasswd` (group apache, mode 660).
- `hilink-dash.html`: Settings tab with password form.
- Apache: AuthUserFile updated.

Verified:
- Password change → OK, dashboard with new password → 200, old password → 401.

## 2026-06-01 — Dashboard Redesign (PlurumTech)

Status: `hilink-dash.html` fully redesigned in dark theme.

Changed:
- Background `#04070d`, accents `#00d4ff`/`#7b61ff`, Roboto, glassmorphism cards.
- Animated background bars.
- Custom tabs instead of nav-pills.
- Pt logo (SVG) at bottom.

Verified: dashboard returns 200, all tabs load data.

## Current Ready State

Status: working SMS gateway and partial modem API.

Ready:
- CGI: `/cgi-bin/sms-gw.pl`.
- SMS list: `action=list` → modem XML.
- Send: `action=send` — normalizes `+7`, working delivery.
- Send status: `action=send-status`.
- Token/session working for Brovi/E3372-325.
- Raw TCP POST for underscore header fix.

Core root causes solved:
- Old code stripped `+` from phone → modem returned `FailPhone=792...`.
- LWP serialized `__RequestVerificationToken` as `--RequestVerificationToken` → `125003`.
- Needed explicit HTTP::Cookies jar for SessionID.
- WebUI uses `/api/webserver/token`, stores `token.substr(32)`.

Phone normalization:
- `792...` → `+792...`, `892...` → `+792...`, `+792...` → `+792...`.

Main actions:
- `action=send&phone=+7XXXXXXXXXX&msg=test` — sync send.
- `action=send-async&phone=+7XXXXXXXXXX&msg=test` — background send with job ID.
- `action=send-status`, `action=list`, `action=delete&index=...`.
- `action=sms-count`, `action=sms-config`, `action=sms-config-xml`.

Async jobs:
- Job files in `/tmp/hilink-sms-jobs`.
- `action=job&id=...`, `action=jobs`.

Diagnostics:
- `action=debug` — session/token check.
- `action=probe` — POST auth method test.
- `action=api-list` — available API list.

Generic API:
- `action=get&name=...` — read-only modem endpoints.
- `action=post&name=...&xml=...` — SMS/USSD POST.

Caveats:
- `send-async` relies on `fork` — may not work if Apache kills child processes.
- `/tmp/hilink-sms-jobs` may be cleaned by OS.
- `+` in query string treated as space — use `%2B`.
- Responses are XML, not JSON.

## 2026-06-01 — Zabbix Webhook Integration

Status: webhook tested and working via GET method.

Findings:
- Zabbix POST returned `OK` (200, 2 bytes) but SMS not delivered.
- Root cause: message not reaching modem via POST.
- Switched to GET: Zabbix script parses JSON, sends GET with query params.
- After re-importing YAML with GET — SMS delivered.

Changed:
- `zabbix_hilink_sms_webhook.yaml`: `request.get(fullUrl)` instead of POST, `encodeURIComponent`, `%20`→`+`.

Verified:
- Zabbix alert → SMS via Hilink gateway.
- `/cgi-bin/sms-gw.pl?action=send&phone=...&msg=...` → OK.

## Git
- First commit: SMS gateway, Zabbix webhook, E3372-325 WebUI.

## 2026-06-01 — Web Dashboard

Status: dashboard deployed — device info, signal, network, SMS, config, inbox.

Changed:
- `hilink-dash.html` — Bootstrap, 6 tabs.
- Signal: visual bars + RSRP/RSRQ/RSSI/SINR.
- Inbox: SMS table.
- Auto-refresh 30s.
- Deployed to server.

## 2026-06-01 — File-based Logging

Status: logging to `/var/www/cgi-bin/log/hilink-sms.log`, working.

Changed:
- `log_msg`: timestamp, level, IP, PID.
- Logs: every action, send_sms debug/ok/fail, unknown actions.
- Deployed via SCP.

Verified: log written, full SMS flow visible.

## Recommendations
- Extract modem logic to separate Perl module (done: HilinkSMS.pm).
- Add `ussd`, `mark-read`, `phonebook-list`.
- Raspberry Pi 3 system image spec.
- Access control if exposed beyond LAN.
