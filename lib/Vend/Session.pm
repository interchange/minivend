# Session.pm - Minivend Sessions
#
# $Id: Session.pm,v 1.34 1999/02/15 08:51:29 mike Exp mike $
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
#

package Vend::Session;
require Exporter;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.34 $, 10);

@ISA = qw(Exporter);

@EXPORT = qw(

check_save
dump_sessions
expire_sessions
get_session
init_session
new_session
put_session
release_session
session_name

);

use strict;
use Fcntl;
use Vend::Util;

require Vend::SessionDB;

BEGIN {
	if($Global::GDBM) {
		require GDBM_File;
		import GDBM_File;
	}
	elsif($Global::DB_File) {
		require DB_File;
		import DB_File;
	}
	else {
		require Vend::SessionFile;
	}
}

my ($Session_open, $File_sessions, $DB_sessions, $DB_object);


# Selects based on initial config
if($Global::GDBM) {
	$File_sessions = 0;
	$Session_open = sub {
		$DB_object = tie(%Vend::SessionDBM,
			'GDBM_File',
			$Vend::Cfg->{'SessionDatabase'} . ".gdbm",
			&GDBM_WRCREAT,
			$Vend::Cfg->{'FileCreationMask'}
			);
		die "Could not tie to $Vend::Cfg->{'SessionDatabase'}: $!\n"
			unless defined $DB_object;
	};
}
elsif($Global::DB_File) {
	$File_sessions = 0;
	$Session_open = sub {
		tie(%Vend::SessionDBM, 'DB_File',
			$Vend::Cfg->{'SessionDatabase'} . ".db",
			&O_RDWR|&O_CREAT, $Vend::Cfg->{'FileCreationMask'})
		or die "Could not tie to $Vend::Cfg->{'SessionDatabase'}: $!\n";
	};
}
else {
	$File_sessions = 1;
	$Session_open = sub {
		tie(%Vend::SessionDBM, 'Vend::SessionFile', $Vend::Cfg->{'SessionDatabase'})
			or die "Could not tie to $Vend::Cfg->{'SessionDatabase'}: $!\n";
	};
}


# SESSIONS implemented using DBM

sub get_session {
	$Vend::HaveSession = 0;
	open_session();
	read_session();
	unless($File_sessions) {
		lock_session();
		close_session();
	}
	$Vend::HaveSession = 1;
}

sub release_session {
	unless($File_sessions) {
		open_session();
		read_session();
		unlock_session();
		close_session();
	}
	$Vend::HaveSession = 0;
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
	if($Vend::Cfg->{SessionDB}) {
		$Session_open = sub {
			return 1 if $DB_sessions;
			tie(%Vend::SessionDBM,
				'Vend::SessionDB',
				$Vend::Cfg->{SessionDB})
			or die "Could not tie to $Vend::Cfg->{SessionDB}: $!\n";
			$DB_sessions = 1;
		};
	}
	unless($File_sessions) {
		open(Vend::SessionLock, "+>>$Vend::Cfg->{'SessionLockFile'}")
			or die "Could not open '$Vend::Cfg->{'SessionLockFile'}': $!\n";
		lockfile(\*Vend::SessionLock, 1, 1)
			or die "Could not lock '$Vend::Cfg->{'SessionLockFile'}': $!\n";
	}
	
	&$Session_open;
	$Vend::SessionOpen = 1;

}


sub new_session {
    my($seed) = @_;
    my($name);

# DEBUG
#Vend::Util::logDebug
#("new session id=$Vend::SessionID  name=$Vend::SessionName\n")
#	if ::debug(0x20);
# END DEBUG
	open_session();
    for (;;) {
		$Vend::SessionID = random_string() unless defined $seed;
		undef $seed;
		$name = session_name();
		unless ($File_sessions) { 
			last unless defined $Vend::SessionDBM{$name};
		}
		else {
			last unless exists $Vend::SessionDBM{$name};
		}
    }
	$CGI::cookie = $Vend::Cookie = '';
    $Vend::SessionName = $name;
    init_session();
	return if $File_sessions;
	write_session();
	close_session();
}

sub check_override {
	return 1 unless defined $CGI::values{mv_override_domain};
	return 1 if $CGI::values{mv_override_check} eq $Vend::Session->{override_check};
	logError "Override check '" .
		$Vend::Session->{override_check} . "' not good from $CGI::original_host.\n";
	logGlobal "Override check '" .
		$Vend::Session->{override_check} . "' not good from $CGI::original_host.\n";
	die "Security violation. Check error log $Global::ErrorFile\n";
}

sub close_session {
# DEBUG
#Vend::Util::logDebug
#("close session id=$Vend::SessionID  name=$Vend::SessionName\n")
#	if ::debug(0x20);
# END DEBUG
	return 1 if ! defined $Vend::SessionOpen;

	unless($DB_sessions) {
		undef $DB_object;
		untie %Vend::SessionDBM
			or die "Could not close $Vend::Cfg->{'SessionDatabase'}: $!\n";
	}
	
	return 1 if $File_sessions;

	unlockfile(\*Vend::SessionLock)
		or die "Could not unlock '$Vend::Cfg->{'SessionLockFile'}': $!\n";
    close(Vend::SessionLock)
		or die "Could not close '$Vend::Cfg->{'SessionLockFile'}': $!\n";
	undef $Vend::SessionOpen;
}

