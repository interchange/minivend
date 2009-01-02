# Table/GDBM.pm: access a table stored in a GDBM file
#
# $Id: GDBM.pm,v 1.2 1996/08/22 17:35:08 mike Exp $
#

# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# $Log: GDBM.pm,v $
# Revision 1.2  1996/08/22 17:35:08  mike
# Save solid snapshot of multiple catalog Vend
#
# Revision 1.1  1996/08/09 22:21:11  mike
# Initial revision
#
# Revision 1.11  1996/05/18 20:02:39  mike
# Minivend 1.03 Beta 1
#
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

package Vend::Table::GDBM;
$VERSION = substr(q$Revision: 1.2 $, 10);
use Carp;
use strict;
use GDBM_File;

my @Hex_string;
{
    my $i;
    foreach $i (0..255) {
        $Hex_string[$i] = sprintf("%02X", $i);
    }
}

sub stuff {
    my ($val) = @_;

    $val =~ s,([\t\%]),$Hex_string[ord($1)],eg;
    return $val;
}

sub unstuff {
    my ($val) = @_;
    $val =~ s,%(..),chr(hex($1)),eg;
    return $val;
}


# 0: filename
# 1: column names
# 2: column index
# 3: tie hash
# 4: dbm object

my ($FILENAME, $COLUMN_NAMES, $COLUMN_INDEX, $TIE_HASH, $DBM) = (0 .. 4);

sub create_table {
    my ($class, $config, $filename, $columns) = @_;

    return $class->create($columns, $filename, $config);
}

sub create {
    my ($class, $columns, $filename, $config) = @_;

    $config = {} unless defined $config;
    my ($File_permission_mode, $Fast_write)
        = @$config{'File_permission_mode', 'Fast_write'};
    $File_permission_mode = 0666 unless defined $File_permission_mode;
    $Fast_write = 1 unless defined $Fast_write;

    croak "columns argument $columns is not an array ref\n"
        unless ref($columns) eq 'ARRAY';

    # my $column_file = "$filename.columns";
    # my @columns = @$columns;
    # open(COLUMNS, ">$column_file")
    #    or croak "Couldn't create '$column_file': $!";
    # print COLUMNS join("\t", @columns), "\n";
    # close(COLUMNS);

    my $column_index = {};
    my $i;
    for ($i = 0;  $i < @$columns;  ++$i) {
        $column_index->{$columns->[$i]} = $i;
    }

    my $tie = {};
    my $flags = GDBM_NEWDB;
    $flags |= GDBM_FAST if $Fast_write;
    my $dbm = tie(%$tie, 'GDBM_File', $filename, $flags, $File_permission_mode)
        or croak "Could not create '$filename': $!";

    $tie->{'c'} = join("\t", @$columns);

    my $self = [$filename, $columns, $column_index, $tie, $dbm];
    bless $self, $class;
}


sub open_table {
    my ($class, $config, $filename) = @_;
    my ($Fast_write, $Read_only) = @$config{'Fast_write', 'Read_only'};

    my $tie = {};

    my $flags;
    if ($Read_only) {
        $flags = GDBM_READER;
    }
    else {
        my $flags = GDBM_WRITER;
        $flags |= GDBM_FAST if $Fast_write;
    }

    my $dbm = tie(%$tie, 'GDBM_File', $filename, $flags, 0600)
        or croak "Could not open '$filename': $!";

    my $columns = [split(/\t/, $tie->{'c'})];

    my $column_index = {};
    my $i;
    for ($i = 0;  $i < @$columns;  ++$i) {
        $column_index->{$columns->[$i]} = $i;
    }

    my $self = [$filename, $columns, $column_index, $tie, $dbm];
    bless $self, $class;
}

sub close_table {
    my ($s) = @_;

    untie %{$s->[$TIE_HASH]} or die "Could not close '$s->[$FILENAME]': $!\n";
}


sub columns {
    my ($s) = @_;
    return @{$s->[$COLUMN_NAMES]};
}


sub test_column {
    my ($s, $column) = @_;
    my $i = $s->[$COLUMN_INDEX]{$column};
    unless(defined $i) {
		carp "There is no column named '$column'\n";
		return undef;
	}
	return $i;
}

sub column_index {
    my ($s, $column) = @_;
    my $i = $s->[$COLUMN_INDEX]{$column};
    croak "There is no column named '$column'" unless defined $i;
    return $i;
}

sub row {
    my ($s, $key) = @_;
    my $line = $s->[$TIE_HASH]{"k$key"};
    croak "There is no row with index '$key'" unless defined $line;
    return map(unstuff($_), split(/\t/, $line, 9999));
}

sub field_accessor {
    my ($self, $column) = @_;
    my $index = $self->column_index($column);
    return sub {
        my ($key) = @_;
        return ($self->row($key))[$index];
    };
}

sub field_settor {
    my ($self, $column) = @_;
    my $index = $self->column_index($column);
    return sub {
        my ($key, $value) = @_;
        my @row = $self->row($key);
        $row[$index] = $value;
        $self->set_row($key, @row);
    };
}

sub set_row {
    my ($s, $key, @fields) = @_;
    my $line = join("\t", map(stuff($_), @fields));
    $s->[$TIE_HASH]{"k$key"} = $line;
}

sub field {
    my ($s, $key, $column) = @_;
    return ($s->row($key))[$s->column_index($column)];
}

sub set_field {
    my ($s, $key, $column, $value) = @_;
    my @row = $s->row($key);
    $row[$s->column_index($column)] = $value;
    $s->set_row($key, @row);
}

sub each_record {
    my ($s) = @_;
    my ($key, $value);

    for (;;) {
        ($key, $value) = each %{$s->[3]};
        if (defined $key) {
            if ($key =~ s/^k//) {
                return ($key, map(unstuff($_), split(/\t/, $value, 9999)));
            }
        }
        else {
            return ();
        }
    }
}

sub record_exists {
    my ($s, $key) = @_;
    # guess what?  The GDBM "exists" function got renamed to "EXISTS" 
    # in 5.002.
    my $r = eval { $s->[$DBM]->EXISTS("k$key") };
    if ($@) {
        $r = $s->[$DBM]->exists("k$key");
    }
    return $r;
}

sub delete_record {
    my ($s, $key) = @_;

    delete $s->[$TIE_HASH]{"k$key"};
}

sub version { $Vend::Table::GDBM::VERSION }

1;
