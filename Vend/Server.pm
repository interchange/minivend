# Server.pm:  listen for cgi requests as a background server
#
# $Id: Server.pm,v 1.10 1997/03/14 07:54:16 mike Exp mike $

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
	if (! $CGI::cookie and $Vend::Cfg->{'Cookies'}) {
		print $fh "Set-Cookie: MV_SESSION_ID=" . $Vend::SessionName . "; path=/\r\n";
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
use Config;
use Socket;
use strict;
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

sub unix_connection {
    my ($socket,$debug) = @_;

    my (@argv, %env, $entity);
    read_cgi_data(\@argv, \%env, \$entity);

    my $http = new Vend::Http::Server \*Vend::Server::MESSAGE, \%env, $entity;
    my $forked;
    eval {$forked = ::dispatch($http,$socket,$debug);};
	if($@) {
		::logGlobal("Error in '$Vend::Cfg->{CatalogName}': $@");
		::logError("Error in '$Vend::Cfg->{CatalogName}': $@");
		$forked = 0;
	}
    $forked;
}

sub inet_connection {
    my ($handle,$debug) = @_;

    my (@argv, %env, $entity);
    read_cgi_data(\@argv, \%env, \$entity);

    my $http = new Vend::Http::Server \*Vend::Server::MESSAGE, \%env, $entity;
    
    ::dispatch($http,$handle,$debug);
}

## Signals

my $Signal_Terminate;
my $Signal_Debug;
my $Signal_Locking;
my %orig_signal;
my @trapped_signals = qw(HUP INT TERM USR1 USR2);
$Vend::Server::Num_servers = 0;

# might also trap: QUIT USR1 USR2

my $DEBUG = 0;

my ($Routine_USR1, $Routine_USR2, $Routine_TERM, $Routine_INT);

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
		::logGlobal ("using stupid SYSV signal semantics...");
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

}

sub restore_signals {
    @SIG{@trapped_signals} = @orig_signal{@trapped_signals};
}


# Reconfigure any catalogs that have requested it, and 
# check to make sure we haven't too many running servers
sub housekeeping {

	return;
	my ($c, $num,$reconfig, @files);

		opendir(Vend::Server::CHECKRUN, $Global::ConfDir)
			or die "opendir $Global::ConfDir: $!\n";
		@files = readdir Vend::Server::CHECKRUN;
		closedir(Vend::Server::CHECKRUN)
			or die "closedir $Global::ConfDir: $!\n";
		($reconfig) = grep $_ eq 'reconfig', @files;
		if (defined $reconfig) {
			open(Vend::Server::RECONFIG, "+<$Global::ConfDir/reconfig")
				or die "open $Global::ConfDir/reconfig: $!\n";
			lockfile(\*Vend::Server::RECONFIG, 1, 1)
				or die "lock $Global::ConfDir/reconfig: $!\n";
			while(<Vend::Server::RECONFIG>) {
				chomp;
				my $script_name = $_;
				next unless defined $Global::Selector{$script_name};
				$c = ::config_named_catalog($script_name, "master server");
				if (defined $c) {
					$Global::Selector{$script_name} = $c;
				}
				else {
					logGlobal("Error reconfiguring catalog $script_name" .
				                    ' from master server.');
				}
			}
			unlockfile(\*Vend::Server::RECONFIG)
				or die "unlock $Global::ConfDir/reconfig: $!\n";
			unlink "$Global::ConfDir/reconfig"
				or die "close $Global::ConfDir/reconfig: $!\n";
			close(Vend::Server::RECONFIG)
				or die "close $Global::ConfDir/reconfig: $!\n";
		}
		@files = grep /^mvrunnin/, @files;
		my $pdata;
		for(@files) {
			open(CHECKIT, "$Global::ConfDir/$_") or die "open $_: $!\n";
			chop($pdata = <CHECKIT>);
			close(CHECKIT) or die "close $_: $!\n";
			my($pid, $time) = split /\s+/, $pdata;
			if((time - $time) > 180) {
				kill(9, $pid);
				unlink "$Global::ConfDir/$_";
			}
		}

}


