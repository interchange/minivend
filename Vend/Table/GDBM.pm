# Table/GDBM.pm: access a table stored in a GDBM file
#
# $Id: GDBM.pm,v 1.4 1995/10/10 19:07:13 amw Exp $
#
package Vend::Table::GDBM;

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

use Carp;
use strict;
use GDBM_File;

sub create_table {
    my ($class, $filename, $columns, $file_mode, $fast) = @_;
    $file_mode = 0666 unless defined $file_mode;
    $fast = 0 unless defined $fast;

    my $column_file = "$filename.columns";
    my @columns = @$columns;
    open(COLUMNS, ">$column_file")
        or croak "Couldn't create '$column_file': $!";
    print COLUMNS join("\t", @columns), "\n";
    close(COLUMNS);

    my $column_index = {};
    my $i;
    for ($i = 0;  $i < @columns;  ++$i) {
        $column_index->{$columns[$i]} = $i;
    }

    my $gdbm_file = "$filename.gdbm";
    my $tie = {};
    my $flags = GDBM_NEWDB;
    $flags |= GDBM_FAST if $fast;
    my $dbm = tie(%$tie, 'GDBM_File', $gdbm_file, $flags, $file_mode)
        or croak "Could not open '$gdbm_file': $!";

    my $self = [$filename, [@columns], $column_index, $tie, $dbm];
    bless $self, $class;
}


sub open_table {
    my ($class, $filename, $fast) = @_;
    $fast = 0 unless defined $fast;

    my $column_file = "$filename.columns";
    open(COLUMNS, $column_file) or croak "Couldn't open '$column_file': $!";
    my $columns = <COLUMNS>
        or croak "Couldn't read columns from '$column_file': $!";
    chomp $columns;
    close(COLUMNS);
    my @columns = split(/\t/, $columns);
    croak "No columns listed in '$filename.columns'" unless @columns;

    my $column_index = {};
    my $i;
    for ($i = 0;  $i < @columns;  ++$i) {
        $column_index->{$columns[$i]} = $i;
    }

    my $gdbm_file = "$filename.gdbm";
    my $tie = {};
    my $flags = GDBM_WRITER;
    $flags |= GDBM_FAST if $fast;
    my $dbm = tie(%$tie, 'GDBM_File', $gdbm_file, $flags, 0600)
        or croak "Could not open '$gdbm_file': $!";

    my $self = [$filename, [@columns], $column_index, $tie, $dbm];
    bless $self, $class;
}

# 0: filename
# 1: column names
# 2: column index
# 3: tie hash
# 4: dbm object

sub close_table {
    my ($s) = @_;

    untie %{$s->[3]} or die "Could not close '$s->[0]': $!\n";
}


sub columns {
    my ($s) = @_;
    @{$s->[1]};
}

sub column_index {
    my ($s, $column) = @_;
    my $i = $s->[2]{$column};
    croak "There is no column named '$column'" unless defined $i;
    $i;
}

sub row {
    my ($s, $key) = @_;
    my $line = $s->[3]{$key};
    croak "There is no row with index '$key'" unless defined $line;
    return split(/\t/, $line);
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
    my $line = join("\t", @fields);
    $s->[3]{$key} = $line;
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
    my @a = each %{$s->[3]};
    if (@a) {
        return ($a[0], split(/\t/, $a[1]));
    }
    else {
        return ();
    }
}

sub record_exists {
    my ($s, $key) = @_;
    $s->[4]->exists($key);
}

sub delete_record {
    my ($s, $key) = @_;

    delete $s->[3]{$key};
}

sub clear_table {
    my ($s) = @_;
    %{$s->[3]} = ();
}

1;
