# Server.pm:  listen for cgi requests as a background server
#
# $Id: Server.pm,v 1.55 1999/06/07 08:07:47 mike Exp mike $
#
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
# Copyright 1996-1999 by Michael J. Heins <mikeh@iac.net>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

package Vend::Http::Server;
require Vend::Http;
@ISA = qw(Vend::Http::CGI);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.55 $, 10);

use Vend::Util qw(strftime);
use POSIX qw(setsid);
use strict;

my $Pidfile;

sub new {
    my ($class, $fh, $env, $entity) = @_;
    my $http = new Vend::Http::CGI;
    $http->populate($env);
    $http->{fh} = $fh;
    $http->{entity} = $entity;
    bless $http, $class;
}

sub read_entity_body {
    my ($s) = @_;
    $s->{entity};
}

sub create_cookie {
	my($domain,$path) = @_;
	my ($name, $value, $out, $expire, $cookie);
	my @jar;
	@jar = ['MV_SESSION_ID', $Vend::SessionName, $Vend::Expire || undef];
	push @jar, @{$::Instance->{Cookies}}
		if defined $::Instance->{Cookies};
	$out = '';
	foreach $cookie (@jar) {
		($name, $value, $expire) = @$cookie;
#::logGlobal("create_cookie: name=$name value=$value expire=$expire");
		$value = Vend::Interpolate::esc($value) 
			if $value !~ /^[-\w:.]+$/;
		$out .= "Set-Cookie: $name=$value;";
		$out .= " path=$path;";
		$out .= " domain=" . $domain . ";" if $domain;
		if (defined $expire or $Vend::Expire) {
			$expire = $Vend::Expire unless defined $expire;
			$out .= " expires=" .
						strftime "%a, %d-%b-%y %H:%M:%S GMT ", gmtime($expire);
		}
		$out .= "\r\n";
	}
	return $out;
}

sub canon_status {
	local($_);
	$_ = shift;
	s:\s+$::;
	s:\s*\n:\r\n:mg;
	return "$_\r\n";
}

sub respond {
	# $body is now a reference
    my ($s, $content_type, $body) = @_;
	if(! $s and $Vend::StatusLine) {
		$Vend::StatusLine = "HTTP/1.0 200 OK\r\n$Vend::StatusLine"
			if defined $Vend::InternalHTTP
				and $Vend::StatusLine !~ m{^HTTP/};
		$Vend::StatusLine .= $Vend::StatusLine =~ /^Content-Type:/im
							? '' : "Content-Type: $content_type\r\n";
		print Vend::Server::MESSAGE canon_status($Vend::StatusLine);
		print Vend::Server::MESSAGE "\r\n";
		print Vend::Server::MESSAGE $$body;
		undef $Vend::StatusLine;
		$Vend::ResponseMade = 1;
		return;
	}

    my $fh = $s->{fh};

	# Fix for SunOS, Ultrix, Digital UNIX
	my($oldfh) = select($fh);
	$| = 1;
	select($oldfh);

	if($Vend::ResponseMade) {
		print $fh $$body;
		return 1;
	}

	if (defined $Vend::InternalHTTP or $CGI::script_name =~ m:/nph-[^/]+$:) {
		if(defined $Vend::StatusLine) {
			$Vend::StatusLine = "HTTP/1.0 200 OK\r\n$Vend::StatusLine"
				if $Vend::StatusLine !~ m{^HTTP/};
			print $fh canon_status($Vend::StatusLine);
			$Vend::ResponseMade = 1;
			undef $Vend::StatusLine;
		}
		else { print $fh "HTTP/1.0 200 OK\r\n"; }
	}

	if ( (	! $CGI::cookie && ! $::Instance->{CookiesSet}
			or defined $Vend::Expire
			or defined $::Instance->{Cookies}
		  )
			and $Vend::Cfg->{'Cookies'}
		)
	{

		my @domains;
		@domains = ('');
		if ($Vend::Cfg->{CookieDomain}) {
			@domains = split /\s+/, $Vend::Cfg->{CookieDomain};
		}

		my @paths;
		@paths = ('/');
		if($Global::Mall) {
			my $ref = $Global::Catalog{$Vend::Cfg->{CatalogName}};
			@paths = ($ref->{'script'});
			push (@paths, @{$ref->{'alias'}}) if defined $ref->{'alias'};
			if ($Global::FullUrl) {
				# remove domain from script
				for (@paths) { s:^[^/]+/:/: ; }
			}
		}

		my ($d, $p);
		foreach $d (@domains) {
			foreach $p (@paths) {
				print $fh create_cookie($d, $p);
			}
		}
		$::Instance->{CookiesSet} = delete $::Instance->{Cookies};
    }

    if (defined $Vend::StatusLine) {
		print $fh canon_status($Vend::StatusLine);
	}
	elsif(! $Vend::ResponseMade) {
		print $fh canon_status("Content-Type: $content_type");
	}

	if ($Vend::Session->{frames} and $CGI::values{mv_change_frame}) {
# DEBUG
#Vend::Util::logDebug
#("Changed Frame: Window-target: " . $CGI::values{mv_change_frame} . "\r\n")
#	if ::debug(0x40);
# END DEBUG
		print $fh canon_status("Window-target: $CGI::values{mv_change_frame}");
    }

    print $fh "\r\n";
    print $fh $$body;
    $Vend::ResponseMade = 1;
}

