#!@@Perl_program@@

BEGIN { unshift @INC, "@@Vend_lib@@" };
use strict;
use Vend::lock;

my $pidfile = "@@Data_directory@@/@@App@@.pid";
open(PID, "+>>$pidfile") or exit 0;

if (lockfile(*PID, 1, 0)) {
    print "The Vend @@App@@ server is not running.\n";
    exit 0;
}

my $pid = <PID> or die "Couldn't read '$pidfile': $!\n";
chomp $pid;

kill('TERM', $pid) or die "Couldn't send signal to terminate process $pid: $!\n";
print "Shutting down Vend @@App@@ server...\n";
lockfile(*PID, 1, 1);
print "@@App@@ shut down.\n";
