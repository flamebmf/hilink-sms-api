# Hilink SMS Gateway — API Reference

Copyright (c) 2026 PlurumTech.com. See [LICENSE](LICENSE) for terms.

---

## Quick Start

```bash
# CLI — directly to modem, no setup
perl sms-gw.pl phone=79219615926 text="Hello"

# CGI — via Apache (after install)
curl "http://host/cgi-bin/sms-gw.pl?action=send&phone=79219615926&msg=Hello"

# Daemon — standalone HTTP
perl hilink-smsd.pl --daemon --port 8080
curl "http://localhost:8080/cgi-bin/sms-gw.pl?action=signal"
```

---

## 1. CGI Gateway API

Base URL: `http://<host>/cgi-bin/sms-gw.pl`

All requests require [Apache Basic Auth](#authentication) unless from the whitelisted Zabbix server IP.

### Authentication

- Default credentials: `admin` / `hilink2026`
- Changed via Settings tab or `?action=change-password`
- Zabbix server IP configured in `hilink-auth.conf` bypasses auth

---

### 1.1 SMS

#### `action=send`
Send SMS synchronously.

| Param | Required | Description |
|-------|----------|-------------|
| `phone` | yes | Phone number (auto-normalized: `8...` → `+7...`) |
| `msg` | yes | Message text |

**Response:** `OK` or `ERROR: <details>`

```bash
curl "http://host/cgi-bin/sms-gw.pl?action=send&phone=79219615926&msg=Hello"
```

#### `action=send-async`
Send SMS in background (fork). Returns job ID immediately.

| Param | Required | Description |
|-------|----------|-------------|
| `phone` | yes | Phone number |
| `msg` | yes | Message text |

**Response:** XML with `<id>` and `<status>`.

```bash
curl "http://host/cgi-bin/sms-gw.pl?action=send-async&phone=79219615926&msg=Hello"
```

#### `action=send-status`
Check modem send status.

**Response:** Raw modem XML (`<response><SucPhone>...</SucPhone><FailPhone>...</FailPhone></response>`)

#### `action=list`
List SMS inbox (BoxType=1, up to 50 messages).

**Response:** Raw modem XML.

#### `action=list-outbox`
List outbox (BoxType=2 by default).

| Param | Default | Description |
|-------|---------|-------------|
| `box` | `2` | BoxType (2=outbox, 3=draft) |

**Response:** Raw modem XML.

#### `action=delete`
Delete a single SMS by index.

| Param | Required | Description |
|-------|----------|-------------|
| `index` | yes | Message Index from list |

#### `action=clear-box`
Delete all messages in a box.

| Param | Default | Description |
|-------|---------|-------------|
| `type` | `inbox` | `inbox` (BoxType=1), `outbox` (BoxType=2), `draft` (BoxType=3) |

**Response:** `OK: deleted X/Y`

---

### 1.2 Async Job Management

Jobs stored in `/tmp/hilink-sms-jobs/` on server.

#### `action=jobs`
List all async jobs.

**Response:** XML list of jobs with `id`, `status`, `phone`.

#### `action=job`
Get single job status.

| Param | Required | Description |
|-------|----------|-------------|
| `id` | yes | Job ID |

**Response:** XML with full job data.

---

### 1.3 Device Info (read-only shortcuts)

| Action | Modem API Called |
|--------|-----------------|
| `action=status` | `api/monitoring/status` |
| `action=info` | `api/device/information` |
| `action=signal` | `api/device/signal` |
| `action=sms-count` | `api/sms/sms-count` |
| `action=sms-config` | `api/sms/config` |
| `action=sms-config-xml` | `config/sms/config.xml` |

---

### 1.4 Generic API Passthrough

#### `action=get&name=...`
Call any read-only modem API by name.

```bash
curl "http://host/cgi-bin/sms-gw.pl?action=get&name=cellInfo"
```

Full list of available names via `action=api-list`.

#### `action=post&name=...&xml=...`
POST to a modem API with custom XML body (only selected SMS/USSD APIs).

```bash
curl "http://host/cgi-bin/sms-gw.pl?action=post&name=smsList&xml=<?xml...>"
```

#### `action=api-list`
List all available GET and POST API names with their paths.

**Response:** XML with `<Get>` and `<Post>` sections.

---

### 1.5 Auth

#### `action=change-password`
Change Apache Basic Auth password.

| Param | Required | Description |
|-------|----------|-------------|
| `old` | yes | Current password |
| `new` | yes | New password (min 4 chars) |

**Response:** `OK` or `ERROR: <reason>`

---

### 1.6 Diagnostics

| Action | Description |
|--------|-------------|
| `action=debug` | Show session/token presence |
| `action=probe` | Test all auth/CSRF methods against sms-list |

---

## 2. CLI Mode (No Apache)

`sms-gw.pl` auto-detects CLI mode when run from command line (no `GATEWAY_INTERFACE` env).

`hilink-sms-cli.pl` is a lightweight alternative with the same behaviour.

Both talk directly to the modem at `192.168.8.1`.

```bash
perl sms-gw.pl phone=79219615926 text="Alert message"
perl hilink-sms-cli.pl phone=79219615926 msg="Alert message"
```

### Arguments

| Arg | Alias | Required | Description |
|-----|-------|----------|-------------|
| `phone=` | — | yes | Phone number (auto-normalized) |
| `text=` | `msg=` | yes | Message text |

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | SMS sent successfully |
| 1 | Error (invalid args or send failed) |

### Quiet mode (`hilink-sms-cli.pl` only)

```bash
perl hilink-sms-cli.pl -q phone=79219615926 text="Alert"
```
No output, exit code only — for scripts and cron.

---

## 3. Modem Native HiLink API

Modem at `http://192.168.8.1/`.

### Token & Session

**GET** `api/webserver/SesTokInfo`
- Returns `<SesInfo>` and `<TokInfo>` for GET requests.

**GET** `api/webserver/token`
- Returns `<token>` (64 chars). `token.substr(32)` used as `__RequestVerificationToken` header for POST requests.

### POST Requirements

Headers:
```
__RequestVerificationToken: <short_token>
Cookie: SessionID=<value>
_ResponseSource: Broswer
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
```

### Read-Only GET Endpoints

| Name | Path | Description |
|------|------|-------------|
| monitoringStatus | `api/monitoring/status` | Connection status, signal bars, etc. |
| checkNotifications | `api/monitoring/check-notifications` | Pending notifications |
| trafficStatistics | `api/monitoring/traffic-statistics` | TX/RX bytes |
| deviceInformation | `api/device/information` | IMEI, firmware, serial |
| deviceBasicInfo | `api/device/basic_information` | Device name, vendor |
| deviceSignal | `api/device/signal` | RSSI, RSRP, RSRQ, SINR |
| deviceBootTime | `api/device/boot_time` | Uptime |
| pinStatus | `api/pin/status` | PIN state |
| simlockStatus | `api/pin/simlock` | SIM lock status |
| netCurrentPlmn | `api/net/current-plmn` | Current operator (MCC/MNC) |
| netMode | `api/net/net-mode` | Network mode (4G/3G/2G) |
| netModeList | `api/net/net-mode-list` | Available modes |
| netNetwork | `api/net/network` | Full network info |
| cellInfo | `api/net/cell-info` | Cell tower info |
| cspsState | `api/net/csps_state` | CS/PS domain state |
| lteBandInfo | `api/net/lte-band-info` | LTE band |
| dialupConnection | `api/dialup/connection` | Dial-up status |
| mobileDataSwitch | `api/dialup/mobile-dataswitch` | Data on/off state |
| dialupProfiles | `api/dialup/profiles` | APN profiles |
| smsCount | `api/sms/sms-count` | SMS counters (local inbox/outbox/draft, SIM inbox) |
| smsConfig | `api/sms/config` | SMS center, validity |
| smsSplitinfo | `api/sms/splitinfo-sms` | SMS split info |
| smsFeatureSwitch | `api/sms/sms-feature-switch` | SMS feature flags |
| pbCount | `api/pb/pb-count` | Phonebook count |
| pbList | `api/pb/pb-list` | Phonebook entries |
| pbMatch | `api/pb/pb-match` | Phonebook match |
| timeout | `api/time/timeout` | Session timeout |
| globalModule | `api/global/module-switch` | Module features |
| wlanStationInformation | `api/wlan/station-information` | Connected WiFi stations |
| hostList | `api/system/HostInfo` | LAN hosts |
| dhcpSettings | `api/dhcp/settings` | DHCP config |
| securityNat | `api/security/nat` | NAT settings |
| firewallSwitch | `api/security/firewall-switch` | Firewall state |
| dmzStatus | `api/security/dmz` | DMZ config |
| upnpList | `api/security/upnp` | UPnP rules |
| systemLog | `api/log/loginfo` | System log |

### Configuration XML (GET, `config/<module>/<name>.xml`)

| Name | Path | Description |
|------|------|-------------|
| smsConfigXml | `config/sms/config.xml` | SMS config |
| networkModeXml | `config/network/networkmode.xml` | Network mode config |
| netModeXml | `config/network/net-mode.xml` | Net mode config |
| netTypeXml | `config/global/net-type.xml` | Net type config |
| dialupConfigXml | `config/dialup/config.xml` | Dial-up config |
| connectModeXml | `config/dialup/connectmode.xml` | Connect mode config |
| pbConfigXml | `config/pb/config.xml` | Phonebook config |
| ussdConfigXml | `config/ussd/config.xml` | USSD config |
| globalConfigXml | `config/global/config.xml` | Global config |

### POST Endpoints (SMS/USSD)

| Name | Path | Required XML |
|------|------|-------------|
| smsList | `api/sms/sms-list` | `<request><PageIndex>1</PageIndex><ReadCount>50</ReadCount><BoxType>1</BoxType><SortType>0</SortType><Ascending>0</Ascending><UnreadPreferred>0</UnreadPreferred></request>` |
| smsSetRead | `api/sms/set-read` | `<request><Index>1</Index></request>` |
| smsDelete | `api/sms/delete-sms` | `<request><Index>1</Index></request>` |
| smsSendStatus | `api/sms/send-status` | `<request></request>` |
| ussdSend | `api/ussd/send` | `<request><content>*100#</content><codeType>BG7Urd</codeType></request>` |
| ussdGet | `api/ussd/get` | `<request></request>` |
| ussdRelease | `api/ussd/release` | `<request></request>` |

---

## 4. SMS BoxType Reference

| BoxType | Counter | Description |
|---------|---------|-------------|
| 1 | LocalInbox | Inbox (received messages) |
| 2 | LocalOutbox | Sent messages (lifetime counter, never decrements) |
| 3 | LocalDraft | Draft messages (counter decrements on clear) |

**Note:** BoxType 2 and 3 may return identical data on some firmware versions. Both show sent messages with `Smstat=3`.

---

## 5. Standalone Daemon

The API can run as a standalone HTTP server without Apache.

```bash
perl hilink-smsd.pl --daemon --port 8080
```

Then use `http://localhost:8080/cgi-bin/sms-gw.pl?action=...` — same API, no Apache or auth needed.

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--daemon` | off | Run as HTTP server (required) |
| `--port` | 8080 | Listen port |
| `--host` | 0.0.0.0 | Bind address |

### Daemon vs CGI

| Aspect | CGI (Apache) | Standalone |
|--------|-------------|------------|
| Auth | Apache Basic Auth | No built-in auth |
| Port | 80/443 | 8080 |
| Start | Apache handles | `perl hilink-smsd.pl --daemon` |
| Log file | `/var/www/cgi-bin/log/hilink-sms.log` | Same |
| Location | Server | Any machine with modem access |

---

## 6. Files

| File | Purpose |
|------|---------|
| `HilinkSMS.pm` | Core module — all modem logic |
| `sms-gw.pl` | CGI + CLI dual-mode |
| `hilink-sms-cli.pl` | CLI-only (lightweight) |
| `hilink-smsd.pl` | Standalone HTTP daemon |
| `hilink-dash.html` | Web dashboard UI |
| `hilink-auth.conf` | Apache Basic Auth config |
| `zabbix_hilink_sms_webhook.yaml` | Zabbix media type import |

---

## 7. Deployment

See [README.md](README.md) for full installation instructions.
