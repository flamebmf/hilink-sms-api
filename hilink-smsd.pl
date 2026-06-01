#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;
use POSIX qw(strftime);
use Getopt::Long qw(:config no_ignore_case);
use FindBin;
use lib $FindBin::Bin;
use HilinkSMS qw(process_action $MODEM);

$| = 1;

my %opts = (host => '0.0.0.0', port => 8080, daemon => 0);
GetOptions(
    'daemon'  => \$opts{daemon},
    'port=i'  => \$opts{port},
    'host=s'  => \$opts{host},
    'help'    => sub { print "Usage: $0 --daemon [--port 8080] [--host 0.0.0.0]\n"; exit },
);

unless ($opts{daemon}) {
    print "Standalone HiLink SMS API Proxy v1.0\n";
    print "Usage: $0 --daemon [--port 8080] [--host 0.0.0.0]\n";
    exit;
}

my $server = IO::Socket::INET->new(
    LocalHost => $opts{host},
    LocalPort => $opts{port},
    Proto     => 'tcp',
    ReuseAddr => 1,
    Listen    => 10,
) or die "Cannot bind to $opts{host}:$opts{port}: $!\n";

print "hilink-smsd listening on http://$opts{host}:$opts{port}\n";
print "Modem at $MODEM\nPID: $$\n";

my $quit = 0;
$SIG{INT}  = sub { $quit = 1; };
$SIG{TERM} = sub { $quit = 1; };

while (!$quit) {
    my $rin = '';
    vec($rin, fileno($server), 1) = 1;
    my $ready = select(my $rout = $rin, undef, undef, 1);
    next unless $ready;

    my $client = $server->accept() or next;
    $client->autoflush(1);

    eval {
        local $SIG{ALRM} = sub { die "request_timeout\n" };
        alarm 30;

        my $request = '';
        while (my $line = <$client>) {
            $request .= $line;
            last if $line =~ /^\r?$/;
        }

        my ($method, $path) = $request =~ /^(\w+)\s+(\S+)/;
        $method //= 'GET';
        my $query = '';
        my $path_only = $path;
        if ($path =~ /\?(.+)/) {
            $query = $1;
            $path_only = $`;
        }

        my %headers;
        for my $line (split /\r?\n/, $request) {
            next if $line =~ /^\s*$/ || $line =~ /^\w+\s+\S+/;
            if ($line =~ /^([^:]+):\s*(.*)/) {
                $headers{lc $1} = $2;
            }
        }

        my $body = '';
        if (defined $headers{'content-length'} && $headers{'content-length'} > 0) {
            my $len = $headers{'content-length'};
            read($client, $body, $len);
        }

        local $ENV{REQUEST_METHOD}   = $method;
        local $ENV{QUERY_STRING}     = $query;
        local $ENV{REMOTE_ADDR}      = $headers{'x-forwarded-for'} || $headers{'x-real-ip'} || $ENV{REMOTE_ADDR} || '127.0.0.1';
        local $ENV{CONTENT_LENGTH}   = length($body);
        local $ENV{CONTENT_TYPE}     = $headers{'content-type'} || 'text/plain';

        my $output = '';
        {
            my $q = CGI->new;
            my $action = $q->param('action') || '';
            $output = process_action($action, $q);
        }

        alarm 0;

        my $ctype = $output =~ /^<\?xml/ ? 'text/xml' : 'text/plain';
        print {$client} "HTTP/1.1 200 OK\r\n"
            . "Content-Type: $ctype; charset=utf-8\r\n"
            . "Content-Length: " . length($output) . "\r\n"
            . "Connection: close\r\n"
            . "Access-Control-Allow-Origin: *\r\n"
            . "\r\n"
            . $output;
    };
    if ($@) {
        my $err = $@;
        chomp $err;
        print {$client} "HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nContent-Length: " . length($err) . "\r\nConnection: close\r\n\r\n$err\n";
    }
    close $client;
}

close $server;
print "shutdown\n";
