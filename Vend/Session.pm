# $Id: Session.pm,v 1.2 1996/05/18 20:02:39 mike Exp $

package Vend::Session;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(

close_tracking
dump_sessions
expire_sessions
get_session
init_session
new_session
open_tracking
put_session
read_password
release_session
session_name

);

use strict;
use Carp;
use Fcntl;
use Vend::Util;


BEGIN {
	if(defined $GDBM_File::VERSION or $Config::GDBM) {
		require GDBM_File;
		import GDBM_File;
	}
	elsif(defined $DB_File::VERSION or $Config::DB_File) {
		require DB_File;
		import DB_File;
	}
	elsif(defined $NDBM_File::VERSION or $Config::NDBM) {
		require NDBM_File;
		import NDBM_File;
	}
	else {
		die "No DBM defined! Session.pm can't run.\n";
	}
}

## SESSIONS implemented using DBM

sub get_session {
	$Vend::HaveSession = 0;
	open_session();
	read_session();
	lock_session();
	close_session();
	$Vend::HaveSession = 1;
}

sub release_session {
	open_session();
	read_session();
	unlock_session();
	close_session();
	$Vend::HaveSession = 0;
}

sub put_session {
	open_session();
	write_session();
	unlock_session();
	close_session();
	$Vend::HaveSession = 0;
}

sub open_session {

    open(Vend::SessionLock, "+>>$Config::ConfDir/session.lock")
		or die "Could not open 'session.lock': $!\n";
    lockfile(\*Vend::SessionLock, 1, 1)
		or die "Could not lock 'session.lock': $!\n";
    
    # Selects based on initial config
	if($Config::GDBM) {
    	tie(%Vend::SessionDBM, 'GDBM_File', $Config::SessionDatabase . ".gdbm",
		&GDBM_WRCREAT, $Config::FileCreationMask)
		or die "Could not tie to $Config::SessionDatabase: $!\n";
	}
	elsif($Config::DB_File) {
    	tie(%Vend::SessionDBM, 'DB_File', $Config::SessionDatabase . ".db",
		&O_RDWR|&O_CREAT, $Config::FileCreationMask)
		or die "Could not tie to $Config::SessionDatabase: $!\n";
	}
	elsif($Config::NDBM) {
    	tie(%Vend::SessionDBM, 'NDBM_File', $Config::SessionDatabase,
		&O_RDWR|&O_CREAT, $Config::FileCreationMask)
		or die "Could not tie to $Config::SessionDatabase: $!\n";
	}
	else {
		die "No DBM implementation configured!\n";
	}

}

sub new_session {
    my($name);

    open_session();
    $Vend::SessionName = session_name();
    for (;;) {
		$Vend::SessionID = random_string();
		$name = session_name();
		last unless defined $Vend::SessionDBM{$name};
    }
    $Vend::SessionName = $name;
    init_session();
	write_session();
	close_session();
}

sub close_tracking {

	if ($Config::Tracking && defined %Vend::Tracking) {
	   	untie %Vend::Tracking
			or die "Could not untie $Config::ProductDir/tracking: $!\n";
	   	unlockfile(\*Vend::TrackingLock)
			or die "Could not unlock 'tracking.lock': $!\n";
	   	close(Vend::TrackingLock)
			or die "Could not close 'tracking.lock': $!\n";
	}
}

sub close_session {
    #pick one

    untie %Vend::SessionDBM
	or die "Could not close $Config::SessionDatabase: $!\n";
	
	unlockfile(\*Vend::SessionLock)
		or die "Could not unlock 'session.lock': $!\n";
    close(Vend::SessionLock)
		or die "Could not close 'session.lock': $!\n";
}

sub write_session {
    my($s);
    $Vend::Session->{'time'} = time;
    $s = uneval($Vend::Session);
    $Vend::SessionDBM{$Vend::SessionName} = $s;
    die "Data was not stored in DBM file\n"
		if $Vend::SessionDBM{$Vend::SessionName} ne $s;
}

sub unlock_session {
	$Vend::SessionDBM{'LOCK_' . $Vend::SessionName} = 0;
}

