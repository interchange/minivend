# Server.pm:  listen for cgi requests as a background server
#
# $Id: Server.pm,v 1.17 1997/06/27 11:32:10 mike Exp mike $

# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
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

use POSIX 'strftime';
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

sub respond {
    my ($s, $content_type, $body) = @_;
    my $fh = $s->{fh};

	# Fix for SunOS, Ultrix, Digital UNIX
	my($oldfh) = select($fh);
	$| = 1;
	select($oldfh);

	if($s->{response_made}) {
		print $fh $body;
		return 1;
	}

	if ($CGI::script_name =~ m:/nph-[^/]+$:) {
		print $fh "HTTP/1.0 200 OK\r\n";
	}
	if ($Vend::Session->{frames} and $CGI::values{mv_change_frame}) {
print "Changed Frame: Window-target: " . $CGI::values{mv_change_frame} . "\r\n" if $Global::DEBUG;
		print $fh "Window-target: " . $CGI::values{mv_change_frame} . "\r\n";
    }

	if ((defined $Vend::Expire or ! $CGI::cookie) and $Vend::Cfg->{'Cookies'}) {
		print $fh "Set-Cookie: MV_SESSION_ID=" . $Vend::SessionName . ";";
		print $fh "domain=" . $Vend::Cfg->{CookieDomain} . ";"
			if $Vend::Cfg->{CookieDomain};
		if($Global::Mall) {
			print $fh " path=$CGI::script_path;";
		}
		else {
			print $fh " path=/;";
		}
		print $fh " expires=" .
					strftime "%a, %d-%b-%y %H:%M:%S GMT ", gmtime($Vend::Expire)
			if defined $Vend::Expire and $Vend::Expire;
		print $fh "\r\n";
    }
    if (defined $Vend::StatusLine) {
		print $fh "$Vend::StatusLine\r\n";
	}
	else {
		print $fh "Content-type: $content_type\r\n";
	}
    print $fh "\r\n";
    print $fh $body;
    $s->{'response_made'} = 1;
}
    

package Vend::Server;
require Exporter;
@Vend::Server::ISA = qw(Exporter);
@Vend::Server::EXPORT = qw(run_server);

use Fcntl;
use Config;
use Socket;
use strict;
use POSIX;
use Vend::Util;

my $LINK_FILE = "$Global::ConfDir/socket";

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

