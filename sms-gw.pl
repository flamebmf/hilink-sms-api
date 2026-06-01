#!/usr/bin/perl
use strict;
use warnings;
use CGI;
use FindBin;
use lib $FindBin::Bin;
use HilinkSMS qw(process_action);

$| = 1;

my $q = CGI->new;
my $action = $q->param('action') || '';
my $output = process_action($action, $q);

print $q->header(-type => 'text/plain', -charset => 'utf-8');
print $output;