package Vend::Server;
require Exporter;
@Vend::Server::ISA = qw(Exporter);
@Vend::Server::EXPORT = qw(run_server);

use Fcntl;
use Config;
use Socket;
use strict;
use Vend::Util;
use POSIX qw(setsid);

my $LINK_FILE = "$Global::ConfDir/socket"
	if defined $Global::ConfDir;

sub _read {
    my ($in) = @_;
    my ($r);
    
    do {
        $r = sysread(Vend::Server::MESSAGE, $$in, 512, length($$in));
    } while (!defined $r and $! =~ m/^Interrupted/);
    die "read: $!" unless defined $r;
    die "read: closed" unless $r > 0;
}

sub _find {
    my ($in, $char) = @_;
    my ($x);

    _read($in) while (($x = index($$in, $char)) == -1);
    my $before = substr($$in, 0, $x);
    substr($$in, 0, $x + 1) = '';
    $before;
}

sub _string {
    my ($in) = @_;
    my $len = _find($in, " ");
    _read($in) while (length($$in) < $len + 1);
    my $str = substr($$in, 0, $len);
    substr($$in, 0, $len + 1) = '';
    $str;
}

my $HTTP_enabled;
my $Remote_addr;
my $Remote_host;
my %CGImap;
my %CGIspecial;
my %MIME_type;

BEGIN {
	eval {
		require URI::URL;
		require MIME::Base64;
		$HTTP_enabled = 1;
		%CGImap = ( qw/
				content-length       CONTENT_LENGTH
				content-type         CONTENT_TYPE
                authorization-type   AUTH_TYPE
                authorization        AUTHORIZATION
				cookie               HTTP_COOKIE
                client-hostname      REMOTE_HOST
                client-ip-address    REMOTE_ADDR
                client-ident         REMOTE_IDENT
                content-length       CONTENT_LENGTH
                content-type         CONTENT_TYPE
                cookie               HTTP_COOKIE
                from                 HTTP_FROM
                host                 HTTP_HOST
                https-on             HTTPS
                method               REQUEST_METHOD
                path-info            PATH_INFO
                path-translated      PATH_TRANSLATED
                pragma               HTTP_PRAGMA
                query                QUERY_STRING
                reconfigure          RECONFIGURE_MINIVEND
                referer              HTTP_REFERER
                script               SCRIPT_NAME
                server-host          SERVER_NAME
                server-port          SERVER_PORT
                user-agent           HTTP_USER_AGENT
                content-encoding     HTTP_CONTENT_ENCODING
                content-language     HTTP_CONTENT_LANGUAGE
                content-transfer-encoding HTTP_CONTENT_TRANSFER_ENCODING

					/
		);
		%CGIspecial = ();

		%MIME_type = (qw|
							jpg		image/jpeg
							gif		image/gif
							JPG		image/jpeg
							GIF		image/gif
							JPEG	image/jpeg
							jpeg	image/jpeg
							htm		text/html
							html	text/html
						|
		);
	};
										 
}                                    

sub http_log_msg {
	my($status, $env, $request) = @_;
	my(@params);

	# IP, Session, REMOTE_USER (if any) and time
    push @params, ($$env{REMOTE_HOST} || $$env{REMOTE_ADDR});
	push @params, ($$env{SERVER_PORT} || '-');
	push @params, ($$env{REMOTE_USER} || '-');
	push @params, logtime();

	# Catalog name
	push @params, qq{"$request"};

	push @params, $status;

	push @params, '-';
	return join " ", @params;
}

