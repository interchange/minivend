# Ephemeral.pm: set up symbolic links for a limited time
#
# $Id: Ephemeral.pm,v 1.1 1996/02/26 21:28:58 amw Exp $

package Vend::Ephemeral;

# Copyright 1996 by Andrew M. Wilcox <awilcox@world.std.com>
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
@EXPORT = qw(ephemeral_key);

my $Debug = 0;

use FileHandle;
use strict;
use Vend::lock;
use Vend::Util qw(random_string);

my ($Switch_file, $Switch_mark_file, $Symlink_directory, $Symlink_target,
    $Lifetime);

sub configure {
    my ($class, $config) = @_;

    my $data           = $config->{'Data_directory'};
    $Lifetime          = $config->{'Lifetime'};
    $Symlink_directory = $config->{'Symlink_directory'};
    $Symlink_target    = $config->{'Symlink_target'};

    $Switch_mark_file = "$data/ephemeral.mark";
    $Switch_file = "$data/ephemeral";
}

my ($New, $Old);

sub ephemeral_key {
    print STDERR "Entering ephemeral_key\n" if $Debug;

    open_switch();

    switch() if (! defined($New) or 
                 ! -e $Switch_mark_file or
                 time - last_switch_time() > $Lifetime / 2);

    close_switch();

    print STDERR "ephemeral_key: returning '$New'\n\n" if $Debug;
    return $New;
}

sub open_switch {
    open(SWITCH, "+>>$Switch_file")
        or die "Can't open '$Switch_file': $!\n";
    lockfile(\*SWITCH, 1, 1);

    seek(SWITCH, 0, 0);
    $New = <SWITCH>;
    if (defined $New and $New =~ m/(\w+)/) {
        $New = $1;
        print STDERR "open_switch: read New: $New\n" if $Debug;

        $Old = <SWITCH>;
        if (defined $Old and $Old =~ m/(\w+)/) {
            $Old = $1;
            print STDERR "open_switch: read Old: $Old\n" if $Debug;
        }
        else {
            $Old = undef;
            print STDERR "open_switch: undef Old\n" if $Debug;
        }
    }
    else {
        $New = undef;
        $Old = undef;
        print STDERR "open_switch: undef New, Old\n" if $Debug;
        switch();
    }
}

sub close_switch {
    autoflush SWITCH 1;
    print SWITCH '';
    unlockfile(\*SWITCH);
    close(SWITCH);
    print STDERR "close_switch:\n" if $Debug;
}

sub last_switch_time {
    my @s = stat($Switch_mark_file);
    die "Can't stat '$Switch_mark_file': $!\n" unless @s;
    return $s[9];
}

sub switch {
    if (defined $Old) {
        unlink("$Symlink_directory/$Old");
        print STDERR "switch: '$Symlink_directory/$Old' deleted\n" if $Debug;
    }

    $Old = $New;

    $New = random_string();
    symlink($Symlink_target, "$Symlink_directory/$New")
        or die "Can't make a symbolic link from $Symlink_directory/$New ".
               "to $Symlink_target: $!\n";
    print STDERR "switch: symlink $Symlink_directory/$New -> $Symlink_target created\n" if $Debug;

    no strict 'subs';
    truncate(SWITCH, 0);
    seek(SWITCH, 0, 0);
    print SWITCH "$New\n";
    print STDERR "switch: '$New' written\n" if $Debug;
    if (defined $Old) {
        print SWITCH "$Old\n";
        print STDERR "switch: '$Old' written\n" if $Debug;
    }

    touch_switch_mark();
}


sub touch_switch_mark {
    my $now = time;
    if (-e $Switch_mark_file) {
        utime($now, $now, $Switch_mark_file)
            or die "Couldn't set modification time for '$Switch_mark_file': $!\n";
    }
    else {
        open(MARK, ">$Switch_mark_file")
            or die "Couldn't create '$Switch_mark_file': $!\n";
        close(MARK);
    }
}

1;
