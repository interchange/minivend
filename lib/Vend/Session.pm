# Session.pm - Interchange Sessions
#
# $Id$
# 
# Copyright (C) 1996-2000 Akopia, Inc. <info@akopia.com>
#
# This program was originally based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
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
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA.
#

package Vend::Session;
require Exporter;

use vars qw($VERSION);
$VERSION = substr(q$Revision$, 10);

@ISA = qw(Exporter);

@EXPORT = qw(

check_save
dump_sessions
expire_sessions
get_session
init_session
new_session
put_session
session_name

);

use strict;
use Fcntl;
use Vend::Util;

require Vend::SessionFile;

BEGIN {
	if($Global::GDBM) {
		require GDBM_File;
		import GDBM_File;
	}
	if($Global::DB_File) {
		require DB_File;
		import DB_File;
	}
	if($Global::DBI) {
		require Vend::SessionDB;
	}
}

my (%Session_class);
my ($Session_open, $File_sessions, $Lock_sessions, $DB_sessions, $DB_object);


# Selects based on initial config

%Session_class = (
# $File_sessions, $Lock_sessions, &$Session_open
GDBM => [ 0, 1, sub {
			$DB_object =
				tie(%Vend::SessionDBM,
					'GDBM_File',
					$Vend::Cfg->{SessionDatabase} . ".gdbm",
					&GDBM_WRCREAT,
					$Vend::Cfg->{FileCreationMask}
			);
			die "Could not tie to $Vend::Cfg->{SessionDatabase}: $!\n"
				unless defined $DB_object;
		},
	],
DB_File => [ 0, 1, sub {
					tie(
						%Vend::SessionDBM,
						'DB_File',
						$Vend::Cfg->{SessionDatabase} . ".db",
						&O_RDWR|&O_CREAT,
						$Vend::Cfg->{FileCreationMask}
					)
					or die "Could not tie to $Vend::Cfg->{SessionDatabase}: $!\n";
				},
],

DBI => [ 0, 0, sub {
				return 1 if $DB_sessions;
				tie (
					%Vend::SessionDBM,
					'Vend::SessionDB',
					$Vend::Cfg->{SessionDB}
				)
				or die "Could not tie to $Vend::Cfg->{SessionDB}: $!\n";
				$DB_sessions = 1;
			},
		],

File => [ 1, 0, sub {
				tie(
					%Vend::SessionDBM,
					'Vend::SessionFile',
					$Vend::Cfg->{SessionDatabase}
				)
				or die "Could not tie to $Vend::Cfg->{SessionDatabase}: $!\n";
			},
		],

);

# SESSIONS implemented using DBM

sub get_session {
	$Vend::HaveSession = 0;
	open_session();
	my $new;
	$new = read_session() unless $Vend::ExternalProgram;
	unless($File_sessions) {
		lock_session();
		close_session();
	}
	$Vend::HaveSession = 1;
	return ($new || 0);
}

sub put_session {
	unless($File_sessions) {
		open_session();
		write_session();
		unlock_session();
		close_session();
	}
	else {
		write_session();
	}
	$Vend::HaveSession = 0;
}

sub open_session {
	return 1 if defined $Vend::SessionOpen;
	($File_sessions, $Lock_sessions, $Session_open) 
		= @{$Session_class{ $Vend::Cfg->{SessionType} || 'File' }};
	if (! defined $File_sessions) {
		($File_sessions, $Lock_sessions, $Session_open) = @{$Session_class{File}};
	}
#::logDebug("open_session: File_sessions=$File_sessions Sub=$Session_open");
	unless($File_sessions) {
		open(Vend::SessionLock, "+>>$Vend::Cfg->{SessionLockFile}")
			or die "Could not open lock file '$Vend::Cfg->{SessionLockFile}': $!\n";
		lockfile(\*Vend::SessionLock, 1, 1)
			or die "Could not lock '$Vend::Cfg->{SessionLockFile}': $!\n";
	}
	
	&$Session_open;
	$Vend::SessionOpen = 1;

}

sub count_ip {
	my $inc = shift;
	my $ip = $CGI::remote_addr;
	$ip =~ s/\W/_/g;
	my $dir = "$Vend::Cfg->{ScratchDir}/addr_ctr";
	mkdir $dir, 0777 unless -d $dir;
	my $fn = Vend::Util::get_filename($ip, 2, 1, $dir);
	if(-f $fn) {
		my $grace = time() - ($Global::Variable->{MV_ROBOT_EXPIRE} || 86400);
		unlink $fn if -M $fn < $grace;
	}
	return File::CounterFile->new($fn)->inc() if $inc;
	return File::CounterFile->new($fn)->value();
}