sub http_server {
	my($status_line, $in, $argv, $env, $entity) = @_;

	die "Need URI::URL for this functionality.\n"
		unless defined $HTTP_enabled;

	$Vend::InternalHTTP = 1;
	my ($header, $request, $block);
	my $waiting = 0;
	($$env{REQUEST_METHOD},$request) = split /\s+/, $status_line;
	for(;;) {
        $block = _find(\$in, "\n");
#::logGlobal("read: $block");
		$block =~ s/\s+$//;
		if($block eq '') {
			last;
		}
		if ( $block =~ s/^([^:]+):\s*//) {
			$header = lc $1;
			if(defined $CGImap{$header}) {
				$$env{$CGImap{$header}} = $block;
			}
			elsif(defined $CGIspecial{$header}) {
				&{$CGIspecial{$header}}($env, $block);
			}
			# else { throw_away() }
			next;
		}
		else {
			die "HTTP protocol error on '$block':\n$in";
		}
		last;
	}

	if ($$env{CONTENT_LENGTH}) {
		_read(\$in) while length($in) < $$env{CONTENT_LENGTH};
	}
	$in =~ s/\s+$//;
	$$entity = $in;

#::logGlobal("exiting loop");
	my $url = new URI::URL $request;
	@{$argv} = $url->keywords();

	(undef, $Remote_addr) =
				sockaddr_in(getpeername(Vend::Server::MESSAGE));
	$$env{REMOTE_HOST} = gethostbyaddr($Remote_addr, AF_INET)
		if $Global::DomainTail;
	$Remote_addr = inet_ntoa($Remote_addr);

	$$env{QUERY_STRING} = $url->query();
	$$env{REMOTE_ADDR} = $Remote_addr;

	my (@path) = $url->path_components();
	my $path = $url->path();
	my $doc;
	my $status = 200;

	shift(@path);
	my $cat = "/" . shift(@path);

	if ($Global::TcpMap->{$Global::TcpPort} =~ /^\w+/) {
		$cat = $Global::TcpMap->{$Global::TcpPort};
		$cat = "/$cat" unless index($cat, '/') == 0;
	}

	if($cat eq '/mv_admin') {
#::logGlobal("found mv_admin");
		if ($$env{AUTHORIZATION}) {
			$$env{REMOTE_USER} =
					Vend::Util::check_authorization( delete $$env{AUTHORIZATION} );
		}
		if (! $$env{REMOTE_USER}) {
			$Vend::StatusLine = <<EOF;
HTTP/1.0 401 Unauthorized
WWW-Authenticate: Basic realm="MiniVend Admin"
EOF
			$doc = "Requires correct username and password.\n";
			$path = '';
		}
	}

	if($Global::Selector{$cat} || $Global::SelectorAlias{$cat}) {
#::logGlobal("found direct catalog $cat");
		$$env{SCRIPT_NAME} = $cat;
		$$env{PATH_INFO} = join "/", '', @path;
	}
	elsif(-f "$Global::VendRoot/doc$path") {
#::logGlobal("found doc file");
		$Vend::StatusLine = "HTTP/1.0 200 OK";
		$doc = "Would have read file.\n";
		$doc = readfile("$Global::VendRoot/doc$path");
	}
	else {
#::logGlobal("not found");
		$status = 404;
		$Vend::StatusLine = "HTTP/1.0 404 Not found";
		$doc = "$path not a MiniVend catalog or help file.\n";
	}

	if($$env{REQUEST_METHOD} eq 'HEAD') {
		$Vend::StatusLine = "HTTP/1.0 200 OK\nLast-modified: "
			. Vend::Util::logtime;
		$doc = '';
	}

	logData("$Global::VendRoot/etc/access_log",
			http_log_msg(
						$status,
						$env,
						($$env{REQUEST_METHOD} .  " " .  $request),
						)
		);

	if (defined $doc) {
		$path =~ /\.([^.]+)$/;
		Vend::Http::Server::respond(
					'',
					$MIME_type{$1} || "text/plain",
					\$doc,
				);
		return;
	}
	return 1;
}

sub read_cgi_data {
    my ($argv, $env, $entity) = @_;
    my ($in, $block, $n, $i, $e, $key, $value);
    $in = '';

    for (;;) {
        $block = _find(\$in, "\n");
        if ($block =~ m/^[GP]/) {
           	return http_server($block, $in, @_);
		} elsif (($n) = ($block =~ m/^arg (\d+)$/)) {
            $#$argv = $n - 1;
            foreach $i (0 .. $n - 1) {
                $$argv[$i] = _string(\$in);
            }
        } elsif (($n) = ($block =~ m/^env (\d+)$/)) {
            foreach $i (0 .. $n - 1) {
                $e = _string(\$in);
                if (($key, $value) = ($e =~ m/^([^=]+)=(.*)$/s)) {
                    $$env{$key} = $value;
                }
            }
        } elsif ($block =~ m/^entity$/) {
            $$entity = _string(\$in);
        } elsif ($block =~ m/^end$/) {
            last;
        } else {
			die "Unrecognized block: $block\n";
        }
    }
	if($Vend::OnlyInternalHTTP) {
		::logGlobal(
			"attempt to connect from unauthorized host $Vend::OnlyInternalHTTP.\n"
		);
		die "attempt to connect from unauthorized host $Vend::OnlyInternalHTTP.\n";
	}
	return 1;
}

