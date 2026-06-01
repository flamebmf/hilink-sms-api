#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use HilinkSMS qw(process_action send_sms normalize_phone);

$| = 1;

if ($ENV{GATEWAY_INTERFACE} && $ENV{GATEWAY_INTERFACE} =~ /CGI/) {
    require CGI;
    CGI->import;
    my $q = CGI->new;
    my $action = $q->param('action') || '';
    my $output = process_action($action, $q);
    print $q->header(-type => 'text/plain', -charset => 'utf-8');
    print $output;
}
else {
    my $phone = '';
    my $text  = '';
    for (@ARGV) {
        if (/^phone=(.+)/)           { $phone = $1 }
        elsif (/^(?:msg|text)=(.+)/) { $text  = $1 }
    }
    unless ($phone && $text) {
        print STDERR "Usage: sms-gw.pl phone=79219615926 text=\"Hello\"\n";
        exit 1;
    }
    $phone = normalize_phone($phone);
    my ($ok, $err) = send_sms($phone, $text);
    print($ok ? "OK: $phone\n" : "ERROR: $phone $err\n");
    exit($ok ? 0 : 1);
}
