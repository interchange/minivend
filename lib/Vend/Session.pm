# $Id: Session.pm,v 1.13 1997/08/26 20:45:39 mike Exp mike $

package Vend::Session;
require Exporter;

# AUTOLOAD
#use AutoLoader;
#@ISA = qw(Exporter AutoLoader);
#*AUTOLOAD = \&AutoLoader::AUTOLOAD;
# END AUTOLOAD

# NOAUTO
@ISA = qw(Exporter);
# END NOAUTO

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
use Carp;
use Fcntl;
use Vend::Util;


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

# AUTOLOAD
#use vars qw($Session_open $File_sessions);
# END AUTOLOAD

# NOAUTO
my ($Session_open, $File_sessions);
# END NOAUTO


# Selects based on initial config
if($Global::GDBM) {
	$File_sessions = 0;
	$Session_open = sub {
		 tie(%Vend::SessionDBM, 'GDBM_File',
			$Vend::Cfg->{'SessionDatabase'} . ".gdbm",
			&GDBM_WRCREAT, $Vend::Cfg->{'FileCreationMask'})
		or die "Could not tie to $Vend::Cfg->{'SessionDatabase'}: $!\n";
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


## SESSIONS implemented using DBM

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

#print("new session id=$Vend::SessionID  name=$Vend::SessionName\n") if $Global::DEBUG;
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
	$CGI::cookie = '';
    $Vend::SessionName = $name;
	#add_session_marker();
    init_session();
	return if $File_sessions;
	write_session();
	close_session();
}

sub save_session {
	my($source,$dest,$name) = @_;
	my($s,$d,$found);
#print("save session id=$Vend::SessionID  name=$Vend::SessionName\n") if $Global::DEBUG;
	$dest = $dest || $Vend::SessionID;
	$name = $name || time;
	open_session();
	unless ($File_sessions) { 
		$found = defined $Vend::SessionDBM{$source};
	}
	else {
		$found = exists $Vend::SessionDBM{$source};
	}

	unless($found) {
		close_session();
		return '';
	}

	$s = eval $Vend::SessionDBM{$source};
    die "Could not eval '$s' from session dbm: $@\n" if $@;
	
	unless ($File_sessions) { 
		$found = defined $Vend::SessionDBM{$dest};
	}
	else {
		$found = exists $Vend::SessionDBM{$dest};
	}

	if ($found) {
		$d = eval $Vend::SessionDBM{$dest};
		die "Could not eval '$d' from session dbm: $@\n" if $@;
	}
	else {
		$d = {};
	}

	$d->{$name} = $s;

	$Vend::SessionDBM{$dest} = uneval($d);

	close_session();
}



sub close_session {
#print("close session id=$Vend::SessionID  name=$Vend::SessionName\n") if $Global::DEBUG;
	return 1 if ! defined $Vend::SessionOpen;
    untie %Vend::SessionDBM
		or die "Could not close $Vend::Cfg->{'SessionDatabase'}: $!\n";
	
	return 1 if $File_sessions;

	unlockfile(\*Vend::SessionLock)
		or die "Could not unlock '$Vend::Cfg->{'SessionLockFile'}': $!\n";
    close(Vend::SessionLock)
		or die "Could not close '$Vend::Cfg->{'SessionLockFile'}': $!\n";
	undef $Vend::SessionOpen;
}

sub write_session {
    my($s);
#print("write session id=$Vend::SessionID  name=$Vend::SessionName\n") if $Global::DEBUG;
	my $time = time;
    $Vend::Session->{'time'} = $time;
    undef $Vend::Session->{'user'};
    undef $Vend::Session->{'arg'};
	undef $Vend::Session->{'items'};
	undef $Vend::Session->{'values'}->{mv_change_frame};
    $s = uneval($Vend::Session);
    $Vend::SessionDBM{$Vend::SessionName} = $s or 
		die "Data was not stored in DBM file\n";
		#if $Vend::SessionDBM{$Vend::SessionName} ne $s;
}

sub unlock_session {
#print("unlock session id=$Vend::SessionID  name=$Vend::SessionName\n") if $Global::DEBUG;
	delete $Vend::SessionDBM{'LOCK_' . $Vend::SessionName}
		unless $File_sessions;
}

sub lock_session {
	return 1 if $File_sessions;
#print("lock session id=$Vend::SessionID  name=$Vend::SessionName\n") if $Global::DEBUG;
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
				logError("Hammered session lock $lockname left by PID $pid");
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

#print("read session id=$Vend::SessionID  name=$Vend::SessionName\n") if $Global::DEBUG;
	$s = $Vend::SessionDBM{$Vend::SessionName};
#print("Session:\n$s\n") if $Global::DEBUG;
	return new_session($Vend::SessionID) unless $s;
    $Vend::Session = eval($s);
    die "Could not eval '$s' from session dbm: $@\n" if $@;
    $Vend::Items	= $Vend::Session->{'items'}
					= $Vend::Session->{'carts'}->{'main'};
}


## SESSIONS

sub session_name {
    my($host, $user, $fn, $proxy);

	if(defined $CGI::user and $CGI::user) {
		$host = escape_chars($CGI::user);
	}
	else {
		$host = $CGI::host;
		$proxy = index($host,"proxy");
		$host = substr($host,$proxy)
			if ($proxy >= 0);
		$host = escape_chars($host);
	}
#print("name session user=$CGI::user host=$host ($CGI::host)\n") if $Global::DEBUG;
    $fn = $Vend::SessionID . ':' . $host;
#print("name session id=$Vend::SessionID  name=$fn\n") if $Global::DEBUG;
    $fn;
}


sub init_session {
#print("init session id=$Vend::SessionID  name=$Vend::SessionName\n") if $Global::DEBUG;
    $Vend::Session = {
	'version' => 1,
	'frames' => 0,
	'login' => '',
	'browser' => $CGI::useragent,
	'referer' => $CGI::referer,
	'scratch' => {},
	'values' => {},
	'carts' => {main => []},
    };
    $Vend::Items	= $Vend::Session->{'items'}
					= $Vend::Session->{'carts'}->{'main'};
	$Vend::Session->{'secure'} = $Vend::Cfg->{'AlwaysSecure'} ? 1 : 0;
	$Vend::Session->{'values'}->{'mv_shipmode'} = $Vend::Cfg->{'DefaultShipping'};
}

# AUTOLOAD
#1;
#__END__
# END AUTOLOAD

sub remove_session_marker {
	my ($id) = @_;
	my ($name);
	if(defined $id) {
		$id =~ /^(\w{8}):(.*)/;
		$id = $1; $name = $2;
	}
	else {
		$id = $Vend::SessionID;
		$name = $Vend::SessionName;
	}

	return undef unless $name and $id;

	my $s = eval $Vend::SessionDBM{$id};
    die "Could not eval '$s' from session dbm: $@\n" if $@;
	delete $s->{$name};
	$Vend::SessionDBM{$id} = uneval $s;
}

sub add_session_marker {
	my $s = eval $Vend::SessionDBM{$Vend::SessionID};
    die "Could not eval '$s' from session dbm: $@\n" if $@;
#print("Add session marker id=$Vend::SessionID  name=$Vend::SessionName\n") if $Global::DEBUG;
	$s = {} unless $s;
	$s->{$Vend::SessionName} = {};
	$Vend::SessionDBM{$Vend::SessionID} = uneval $s;
}

sub dump_sessions {
	my($called) = @_;
    my($session_name, $s);
	die "Can't dump file-based sessions.\n" if $File_sessions;
	my $pretty;

	eval {	require Data::Dumper;
			import Data::Dumper 'DumperX';
			$Data::Dumper::Indent = 3;
			$Data::Dumper::Terse = 1; };
	$pretty = $@ ? 0 : 1;
    open_session();
    while(($session_name, $s) = each %Vend::SessionDBM) {
		if(defined $called) {
			next unless $session_name =~ /$called/;
		}
		if ($pretty) {
			my $ref = eval $s;
			$s = uneval($ref);
		}
		print "$session_name $s\n\n";
    }
    close_session();
}

sub expire_sessions {
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
			$session = eval ($s);
			die "Could not eval '$s' from session dbm: $@\n" if $@;
			next if keys %$session;   # Don't remove if has session marker
			push @delete, $session_name;
		}

		$session = eval($s);
		die "Could not eval '$s' from session dbm: $@\n" if $@;
		next if check_save($session,$time);
		if ( (! defined $session) ||
			 $time - $session->{'time'} > $Vend::Cfg->{'SessionExpire'}) {
			push @delete, $session_name;
			remove_session_marker($session_name);
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
    close_session();
}

sub check_save {
	my($time) = (@_);
	return 0 unless $Vend::Session->{'values'}->{mv_save_session};
	my $expire;

	$time = $time || time();

	if(defined $Vend::Session->{'values'}->{mv_expire_time}) {
		$expire = $Vend::Session->{'values'}->{mv_expire_time};
		unless($expire =~ /^\d{6,}$/) {
			$expire = Vend::Config::time_to_seconds($expire);
			if(defined $expire) {
				$Vend::Session->{'values'}->{mv_expire_time} = $expire;
			}
		}
	}
	else {
		$expire = $Vend::Cfg->{SaveExpire};
	}

	$Vend::Expire = $time + $expire;

	return ($time - $expire < $Vend::Session->{'time'}) ? 1 : 0;
}	

1;

__END__
