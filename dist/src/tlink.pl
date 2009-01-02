#!/usr/local/bin/perl -wT
# tlink.pl: runs as a cgi program and passes request to Vend server
#
#   $Id: tlink.pl,v 1.1 1997/04/22 15:31:27 mike Exp $
#
# Copyright 1996-1998 by Michael J. Heins <mikeh@minivend.com>
#
#    This program is free software; you can redistribute it and/or
#    modify it under the terms of the GNU General Public License as
#    published by the Free Software Foundation; either version 2 of the
#    License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

require 5.002;
use strict;
use Socket;
my $LINK_TIMEOUT = 45;
my $LINK_PORT    = 7786;
my $LINK_HOST    = 'localhost';
my $ERROR_ACTION = "-notify";

$ENV{PATH} = "/bin:/usr/bin";
$ENV{IFS} = " ";

# Return this message to the browser when the server is not running.
# Log an error log entry if set to notify

sub server_not_running {

	my $msg;

	if($ERROR_ACTION =~ /not/i) {
		warn "ALERT: MiniVend server not running for $ENV{SCRIPT_NAME}\n";	
	}

	$| = 1;
	print <<EOF;
Content-type: text/html

<HTML><HEAD><TITLE>MiniVend server not running</TITLE></HEAD>
<BODY BGCOLOR="#FFFFFF">
<H3>We're sorry, the MiniVend server was not running...</H3>
<P>
We are out of service or may be experiencing high system demand,
please try again soon.

</BODY></HTML>
EOF

}

# Return this message to the browser when a system error occurs.
#
sub die_page {
  printf("Content-type: text/plain\r\n\r\n");
  printf("We are sorry, but the cgi-bin server is unavailable due to a\r\n");
  printf("system error.\r\n\r\n");
  printf("%s: %s (%d)\r\n", $_[0], $!, $?);
  if($ERROR_ACTION =~ /not/i) {
	warn "ALERT: MiniVend $ENV{SCRIPT_NAME} $_[0]: $! ($?)\n";
  }
  exit(1);
}


my $Entity = '';

# Read the entity from stdin if present.

sub get_entity {

  return '' unless defined $ENV{CONTENT_LENGTH};
  my $len = $ENV{CONTENT_LENGTH} || 0;
  return '' unless $len;

  my $check;

  $check = read(STDIN, $Entity, $len);

  die_page("Entity wrong length")
      unless $check == $len;

  $Entity;

}



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

sub send_entity {
	return '' unless defined $ENV{CONTENT_LENGTH};
	my $len = $ENV{CONTENT_LENGTH};
	return '' unless $len > 0;

	my $val = "entity\n";
	$val .= "$len $Entity\n";
	return $val;
}

$SIG{PIPE} = sub { die_page("signal"); };
$SIG{ALRM} = sub { server_not_running(); exit 1; };

alarm $LINK_TIMEOUT;

my ($remote, $port, $iaddr, $paddr, $proto, $line);

$remote = $LINK_HOST;
$port   = $LINK_PORT;

if ($port =~ /\D/) { $port = getservbyname($port, 'tcp'); }

die_page("no port") unless $port;

$iaddr = inet_aton($remote);
$paddr = sockaddr_in($port,$iaddr);

$proto = getprotobyname('tcp');

socket(SOCK, PF_INET, SOCK_STREAM, $proto)	or die "socket: $!\n";

my $ok;

do {
   $ok = connect(SOCK, $paddr);
} while ( ! defined $ok and $! =~ /interrupt/i);

my $def = defined $ok;
die "ok=$ok def: $def connect: $!\n" if ! $ok;

get_entity();

select SOCK;
$| = 1;
select STDOUT;

print SOCK send_arguments();
print SOCK send_environment();
print SOCK send_entity();
print SOCK "end\n";


while(<SOCK>) {
	print;
}

close (SOCK)								or die "close: $!\n";
exit;



get_entity();

print SOCK send_arguments();
print SOCK send_environment();
print SOCK send_entity();

while(<SOCK>) {
	print;
}

close (SOCK)								or die "close: $!\n";
exit;

