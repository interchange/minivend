# Server.pm:  listen for cgi requests as a background server
#
# $Id: Server.pm,v 1.14 1996/01/30 23:23:59 amw Exp $

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
    print $fh "Content-type: $content_type\r\n\r\n";
    print $fh $body;
    $s->{'response_made'} = 1;
}
    

package Vend::Server;
require Exporter;
@Vend::Server::ISA = qw(Exporter);
@Vend::Server::EXPORT = qw(server);

use Socket;
use strict;
use Vend::Directive qw(Display_errors Perl_program App Data_directory
                       App_program);
use Vend::Log;

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
    my $abort = Vend::Dispatch::dispatch($http, $debug);
    $abort;
}


## Signals

my $Signal_Reload;
my $Signal_Terminate;
my $Signal_Debug;
my $Signal_Locking;
my %orig_signal;
my @trapped_signals = qw(HUP INT TERM);

# might also trap: QUIT USR1 USR2

sub setup_signals {
    @orig_signal{@trapped_signals} =
        map(defined $_ ? $_ : 'DEFAULT', @SIG{@trapped_signals});
    $Signal_Reload = $Signal_Terminate = $Signal_Locking = $Signal_Debug = '';
    $SIG{'HUP'}  = sub { $Signal_Reload = 1; };
    $SIG{'INT'}  = sub { $Signal_Terminate = 1; };
    $SIG{'TERM'} = sub { $Signal_Terminate = 1; };
    # $SIG{'QUIT'} = sub { $Signal_Debug = 1; };
    # $SIG{'USR1'} = sub { $Signal_Locking = 'long term'; };
    # $SIG{'USR2'} = sub { $Signal_Locking = 'short term'; };
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

    socket(Vend::Server::SOCKET, AF_UNIX, SOCK_STREAM, 0) || die "socket: $!";
    unlink $socket_filename;
    bind(Vend::Server::SOCKET, pack("S", AF_UNIX) . $socket_filename . chr(0))
	or die "Could not bind (open as a socket) '$socket_filename':\n$!\n";
    chmod 0600, $socket_filename;
    listen(Vend::Server::SOCKET, 5) or die "listen: $!";

    setup_signals();
    $abort = 0;
    for (;;) {
        last if $abort || $Signal_Reload || $Signal_Terminate || $Signal_Debug;

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
                if ($Signal_Reload || $Signal_Terminate) {
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
            # print "connection\n";
            $abort = connection($debug);
            close Vend::Server::MESSAGE;
            # print "  closed\n";
        }

        else {
            die "Why did select return?";
        }
    }

    close(Vend::Server::SOCKET);
    restore_signals();

    if ($Signal_Terminate) {
        log_error(localtime()."\nServer terminating on signal TERM\n\n");
        return 'terminate';
    }
    return 'reload' if $Signal_Reload || $abort;
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


1;