sub write_session {
    my($s);
# DEBUG
#Vend::Util::logDebug
#("write session id=$Vend::SessionID  name=$Vend::SessionName\n")
#	if ::debug(0x20);
# END DEBUG
	my $time = time;
    $Vend::Session->{'time'} = $time;
    my $save = $Vend::Session->{'user'};
    undef $Vend::Session->{'user'};
    #undef $Vend::Session->{'arg'};
	undef $Vend::Session->{'items'};
	undef $Vend::Session->{'values'}->{mv_change_frame};
    $s = uneval_fast($Vend::Session);
    $Vend::SessionDBM{$Vend::SessionName} = $s or 
		die "Data was not stored in DBM file\n";
    $Vend::Session->{'user'} = $save;
}

sub unlock_session {
# DEBUG
#Vend::Util::logDebug
#("unlock session id=$Vend::SessionID  name=$Vend::SessionName\n")
#	if ::debug(0x20);
# END DEBUG
	delete $Vend::SessionDBM{'LOCK_' . $Vend::SessionName}
		unless $File_sessions;
}

sub lock_session {
	return 1 if $File_sessions;
# DEBUG
#Vend::Util::logDebug
#("lock session id=$Vend::SessionID  name=$Vend::SessionName\n")
#	if ::debug(0x20);
# END DEBUG
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
#				logError("Hammered session lock $lockname left by PID $pid");
				logError( errmsg('Session.pm:1', "Hammered session lock %s left by PID %s" , $lockname, $pid) );
				return 1;
			}
			elsif ($left < 0) {
				my $m = <<EOF;
lock_session: Time earlier than lock time for $lockname
left by PID $pid.
EOF
				logError($m);
				die "Locking error!";
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

# DEBUG
#Vend::Util::logDebug
#("read session id=$Vend::SessionID  name=$Vend::SessionName\n")
#	if ::debug(0x20);
# END DEBUG
	$s = $Vend::SessionDBM{$Vend::SessionName};
# DEBUG
#Vend::Util::logDebug
#("Session:\n$s\n")
#	if ::debug(0x20);
# END DEBUG
	return new_session($Vend::SessionID) unless $s;
    $Vend::Session = evalr($s);
    die "Could not eval '$s' from session dbm: $@\n" if $@;

	$Vend::Session->{host} = $CGI::host;

	# The below can die if there is an override and the hosts/checks
	# don't match
	check_override();

	$Vend::Session->{'arg'} = $Vend::Argument;
	$Vend::Session->{override_check} = $Vend::Session->{'time'};

    $::Values	= $Vend::Session->{'values'};
    $::Scratch	= $Vend::Session->{'scratch'};
    $Vend::Items	= $Vend::Session->{'items'}
					= $Vend::Session->{'carts'}->{'main'};
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
# DEBUG
#Vend::Util::logDebug
#("name session user=$CGI::user host=$host ($CGI::host)\n")
#	if ::debug(0x20);
# END DEBUG
    $fn = $Vend::SessionID . $joiner . $host;
# DEBUG
#Vend::Util::logDebug
#("name session id=$Vend::SessionID  name=$fn\n")
#	if ::debug(0x20);
# END DEBUG
    $fn;
}


sub init_session {
# DEBUG
#Vend::Util::logDebug
#("init session id=$Vend::SessionID  name=$Vend::SessionName\n")
#	if ::debug(0x20);
# END DEBUG
    $Vend::Session = {
	'version' => 1,
	'frames' => $Vend::Cfg->{FramesDefault},
	'arg' => $Vend::Argument,
	'browser' => $CGI::useragent,
	'referer' => $CGI::referer,
	'scratch' => { 'mv_no_cache' => 1 },
	'values' => {},
	'carts' => {main => []},
    };
    $Vend::Items	= $Vend::Session->{'items'}
					= $Vend::Session->{'carts'}->{'main'};
	$::Values = $Vend::Session->{'values'};
	$::Scratch = $Vend::Session->{'scratch'};
	$Vend::Session->{'secure'} = $Vend::Cfg->{'AlwaysSecure'} ? 1 : 0;
	$::Values->{'mv_shipmode'} = $Vend::Cfg->{'DefaultShipping'};
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
			 $time - $session->{'time'} > $Vend::Cfg->{'SessionExpire'}) {
			push @delete, $session_name;
		}
    }
    foreach $session_name (@delete) {
		delete $Vend::SessionDBM{$session_name};
		delete $Vend::SessionDBM{"LOCK_$session_name"}
				if ! $File_sessions && $Vend::SessionDBM{"LOCK_$session_name"};
		my $file = $session_name;
		$file =~ s/:.*//;
		opendir(Vend::DELDIR, $Vend::Cfg->{'ScratchDir'}) ||
			die "Could not open configuration directory $Vend::Cfg->{'ScratchDir'}: $!\n";
		my @files = grep /^$file/, readdir(Vend::DELDIR);
		for(@files) {
			unlink "$Vend::Cfg->{'ScratchDir'}/$_";
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