sub connection {
    my (%env, $entity);
    read_cgi_data(\@Global::argv, \%env, \$entity)
		or return;
    my $http = new Vend::Http::Server \*Vend::Server::MESSAGE, \%env, $entity;
    ::dispatch($http);
	undef $Vend::ResponseMade;
	undef $Vend::InternalHTTP;
}

## Signals

my $Signal_Terminate;
my $Signal_Debug;
my $Signal_Restart;
my %orig_signal;
my @trapped_signals = qw(INT TERM);
$Vend::Server::Num_servers = 0;

# might also trap: QUIT

my ($Routine_USR1, $Routine_USR2, $Routine_HUP, $Routine_TERM, $Routine_INT);
my ($Sig_inc, $Sig_dec, $Counter);

unless ($Global::Windows) {
	push @trapped_signals, qw(HUP USR1 USR2);
	$Routine_USR1 = sub { $SIG{USR1} = $Routine_USR1; $Vend::Server::Num_servers++};
	$Routine_USR2 = sub { $SIG{USR2} = $Routine_USR2; $Vend::Server::Num_servers--};
	$Routine_HUP  = sub { $SIG{HUP} = $Routine_HUP; $Signal_Restart = 1};
}

$Routine_TERM = sub { $SIG{TERM} = $Routine_TERM; $Signal_Terminate = 1 };
$Routine_INT  = sub { $SIG{INT} = $Routine_INT; $Signal_Terminate = 1 };

sub setup_signals {
    @orig_signal{@trapped_signals} =
        map(defined $_ ? $_ : 'DEFAULT', @SIG{@trapped_signals});
    $Signal_Terminate = $Signal_Debug = '';
    $SIG{'PIPE'} = 'IGNORE';

	if ($Global::Windows) {
		$SIG{'INT'}  = sub { $Signal_Terminate = 1; };
		$SIG{'TERM'} = sub { $Signal_Terminate = 1; };
	}
	elsif($Config{'osname'} eq 'irix' or ! $Config{d_sigaction}) {
		$SIG{'INT'}  = $Routine_INT;
		$SIG{'TERM'} = $Routine_TERM;
		$SIG{'HUP'}  = $Routine_HUP;
		$SIG{'USR1'} = $Routine_USR1;
		$SIG{'USR2'} = $Routine_USR2;
	}
	else  {
		$SIG{'INT'}  = sub { $Signal_Terminate = 1; };
		$SIG{'TERM'} = sub { $Signal_Terminate = 1; };
		$SIG{'HUP'}  = sub { $Signal_Restart = 1; };
		$SIG{'USR1'} = sub { $Vend::Server::Num_servers++; };
		$SIG{'USR2'} = sub { $Vend::Server::Num_servers--; };
	}

	if(! $Global::MaxServers) {
        $Sig_inc = sub { 1 };
        $Sig_dec = sub { 1 };
	}
    else {
        $Sig_inc = sub { kill "USR1", $Vend::MasterProcess; };
        $Sig_dec = sub { kill "USR2", $Vend::MasterProcess; };
    }
}

sub restore_signals {
    @SIG{@trapped_signals} = @orig_signal{@trapped_signals};
}

my $Last_housekeeping = 0;

