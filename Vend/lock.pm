package Vend::lock;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(lockfile unlockfile);

use Carp;
use Config;
use Fcntl;
use strict;

my $debug = 0;
my $use = undef;

### flock locking

# sys/file.h:
my $flock_LOCK_SH = 1;          # Shared lock
my $flock_LOCK_EX = 2;          # Exclusive lock
my $flock_LOCK_NB = 4;          # Don't block when locking
my $flock_LOCK_UN = 8;          # Unlock

sub flock_lock {
    my ($fh, $excl, $wait) = @_;
    my $flag = $excl ? $flock_LOCK_EX : $flock_LOCK_SH;

    if ($wait) {
        flock($fh, $flag) or confess "Could not lock file: $!\n";
        return 1;
    }
    else {
        if (! flock($fh, $flag | $flock_LOCK_NB)) {
            if ($! =~ m/^Try again/
                or $! =~ m/^Resource temporarily unavailable/
                or $! =~ m/^Operation would block/) {
                return 0;
            }
            else {
                confess "Could not lock file: $!\n";
            }
        }
        return 1;
    }
}

sub flock_unlock {
    my ($fh) = @_;
    flock($fh, $flock_LOCK_UN) or confess "Could not unlock file: $!\n";
}


### fcntl locking

# Linux 1.2.8 fcntl.h, types.h:
#
# struct flock {
#	short l_type;
#	short l_whence;
#	off_t l_start;
#	off_t l_len;
#	pid_t l_pid;
# };
#
# typedef int pid_t;
# typedef long off_t;

# Solaris fcntl(2), types.h:
#
#    typedef struct flock {
#         short     l_type;
#         short     l_whence;
#         off_t     l_start;
#         off_t     l_len;          /* len == 0 means until end of file */
#         long      l_sysid;
#         pid_t     l_pid;
#         long      pad[4];         /* reserve area */
#    } flock_t;
#
# typedef long            off_t;          /* ?<offset> type */
# typedef long    pid_t;                  /* process id type      */

my $flock_struct = "ssll";

# call with *FH

sub fcntl_lock {
    my ($fh, $excl, $wait) = @_;
    my $cmd = $wait ? F_SETLKW : F_SETLK;
    my $lock = $excl ? F_WRLCK : F_RDLCK;
    my $flock = pack($flock_struct, $lock, 0, 0, 0);

    my $r;
    do {
        $r = fcntl($fh, $cmd, $flock);
    } while (not $r and $! =~ m/^Interrupted/);

    if (not $r) {
        if ($! =~ m/^No such file/ or
            $! =~ m/^Resource temporarily/) {
            return 0;
        }
        else {
            confess "Could not lock file $fh: $!\n";
        }
    }
    return 1;
}

sub fcntl_unlock {
    my ($fh) = @_;
    my $flock = pack($flock_struct, F_UNLCK, 0, 0, 0);
    my $r;
    do {
        $r = fcntl($fh, F_SETLKW, $flock);
    } while (not $r and $! =~ m/^Interrupted/);
    confess "Could not unlock file: $!\n" unless $r;
    1;
}

### Select based on os

my $lock_function;
my $unlock_function;

unless (defined $use) {
    my $os = $Vend::lock::Config{'osname'};
    warn "lock.pm: os is $os\n" if $debug;
    if ($os eq 'solaris') {
        $use = 'fcntl';
    }
    else {
        $use = 'flock';
    }
}
        
if ($use eq 'fcntl') {
    warn "lock.pm: using fcntl locking\n" if $debug;
    $lock_function = \&fcntl_lock;
    $unlock_function = \&fcntl_unlock;
}
else {
    warn "lock.pm: using flock locking\n" if $debug;
    $lock_function = \&flock_lock;
    $unlock_function = \&flock_unlock;
}
    
sub lockfile {
    &$lock_function(@_);
}

sub unlockfile {
    &$unlock_function(@_);
}

1;
