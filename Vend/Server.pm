# Server.pm:  listen for cgi requests as a background server
#
# $Id: Server.pm,v 1.6 1996/05/25 07:06:03 mike Exp mike $

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

use strict;

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
	if ($Config::Cookies) {
		print $fh "Set-Cookie: MV_SESSION_ID=" . $Vend::SessionID . "; path=/\r\n";
    }
    print $fh "Content-type: $content_type\r\n\r\n";
    print $fh $body;
    $s->{'response_made'} = 1;
}
    

package Vend::Server;
require Exporter;
@Vend::Server::ISA = qw(Exporter);
@Vend::Server::EXPORT = qw(run_server);

use Fcntl;
use Socket;
use strict;
use Vend::Util;

my $LINK_FILE = '/tmp/test/etc/socket';

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

sub get_socketname {
	my $base = shift;
	$base =~ s:(.*)/::;
	my $dir = $1;
	$base =~ s/[^A-Za-z0-9]//g;
	$base .= int rand 10;
	for(;;) {
		last unless -e "$dir/$base";
		$base++;
	}
	"$dir/$base";
}

sub connection {
    my ($socket,$debug) = @_;

    my (@argv, %env, $entity);
    read_cgi_data(\@argv, \%env, \$entity);

    my $http = new Vend::Http::Server \*Vend::Server::MESSAGE, \%env, $entity;
    my $abort = ::dispatch($http,$socket,$debug);
    $abort;
}


## Signals

my $Signal_Terminate;
my $Signal_Debug;
my $Signal_Locking;
my %orig_signal;
my @trapped_signals = qw(HUP INT TERM USR1 USR2);

# might also trap: QUIT USR1 USR2

sub setup_signals {
    @orig_signal{@trapped_signals} =
        map(defined $_ ? $_ : 'DEFAULT', @SIG{@trapped_signals});
    $Signal_Terminate = $Signal_Locking = $Signal_Debug = '';
    $SIG{'HUP'}  = 'IGNORE';
    $SIG{'INT'}  = sub { $Signal_Terminate = 1; };
    $SIG{'TERM'} = sub { $Signal_Terminate = 1; };
    # $SIG{'QUIT'} = sub { $Signal_Debug = 1; };
    $SIG{'USR1'} = sub { $Signal_Locking = 'short term'; };
    $SIG{'USR2'} = sub { $Signal_Locking = 'long term'; };
    $SIG{'PIPE'} = 'IGNORE';
}

sub restore_signals {
    @SIG{@trapped_signals} = @orig_signal{@trapped_signals};
}

