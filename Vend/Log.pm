# Log.pm:  log errors and warnings to error log file
#
# $Id: Log.pm,v 1.7 1995/11/10 15:13:18 amw Exp $
#
package Vend::Log;

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

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(open_log lock_log log_error unlock_log close_log);

use strict;
use Vend::Directive qw(Error_file);
use Vend::lock;

my $log_locked = 0;

sub open_log {
    open(Vend::Log::ERROR, ">>".Error_file)
        or die "Could not open '".Error_file."': $!\n";
    {
        no strict 'refs';
        my $old = select(Vend::Log::ERROR);
        $| = 1;
        select($old);
    }
    $Vend::Log::log_open = 1;
}

sub lock_log {
    open_log() unless $Vend::Log::log_open;
    lockfile(\*Vend::Log::ERROR);
    $log_locked = 1;
}

sub unlock_log {
    return unless $log_locked;
    unlockfile(\*Vend::Log::ERROR);
    $log_locked = 0;
}

sub close_log {
    return unless $Vend::Log::log_open;
    unlock_log();
    close(Vend::Log::ERROR)
        or die "Could not close '".Error_file."': $!\n";
    $Vend::Log::log_open = 0;
}


# END {
#    close_log();
# }


# Log MSG to the error file.

sub log_error {
    my ($msg) = @_;

    open_log() unless $Vend::Log::log_open;

    seek(Vend::Log::ERROR, 0, 2)
        or die "Could not seek '".Error_file."': $!\n";
    print(Vend::Log::ERROR $msg)
        or die "Could not write to '".Error_file."': $!\n";
}

1;
