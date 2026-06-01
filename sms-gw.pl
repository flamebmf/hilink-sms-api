#!/usr/bin/perl
use strict;
use warnings;
use CGI;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Cookies;
use IO::Socket::INET;
use POSIX qw(strftime setsid);
use HTML::Entities;

$| = 1;

my $MODEM = 'http://192.168.8.1';
my $JOB_DIR = '/tmp/hilink-sms-jobs';
my $LOG_FILE = '/var/www/cgi-bin/log/hilink-sms.log';
my $HTPASSWD_FILE = '/var/www/cgi-bin/.htpasswd';
my $q = CGI->new;
my $action = $q->param('action') || '';

sub log_msg {
    my ($level, $msg) = @_;
    my $ts = strftime('%Y-%m-%d %H:%M:%S', localtime());
    my $from = $ENV{REMOTE_ADDR} || 'unknown';
    my $pid = $$;
    open my $fh, '>>', $LOG_FILE or warn "log_open_fail: $! [$LOG_FILE]";
    print {$fh} "$ts [$level] [$from] [pid=$pid] $msg\n" or warn "log_print_fail: $!";
    close $fh;
}

my %GET_API = (
    monitoringStatus => 'api/monitoring/status',
    checkNotifications => 'api/monitoring/check-notifications',
    trafficStatistics => 'api/monitoring/traffic-statistics',
    deviceInformation => 'api/device/information',
    deviceBasicInfo => 'api/device/basic_information',
    deviceSignal => 'api/device/signal',
    deviceBootTime => 'api/device/boot_time',
    pinStatus => 'api/pin/status',
    simlockStatus => 'api/pin/simlock',
    netCurrentPlmn => 'api/net/current-plmn',
    netMode => 'api/net/net-mode',
    netModeList => 'api/net/net-mode-list',
    netNetwork => 'api/net/network',
    cellInfo => 'api/net/cell-info',
    cspsState => 'api/net/csps_state',
    lteBandInfo => 'api/net/lte-band-info',
    dialupConnection => 'api/dialup/connection',
    mobileDataSwitch => 'api/dialup/mobile-dataswitch',
    dialupProfiles => 'api/dialup/profiles',
    smsCount => 'api/sms/sms-count',
    smsConfig => 'api/sms/config',
    smsSplitinfo => 'api/sms/splitinfo-sms',
    smsFeatureSwitch => 'api/sms/sms-feature-switch',
    pbCount => 'api/pb/pb-count',
    pbList => 'api/pb/pb-list',
    pbMatch => 'api/pb/pb-match',
    groupCount => 'api/pb/group-count',
    groupList => 'api/pb/group-list',
    timeout => 'api/time/timeout',
    globalModule => 'api/global/module-switch',
    hilinkLogin => 'api/user/hilink_login',
    userStateLogin => 'api/user/state-login',
    userSession => 'api/user/session',
    userHeartbeat => 'api/user/heartbeat',
    onlineUpdateStatus => 'api/online-update/status',
    wlanStationInformation => 'api/wlan/station-information',
    hostList => 'api/system/HostInfo',
    dhcpSettings => 'api/dhcp/settings',
    securityNat => 'api/security/nat',
    firewallSwitch => 'api/security/firewall-switch',
    dmzStatus => 'api/security/dmz',
    upnpList => 'api/security/upnp',
    systemLog => 'api/log/loginfo',
    webserverToken => 'api/webserver/token',
    webserverSesTokInfo => 'api/webserver/SesTokInfo',
    webserverPublicKey => 'api/webserver/publickey',
    smsConfigXml => 'config/sms/config.xml',
    networkModeXml => 'config/network/networkmode.xml',
    netModeXml => 'config/network/net-mode.xml',
    netTypeXml => 'config/global/net-type.xml',
    dialupConfigXml => 'config/dialup/config.xml',
    connectModeXml => 'config/dialup/connectmode.xml',
    pbConfigXml => 'config/pb/config.xml',
    ussdConfigXml => 'config/ussd/config.xml',
    globalConfigXml => 'config/global/config.xml',
);

my %POST_API = (
    smsList => 'api/sms/sms-list',
    smsSetRead => 'api/sms/set-read',
    smsDelete => 'api/sms/delete-sms',
    smsListPhone => 'api/sms/sms-list-phone',
    smsListContact => 'api/sms/sms-list-contact',
    smsCountContact => 'api/sms/sms-count-contact',
    smsSendStatus => 'api/sms/send-status',
    ussdSend => 'api/ussd/send',
    ussdGet => 'api/ussd/get',
    ussdRelease => 'api/ussd/release',
);