sub server {
    my ($socket_filename, $debug) = @_;
    my ($n, $rin, $rout, $abort);

    my $AF_UNIX = 1;
    my $SOCK_STREAM = 1;
    my $SOCK_DGRAM = 2;


    setup_signals();
    $abort = 0;
    for (;;) {
        last if $abort || $Signal_Terminate || $Signal_Debug;

		if($Config::MultiServer) {
			open(Vend::Server::SOCKET_LOCK,"+>>$socket_filename.lock")
				or die "Couldn't open $socket_filename.lock: $!";
			fcntl(Vend::Server::SOCKET_LOCK, F_SETFD, 0)
				or die "Can't fcntl close-on-exec flag for socket lock: $!";
			lockfile(\*Vend::Server::SOCKET_LOCK,1,1)
				or die "Couldn't lock $socket_filename.lock: $!";
		}
		unlink $socket_filename;
		socket(Vend::Server::SOCKET, AF_UNIX, SOCK_STREAM, 0) || die "socket: $!";
		bind(Vend::Server::SOCKET, pack("S", AF_UNIX) . $socket_filename . chr(0))
			or die "Could not bind (open as a socket) '$socket_filename':\n$!\n";
		chmod $Config::FileCreationMask, $socket_filename;
		listen(Vend::Server::SOCKET, 5) or die "listen: $!";

		if ($Signal_Locking) {
			my $sleep = 1;
			if ($Signal_Locking =~ /short/i) {
            	::logError("\nUnlock for $sleep seconds on pid $$\n\n");
			}
			elsif ($Signal_Locking =~ /long/i) {
            	::logError("\nUnlock for 120 seconds on pid $$\n\n");
				$sleep = 120;
			}
			$SIG{'USR1'} = $SIG{'USR2'} = 'IGNORE';
			::close_session();
			sleep $sleep;
			::read_products();
			::open_session();
			setup_signals();
		}

        $rin = '';
        vec($rin, fileno(Vend::Server::SOCKET), 1) = 1;
        $n = select($rout = $rin, undef, undef, undef);

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
                die "select: $!\n";
            }
        }

        elsif (vec($rout, fileno(Vend::Server::SOCKET), 1)) {
            my $ok = accept(Vend::Server::MESSAGE, Vend::Server::SOCKET);
            die "accept: $!" unless defined $ok;
			my $new_socket = get_socketname $socket_filename;
			rename $socket_filename, $new_socket;

			if($Config::MultiServer) {
				# unlock the socketlock so a new server can get it
				unlockfile(\*Vend::Server::SOCKET_LOCK)
					or die "Couldn't unlock socket lock: $!";;
				close Vend::Server::SOCKET_LOCK
					or die "Couldn't close socket lock: $!";;
			}

			# Pass the socket name so that a child can unlink it
            $abort = connection($new_socket, $debug);
            close Vend::Server::SOCKET;
            close Vend::Server::MESSAGE;

			# Here we are using $abort to tell us
			# if we have forked. It will have a PID in it
			# if we did (that won't be 1!). If we really want
			# to add abort later, then we can make an abort be 1.
			# If we forked, we don't want to unlink the socket,
			# the child will do that in minivend.pl
			if ($abort == 0) {
				unlink $new_socket;
			}
			elsif ($abort > 1) {
				$abort = 0;
			}
        }

        else {
            die "Why did select return?";
        }
    }

    close(Vend::Server::SOCKET);
    restore_signals();

   	if ($Signal_Terminate) {
       	::logError("\nServer terminating on signal TERM\n\n");
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


my $Print_errors;
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

use POSIX;

my $pidfile;

sub open_pid {
	my $multi = shift;
	my $it = 0;
	if(defined $multi and $multi) {
		do {
			$pidfile = $Config::ConfDir . "/minivend.pid" . $it++;
		} until ! -e $pidfile;
	}
	else {
		$pidfile = $Config::ConfDir . "/minivend.pid";
	}
    open(Vend::Server::Pid, "+>>$pidfile")
        or die "Couldn't open '$pidfile': $!\n";
    seek(Vend::Server::Pid, 0, 0);
    my $o = select(Vend::Server::Pid);
    $| = 1;
    {
        no strict 'refs';
        select($o);
    }
}

sub run_server {
    my ($multi,$debug) = @_;
    my $next;
    my $pid;
	my $silent = 0;
	
	# This will happen if it is a netstart
	if ($debug < 0) {
		$debug = 0;
		$silent = 1;
	}
    $Print_errors = $debug;

    open_pid($multi);

    if ($debug) {
        $pid = grab_pid();
        if ($pid) {
            print "The MiniVend server is already running ".
                "(process id $pid)\n";
            exit 1;
        }

        print "MiniVend server started (process id $$)\n";
        server($LINK_FILE, $debug);
        exit 0;
    }

    else {
        fcntl(Vend::Server::Pid, F_SETFD, 0)
            or die "Can't fcntl close-on-exec flag for '$pidfile': $!\n";
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

                print "MiniVend server started (process id $$)\n"
					unless $silent;

                close(STDIN);
                close(STDOUT);
                close(STDERR);
                open(STDOUT, ">&Vend::DEBUG");
                $| = 1;
                open(STDERR, ">&Vend::DEBUG");
                select(STDERR); $| = 1; select(STDOUT);

                ::logError("\nServer running on pid $$\n\n");
                setsid();

                fcntl(Vend::Server::Pid, F_SETFD, 1)
                    or die "Can't fcntl close-on-exec flag for '$pidfile': $!\n";

                $next = server($LINK_FILE, $debug);
				unlink $pidfile;
                exit 0;
            }
        }
    }                
}

1;