sub new_session {
    my($seed) = @_;
    my($name);

#::logDebug ("new session id=$Vend::SessionID  name=$Vend::SessionName\n");
	open_session();
    for (;;) {
		$Vend::SessionID = random_string() unless defined $seed;
		undef $seed;
		if (::is_retired($Vend::SessionID)) {
			::retire_id($Vend::SessionID);
			next;
		}
		$name = session_name();
		unless ($File_sessions) { 
			last unless defined $Vend::SessionDBM{$name};
		}
		else {
			last unless exists $Vend::SessionDBM{$name};
		}
    }
	count_ip(1);
	$CGI::cookie = $Vend::Cookie = '';
    $Vend::SessionName = $name;
    init_session();
#::logDebug("init_session $Vend::SessionName is: " . ::uneval($Vend::Session));
#::logDebug("init_session $Vend::SessionName");
	$Vend::HaveSession = 1;
	return if $File_sessions || $DB_sessions;
	write_session();
	close_session();
	return;
}

sub close_session {
#::logDebug ("close session id=$Vend::SessionID  name=$Vend::SessionName\n");
	return 1 if ! defined $Vend::SessionOpen;

	unless($DB_sessions) {
		undef $DB_object;
		untie %Vend::SessionDBM
			or die "Could not close $Vend::Cfg->{SessionDatabase}: $!\n";
	}
	
	return 1 unless $Lock_sessions;

	unlockfile(\*Vend::SessionLock)
		or die "Could not unlock '$Vend::Cfg->{SessionLockFile}': $!\n";
    close(Vend::SessionLock)
		or die "Could not close '$Vend::Cfg->{SessionLockFile}': $!\n";
	undef $Vend::SessionOpen;
}

sub write_session {
    my($s);
#::logDebug ("write session id=$Vend::SessionID  name=$Vend::SessionName\n");
	my $time = time;
    $Vend::Session->{'time'} = $time;
    my $save = $Vend::Session->{'user'};
    undef $Vend::Session->{'user'};
    #undef $Vend::Session->{'arg'};
	$Vend::Session->{username} = $Vend::username;
	$Vend::Session->{admin} = $Vend::admin;
    $s = ! $File_sessions ? uneval_fast($Vend::Session) : $Vend::Session;
    $Vend::SessionDBM{$Vend::SessionName} = $s or 
		die "Data was not stored in SessionDBM\n";
    $Vend::Session->{'user'} = $save;
}

sub unlock_session {
#::logDebug ("unlock session id=$Vend::SessionID  name=$Vend::SessionName\n");
	delete $Vend::SessionDBM{'LOCK_' . $Vend::SessionName}
		unless $File_sessions;
}

sub lock_session {
	return 1 if $File_sessions;
#::logDebug ("lock session id=$Vend::SessionID  name=$Vend::SessionName\n");
	my $lockname = 'LOCK_' . $Vend::SessionName;
	my ($tried, $locktime, $sleepleft, $pid, $now, $left);
	$tried = 0;

	LOCKLOOP: {
		if (defined $Vend::SessionDBM{$lockname}) {
			($locktime, $pid) = split /:/, $Vend::SessionDBM{$lockname}, 2;
		}
		$now = time;
		if(defined $locktime and $locktime) {
			$left = $now - $locktime;
			if ( $left > $Global::HammerLock ) {
				$Vend::SessionDBM{$lockname} = "$now:$$";
				logError("Hammered session lock %s left by PID %s" , $lockname, $pid );
				return 1;
			}
			elsif ($left < 0) {
				my $m = <<EOF;
lock_session: Time earlier than lock time for $lockname
left by PID %s.
EOF
				logError($m, $pid);
				die errmsg("Locking error!\n", '');
			}
			else {
				unless ($tried) {
					$sleepleft = 1;
					$tried = 1;
				}
				else {
					$sleepleft = int($left / 2);
					if ($sleepleft < 3) {
						$sleepleft = $left;
					}
				}
				close_session();
				sleep $sleepleft;
				open_session();
				read_session();
				next LOCKLOOP;
			}
		}
		else {
			$Vend::SessionDBM{$lockname} = "$now:$$";
			return 1;
		}
	} #LOCKLOOP

	# Should never get here
	return undef;
}

sub read_session {
    my($s);

#::logDebug ("read session id=$Vend::SessionID  name=$Vend::SessionName\n");
	$s = $Vend::SessionDBM{$Vend::SessionName}
		or $Global::Variable->{MV_SESSION_READ_RETRY}
		and do {
			my $i = 0;
			my $tries = $Global::Variable->{MV_SESSION_READ_RETRY} + 0 || 5;
			while($i++ < $tries) {
				::logDebug("retrying session read on undef, try $i");
				$s = $Vend::SessionDBM{$Vend::SessionName};
				next unless $s;
				::logDebug("Session re-read successfully on try $i");
				last;
			}
		};
		
#::logDebug ("Session:\n$s\n");
	return new_session() unless $s;
    $Vend::Session = ref $s ? $s : evalr($s);
    die "Could not eval '$s' from session dbm: $@\n" if $@;

	$Vend::Session->{host} = $CGI::host;

	$Vend::username = $Vend::Session->{username};
	$Vend::admin    = $Vend::Session->{admin};

	$Vend::Session->{arg}  = $Vend::Argument;

    $::Values	= $Vend::Session->{'values'};
    $::Scratch	= $Vend::Session->{scratch};
    $::Carts	= $Vend::Session->{carts};
	tie $Vend::Items, 'Vend::Cart';
}


## SESSIONS

my $joiner = $Global::Windows ? '_' : ':';

