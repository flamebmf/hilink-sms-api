# hilink-sms-api

Perl CGI SMS gateway for Brovi/Huawei HiLink LTE modems (E3372-325). Provides a web dashboard and Zabbix webhook integration for alert notifications.

Copyright (c) 2026 PlurumTech.com. See [LICENSE](LICENSE) for terms.

## Features

- Send SMS via modem HTTP API
- Async SMS sending with job queue
- Web dashboard: device status, signal info, network, SMS inbox/outbox
- Zabbix 6+ GET-based webhook alert integration
- Apache Basic Auth protection
- Phone number normalization (`8...` → `+7...`)

## Requirements

- Apache httpd with mod_cgi
- Perl 5 with `CGI`, `IO::Socket::INET`, `JSON` modules
- HiLink modem (E3372-325 or similar) at `192.168.8.1`

## Files

| File | Purpose |
|------|---------|
| `sms-gw.pl` | Main CGI handler (send SMS, API proxy, password change) |
| `hilink-dash.html` | Web dashboard UI |
| `hilink-auth.conf` | Apache Basic Auth config |
| `zabbix_hilink_sms_webhook.yaml` | Zabbix media type import |

## Install

1. Copy files to server:
```bash
scp sms-gw.pl user@server:/var/www/cgi-bin/
scp hilink-dash.html user@server:/var/www/html/
scp hilink-auth.conf user@server:/etc/httpd/conf.d/
```

2. Set permissions:
```bash
chmod 755 /var/www/cgi-bin/sms-gw.pl
chgrp apache /var/www/cgi-bin/sms-gw.pl
```

3. Create log directory:
```bash
mkdir -p /var/www/cgi-bin/log
chown apache:apache /var/www/cgi-bin/log
```

4. Create htpasswd file:
```bash
htpasswd -c /var/www/cgi-bin/.htpasswd admin
chgrp apache /var/www/cgi-bin/.htpasswd
chmod 660 /var/www/cgi-bin/.htpasswd
```

5. Restart Apache:
```bash
systemctl restart httpd
```

### Zabbix IP Exception

By default, Basic Auth protects both the dashboard and CGI. To allow Zabbix server to send SMS without authentication, add your Zabbix server IP to `hilink-auth.conf`:

```apache
<RequireAny>
  Require valid-user
  Require ip 192.168.5.12   # <-- replace with your Zabbix server IP
</RequireAny>
```

Then reload Apache:
```bash
systemctl reload httpd
```

## Usage

- Dashboard: `http://server/hilink-dash.html`
- API: `http://server/cgi-bin/sms-gw.pl?action=send&phone=+71234567890&msg=Hello`
- Default credentials: `admin` / `hilink2026`

## Zabbix Integration

Import `zabbix_hilink_sms_webhook.yaml` as a media type in Zabbix 6+.
Configure user media with URL: `http://server/cgi-bin/sms-gw.pl`
Parameters: `phone`, `msg` — script sends GET with `action=send`.

Zabbix requests from the whitelisted IP bypass Basic Auth.
