# Hilink SMS Gateway Work Status

## 2026-05-06

Status: initial Perl SMS send fixes applied.

Findings:
- WebUI maps `smsSend` to `/api/sms/send-sms` and builds XML with `Index`, `Phones/Phone`, `Sca`, `Content`, `Length`, `Reserved`, and `Date`.
- WebUI sends the request through its password/token helper and then polls `/api/sms/send-status`.
- `smssend.pl` had an invalid token header name: `:__RequestVerificationToken` instead of `__RequestVerificationToken`.
- `sms-gw.pl` fetched `SesTokInfo` but did not send the `Cookie` header on SMS POST requests.
- Session parsing must tolerate both `<SesInfo>rawid</SesInfo>` and `<SesInfo>SessionID=rawid</SesInfo>`.

Changed:
- Backups created with timestamped `.bak` suffix for edited Perl files.
- `smssend.pl` now imports `HTTP::Request`, sends `Cookie`, sends the correct token header, and uses `text/xml; charset=UTF-8`.
- `sms-gw.pl` now normalizes session cookie, sends `Cookie` for send/list/delete, sends the correct token header, and uses `text/xml; charset=UTF-8`.

Verified:
- `perl -c smssend.pl` passes.
- `perl -c sms-gw.pl` passes.

Next:
- Test against the modem with a real phone number.
- If `/api/sms/send-sms` returns OK but SMS is not delivered, add polling of `/api/sms/send-status` like WebUI.
- If error `125001` appears, refresh `SesTokInfo` and retry once with a new token/session.

Update:
- CGI endpoint `http://192.168.5.20/cgi-bin/sms-gw.pl` responds with `OK` for the default action.
- `action=list` returned modem error `125003`, so `sms-gw.pl` now retries POST requests once after refreshing `SesTokInfo` for token/session errors `125001`, `125002`, and `125003`.
- Added `action=debug` to report whether `SesTokInfo` returns a session and token.

Proxy/API discovery:
- `http://192.168.5.20:8080` is a proxy to the modem.
- GET endpoints work through the proxy, including `/api/sms/config` and `/api/sms/sms-count`.
- POST `/api/sms/sms-list` with old `SesTokInfo` token returns `125003`.
- WebUI `getToken` calls `/api/webserver/token` and stores `token.substr(32)` as the POST token.
- `sms-gw.pl` now uses `/api/webserver/token`, sends the last 32 characters as `__RequestVerificationToken`, and keeps the `SessionID` cookie from that token request.

CGI debug result:
- Remote debug returned `session=yes`, `token=yes`, `post_session=no`, `post_token=yes`.
- Cause: `LWP::UserAgent` did not have a cookie jar enabled, and cookie scanning used the wrong callback argument positions.
- Fixed: enabled `HTTP::Cookies` cookie jar and corrected `scan` extraction for `SessionID`.

Latest remote result:
- Remote debug now returns `post_session=yes`, `post_token=yes`, but `action=list` still returns `125003`.
- Added `Origin` and `Referer` to the WebUI token POST path.
- Added `action=probe` to test SMS list with short web token, full web token, and old SesTok token across form/xml content types.

Root cause found:
- Perl `HTTP::Headers` translates underscores to dashes when serializing header names.
- `__RequestVerificationToken` became `--RequestVerificationToken`, and `_ResponseSource` became `-ResponseSource`.
- Modem therefore never received the CSRF header and returned `125003` for every POST variant.
- `sms-gw.pl` now uses a raw TCP HTTP POST for modem POST requests so header names are sent exactly as WebUI sends them.

Remote probe result:
- `webtoken_short_form=response`
- `webtoken_short_xml=response`
- `webtoken_full_form=response`
- `sestok_form=response`
- `sestok_xml=response`
- Conclusion: raw POST fixed `125003`; the modem accepts the CSRF/session data once underscore headers are sent literally.
- Added `action=send-status` for checking `/api/sms/send-status` after an SMS send attempt.

Send-status result:
- `/api/sms/send-status` returned `FailPhone=79219615926`, so SMS API accepted the send task but modem/network rejected the recipient/message.
- WebUI phone validation allows a leading `+`, but `sms-gw.pl` stripped it. Updated phone normalization to preserve one leading `+`.
- `Reserved` is now configurable with `reserved=` and defaults to `0` instead of fixed `1`.
- `Sca` is now configurable with `sca=` for testing SMS center behavior.
- Confirmed working send URL used `%2B` for leading plus.

API expansion:
- `send` now normalizes phone numbers and automatically adds `+` for Russian `7XXXXXXXXXX` and converts `8XXXXXXXXXX` to `+7XXXXXXXXXX`.
- Added `send-async` action. It forks a background sender and returns a job id immediately.
- Added job status storage under `/tmp/hilink-sms-jobs`.
- Added `job&id=...` and `jobs` actions.
- Added modem read-only actions: `status`, `info`, `signal`, `sms-count`, `sms-config`, `sms-config-xml`.
- Perl syntax check passes after the API expansion.

WebUI API map expansion:
- Extracted representative endpoint names from WebUI `main.js` API map.
- Added allowlisted generic `action=get&name=...` for safe read-only endpoints.
- Added allowlisted generic `action=post&name=...&xml=...` for selected SMS/USSD POST endpoints.
- Added `action=api-list` to expose supported allowlist names and paths.
- Kept destructive/system-changing WebUI endpoints out of the generic POST allowlist by default.
- Perl syntax check passes after adding the allowlist API.