sub read_cgi_data {
    my ($argv, $env, $entity) = @_;
    my ($in, $block, $n, $i, $e, $key, $value);
    $in = '';

    for (;;) {
        $block = _find(\$in, "\n");
        if (($n) = ($block =~ m/^arg (\d+)$/)) {
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
}

sub connection {
    my ($debug) = @_;

    my (@argv, %env, $entity);
    read_cgi_data(\@argv, \%env, \$entity);

    my $http = new Vend::Http::Server \*Vend::Server::MESSAGE, \%env, $entity;
    
    ::dispatch($http,$debug);
}

## Signals

my $Signal_Terminate;
my $Signal_Debug;
my $Signal_Restart;
my %orig_signal;
my @trapped_signals = qw(HUP INT TERM USR1 USR2);
$Vend::Server::Num_servers = 0;

# might also trap: QUIT

my ($Routine_USR1, $Routine_USR2, $Routine_TERM, $Routine_INT);
my ($Sig_inc, $Sig_dec, $Counter);

$Routine_USR1 = sub { $SIG{USR1} = $Routine_USR1; $Vend::Server::Num_servers++};
$Routine_USR2 = sub { $SIG{USR2} = $Routine_USR2; $Vend::Server::Num_servers--};
$Routine_TERM = sub { $SIG{TERM} = $Routine_TERM; $Signal_Terminate = 1 };
$Routine_INT  = sub { $SIG{INT} = $Routine_INT; $Signal_Terminate = 1 };

sub setup_signals {
    @orig_signal{@trapped_signals} =
        map(defined $_ ? $_ : 'DEFAULT', @SIG{@trapped_signals});
    $Signal_Terminate = $Signal_Debug = '';
    $SIG{'HUP'}  = 'IGNORE';
    $SIG{'PIPE'} = 'IGNORE';

	if($Config{'osname'} eq 'irix' or ! $Config{d_sigaction}) {
		$SIG{'INT'}  = $Routine_INT;
		$SIG{'TERM'} = $Routine_TERM;
		$SIG{'USR1'} = $Routine_USR1;
		$SIG{'USR2'} = $Routine_USR2;
	}

	else {
		$SIG{'INT'}  = sub { $Signal_Terminate = 1; };
		$SIG{'TERM'} = sub { $Signal_Terminate = 1; };
		$SIG{'USR1'} = sub { $Vend::Server::Num_servers++; };
		$SIG{'USR2'} = sub { $Vend::Server::Num_servers--; };
	}

    if(! $Global::SafeSignals or $Config{'osname'} =~ /bsd/) {
        require File::CounterFile;
        my $filename = "$Global::ConfDir/process.counter";
        unlink $filename;
        $Counter = new File::CounterFile $filename;
        $Sig_inc = sub { $Vend::Server::Num_servers = $Counter->inc(); };
        $Sig_dec = sub { $Vend::Server::Num_servers = $Counter->dec(); };
    }
    else {
        $Sig_inc = sub { kill "USR1", $Vend::MasterProcess; };
        $Sig_dec = sub { kill "USR2", $Vend::MasterProcess; };
    }

}

sub restore_signals {
    @SIG{@trapped_signals} = @orig_signal{@trapped_signals};
}

my $Last_housekeeping;

# Reconfigure any catalogs that have requested it, and 
# check to make sure we haven't too many running servers
sub housekeeping {
	my ($tick) = @_;
	my $now = time;
	rand();

	# Always do it if called without argument, otherwise
	# only after $tick seconds
	unless (!defined $tick) {
		return if ($now - $Last_housekeeping < $tick);
	}

	$Last_housekeeping = $now;

	my ($c, $num,$reconfig, $restart, @files);

		opendir(Vend::Server::CHECKRUN, $Global::ConfDir)
			or die "opendir $Global::ConfDir: $!\n";
		@files = readdir Vend::Server::CHECKRUN;
		closedir(Vend::Server::CHECKRUN)
			or die "closedir $Global::ConfDir: $!\n";
		($reconfig) = grep $_ eq 'reconfig', @files;
		($restart) = grep $_ eq '.restart', @files;
		if (defined $restart) {
			open(Vend::Server::RECONFIG, "+<$Global::ConfDir/.restart")
				or die "open $Global::ConfDir/.restart: $!\n";
			lockfile(\*Vend::Server::RECONFIG, 1, 1)
				or die "lock $Global::ConfDir/reconfig: $!\n";
			my $options = <Vend::Server::RECONFIG>;
			chomp $options;
			$Signal_Restart = $options;
			unlockfile(\*Vend::Server::RECONFIG)
				or die "unlock $Global::ConfDir/.restart: $!\n";
			close(Vend::Server::RECONFIG)
				or die "close $Global::ConfDir/.restart: $!\n";
			unlink "$Global::ConfDir/.restart"
				or die "unlink $Global::ConfDir/.restart: $!\n";
			unlink "$Global::ConfDir/reconfig";
			logGlobal "Restarting server at admin request.\n\nOptions: $options.\n";
			$Signal_Terminate = 1;
		}
		elsif (defined $reconfig) {
			open(Vend::Server::RECONFIG, "+<$Global::ConfDir/reconfig")
				or die "open $Global::ConfDir/reconfig: $!\n";
			lockfile(\*Vend::Server::RECONFIG, 1, 1)
				or die "lock $Global::ConfDir/reconfig: $!\n";
			while(<Vend::Server::RECONFIG>) {
				chomp;
				my ($script_name,$build) = split /\s+/, $_;
                my $cat = $Global::Selector{$script_name};
                unless (defined $cat) {
                    logGlobal(<<EOF);
Bad script name '$script_name' for reconfig.
EOF
                    next;
                }
                $c = ::config_named_catalog($cat->{'CatalogName'},
                                    "from running server ($$)", $build);
				if (defined $c) {
					$Global::Selector{$script_name} = $c;
					for(sort keys %Global::SelectorAlias) {
						next unless $Global::SelectorAlias{$_} eq $script_name;
						$Global::Selector{$_} = $c;
					}
					logGlobal "Reconfig of $c->{CatalogName} successful, build=$build.";
				}
				else {
					logGlobal <<EOF;
Error reconfiguring catalog $script_name from running server ($$):
$@
EOF
				}
			}
			unlockfile(\*Vend::Server::RECONFIG)
				or die "unlock $Global::ConfDir/reconfig: $!\n";
			close(Vend::Server::RECONFIG)
				or die "close $Global::ConfDir/reconfig: $!\n";
			unlink "$Global::ConfDir/reconfig"
				or die "unlink $Global::ConfDir/reconfig: $!\n";
		}

}

# The servers for both are now combined
# Can have both INET and UNIX on same system
sub server_both {
    my ($socket_filename, $debug) = @_;
    my ($n, $rin, $rout, $pid, $tick, $max_servers);

	$Vend::MasterProcess = $$;

	$max_servers = $Global::MaxServers   || 4;
	$tick        = $Global::HouseKeeping || 60;

    setup_signals();


	my $port = $Global::TcpPort || 7786;
	my $host = $Global::TcpHost || '127.0.0.1';
	my $proto = getprotobyname('tcp');

	unlink $socket_filename;

	my $vector = '';
	my $spawn;

	my $so_max;
	if(defined &SOMAXCONN) {
		$so_max = SOMAXCONN;
	}
	else {
		$so_max = 10;
	}

	if($Global::Unix_Mode) {
		socket(Vend::Server::USOCKET, AF_UNIX, SOCK_STREAM, 0) || die "socket: $!";

		setsockopt(Vend::Server::USOCKET, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
			|| die "setsockopt: $!";

		bind(Vend::Server::USOCKET, pack("S", AF_UNIX) . $socket_filename . chr(0))
			or die "Could not bind (open as a socket) '$socket_filename':\n$!\n";
		listen(Vend::Server::USOCKET,$so_max) or die "listen: $!";

		$rin = '';
		vec($rin, fileno(Vend::Server::USOCKET), 1) = 1;
		$vector |= $rin;

		chmod 0600, $socket_filename;

		#DEBUG or very insecure installations with no sensitive data
		#chmod 0666, $socket_filename; #DEBUG

	}

	if($Global::Inet_Mode) {
		socket(Vend::Server::ISOCKET, PF_INET, SOCK_STREAM, $proto)
				|| die "socket: $!";
		setsockopt(Vend::Server::ISOCKET, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
				|| die "setsockopt: $!";
		bind(Vend::Server::ISOCKET, sockaddr_in($port, INADDR_ANY))
				|| die "bind: $!";
		listen(Vend::Server::ISOCKET,$so_max)
				|| die "listen: $!";
		$rin = '';
		vec($rin, fileno(Vend::Server::ISOCKET), 1) = 1;
		$vector |= $rin;
	}

    for (;;) {


	  eval {
        $rin = $vector;
		undef $spawn;
        $n = select($rout = $rin, undef, undef, $tick);

        if ($n == -1) {
            if ($! =~ m/^Interrupted/) {
                # if ($Signal_Debug) {
                #    $Signal_Debug = 0;
                #    debug();
                # }
                # elsif
                if ($Signal_Terminate) {
                    last;
                }
            }
            else {
				my $msg = $!;
				logGlobal("error '$msg' from select.");
                die "select: $msg\n";
            }
        }

        elsif (	$Global::Inet_Mode && vec($rout, fileno(Vend::Server::ISOCKET), 1) ) {
            my $ok = accept(Vend::Server::MESSAGE, Vend::Server::ISOCKET);
            die "accept: $!" unless defined $ok;
			$spawn = 1;
		}
        elsif (	$Global::Unix_Mode && vec($rout, fileno(Vend::Server::USOCKET), 1) ) {
            my $ok = accept(Vend::Server::MESSAGE, Vend::Server::USOCKET);
            die "accept: $!" unless defined $ok;
			$spawn = 1;
		}
		elsif($n == 0) {
			housekeeping();
		}
        else {
            die "Why did select return with $n?";
        }
	  };
	  logGlobal("Died in select, retrying: $@") if $@;


	  eval {
		SPAWN: {
			last SPAWN unless defined $spawn;
			if(! defined ($pid = fork) ) {
				logGlobal ("Can't fork: $!");
				die ("Can't fork: $!");
			}
			elsif (! $pid) {
				#fork again
				unless ($pid = fork) {

					eval { 
						&$Sig_inc;
						connection($debug);
					};
					if ($@) {
						my $msg = $@;
						logGlobal("Runtime error: $msg");
						logError("Runtime error: $msg")
					}

					&$Sig_dec;
					select(undef,undef,undef,0.050) until getppid == 1;
					exit(0);
				}
				exit(0);
			}
			close Vend::Server::MESSAGE;
			wait;
		}
	  };
	  logGlobal("Died in server spawn, retry.\n") if $@;

        last if $Signal_Terminate || $Signal_Debug;

	  eval {
        for(;;) {
		   housekeeping($tick);
           last if $Vend::Server::Num_servers < $max_servers;
           select(undef,undef,undef,0.300);
           last if $Signal_Terminate || $Signal_Debug;
        }

	  };
	  logGlobal("Died in housekeeping, retry.\n") if $@;


    }

    close(Vend::Server::SOCKET);
    restore_signals();

   	if ($Signal_Terminate) {
       	logGlobal("STOP server ($$) on signal TERM");
       	return 'terminate';
   	}

    return '';
}

# sub debug {
#     my ($x, $y);
#     for (;;) {
#         print "> ";
#         $x = <STDIN>;
#         return if $x eq "\n";
#         $y = eval $x;
#         if ($@) {
#             print $@, "\n";
#         }
#         else {
#             print "$y\n";
#         }
#     }
# }


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
    my ($debug) = @_;
    my $next;
    my $pid;
	my $silent = 0;
	
    open_pid();

	unless($Global::Inet_Mode || $Global::Unix_Mode) {
		$Global::Inet_Mode = $Global::Unix_Mode = 1;
	}

	my @types;
	push (@types, 'INET') if $Global::Inet_Mode;
	push (@types, 'UNIX') if $Global::Unix_Mode;
	my $server_type = join(" and ", @types);

    if ($debug) {
        $pid = grab_pid();
        if ($pid) {
            print "The MiniVend server is already running ".
                "(process id $pid)\n";
            exit 1;
        }

        print "MiniVend server started ($$) ($server_type)\n";
		$next = server_both($LINK_FILE, $debug);
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

				if($Global::DebugMode) {
					$Global::DEBUG = 1;
					open(Vend::DEBUG, ">>mvdebug");
					select Vend::DEBUG;
					print "Start DEBUG at " . localtime() . "\n";
					$| =1;
				}
				else {
					# May as well turn warnings off, not going anywhere
					$ = 0;
				}

                open(STDOUT, ">&Vend::DEBUG");
				select(STDOUT);
                $| = 1;
                open(STDERR, ">&Vend::DEBUG");
                select(STDERR); $| = 1; select(STDOUT);

                logGlobal("START server ($$) ($server_type)");

                setsid();

                fcntl(Vend::Server::Pid, F_SETFD, 1)
                    or die "Can't fcntl close-on-exec flag for '$Pidfile': $!\n";

				$next = server_both($LINK_FILE, $debug);

				unlockfile(\*Vend::Server::Pid);
				opendir(CONFDIR, $Global::ConfDir) 
					or die "Couldn't open directory $Global::ConfDir: $!\n";
				my @running = grep /^mvrunning/, readdir CONFDIR;
				for(@running) {
					unlink "$Global::ConfDir/$_" or die
						"Couldn't unlink status file $Global::ConfDir/$_: $!\n";
				}
				unlink $Pidfile;
				system "$Global::VendRoot/bin/minivend $Signal_Restart"
					if $Signal_Restart;
                exit 0;
            }
        }
    }                
}

1;
__END__