my $ua = LWP::UserAgent->new(
    agent => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.132 Safari/537.36',
        timeout => 8,
    cookie_jar => HTTP::Cookies->new,
);

sub modem_host_port {
    my ($host, $port) = $MODEM =~ m{^http://([^/:]+)(?::(\d+))?}i;
    return ($host, $port || 80);
}

sub ensure_job_dir {
    return 1 if -d $JOB_DIR;
    return mkdir $JOB_DIR, 0700;
}

sub api_get {
    my ($path) = @_;
    my $resp = $ua->get("$MODEM/$path");
    return $resp->decoded_content;
}

sub normalize_phone {
    my ($phone) = @_;
    $phone //= '';
    $phone =~ s/[^\d+]//g;
    $phone =~ s/(?!^)\+//g;
    $phone = '+7' . substr($phone, 1) if $phone =~ /^8\d{10}$/;
    $phone = '+' . $phone if $phone =~ /^7\d{10}$/;
    return $phone;
}

sub xml_escape {
    my ($s) = @_;
    $s //= '';
    return encode_entities($s);
}

sub job_id {
    return strftime('%Y%m%d%H%M%S', localtime()) . '-' . $$ . '-' . int(rand(100000));
}

sub job_file {
    my ($id) = @_;
    return unless defined $id && $id =~ /^[A-Za-z0-9_.-]+$/;
    return "$JOB_DIR/$id.txt";
}

sub write_job {
    my ($id, %data) = @_;
    ensure_job_dir() or return 0;
    my $file = job_file($id) or return 0;
    open my $fh, '>', $file or return 0;
    for my $key (sort keys %data) {
        my $val = defined $data{$key} ? $data{$key} : '';
        $val =~ s/\r?\n/\\n/g;
        print {$fh} "$key=$val\n";
    }
    close $fh;
    return 1;
}

sub read_job {
    my ($id) = @_;
    my $file = job_file($id) or return;
    return unless -f $file;
    open my $fh, '<', $file or return;
    my %data;
    while (my $line = <$fh>) {
        chomp $line;
        my ($key, $val) = split /=/, $line, 2;
        next unless defined $key;
        $val //= '';
        $val =~ s/\\n/\n/g;
        $data{$key} = $val;
    }
    close $fh;
    return %data;
}

sub job_to_xml {
    my (%data) = @_;
    my $xml = qq{<?xml version="1.0" encoding="UTF-8"?><response>};
    for my $key (sort keys %data) {
        next unless $key =~ /^[A-Za-z0-9_-]+$/;
        $xml .= "<$key>" . xml_escape($data{$key}) . "</$key>";
    }
    return $xml . '</response>';
}

sub api_list_xml {
    my $xml = qq{<?xml version="1.0" encoding="UTF-8"?><response><Get>};
    for my $name (sort keys %GET_API) {
        $xml .= '<Api><name>' . xml_escape($name) . '</name><path>' . xml_escape($GET_API{$name}) . '</path></Api>';
    }
    $xml .= '</Get><Post>';
    for my $name (sort keys %POST_API) {
        $xml .= '<Api><name>' . xml_escape($name) . '</name><path>' . xml_escape($POST_API{$name}) . '</path></Api>';
    }
    return $xml . '</Post></response>';
}

sub api_get_named {
    my ($name) = @_;
    return job_to_xml(error => 'unknown_get_api', name => $name || '') unless $name && exists $GET_API{$name};
    return api_get($GET_API{$name});
}

sub api_post_named {
    my ($name) = @_;
    return job_to_xml(error => 'unknown_post_api', name => $name || '') unless $name && exists $POST_API{$name};
    my $xml = $q->param('xml');
    $xml = '<?xml version="1.0" encoding="UTF-8"?><request></request>' unless defined $xml && length $xml;
    return hi_post_xml($POST_API{$name}, $xml, "$MODEM/html/index.html");
}

sub hi_get_session {
    my $resp = $ua->get("$MODEM/api/webserver/SesTokInfo");
    return () unless $resp->is_success;
    my $c = $resp->decoded_content;
    my ($token) = $c =~ /<TokInfo>(.+?)<\/TokInfo>/;
    my ($sess)  = $c =~ /<SesInfo>(.+?)<\/SesInfo>/;
    $sess = "SessionID=$sess" if defined $sess && $sess !~ /^SessionID=/;
    return ($sess, $token);
}

sub hi_get_post_token {
    my $resp = $ua->get("$MODEM/api/webserver/token");
    return () unless $resp->is_success;

    my $c = $resp->decoded_content;
    my ($token) = $c =~ /<token>(.+?)<\/token>/;
    return () unless $token;

    my $full_token = $token;
    # New Brovi WebUI stores only token.substr(32) for POST requests.
    my $short_token = length($token) > 32 ? substr($token, 32) : $token;

    my $sess;
    if (my $cookie = $ua->cookie_jar) {
        $cookie->scan(sub {
            my (undef, $key, $val) = @_;
            $sess = "SessionID=$val" if $key eq 'SessionID';
        });
    }

    return ($sess, $short_token, $full_token);
}

sub hi_post_xml {
    my ($path, $body, $referer) = @_;

    my $content = '';
    for my $try (1 .. 2) {
        my ($sess, $token) = hi_get_post_token();
        ($sess, $token) = hi_get_session() unless $token;

        $content = hi_raw_post($path, $body, $sess, $token, 'application/x-www-form-urlencoded; charset=UTF-8', $referer);
        last unless $content =~ /<code>12500[123]<\/code>/;
    }

    return $content;
}

sub hi_raw_post {
    my ($path, $body, $sess, $token, $content_type, $referer) = @_;
    my ($host, $port) = modem_host_port();

    my $sock = IO::Socket::INET->new(
        PeerHost => $host,
        PeerPort => $port,
        Proto    => 'tcp',
        Timeout  => 5,
    );
    return '' unless $sock;

    binmode($sock);
    my $request = "POST /$path HTTP/1.1\r\n"
        . "Host: $host" . ($port == 80 ? '' : ":$port") . "\r\n"
        . "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.132 Safari/537.36\r\n"
        . "Accept: */*\r\n"
        . "Origin: $MODEM\r\n"
        . ($referer ? "Referer: $referer\r\n" : '')
        . "Content-Type: $content_type\r\n"
        . "X-Requested-With: XMLHttpRequest\r\n"
        . ($sess ? "Cookie: $sess\r\n" : '')
        . ($token ? "__RequestVerificationToken: $token\r\n" : '')
        . "_ResponseSource: Broswer\r\n"
        . "Content-Length: " . length($body) . "\r\n"
        . "Connection: close\r\n\r\n"
        . $body;

    my $old_alarm = alarm 12;
    eval {
        local $SIG{ALRM} = sub { die "raw_post_timeout\n" };
        print {$sock} $request;
    };
    if ($@) {
        close $sock;
        alarm $old_alarm;
        return '';
    }

    my $response = '';
    my $buf = '';
    while (1) {
        my $rin = '';
        vec($rin, fileno($sock), 1) = 1;
        my $ready = select(my $rout = $rin, undef, undef, 2);
        last unless $ready;
        my $read = sysread($sock, $buf, 8192);
        last unless $read;
        $response .= $buf;
    }
    close $sock;
    alarm $old_alarm;

    $response =~ s/^.*?\r?\n\r?\n//s;
    $response =~ s/^\h*[0-9a-fA-F]+\h*\r?\n//mg;
    $response =~ s/\r?\n0\r?\n\r?\n$//s;
    return $response;
}

sub send_sms {
    my ($phone, $msg, %opts) = @_;
    log_msg('DEBUG', "send_sms: phone=$phone msg_len=" . length($msg));
    my $reserved = defined $opts{reserved} ? $opts{reserved} : $q->param('reserved');
    $reserved = 0 unless defined $reserved && $reserved =~ /^-?\d+$/;
    my $sca = defined $opts{sca} ? $opts{sca} : $q->param('sca');
    $sca = '' unless defined $sca;

    my $body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        . "<request><Index>-1</Index><Phones><Phone>" . encode_entities($phone) . "</Phone></Phones>"
        . "<Sca>" . encode_entities($sca) . "</Sca><Content>" . encode_entities($msg) . "</Content>"
        . "<Length>" . length($msg) . "</Length><Reserved>" . encode_entities($reserved) . "</Reserved><Date>"
        . encode_entities(strftime("%Y-%m-%d %H:%M:%S", localtime()))
        . "</Date></request>";

    my $content = hi_post_xml('api/sms/send-sms', $body, "$MODEM/html/smsinbox.html");
    if ($content =~ /<response>OK<\/response>/) {
        log_msg('INFO', "send_sms: phone=$phone OK");
        return (1, '');
    }
    log_msg('ERROR', "send_sms: phone=$phone FAIL: $content");
    return (0, $content);
}

sub list_sms {
    my $body = '<?xml version="1.0" encoding="UTF-8"?>'
        . '<request><PageIndex>1</PageIndex><ReadCount>50</ReadCount>'
        . '<BoxType>1</BoxType><SortType>0</SortType>'
        . '<Ascending>0</Ascending><UnreadPreferred>0</UnreadPreferred></request>';
    return hi_post_xml('api/sms/sms-list', $body, "$MODEM/html/smsinbox.html");
}

sub delete_sms {
    my ($index) = @_;
    my $body = '<?xml version="1.0" encoding="UTF-8"?><request><Index>' . encode_entities($index) . '</Index></request>';
    my $content = hi_post_xml('api/sms/delete-sms', $body, "$MODEM/html/smsinbox.html");
    return $content =~ /<response>OK<\/response>/ ? 1 : 0;
}

sub send_status {
    my $body = '<?xml version="1.0" encoding="UTF-8"?><request></request>';
    return hi_post_xml('api/sms/send-status', $body, "$MODEM/html/smsinbox.html");
}

sub send_sms_job {
    my ($id, $phone, $msg, %opts) = @_;
    write_job($id,
        id => $id,
        status => 'running',
        phone => $phone,
        created_at => strftime('%Y-%m-%d %H:%M:%S', localtime()),
    );

    my ($ok, $err) = send_sms($phone, $msg, %opts);
    my $status_xml = send_status();
    my ($suc)  = $status_xml =~ /<SucPhone>(.*?)<\/SucPhone>/s;
    my ($fail) = $status_xml =~ /<FailPhone>(.*?)<\/FailPhone>/s;

    write_job($id,
        id => $id,
        status => $ok && (!$fail || $fail eq '') ? 'sent' : 'failed',
        phone => $phone,
        ok => $ok ? 1 : 0,
        error => $err,
        suc_phone => $suc || '',
        fail_phone => $fail || '',
        send_status => $status_xml,
        finished_at => strftime('%Y-%m-%d %H:%M:%S', localtime()),
    );
}

sub send_sms_async {
    my ($phone, $msg, %opts) = @_;
    ensure_job_dir() or return (0, 'Unable to create job dir');
    my $id = job_id();
    write_job($id,
        id => $id,
        status => 'queued',
        phone => $phone,
        created_at => strftime('%Y-%m-%d %H:%M:%S', localtime()),
    );

    my $pid = fork();
    return (0, 'fork failed') unless defined $pid;

    if ($pid == 0) {
        close STDIN;
        close STDOUT;
        close STDERR;
        setsid();
        send_sms_job($id, $phone, $msg, %opts);
        exit 0;
    }

    return (1, $id);
}

sub list_jobs {
    ensure_job_dir() or return qq{<?xml version="1.0" encoding="UTF-8"?><response><error>job_dir</error></response>};
    opendir my $dh, $JOB_DIR or return qq{<?xml version="1.0" encoding="UTF-8"?><response><error>open_job_dir</error></response>};
    my @ids = sort grep { /^[A-Za-z0-9_.-]+\.txt$/ } readdir $dh;
    closedir $dh;
    my $xml = qq{<?xml version="1.0" encoding="UTF-8"?><response><Jobs>};
    for my $file (@ids) {
        (my $id = $file) =~ s/\.txt$//;
        my %job = read_job($id);
        $xml .= '<Job><id>' . xml_escape($id) . '</id><status>' . xml_escape($job{status} || '') . '</status><phone>' . xml_escape($job{phone} || '') . '</phone></Job>';
    }
    return $xml . '</Jobs></response>';
}

sub get_job_xml {
    my ($id) = @_;
    my %job = read_job($id);
    return job_to_xml(%job ? %job : (error => 'not_found'));
}

sub debug_session {
    my ($sess, $token) = hi_get_session();
    my ($post_sess, $post_token) = hi_get_post_token();
    log_msg('DEBUG', "debug_session called");
    return "session=" . ($sess ? 'yes' : 'no') . "\n"
        . "token=" . ($token ? 'yes' : 'no') . "\n"
        . "post_session=" . ($post_sess ? 'yes' : 'no') . "\n"
        . "post_token=" . ($post_token ? 'yes' : 'no') . "\n";
}

sub response_code {
    my ($content) = @_;
    return 'OK' if $content =~ /<response>OK<\/response>/;
    return $1 if $content =~ /<code>(\d+)<\/code>/;
    return 'response' if $content =~ /<response>/;
    return 'empty' unless length $content;
    return 'unknown';
}

sub probe_sms_list {
    my $body = '<?xml version="1.0" encoding="UTF-8"?>'
        . '<request><PageIndex>1</PageIndex><ReadCount>1</ReadCount>'
        . '<BoxType>1</BoxType><SortType>0</SortType>'
        . '<Ascending>0</Ascending><UnreadPreferred>0</UnreadPreferred></request>';

    my @tests = (
        ['webtoken_short_form', 'webtoken_short', 'application/x-www-form-urlencoded; charset=UTF-8'],
        ['webtoken_short_xml',  'webtoken_short', 'text/xml; charset=UTF-8'],
        ['webtoken_full_form',  'webtoken_full',  'application/x-www-form-urlencoded; charset=UTF-8'],
        ['sestok_form',        'sestok',         'application/x-www-form-urlencoded; charset=UTF-8'],
        ['sestok_xml',         'sestok',         'text/xml; charset=UTF-8'],
    );

    my $out = '';
    for my $test (@tests) {
        my ($name, $token_kind, $content_type) = @$test;
        my ($sess, $token, $full_token);
        if ($token_kind =~ /^webtoken/) {
            ($sess, $token, $full_token) = hi_get_post_token();
            $token = $full_token if $token_kind eq 'webtoken_full';
        } else {
            ($sess, $token) = hi_get_session();
        }

        my $content = hi_raw_post('api/sms/sms-list', $body, $sess, $token, $content_type, "$MODEM/html/smsinbox.html");
        $out .= "$name=" . response_code($content) . "\n";
    }

    return $out;
}

print $q->header(-type => 'text/plain', -charset => 'utf-8');

log_msg('INFO', "action=$action" . ($q->param('phone') ? " phone=" . normalize_phone($q->param('phone') // '') : '') . " msg_len=" . (length($q->param('msg') // '')));

if ($action eq 'send') {
    my $phone = $q->param('phone') || '';
    my $msg   = $q->param('msg')   || '';
    $phone = normalize_phone($phone);
    $msg =~ s/\+/ /g;
    my ($ok, $err) = send_sms($phone, $msg);
    log_msg($ok ? 'INFO' : 'ERROR', "send: phone=$phone result=" . ($ok ? 'OK' : "FAIL: $err"));
    print $ok ? "OK" : "ERROR: $err";
} elsif ($action eq 'send-async') {
    my $phone = normalize_phone($q->param('phone') || '');
    my $msg = $q->param('msg') || '';
    $msg =~ s/\+/ /g;
    my ($ok, $id_or_err) = send_sms_async($phone, $msg);
    print $ok ? job_to_xml(id => $id_or_err, status => 'queued') : job_to_xml(error => $id_or_err);
} elsif ($action eq 'job') {
    print get_job_xml($q->param('id') || '');
} elsif ($action eq 'jobs') {
    print list_jobs();
} elsif ($action eq 'list') {
    print list_sms();
} elsif ($action eq 'delete') {
    print delete_sms($q->param('index') || 0) ? "OK" : "ERROR";
} elsif ($action eq 'send-status') {
    print send_status();
} elsif ($action eq 'debug') {
    print debug_session();
} elsif ($action eq 'probe') {
    print probe_sms_list();
} elsif ($action eq 'api-list') {
    print api_list_xml();
} elsif ($action eq 'get') {
    print api_get_named($q->param('name') || '');
} elsif ($action eq 'post') {
    print api_post_named($q->param('name') || '');
} elsif ($action eq 'status') {
    print api_get('api/monitoring/status');
} elsif ($action eq 'info') {
    print api_get('api/device/information');
} elsif ($action eq 'signal') {
    print api_get('api/device/signal');
} elsif ($action eq 'sms-count') {
    print api_get('api/sms/sms-count');
} elsif ($action eq 'sms-config') {
    print api_get('api/sms/config');
} elsif ($action eq 'change-password') {
    my $old = $q->param('old') || '';
    my $new = $q->param('new') || '';
    if (length $new < 4) { print "ERROR: password too short"; }
    else {
        system('htpasswd', '-vb', $HTPASSWD_FILE, 'admin', $old);
        if ($? == 0) {
            my $new_hash = `htpasswd -nb admin '$new' 2>/dev/null | cut -d: -f2`;
            chomp $new_hash;
            if ($new_hash) {
                open my $out, '>', $HTPASSWD_FILE;
                if ($out) { print {$out} "admin:$new_hash\n"; close $out; print "OK"; log_msg('INFO', 'password changed'); }
                else { print "ERROR: write failed"; }
            } else { print "ERROR: hash failed"; }
        } else { print "ERROR: wrong password"; }
    }
} elsif ($action eq 'sms-config-xml') {
    print api_get('config/sms/config.xml');
} else {
    log_msg('WARN', "unknown_action: $action");
    print "OK";
}
