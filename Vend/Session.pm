# $Id: Session.pm,v 1.6 1996/10/30 04:22:28 mike Exp $

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
	if(defined $GDBM_File::VERSION or $Global::GDBM) {
		require GDBM_File;
		import GDBM_File;
	}
	elsif(defined $DB_File::VERSION or $Global::DB_File) {
		require DB_File;
		import DB_File;
	}
	elsif(defined $NDBM_File::VERSION or $Global::NDBM) {
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

    open(Vend::SessionLock, "+>>$Vend::Cfg->{'SessionLockFile'}")
		or die "Could not open '$Vend::Cfg->{'SessionLockFile'}': $!\n";
    lockfile(\*Vend::SessionLock, 1, 1)
		or die "Could not lock '$Vend::Cfg->{'SessionLockFile'}': $!\n";
    
    # Selects based on initial config
	if($Global::GDBM) {
    	tie(%Vend::SessionDBM, 'GDBM_File', $Vend::Cfg->{'SessionDatabase'} . ".gdbm",
		&GDBM_WRCREAT, $Vend::Cfg->{'FileCreationMask'})
		or die "Could not tie to $Vend::Cfg->{'SessionDatabase'}: $!\n";
	}
	elsif($Global::DB_File) {
    	tie(%Vend::SessionDBM, 'DB_File', $Vend::Cfg->{'SessionDatabase'} . ".db",
		&O_RDWR|&O_CREAT, $Vend::Cfg->{'FileCreationMask'})
		or die "Could not tie to $Vend::Cfg->{'SessionDatabase'}: $!\n";
	}
	elsif($Global::NDBM) {
    	tie(%Vend::SessionDBM, 'NDBM_File', $Vend::Cfg->{'SessionDatabase'},
		&O_RDWR|&O_CREAT, $Vend::Cfg->{'FileCreationMask'})
		or die "Could not tie to $Vend::Cfg->{'SessionDatabase'}: $!\n";
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

	if ($Vend::Cfg->{'Tracking'} && defined %Vend::Tracking) {
	   	untie %Vend::Tracking
			or die "Could not untie $Vend::Cfg->{'ProductDir'}/tracking: $!\n";
	   	unlockfile(\*Vend::TrackingLock)
			or die "Could not unlock 'tracking.lock': $!\n";
	   	close(Vend::TrackingLock)
			or die "Could not close 'tracking.lock': $!\n";
	}
}

sub close_session {
    #pick one

    untie %Vend::SessionDBM
	or die "Could not close $Vend::Cfg->{'SessionDatabase'}: $!\n";
	
	unlockfile(\*Vend::SessionLock)
		or die "Could not unlock '$Vend::Cfg->{'SessionLockFile'}': $!\n";
    close(Vend::SessionLock)
		or die "Could not close '$Vend::Cfg->{'SessionLockFile'}': $!\n";
}

sub write_session {
    my($s);
    $Vend::Session->{'time'} = time;
	undef $Vend::Session->{'items'};
    $s = uneval($Vend::Session);
    $Vend::SessionDBM{$Vend::SessionName} = $s;
    die "Data was not stored in DBM file\n"
		if $Vend::SessionDBM{$Vend::SessionName} ne $s;
}

sub unlock_session {
	#$Vend::SessionDBM{'LOCK_' . $Vend::SessionName} = 0;
	delete $Vend::SessionDBM{'LOCK_' . $Vend::SessionName};
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
			if ( $left > $Global::HammerLock ) {
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
    $Vend::Items	= $Vend::Session->{'items'}
					= $Vend::Session->{'carts'}->{'main'};
    $Vend::Scratch	= $Vend::Session->{'scratch'};
}

sub expire_sessions {
    my($time, $session_name, $s, $session, @delete);

    $time = time;
    open_session();
    while(($session_name, $s) = each %Vend::SessionDBM) {
		if ($session_name =~ /^LOCK_/) {;
			delete $Vend::SessionDBM{$session_name}
				unless $s;
			next;
		}
		$session = eval($s);
		die "Could not eval '$s' from session dbm: $@\n" if $@;
		next if is_yes($session->{'values'}->{'mv_save_session'});
		if ( (! defined $session) ||
			 $time - $session->{'time'} > $Vend::Cfg->{'SessionExpire'}) {
			push @delete, $session_name;
		}
    }
    foreach $session_name (@delete) {
		delete $Vend::SessionDBM{$session_name};
		delete $Vend::SessionDBM{"LOCK_$session_name"}
				if $Vend::SessionDBM{"LOCK_$session_name"};
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
	'carts' => {main => []},
    };
    $Vend::Items	= $Vend::Session->{'items'}
					= $Vend::Session->{'carts'}->{'main'};
    $Vend::Scratch	= $Vend::Session->{'scratch'};
	$Vend::Session->{'secure'} = $Vend::Cfg->{'AlwaysSecure'} ? 1 : 0;
	$Vend::Session->{'values'}->{'mv_shipmode'} = $Vend::Cfg->{'DefaultShipping'};
}


sub read_password {
	my($password,$string,$check);
	my $i = 0;

	if ($Vend::Cfg->{'Tracking'}) {
		open_tracking();
		$check = defined $Vend::Tracking{'encrypted_pass'}
				? $Vend::Tracking{'encrypted_pass'}
				: 0;
		close_tracking();
	}
	else {
		$check = 0;
	}

	if($Vend::Cfg->{'CreditCards'}) {
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
					$Vend::Cfg->{'Password'} = $password;
					$check =~ s/^(........).*/$1/;
					$Vend::Cfg->{'Pw_Ivec'} = $check;
					return;
				}
				else {
					print "\n\nWrong password!\n\n" if -t;
					next;
				}
			}
			elsif($string eq $password) {
				$Vend::Cfg->{'Password'} = $password;
				if($Vend::Cfg->{'Tracking'}) {
					open_tracking();
					$check = crypt($password,random_string());
					$Vend::Tracking{'encrypted_pass'} = $check;
					$check =~ s/^(........).*/$1/;
					$Vend::Cfg->{'Pw_Ivec'} = $check;
					close_tracking();
				}
				else {
					$Vend::Cfg->{'Pw_Ivec'} = 'mINIvEND';
				}
				return;
			}
			else {
				undef $password;
				undef $Vend::Cfg->{'Password'};
				print "\n\nThey don't match!\n\n" if -t;
				next;
			}
		}
	}

	# If we made it here, we failed to get a password
	$Vend::Cfg->{'Password'} = '';
	$Vend::Cfg->{'EncryptProgram'} = '';
	$Vend::Cfg->{'CreditCards'} = 0;
}