sub session_name {
    my($host, $user, $fn, $proxy);

	if(defined $CGI::user and $CGI::user) {
		$host = escape_chars($CGI::user);
	}
	elsif(defined $CGI::cookieuser) {
		$host = $CGI::cookieuser;
	}
	elsif(defined $CGI::cookiehost) {
		$host = $CGI::cookiehost;
	}
	else {
		$host = $CGI::host;
		$proxy = index($host,"proxy");
		$host = substr($host,$proxy)
			if ($proxy >= 0);
		$host = escape_chars($host);
	}
#::logDebug ("name session user=$CGI::user host=$host ($CGI::host)\n");
    $fn = $Vend::SessionID . $joiner . $host;
#::logDebug ("name session id=$Vend::SessionID  name=$fn\n");
    $fn;
}


sub init_session {
    $Vend::Session = {
		'ohost'		=> $CGI::remote_addr,
		'arg'		=> $Vend::Argument,
		'browser'	=> $CGI::useragent,
		'referer'	=> $CGI::referer,
		'scratch'	=> { %{$Vend::Cfg->{ScratchDefault}} },
		'values'	=> { %{$Vend::Cfg->{ValuesDefault}} },
		'carts'		=> {main => []},
    };
	$Vend::Session->{shost} = $CGI::remote_addr
		if $CGI::secure;
	$::Values     = $Vend::Session->{'values'};
	$::Scratch	  = $Vend::Session->{scratch};
	$::Scratch->{mv_locale} = $Vend::Cfg->{DefaultLocale}
		if ! $::Scratch->{mv_locale} and $Vend::Cfg->{DefaultLocale};
	$::Carts	  = $Vend::Session->{carts};
	tie $Vend::Items, 'Vend::Cart';
	$::Values->{mv_shipmode} = $Vend::Cfg->{DefaultShipping}
		if ! defined $::Values->{mv_shipmode};
}

sub dump_sessions {
	my($called) = @_;
    my($session_name, $s);
	die "Can't dump file-based sessions.\n" if $File_sessions;
	my $pretty;

	eval {	require Data::Dumper;
			$Data::Dumper::Indent = 3;
			$Data::Dumper::Terse = 1; };
	$pretty = $@ ? 0 : 1;
    open_session();
    while(($session_name, $s) = each %Vend::SessionDBM) {
		next if $session_name eq 'dumpprog:DUMP';
		next if $session_name =~ /^LOCK_/;
		if(defined $called) {
			next unless $session_name =~ /$called/;
		}
		if ($pretty or defined $Storable::VERSION) {
			my $ref = evalr $s;
			$s = uneval($ref);
		}
		print "$session_name $s\n\n";
    }
    close_session();
}

sub reorg {
	return unless $DB_object;
	GDBM_File::reorganize($DB_object);
	GDBM_File::sync($DB_object);
}

sub expire_sessions {
	my ($reorg) = @_;
    my($time, $session_name, $s, $session, @delete);

    $time = time;
    open_session();
    while(($session_name, $s) = each %Vend::SessionDBM) {

		# Lock records
		if ($session_name =~ /^LOCK_/) {;
			delete $Vend::SessionDBM{$session_name}
				unless ($File_sessions or $s);
			next;
		}

		# Session markers
		if ($session_name =~ /^\w{8}$/) {
			$session = evalr ($s);
			die "Could not eval '$s' from session dbm: $@\n" if $@;
			next if keys %$session;   # Don't remove if has session marker
			push @delete, $session_name;
		}

		$session = evalr($s);
		die "Could not eval '$s' from session dbm: $@\n" if $@;
		next if check_save($time);
		if ( (! defined $session) ||
			 $time - $session->{'time'} > $Vend::Cfg->{SessionExpire}) {
			push @delete, $session_name;
		}
    }
    foreach $session_name (@delete) {
		delete $Vend::SessionDBM{$session_name};
		delete $Vend::SessionDBM{"LOCK_$session_name"}
				if ! $File_sessions && $Vend::SessionDBM{"LOCK_$session_name"};
		my $file = $session_name;
		$file =~ s/:.*//;
		opendir(Vend::DELDIR, $Vend::Cfg->{ScratchDir}) ||
			die "Could not open configuration directory $Vend::Cfg->{ScratchDir}: $!\n";
		my @files = grep /^$file/, readdir(Vend::DELDIR);
		for(@files) {
			unlink "$Vend::Cfg->{ScratchDir}/$_";
		}
		closedir(Vend::DELDIR);
    }
	reorg() if $reorg;
    close_session();
}

sub check_save {
	my($time) = (@_);
	my $expire;

	$time = $time || time();

	if(defined $Vend::Session->{'values'}->{mv_expire_time}) {
		$expire = $Vend::Session->{'values'}->{mv_expire_time};
		unless($expire =~ /^\d{6,}$/) {
			$expire = Vend::Config::time_to_seconds($expire);
		}
	}
	$expire = $Vend::Cfg->{SaveExpire} unless $expire;

	$Vend::Session->{'expire'} = $Vend::Expire = $time + $expire;

	return ($expire > $time);
}	

1;

__END__
