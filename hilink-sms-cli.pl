#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use HilinkSMS qw(send_sms normalize_phone log_msg);

$| = 1;

my $phone = '';
my $text  = '';
my $quiet = 0;

for (@ARGV) {
    if (/^phone=(.+)/)       { $phone = $1 }
    elsif (/^(?:msg|text)=(.+)/) { $text  = $1 }
    elsif (/^-q$|^--quiet$/) { $quiet = 1 }
}

unless ($phone && $text) {
    print STDERR "Usage: $0 phone=79219615926 text=\"Hello world\"\n";
    exit 1;
}

$phone = normalize_phone($phone);
my ($ok, $err) = send_sms($phone, $text);

if ($quiet) {
    exit($ok ? 0 : 1);
}
print($ok ? "OK: $phone\n" : "ERROR: $phone $err\n");
exit($ok ? 0 : 1);