sub server_inet {
    my ($debug) = @_;
    my ($n, $rin, $rout, $ok, $pid, $max_servers, $tick, $count);

	my $port = $Global::TcpPort || 7786;
	my $host = $Global::TcpHost || '127.0.0.1';
	my $proto = getprotobyname('tcp');

	# We are already forking, so no need to fork searches
	$Global::ForkSearches = 0;

	$Vend::MasterProcess = $$;

	$tick = $Global::HouseKeeping || 60;

	$max_servers = $Global::MaxServers || 4;

	setup_signals();

	#open DEBUG, ">>/tmp/debug.mv" or die;
	#my $save = select DEBUG; $| = 1; select $save;

	socket(Vend::Server::SOCKET, PF_INET, SOCK_STREAM, $proto)
			|| die "socket: $!";
	#print DEBUG "socket created\n";
	setsockopt(Vend::Server::SOCKET, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
			|| die "setsockopt: $!";
	bind(Vend::Server::SOCKET, sockaddr_in($port, INADDR_ANY))
			|| die "bind: $!";
	#print DEBUG "socket bound\n";
	listen(Vend::Server::SOCKET,5)
			|| die "listen: $!";
	#print DEBUG "socket listen\n";

	for (;;) {

        $rin = '';
        vec($rin, fileno(Vend::Server::SOCKET), 1) = 1;

        $n = select($rout = $rin, undef, undef, $tick);
		#print DEBUG "select $n\n";

        if ($n == -1) {
            if ($! =~ m/^Interrupted/) {
                if ($Signal_Terminate) {
                    last;
                }
				#print DEBUG "interrupted $n\n";
            }
            else {
                die "select: $!\n";
            }
        }
        elsif (vec($rout, fileno(Vend::Server::SOCKET), 1)) {

			#print DEBUG "selected SOCKET $rout\n";
			$ok = accept(Vend::Server::MESSAGE, Vend::Server::SOCKET);
			die "accept: $!" unless defined $ok;
		
			my($port,$iaddr) = sockaddr_in($ok);
			my $name = gethostbyaddr($iaddr,AF_INET);

			if($DEBUG) {
				::logGlobal("connection from $name [" . 
						   inet_ntoa($iaddr) . "] at port $port");
			}

			#print DEBUG "accepted $ok $name\n";

			unless ($host =~ /\b$name\b/io
						or do {
							my $ad = inet_ntoa($iaddr); $host=~ /\b$ad\b/o
							} )
			{
				::logGlobal("ALERT: attempted connection from $name ($port)\n");
				close(Vend::Server::MESSAGE) || die "close socket: $!\n";
				next;
			}

			my $handle = get_socketname("$Global::ConfDir/mvrunning");

			if(! defined ($pid = fork) ) { 
				::logGlobal ("Can't fork: $!\n");
			}
			elsif (! $pid) {
				#print DEBUG "fork 1\n";
				#fork again
				unless ($pid = fork) {
					#print DEBUG "fork 2\n";
					kill "USR1", $Vend::MasterProcess;
					open(Vend::Server::PIDFILE, ">$handle")
						or die "create pidfile $handle: $!\n";
					print Vend::Server::PIDFILE "$$ " . time . "\n";
					close(Vend::Server::PIDFILE)
						or die "close pidfile $handle: $!\n";

					select(undef,undef,undef,0.050) until getppid == 1;
					#print DEBUG "going to connection\n";
					eval { inet_connection(undef, $debug) };
					if ($@) {
						::logGlobal("Error in '$Vend::Cfg->{CatalogName}': $@");
						::logError("Error: $@")
					}
					unlink $handle;
					kill "USR2", $Vend::MasterProcess;
					#print DEBUG "back from connection\n";
					exit(0);
				}
				#print DEBUG "fork 2 master\n";
				exit(0);
			}
			close(Vend::Server::MESSAGE) || die "close socket: $!\n";
			#print DEBUG "fork 1 master\n";
			wait;
			#print DEBUG "waited successfully\n";

		}
		elsif($n == 0) {
			housekeeping();
		}
		else {
			die "Why did select return with $n?";
		}

		#print DEBUG "servers:";
		$count = 0;
		for(;;) {
			#print DEBUG " $Vend::Server::Num_servers";
			last if $Vend::Server::Num_servers < $max_servers;
			select(undef,undef,undef,0.300);
			last if $Signal_Terminate || $Signal_Debug;
			housekeeping() if (++$count % 10) == 0;
		}
		#print DEBUG "\n";

        last if $Signal_Terminate || $Signal_Debug;
		
	}

    close(Vend::Server::SOCKET);
	restore_signals();

   	if ($Signal_Terminate) {
       	::logGlobal("\nServer terminating on signal TERM\n\n");
       	return 'terminate';
   	}

    return '';
}


sub server_unix {
    my ($socket_filename, $debug) = @_;
    my ($n, $rin, $rout, $pid, $tick, $max_servers, $count);

    my $AF_UNIX = 1;
    my $SOCK_STREAM = 1;
    my $SOCK_DGRAM = 2;


	$Vend::MasterProcess = $$;

	$max_servers = $Global::MaxServers   || 4;
	$tick        = $Global::HouseKeeping || 60;

    setup_signals();
    for (;;) {

		unlink $socket_filename;
		socket(Vend::Server::SOCKET, AF_UNIX, SOCK_STREAM, 0) || die "socket: $!";
		bind(Vend::Server::SOCKET, pack("S", AF_UNIX) . $socket_filename . chr(0))
			or die "Could not bind (open as a socket) '$socket_filename':\n$!\n";
		#chmod $Global::FileCreationMask, $socket_filename;
		chmod 0600, $socket_filename;
		listen(Vend::Server::SOCKET, 5) or die "listen: $!";

        $rin = '';
        vec($rin, fileno(Vend::Server::SOCKET), 1) = 1;

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
                die "select: $!\n";
            }
        }

        elsif (vec($rout, fileno(Vend::Server::SOCKET), 1)) {
            my $ok = accept(Vend::Server::MESSAGE, Vend::Server::SOCKET);
            die "accept: $!" unless defined $ok;
			my $new_socket = get_socketname $socket_filename;
			rename $socket_filename, $new_socket;

       		my $handle = get_socketname("$Global::ConfDir/mvrunning");

            if(! defined ($pid = fork) ) {
                ::logGlobal ("Can't fork: $!\n");
            }
            elsif (! $pid) {
                #fork again
                unless ($pid = fork) {

					kill "USR1", $Vend::MasterProcess;
                    open(Vend::Server::PIDFILE, ">$handle")
                        or die "create pidfile $handle: $!\n";
                    print Vend::Server::PIDFILE "$$ " . time . "\n";
                    close(Vend::Server::PIDFILE)
                        or die "close pidfile $handle: $!\n";

                    select(undef,undef,undef,0.050) until getppid == 1;
                    eval { inet_connection(undef, $debug) };
                    if ($@) {
                        ::logGlobal("Error in '$Vend::Cfg->{CatalogName}': $@");
                        ::logError("Error: $@")
                    }
                    unlink $handle, $new_socket;
					kill "USR2", $Vend::MasterProcess;
                    exit(0);
                }
                exit(0);
            }

            close Vend::Server::SOCKET;
            close Vend::Server::MESSAGE;
			wait;

        }
		elsif($n == 0) {
			housekeeping();
		}
        else {
            die "Why did select return with $n?";
        }

        $count = 0;
        for(;;) {
           last if $Vend::Server::Num_servers < $max_servers;
           select(undef,undef,undef,0.300);
           last if $Signal_Terminate || $Signal_Debug;
           housekeeping() if (++$count % 10) == 0;
        }

        last if $Signal_Terminate || $Signal_Debug;

    }

    close(Vend::Server::SOCKET);
    restore_signals();

   	if ($Signal_Terminate) {
       	::logGlobal("\nServer terminating on signal TERM\n\n");
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
			$pidfile = $Global::ConfDir . "/minivend.pid" . $it++;
		} until ! -e $pidfile;
	}
	else {
		$pidfile = $Global::ConfDir . "/minivend.pid";
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
				my $type = defined $Global::Inet_Mode ? "INET" : "UNIX";
                ::logGlobal("\nServer running on pid $$ ($type)\n\n");
                setsid();

                fcntl(Vend::Server::Pid, F_SETFD, 1)
                    or die "Can't fcntl close-on-exec flag for '$pidfile': $!\n";

				unless (defined $Global::Inet_Mode) {
					$next = server_unix($LINK_FILE, $debug);
				}
				else {
					$next = server_inet($debug);
				}
				unlockfile(\*Vend::Server::Pid);
	opendir(CONFDIR, $Global::ConfDir) 
		or die "Couldn't open directory $Global::ConfDir: $!\n";
	my @running = grep /^mvrunning/, readdir CONFDIR;
	for(@running) {
		unlink "$Global::ConfDir/$_" or die
			"Couldn't unlink status file $Global::ConfDir/$_: $!\n";
	}
				unlink $pidfile;
                exit 0;
            }
        }
    }                
}

1;
