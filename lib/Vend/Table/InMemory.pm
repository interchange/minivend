# Table/InMemory.pm: store a table in memory
#
# $Id: InMemory.pm,v 1.8 1997/05/22 07:10:45 mike Exp $
#
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

package Vend::Table::InMemory;
$VERSION = substr(q$Revision: 1.8 $, 10);
use Carp;
use strict;

sub create_table {
    my ($class, $columns) = @_;

    my $column_index = {};
    my $i;
    for ($i = 0;  $i < @$columns;  ++$i) {
        $column_index->{$columns->[$i]} = $i;
    }

    my $hash = {};
    my $self = [$columns, $column_index, $hash];
    bless $self, $class;
}

# 0: columns
# 1: column_index
# 2: hash

sub close_table { 1; }

sub columns {
    my ($s) = @_;
    return @{$s->[0]};
}

sub test_column {
    my ($s, $column) = @_;
	return $s->[1]{$column};
}

sub column_index {
    my ($s, $column) = @_;
    my $i = $s->[1]{$column};
    croak "There is no column named '$column'" unless defined $i;
    $i;
}

sub row {
    my ($s, $key) = @_;
    my $a = $s->[2]{$key};
    croak "There is no row with index '$key'" unless defined $a;
    return @$a;
}

sub field_accessor {
    my ($s, $column) = @_;
    my $index = $s->column_index($column);
    return sub {
        my ($key) = @_;
        my $a = $s->[2]{$key};
        croak "There is no row with index '$key'" unless defined $a;
        return $a->[$index];
    };
}

sub field_settor {
    my ($s, $column) = @_;
    my $index = $s->column_index($column);
    return sub {
        my ($key, $value) = @_;
        my $a = $s->[2]{$key};
        $a = $s->[2]{$key} = [] unless defined $a;
        $a->[$index] = $value;
        return undef;
    };
}

sub set_row {
    my ($s, $key, @fields) = @_;
    $s->[2]{$key} = [@fields];
}

sub field {
    my ($s, $key, $column) = @_;
    my $a = $s->[2]{$key};
    croak "There is no row with index '$key'" unless defined $a;
    return $a->[$s->column_index($column)];
}

sub set_field {
    my ($s, $key, $column, $value) = @_;
    my $a = $s->[2]{$key};
    $a = $s->[2]{$key} = [] unless defined $a;
    $a->[$s->column_index($column)] = $value;
}

sub inc_field {
    my ($s, $key, $column, $adder) = @_;
    my $a = $s->[2]{$key};
    $a = $s->[2]{$key} = [] unless defined $a;
    $a->[$s->column_index($column)] += $adder;
}

sub each_record {
    my ($s) = @_;
    my @e = each %{$s->[2]};
    if (@e) {
        return ($e[0], @{$e[1]});
    }
    else {
        return ();
    }
}

sub record_exists {
    my ($s, $key) = @_;
    return exists($s->[2]{$key});
}

sub delete_record {
    my ($s, $key) = @_;
    delete($s->[2]{$key});
}

sub clear_table {
    my ($s) = @_;
    %{$s->[2]} = ();
}

sub touch { 1 }

sub ref {
	return $_[0];
}

sub version { $Vend::Table::InMemory::VERSION }

1;