sub lock_session {
	my $lockname = 'LOCK_' . $Vend::SessionName;
	my ($tried, $locktime, $sleepleft, $pid, $now, $left);
	$tried = 0;

	LOCKLOOP: {
		($locktime, $pid) = split /:/, $Vend::SessionDBM{$lockname}, 2;
		$now = time;
		if(defined $locktime and $locktime) {
			$left = $now - $locktime;
			if ( $left > $Config::HammerLock ) {
				$Vend::SessionDBM{$lockname} = "$now:$$";
				logError("Hammered session lock $lockname left by PID $pid.");
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

    $s = $Vend::SessionDBM{$Vend::SessionName};
    $Vend::Session = eval($s);
    die "Could not eval '$s' from session dbm: $@\n" if $@;
    $Vend::Items = $Vend::Session->{'items'};
}

sub expire_sessions {
    my($time, $session_name, $s, $session, @delete);

    $time = time;
    open_session();
    while(($session_name, $s) = each %Vend::SessionDBM) {
		next if $session_name =~ /^lock_/i;
		$session = eval($s);
		die "Could not eval '$s' from session dbm: $@\n" if $@;
		if ( (! defined $session) ||
			 $time - $session->{'time'} > $Config::SessionExpire) {
			push @delete, $session_name;
		}
    }
    foreach $session_name (@delete) {
		delete $Vend::SessionDBM{$session_name};
		delete $Vend::SessionDBM{"LOCK_$session_name"}
				if $Vend::SessionDBM{"LOCK_$session_name"};
		my $file = $session_name;
		$file =~ s/:.*//;
		opendir(Vend::DELDIR, $Config::ScratchDir) ||
			die "Could not open configuration directory $Config::ScratchDir: $!\n";
		my @files = grep /^$file/, readdir(Vend::DELDIR);
		for(@files) {
			unlink "$Config::ScratchDir/$_";
		}
		closedir(Vend::DELDIR);
    }
    close_session();
}

sub dump_sessions {
    my($session_name, $s);

    open_session();
    while(($session_name, $s) = each %Vend::SessionDBM) {
	print "$session_name $s\n\n";
    }
    close_session();
}


## SESSIONS

sub session_name {
    my($host, $user, $fn);

    $fn = escape_chars($Vend::SessionID) . ':'
	. escape_chars($CGI::host) . ':' . escape_chars($CGI::user);
    #escape_chars($CGI::gateway_interface);
    $fn;
}


sub init_session {
    $Vend::Session = {
	'version' => 1,
	'frames' => 0,
	'login' => '',
	'browser' => $CGI::useragent,
	'scratch' => {},
	'values' => {},
	'items' => [],
    };
    $Vend::Items	= $Vend::Session->{'items'};
    $Vend::Scratch	= $Vend::Session->{'scratch'};
	$Vend::Session->{'secure'} = $Config::AlwaysSecure ? 1 : 0;
	$Vend::Session->{'values'}->{'mv_shipmode'} = $Config::DefaultShipping;
}


sub read_password {
	my($password,$string,$check);
	my $i = 0;

	if ($Config::Tracking) {
		open_tracking();
		$check = defined $Vend::Tracking{'encrypted_pass'}
				? $Vend::Tracking{'encrypted_pass'}
				: 0;
	}
	else {
		$check = 0;
	}

	if($Config::CreditCards) {
		while($i < 3) {
			if (-t) {
				system 'stty', '-echo';
				print "Enter the password: ";
				chop($password = <>);
				unless($check) {
					print "\nVerify: ";
					chop($string = <>);
				}
				system 'stty', 'echo';
				print "\n";
			}
			else {
				$i = 999;
				chomp($password = <>);
			}
			$i++;
			if($check) {
				if( crypt($password,$check) eq $check) {
					$Config::Password = $password;
					$check =~ s/^(........).*/$1/;
					$Config::Pw_Ivec = $check;
					return;
				}
				else {
					print "\n\nWrong password!\n\n" if -t;
					next;
				}
			}
			elsif($string eq $password) {
				$Config::Password = $password;
				if($Config::Tracking) {
					open_tracking();
					$check = crypt($password,random_string());
					$Vend::Tracking{'encrypted_pass'} = $check;
					$check =~ s/^(........).*/$1/;
					$Config::Pw_Ivec = $check;
					close_tracking();
				}
				else {
					$Config::Pw_Ivec = 'mINIvEND';
				}
				return;
			}
			else {
				undef $password;
				undef $Config::Password;
				print "\n\nThey don't match!\n\n" if -t;
				next;
			}
		}
	}

	# If we made it here, we failed to get a password
	$Config::Password = '';
	$Config::EncryptProgram = '';
	$Config::CreditCards = 0;
}

sub open_tracking {
	
	my($page, $desc, $price);

    open(Vend::TrackingLock, "+>>$Config::ConfDir/tracking.lock")
    	or die "Could not open '$Config::ConfDir/tracking.lock': $!\n";
    lockfile(\*Vend::TrackingLock, 0, 1)
    	or die "Could not lock '$Config::ConfDir/tracking.lock': $!\n";

    if($Config::GDBM) {
 		tie(%Vend::Tracking, 'GDBM_File',
				"$Config::ProductDir/tracking.gdbm",
				&GDBM_WRCREAT, $Config::FileCreationMask)
    		or die "Could not tie to $Config::ProductDir/tracking.gdbm: $!\n";

	}
	elsif ($Config::DB_File) {
		tie(%Vend::Tracking, 'DB_File',
				"$Config::ProductDir/tracking.db",
				&O_RDWR|&O_CREAT, $Config::FileCreationMask)
			or die "Could not tie to $Config::ProductDir/tracking: $!\n";
	}
	elsif ($Config::NDBM) {
		tie(%Vend::Tracking, 'NDBM_File',
				"$Config::ProductDir/tracking",
				&O_RDWR|&O_CREAT, $Config::FileCreationMask)
			or die "Could not tie to $Config::ProductDir/tracking: $!\n";
	}
	else {
		die "No DBM configuration defined!\n";
	}

}

1;