sub open_tracking {
	
	my($page, $desc, $price);

    open(Vend::TrackingLock, "+>>$Vend::Cfg->{'ConfDir'}/tracking.lock")
    	or die "Could not open '$Vend::Cfg->{'ConfDir'}/tracking.lock': $!\n";
    lockfile(\*Vend::TrackingLock, 0, 1)
    	or die "Could not lock '$Vend::Cfg->{'ConfDir'}/tracking.lock': $!\n";

    if($Global::GDBM) {
 		tie(%Vend::Tracking, 'GDBM_File',
				"$Vend::Cfg->{'ProductDir'}/tracking.gdbm",
				&GDBM_WRCREAT, $Vend::Cfg->{'FileCreationMask'})
    		or die "Could not tie to $Vend::Cfg->{'ProductDir'}/tracking.gdbm: $!\n";

	}
	elsif ($Global::DB_File) {
		tie(%Vend::Tracking, 'DB_File',
				"$Vend::Cfg->{'ProductDir'}/tracking.db",
				&O_RDWR|&O_CREAT, $Vend::Cfg->{'FileCreationMask'})
			or die "Could not tie to $Vend::Cfg->{'ProductDir'}/tracking: $!\n";
	}
	elsif ($Global::NDBM) {
		tie(%Vend::Tracking, 'NDBM_File',
				"$Vend::Cfg->{'ProductDir'}/tracking",
				&O_RDWR|&O_CREAT, $Vend::Cfg->{'FileCreationMask'})
			or die "Could not tie to $Vend::Cfg->{'ProductDir'}/tracking: $!\n";
	}
	else {
		die "No DBM configuration defined!\n";
	}

}

1;
