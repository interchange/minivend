use Cwd;
use Config;

$cur_dir = cwd();
$failed = 0;
$num_tests = 2;

die "Must be in build directory\n" unless -d 'blib';

$ENV{MINIVEND_ROOT} = "$cur_dir/blib";

open(CONFIG, ">$ENV{MINIVEND_ROOT}/minivend.cfg")
	or die "open: $!\n";

print CONFIG <<EOF;
Catalog  test $ENV{MINIVEND_ROOT} /test
EOF

open(CONFIG, ">$ENV{MINIVEND_ROOT}/catalog.cfg")
	or die "open: $!\n";

print CONFIG <<EOF;
MailOrderTo mikeh\@minivend.com
VendURL      http:/test
SecureURL    http:/test
EOF

mkdir ("$ENV{MINIVEND_ROOT}/etc", 0777);
mkdir ("$ENV{MINIVEND_ROOT}/pages", 0777);
mkdir ("$ENV{MINIVEND_ROOT}/products", 0777);
mkdir ("$ENV{MINIVEND_ROOT}/session", 0777);

open(CONFIG, ">$ENV{MINIVEND_ROOT}/products/products.asc")
	or die "open: $!\n";

print CONFIG <<EOF;
sku	description	price
test	test product	1
EOF

open(CONFIG, ">$ENV{MINIVEND_ROOT}/pages/catalog.html")
	or die "open: $!\n";

for(1 .. 100) {
	print CONFIG <<EOF;
test succeeded test succeeded
EOF
}

close CONFIG;

print "server.......";
if ( system "$Config{'perlpath'} dist/bin/minivend -serve -u >/dev/null" ) {
	print "not ok 1\n";
}
else {
	print "ok 1\n";
}

sleep 1;
open(PID, "$ENV{MINIVEND_ROOT}/etc/minivend.pid") or die "read PID file: $!\n";
$pid = <PID>;

$pid =~ s/\D+//g;

use Socket;
my $LINK_FILE    = "$ENV{MINIVEND_ROOT}/etc/socket";
my $LINK_TIMEOUT = 5;
my $ERROR_ACTION = "-none";

$ENV{SCRIPT_NAME} = "/test";
$ENV{PATH_INFO} = "/catalog";
$ENV{REMOTE_ADDR} = "TEST";
$ENV{REQUEST_METHOD} = "GET";

sub send_arguments {

	my $count = @ARGV;
	my $val = "arg $count\n";
	for(@ARGV) {
		$val .= length($_);
		$val .= " $_\n";
	}
	return $val;
}

sub send_environment () {
	my (@tmp) = keys %ENV;
	my $count = @tmp;
	my ($str);
	my $val = "env $count\n";
	for(@tmp) {
		$str = "$_=$ENV{$_}";
		$val .= length($str);
		$val .= " $str\n";
	}
	return $val;
}

$SIG{PIPE} = sub { die_page("signal"); };
$SIG{ALRM} = sub { server_not_running(); exit 1; };

alarm $LINK_TIMEOUT;

print "socket link..";
socket(SOCK, PF_UNIX, SOCK_STREAM, 0)	or die "socket: $!\n";

my $ok;

do {
   $ok = connect(SOCK, sockaddr_un($LINK_FILE));
} while ( ! defined $ok and $! =~ /interrupt|such file or dir/i);

my $undef = ! defined $ok;
die "ok=$ok def: $undef connect: $!\n" if ! $ok;

select SOCK;
$| = 1;
select STDOUT;

print SOCK send_arguments();
print SOCK send_environment();
print SOCK "end\n";


while(<SOCK>) {
	$result .= $_;
}

close (SOCK)								or die "close: $!\n";

if(length($result) > 500 and $result =~ /test succeeded/i) {
	print "ok 2\n";
}
else {
	print "not ok 2\n";
	$failed++;
}

print "$num_tests tests run";
if($failed) {
	print " -- $failed/$numtests failed.\n";
	exit 1;
}
else {
	print ", all tests successful.\n";
	exit 0;
}

END {
	kill 'KILL', $pid;
}
