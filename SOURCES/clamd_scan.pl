#!/usr/bin/perl

use strict;
use warnings;
use POSIX qw(strftime);

my $LOG_FILE = '/var/log/nginx/clamav_scan.log';
my $timestamp = strftime("%Y-%m-%dT%H:%M:%S", gmtime);

if ($#ARGV != 0) {
    print("Usage: clamdscan.pl <filename>\n");
    exit;
}

my ($FILE) = shift @ARGV;


my $cmd = "curl -s --noproxy '*' -X POST -o /dev/null -w '%{http_code}' http://127.0.0.1:8438/clammit/scan -F file=\@$FILE";
my $RC = `$cmd`;
$RC = int($RC);

# Check the output of above command
# ERROR CODE:
#    000: Clammit container is DOWN
#    200: File is CLEAN
#    418: File has a virus
#    500: File scan FAILED, check the file

if ($RC == 418) {
    print("0 file $FILE has virus\n");
    log_result("file $FILE has virus");
    exit;
} elsif ($RC == 200) {
    print("1 file $FILE is clean\n");
    log_result("file $FILE is clean");
    exit;
} elsif ($RC == 500) {
    print("0 file $FILE scan failed. Please check file\n");
    log_result("file $FILE scan failed. Please check file");
    exit;
} elsif ($RC == 000) {
    print("0 file $FILE scan failed. Likely clammit down\n");
    log_result("file $FILE scan failed. Likely clammit down");
    exit;
} else {
    print("0\n");
    exit;
}


sub log_result {
    my ($result) = @_;
    open my $log, '>>', $LOG_FILE or die "Could not open log file: $!";
    print $log "{\"transaction_timestamp\":\"$timestamp\",\"result\":\"$result\"}\n";
    close $log;
}