# Reconfigure any catalogs that have requested it, and 
# check to make sure we haven't too many running servers
sub housekeeping {
	my ($tick) = @_;
	my $now = time;
	rand();

	return if defined $tick and ($now - $Last_housekeeping < $tick);

	$Last_housekeeping = $now;

	my ($c, $num,$reconfig, $restart, @files);
	my @pids;

		opendir(Vend::Server::CHECKRUN, $Global::ConfDir)
			or die "opendir $Global::ConfDir: $!\n";
		@files = readdir Vend::Server::CHECKRUN;
		closedir(Vend::Server::CHECKRUN)
			or die "closedir $Global::ConfDir: $!\n";
		($reconfig) = grep $_ eq 'reconfig', @files;
		($restart) = grep $_ eq 'restart', @files
			if $Signal_Restart || $Global::Windows;
		if($Global::PIDcheck) {
			$Vend::Server::Num_servers = 0;
			@pids = grep /^pid\.\d+$/, @files;
		}
		#scalar grep($_ eq 'stop_the_server', @files) and exit;
		if (defined $restart) {
			$Signal_Restart = 0;
			open(Vend::Server::RESTART, "+<$Global::ConfDir/restart")
				or die "open $Global::ConfDir/restart: $!\n";
			lockfile(\*Vend::Server::RESTART, 1, 1)
				or die "lock $Global::ConfDir/restart: $!\n";
			while(<Vend::Server::RESTART>) {
				chomp;
				my ($directive,$value) = split /\s+/, $_, 2;
				if($value =~ /<<(.*)/) {
					my $mark = $1;
					$value = Vend::Config::read_here(\*Vend::Server::RESTART, $mark);
					unless (defined $value) {
						logGlobal(<<EOF);
Global reconfig ERROR
Can't find string terminator "$mark" anywhere before EOF.
EOF
						last;
					}
					chomp $value;
				}
				eval {
					if($directive =~ /^\s*(sub)?catalog$/i) {
						::add_catalog("$directive $value");
					}
					elsif($directive =~ /^remove\s+catalog\s+(\S+)$/i) {
						::remove_catalog($1);
					}
					else {
						::change_global_directive($directive, $value);
					}
				};
				if($@) {
					logGlobal($@);
					last;
				}
			}
			unlockfile(\*Vend::Server::RESTART)
				or die "unlock $Global::ConfDir/restart: $!\n";
			close(Vend::Server::RESTART)
				or die "close $Global::ConfDir/restart: $!\n";
			unlink "$Global::ConfDir/restart"
				or die "unlink $Global::ConfDir/restart: $!\n";
		}
		if (defined $reconfig) {
			open(Vend::Server::RECONFIG, "+<$Global::ConfDir/reconfig")
				or die "open $Global::ConfDir/reconfig: $!\n";
			lockfile(\*Vend::Server::RECONFIG, 1, 1)
				or die "lock $Global::ConfDir/reconfig: $!\n";
			while(<Vend::Server::RECONFIG>) {
				chomp;
				my ($script_name,$build) = split /\s+/, $_;
				my $select = $Global::SelectorAlias{$script_name} || $script_name;
                my $cat = $Global::Selector{$select};
                unless (defined $cat) {
#                    logGlobal("Bad script name '$script_name' for reconfig.")
                    logGlobal( errmsg('Server.pm:1', "Bad script name '%s' for reconfig." , $script_name) );
                    next;
                }
                $c = ::config_named_catalog($cat->{'CatalogName'},
                                    "from running server ($$)", $build);
				if (defined $c) {
					$Global::Selector{$select} = $c;
					for(sort keys %Global::SelectorAlias) {
						next unless $Global::SelectorAlias{$_} eq $select;
						$Global::Selector{$_} = $c;
					}
#					logGlobal "Reconfig of $c->{CatalogName} successful, build=$build.";
					logGlobal( errmsg('Server.pm:2', "Reconfig of %s successful, build=%s.",
						$c->{CatalogName},
						$build)
					);
				}
				else {
					logGlobal( errmsg(
'Server.pm:3', "Error reconfiguring catalog %s from running server (%s)\n%s",
						$script_name, $$, $@) );
				}
			}
			unlockfile(\*Vend::Server::RECONFIG)
				or die "unlock $Global::ConfDir/reconfig: $!\n";
			close(Vend::Server::RECONFIG)
				or die "close $Global::ConfDir/reconfig: $!\n";
			unlink "$Global::ConfDir/reconfig"
				or die "unlink $Global::ConfDir/reconfig: $!\n";
		}
        for (@pids) {
            $Vend::Server::Num_servers++;
            my $fn = "$Global::ConfDir/$_";
            ($Vend::Server::Num_servers--, next) if ! -f $fn;
            my $runtime = $now - (stat(_))[9];
            next if $runtime < $Global::PIDcheck;
            s/^pid\.//;
            if(kill 9, $_) {
                unlink $fn and $Vend::Server::Num_servers--;
                ::logGlobal("hammered PID $_ running $runtime seconds");
            }
            elsif (! kill 0, $_) {
				unlink $fn and $Vend::Server::Num_servers--;
				::logGlobal("Spurious PID file for process $_ supposedly running $runtime seconds");
			}
            else {
				unlink $fn and $Vend::Server::Num_servers--;
                ::logGlobal("PID $_ running $runtime seconds would not die!");
            }
        }


}

