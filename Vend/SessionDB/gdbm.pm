# SessionDB/gdbm.pm:  database interface for Session using GDBM
#
# $Id: gdbm.pm,v 1.3 1995/11/10 15:19:34 amw Exp $
#
package Vend::SessionDB::gdbm;

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

use strict;

use GDBM_File;
use Vend::lock;
use Vend::Uneval;

my $dbext = "gdbm";
my $lockext = "lock";

sub _lock {
    my ($filehandle, $fn) = @_;

    open($filehandle, "+>>$fn") or die "Could not open '$fn': $!\n";
    lockfile($filehandle, 1, 0) or die "'$fn' is in use by another process\n";
}
    
sub _unlock {
    my ($filehandle, $fn) = @_;

    unlockfile($filehandle);
    close($filehandle) or die "Couldn't close '$fn': $!\n";
}

sub delete_db {
    my ($class, $fn) = @_;

    _lock(\*LOCK, "$fn.$lockext");
    unlink "$fn.$dbext" or die "Can't remove '$fn.$dbext': $!\n";
    _unlock(\*LOCK, "$fn.$lockext");
}

sub rename_db {
    my ($class, $old, $new) = @_;

    _lock(\*OLDLOCK, "$old.$lockext");
    _lock(\*NEWLOCK, "$new.$lockext");
    rename("$old.$dbext", "$new.$dbext")
        or die "Couldn't rename '$old.$dbext' to '$new.$dbext': $!\n";
    _unlock(\*NEWLOCK, "$new.$lockext");
    _unlock(\*OLDLOCK, "$old.$lockext");
}

sub db_exists {
    my ($class, $fn) = @_;

    return -f "$fn.$dbext";
}

my $Fhc = 0;

sub new {
    my ($class, $fn, $file_creation_mask) = @_;

    my $self = {};
    $self->{file_creation_mask} = $file_creation_mask;
    $self->{'filename'} = "$fn.$dbext";
    $self->{'tievar'} = "Vend::SessionDB::gdbm::Tie" . ++$Fhc;
    {
        no strict 'refs';
        $self->{'lockfilehandle'} =
            \*{"Vend::SessionDB::gdbm::FH" . ++$Fhc};
    }
    $self->{'lockfilename'} = "$fn.$lockext";
    return bless $self, $class;
}

sub dump {
    my ($self) = @_;

    print "$self: \n";
    my ($k, $v);
    while (($k, $v) = each %$self) {
        print "   $k = $v\n";
    }
}

sub open_db {
    my $self = shift;
    my $lockfh = $self->{'lockfilehandle'};
    my $lockfn = $self->{'lockfilename'};
    local *Vend::SessionDB::gdbm::tievar = $self->{'tievar'};
    my $filename = $self->{'filename'};
    no strict 'refs';

    _lock($lockfh, $lockfn);
    tie(%Vend::SessionDB::gdbm::tievar,
        'GDBM_File',
        $filename,
        &GDBM_WRCREAT(),
	$self->{file_creation_mask})
      or die "Could not open '$filename': $!\n";
}

sub close_db {
    my $self = shift;
    local *Vend::SessionDB::gdbm::tievar = $self->{'tievar'};
    my $filename = $self->{'filename'};
    my $lockfh = $self->{'lockfilehandle'};
    my $lockfn = $self->{'lockfilename'};
    no strict 'refs';

    untie %Vend::SessionDB::gdbm::tievar or die "Could not close '$filename': $!\n";
    _unlock($lockfh, $lockfn);
}

sub lock_key {
    my ($self, $key) = @_;
    $self->{'locked_key'} = $key;
}

sub unlock_key {
    my $self = shift;
    undef $self->{'locked_key'};
}

sub defined {
    my ($self) = @_;
    my $key = $self->{'locked_key'};
    local *Vend::SessionDB::gdbm::tievar = $self->{'tievar'};

    return defined($Vend::SessionDB::gdbm::tievar{$key});
}

sub get {
    my ($self) = @_;
    my $key = $self->{'locked_key'};
    local *Vend::SessionDB::gdbm::tievar = $self->{'tievar'};

    return $Vend::SessionDB::gdbm::tievar{$key};
}

sub put {
    my ($self, $value) = @_;
    my $key = $self->{'locked_key'};
    local *Vend::SessionDB::gdbm::tievar = $self->{'tievar'};

    if (defined $value) {
	$Vend::SessionDB::gdbm::tievar{$key} = $value;
	die "Data was not stored in DBM file (maybe Perl's taintcheck bug?)\n"
            if $Vend::SessionDB::gdbm::tievar{$key} ne $value;
    } else {
	delete $Vend::SessionDB::gdbm::tievar{$key};
    }
}

sub each_record {
    my ($self) = @_;
    local *Vend::SessionDB::gdbm::tievar = $self->{'tievar'};

    my @keyvalue = each %Vend::SessionDB::gdbm::tievar;
    return @keyvalue;
}

1;