## Current Ready State

Status: working SMS gateway and partial modem API are implemented in `sms-gw.pl`.

Ready and tested conceptually:
- CGI endpoint: `/cgi-bin/sms-gw.pl`.
- SMS list works: `action=list` returns modem XML response.
- SMS send works when the script normalizes phone to `+7...`; raw URL may pass phone without `+` as `792...` or `892...`.
- SMS send status works: `action=send-status` proxies `/api/sms/send-status`.
- Token/session handling works for Brovi/E3372-325 style WebUI token flow.
- Raw TCP POST is used for modem POST requests because Perl `HTTP::Headers` rewrites underscore headers incorrectly.

Core root causes solved:
- Old code stripped leading `+` from phone numbers; modem then reported `FailPhone=792...`.
- Perl/LWP serialized `__RequestVerificationToken` as `--RequestVerificationToken`; modem returned `125003` because the CSRF header was effectively missing.
- `LWP::UserAgent` needed an explicit `HTTP::Cookies` cookie jar to retain `SessionID` from `/api/webserver/token`.
- WebUI token flow uses `/api/webserver/token`; WebUI stores `token.substr(32)` as the POST token, but raw POST now works with accepted token/session variants.

Phone normalization:
- `79219615926` becomes `+79219615926`.
- `89219615926` becomes `+79219615926`.
- `+79219615926` remains `+79219615926`.

Main SMS actions:
- `action=send&phone=79219615926&msg=test` - synchronous SMS send.
- `action=send-async&phone=79219615926&msg=test` - forked background SMS send with job id.
- `action=send-status` - modem send status.
- `action=list` - SMS inbox list.
- `action=delete&index=...` - delete SMS by index.
- `action=sms-count` - SMS counters.
- `action=sms-config` - SMS runtime config.
- `action=sms-config-xml` - SMS XML config.

Async jobs:
- Job files are stored under `/tmp/hilink-sms-jobs`.
- `action=job&id=...` returns one job status.
- `action=jobs` returns all known job statuses.

Diagnostics:
- `action=debug` checks session/token availability.
- `action=probe` tests POST auth/token variants against `sms-list`.
- `action=api-list` returns generic API allowlist names and modem paths.

Generic allowlist API:
- `action=get&name=...` supports read-only modem endpoints from `%GET_API`.
- `action=post&name=...&xml=...` supports selected SMS/USSD POST endpoints from `%POST_API`.
- Dangerous/system-changing WebUI endpoints are intentionally not exposed generically.

Useful generic GET examples:
- `action=get&name=monitoringStatus`
- `action=get&name=deviceInformation`
- `action=get&name=deviceSignal`
- `action=get&name=netCurrentPlmn`
- `action=get&name=cellInfo`
- `action=get&name=pinStatus`
- `action=get&name=smsCount`
- `action=get&name=smsConfig`

Known caveats:
- `send-async` relies on Linux `fork` in CGI; if Apache/CGI policy kills child processes, use synchronous `send` or move queue processing to a daemon/cron worker.
- `/tmp/hilink-sms-jobs` may be cleaned by the OS; use `/var/tmp` or an app-owned directory for persistent job history.
- Query-string `+` is treated as space by URL encoding rules; clients may send numbers without `+`, or encode plus as `%2B`.
- Responses are currently XML/text, not JSON.

## 2026-06-01 — Zabbix Webhook Integration Complete

Status: Zabbix webhook fully tested and working via GET method.

Findings:
- Zabbix webhook POST method returned `OK` but SMS not delivered; `send-status` showed empty `SucPhone/FailPhone`.
- Root cause: POST from Zabbix returned 200 with 2 bytes ("OK") but message content apparently not reaching modem.
- Switched to GET-based webhook — Zabbix script now parses `value` as optional JSON string and issues GET request with query params.
- Tested: `curl "http://192.168.5.20/cgi-bin/sms-gw.pl?action=send&phone=79219615926&msg=test"` confirmed working.
- After re-importing YAML with GET method, SMS delivered via Zabbix alert.

Changed:
- `zabbix_hilink_sms_webhook.yaml`: webhook script now does `request.get(fullUrl)` instead of POST; parses `value` as JSON string; uses `encodeURIComponent` with `%20`→`+` for message encoding.
- No changes to `sms-gw.pl` — GET-based sending already worked.
- `smsjob.md` updated with final status.

Verified:
- Zabbix alert successfully delivers SMS via Hilink gateway using GET webhook.
- CGI endpoint `/cgi-bin/sms-gw.pl?action=send&phone=...&msg=...` returns `OK`.
- All prior Perl syntax checks pass.

## Git
- First commit: initial project — working SMS gateway, Zabbix webhook, E3372-325 extracted WebUI.

Recommended next steps:
- Move Hilink modem logic from `sms-gw.pl` into a reusable Perl module, for example `Hilink/Brovi.pm`.
- Add explicit safe actions for `ussd`, `mark-read`, `phonebook-list`, and optional `data-on/data-off` only after confirming desired XML bodies.
- Add file-based logging to `sms-gw.pl` (e.g., `/var/log/hilink-sms.log`).
- Create Raspberry Pi 3 system image specification and build plan.
- Add access control for CGI if exposed beyond the trusted LAN.