# The servers for both are now combined
# Can have both INET and UNIX on same system
sub server_both {
    my ($socket_filename) = @_;
    my ($n, $rin, $rout, $pid, $tick);

	$Vend::MasterProcess = $$;

	$tick        = $Global::HouseKeeping || 60;

    setup_signals();

	my ($host, $port);
	if($Global::Inet_Mode) {
		$host = $Global::TcpHost || '127.0.0.1';
		my @hosts;
		$Global::TcpHost =~ s/\./\\./g;
		$Global::TcpHost =~ s/\*/\\S+/g;
		@hosts = grep /\S/, split /\s+/, $Global::TcpHost;
		$Global::TcpHost = join "|", @hosts;
		::logGlobal("Accepting connections from $Global::TcpHost");
	}

	my $proto = getprotobyname('tcp');

# DEBUG
#Vend::Util::logDebug
#("Starting server socket file='$socket_filename' tcpport=$port hosts='$host'\n")
#	if ::debug($Global::DHASH{SERVER});
# END DEBUG
	unlink $socket_filename;

	my $vector = '';
	my $spawn;

	my $so_max;
	if(defined &SOMAXCONN) {
		$so_max = SOMAXCONN;
	}
	else {
		$so_max = 128;
	}

	unlink "$Global::ConfDir/mode.inet", "$Global::ConfDir/mode.unix";

	if($Global::Unix_Mode) {
		socket(Vend::Server::USOCKET, AF_UNIX, SOCK_STREAM, 0) || die "socket: $!";

		setsockopt(Vend::Server::USOCKET, SOL_SOCKET, SO_REUSEADDR, pack("l", 1));

		bind(Vend::Server::USOCKET, pack("S", AF_UNIX) . $socket_filename . chr(0))
			or die "Could not bind (open as a socket) '$socket_filename':\n$!\n";
		listen(Vend::Server::USOCKET,$so_max) or die "listen: $!";

		$rin = '';
		vec($rin, fileno(Vend::Server::USOCKET), 1) = 1;
		$vector |= $rin;
		open(Vend::Server::INET_MODE_INDICATOR, ">$Global::ConfDir/mode.unix")
			or die "creat mode.inet: $!";
		close(Vend::Server::INET_MODE_INDICATOR);

		chmod 0600, $socket_filename;

		#DEBUG or very insecure installations with no sensitive data
		chmod 0666, $socket_filename if $ENV{MINIVEND_INSECURE};

	}

	use Symbol;
	my %fh_map;
	my %vec_map;
	my $made_at_least_one;

	if($Global::Inet_Mode) {

	  foreach $port (keys %{$Global::TcpMap}) {
		my $fh = gensym();
#::logGlobal("Trying to run server on $port, fh created: $fh");
		
		eval {
			socket($fh, PF_INET, SOCK_STREAM, $proto)
					|| die "socket: $!";
			setsockopt($fh, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
					|| die "setsockopt: $!";
			bind($fh, sockaddr_in($port, INADDR_ANY))
					|| die "bind: $!";
			listen($fh,$so_max)
					|| die "listen: $!";
			$made_at_least_one = 1;
		};


		if (! $@) {
			$rin = '';
			vec($rin, fileno($fh), 1) = 1;
			$vector |= $rin;
			$vec_map{$port} = fileno($fh);
			$fh_map{$port} = $fh;
		}
		else {
		  logGlobal( errmsg(
					'Server.pm:5',
					"INET mode server failed to start on port %s: %s",
					$port,
					$@ )
				  );
		}
		next if $made_at_least_one;
		open(Vend::Server::INET_MODE_INDICATOR, ">$Global::ConfDir/mode.inet")
			or die "creat mode.inet: $!";
		close(Vend::Server::INET_MODE_INDICATOR);
	  }
	}

	if (! $made_at_least_one and $Global::Inet_Mode) {
		if ($Global::Unix_Mode) {
			logGlobal( errmsg('Server.pm:4', "Continuing in UNIX MODE ONLY" ));
		}
		else {
		  logGlobal( errmsg('Server.pm:6', "SERVER TERMINATING" ) );
		  exit 1;
		}
	}

	my $no_fork;

	if($Global::Windows or ::debug(0x1000) ) {
# DEBUG
#print
#("Running in foreground, OS=$, debug=$Global::DEBUG\n")
#	if ::debug(0xFFFF);
# END DEBUG
		$no_fork = 1;
		$Vend::Foreground = 1;
	}

    for (;;) {

# DEBUG
#$Global::DEBUG = $Global::DebugMode;
# END DEBUG

	  eval {
        $rin = $vector;
		undef $spawn;
        $n = select($rout = $rin, undef, undef, $tick);

		undef $Vend::Cfg;

        if ($n == -1) {
            if ($! =~ m/^Interrupted/) {
                if ($Signal_Terminate) {
                    last;
                }
            }
            else {
				my $msg = $!;
				logGlobal( errmsg('Server.pm:7', "error '%s' from select." , $msg) );
                die "select: $msg\n";
            }
        }

        elsif (	$Global::Unix_Mode && vec($rout, fileno(Vend::Server::USOCKET), 1) ) {
            my $ok = accept(Vend::Server::MESSAGE, Vend::Server::USOCKET);
            die "accept: $!" unless defined $ok;
			$spawn = 1;
		}
		elsif($n == 0) {
			undef $spawn;
			housekeeping();
		}
        elsif (	$Global::Inet_Mode ) {
            my ($ok, $p, $v);
			while (($p, $v) = each %vec_map) {
        		next unless vec($rout, $v, 1);
				$Global::TcpPort = $p;
				$ok = accept(Vend::Server::MESSAGE, $fh_map{$p});
			}
            die "accept: $!" unless defined $ok;
			my $connector;
			(undef, $ok) = sockaddr_in($ok);
		CHECKHOST: {
			undef $Vend::OnlyInternalHTTP;
			$connector = inet_ntoa($ok);
			last CHECKHOST if $connector =~ /$Global::TcpHost/;
			my $dns_name;
			(undef, $dns_name) = gethostbyaddr($ok, AF_INET);
			$dns_name = "UNRESOLVED_NAME" if ! $dns_name;
			last CHECKHOST if $dns_name =~ /$Global::TcpHost/;
			$Vend::OnlyInternalHTTP = "$dns_name/$connector";
		}
			$spawn = 1;
		}
        else {
            die "Why did select return with $n? Can we even get here?";
        }
	  };
#	  logGlobal("Died in select, retrying: $@") if $@;
	  logGlobal( errmsg('Server.pm:8', "Died in select, retrying: %s", $@ ) ) if $@;


	  eval {
		SPAWN: {
			last SPAWN unless defined $spawn;
# DEBUG
#Vend::Util::logDebug
#("Spawning connection, " .
#	($no_fork ? 'no fork, ' : 'forked, ') .  scalar localtime() . "\n")
#	if ::debug($Global::DHASH{SERVER});
# END DEBUG
			if(defined $no_fork) {
				$Vend::NoFork = {};
				$::Instance = {};
				connection();
				undef $Vend::NoFork;
				undef $::Instance;
			}
			elsif(! defined ($pid = fork) ) {
#				logGlobal ("Can't fork: $!");
				logGlobal( errmsg('Server.pm:9', "Can't fork: %s", $! ) );
				die ("Can't fork: $!");
			}
			elsif (! $pid) {
				#fork again
				unless ($pid = fork) {

					$::Instance = {};
					eval { 
						touch_pid() if $Global::PIDcheck;
						&$Sig_inc;
						connection();
					};
					if ($@) {
						my $msg = $@;
						logGlobal( errmsg('Server.pm:10', "Runtime error: %s" , $msg) );
						logError( errmsg('Server.pm:11', "Runtime error: %s" , $msg) )
					}

					undef $::Instance;
					select(undef,undef,undef,0.050) until getppid == 1;
					if ($Global::PIDcheck) {
						unlink_pid() and &$Sig_dec;
					}
					else {
						&$Sig_dec;
					}
					exit(0);
				}
				exit(0);
			}
			close Vend::Server::MESSAGE;
			last SPAWN if $no_fork;
			wait;
		}
	  };

		# clean up dies during spawn
		if ($@) {
			logGlobal( errmsg('Server.pm:12', "Died in server spawn: %s", $@) ) if $@;

			# Below only happens with Windows or foreground debugs.
			# Prevent corruption of changed $Vend::Cfg entries
			# (only VendURL/SecureURL at this point).
			if($Vend::Save and $Vend::Cfg) {
				Vend::Util::copyref($Vend::Save, $Vend::Cfg);
				undef $Vend::Save;
			}
			undef $Vend::Cfg;
		}

		last if $Signal_Terminate || $Signal_Debug;

	  eval {
        for(;;) {
		   housekeeping($tick);
           last if ! $Global::MaxServers or $Vend::Server::Num_servers < $Global::MaxServers;
           select(undef,undef,undef,0.100);
           last if $Signal_Terminate || $Signal_Debug;
        }
	  };
	  logGlobal( errmsg('Server.pm:13', "Died in housekeeping, retry." ) ) if $@;

    }

    restore_signals();

   	if ($Signal_Terminate) {
       	logGlobal( errmsg('Server.pm:14', "STOP server (%s) on signal TERM", $$ ));
       	return 'terminate';
   	}

    return '';
}

 sub debug {
     my ($x, $y);
     for (;;) {
         print "> ";
         $x = <STDIN>;
         return if $x eq "\n";
         $y = eval $x;
         if ($@) {
             print $@, "\n";
         }
         else {
             print "$y\n";
         }
     }
 }

sub touch_pid {
	open(TEMPPID, ">>$Global::ConfDir/pid.$$") 
		or die "creat PID file $$: $!\n";
	lockfile(\*TEMPPID, 1, 0)
		or die "PID $$ conflict: can't lock\n";
}

sub unlink_pid {
	close(TEMPPID);
	unlink("$Global::ConfDir/pid.$$");
	1;
}

sub grab_pid {
    my $ok = lockfile(\*Vend::Server::Pid, 1, 0);
    if (not $ok) {
        chomp(my $pid = <Vend::Server::Pid>);
        return $pid;
    }
    {
        no strict 'subs';
        truncate(Vend::Server::Pid, 0) or die "Couldn't truncate pid file: $!\n";
    }
    print Vend::Server::Pid $$, "\n";
    return 0;
}



sub open_pid {

	$Pidfile = $Global::ConfDir . "/minivend.pid";
    open(Vend::Server::Pid, "+>>$Pidfile")
        or die "Couldn't open '$Pidfile': $!\n";
    seek(Vend::Server::Pid, 0, 0);
    my $o = select(Vend::Server::Pid);
    $| = 1;
    {
        no strict 'refs';
        select($o);
    }
}

sub run_server {
    my $next;
    my $pid;
	my $silent = 0;
	
    open_pid();

	unless($Global::Inet_Mode || $Global::Unix_Mode || $Global::Windows) {
		$Global::Inet_Mode = $Global::Unix_Mode = 1;
	}
	elsif ( $Global::Windows ) {
		$Global::Inet_Mode = 1;
	}

	my @types;
	push (@types, 'INET') if $Global::Inet_Mode;
	push (@types, 'UNIX') if $Global::Unix_Mode;
	my $server_type = join(" and ", @types);

    if ($Global::Windows || ::debug(4096) ) {
        $pid = grab_pid();
        if ($pid) {
            print "The MiniVend server is already running ".
                "(process id $pid)\n";
            exit 1;
        }

        print "MiniVend server started ($$) ($server_type)\n";
		$next = server_both($LINK_FILE);
    }

    else {

        fcntl(Vend::Server::Pid, F_SETFD, 0)
            or die "Can't fcntl close-on-exec flag for '$Pidfile': $!\n";
        my ($pid1, $pid2);
        if ($pid1 = fork) {
            # parent
            wait;
            exit 0;
        }
        elsif (not defined $pid1) {
            # fork error
            print "Can't fork: $!\n";
            exit 1;
        }
        else {
            # child 1
            if ($pid2 = fork) {
                # still child 1
                exit 0;
            }
            elsif (not defined $pid2) {
                print "child 1 can't fork: $!\n";
                exit 1;
            }
            else {
                # child 2
                sleep 1 until getppid == 1;

                $pid = grab_pid();
                if ($pid) {
                    print "The MiniVend server is already running ".
                        "(process id $pid)\n"
						unless $silent;
                    exit 1;
                }
                print "MiniVend server started in $server_type mode(s) (process id $$)\n"
					unless $silent;

                close(STDIN);
                close(STDOUT);
                close(STDERR);

				if($Global::DEBUG & 2048) {
					$Global::DEBUG = $Global::DEBUG || 255;
					open(Vend::DEBUG, ">>$Global::ConfDir/mvdebug");
					select Vend::DEBUG;
					print "Start DEBUG at " . localtime() . "\n";
					$| =1;
				}
				elsif (!$Global::DEBUG) {
					# May as well turn warnings off, not going anywhere
					$ = 0;
				}

                open(STDOUT, ">&Vend::DEBUG");
				select(STDOUT);
                $| = 1;
                open(STDERR, ">&Vend::DEBUG");
                select(STDERR); $| = 1; select(STDOUT);

                logGlobal( errmsg('Server.pm:15', "START server (%s) (%s)" , $$, $server_type) );

                setsid();

                fcntl(Vend::Server::Pid, F_SETFD, 1)
                    or die "Can't fcntl close-on-exec flag for '$Pidfile': $!\n";

				$next = server_both($LINK_FILE);

				unlockfile(\*Vend::Server::Pid);
				opendir(CONFDIR, $Global::ConfDir) 
					or die "Couldn't open directory $Global::ConfDir: $!\n";
				my @running = grep /^mvrunning/, readdir CONFDIR;
				for(@running) {
					unlink "$Global::ConfDir/$_" or die
						"Couldn't unlink status file $Global::ConfDir/$_: $!\n";
				}
				unlink $Pidfile;
                exit 0;
            }
        }
    }                
}

1;
__END__
