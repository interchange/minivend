# Table/GDBM.pm: access a table stored in a GDBM file
#
# $Id: GDBM.pm,v 1.11 1999/02/15 08:51:50 mike Exp mike $
#

# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
# Copyright 1996-1999 by Mike Heins <mikeh@minivend.com>
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
$VERSION = substr(q$Revision: 1.11 $, 10);
use strict;
use GDBM_File;

use vars qw($Storable);

# See if we can do Storable
BEGIN {
	eval {
		die unless $ENV{MINIVEND_STORABLE_DB};
		require Storable;
		$Storable = 1;
	};
}

my @Hex_string;
{
    my $i;
    foreach $i (0..255) {
        $Hex_string[$i] = sprintf("%%%02X", $i);
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
# 5: configuration

my ($FILENAME, $COLUMN_NAMES, $COLUMN_INDEX, $TIE_HASH, $DBM, $CONFIG) = (0 .. 5);

sub config {
	my ($self, $key, $value) = @_;
	return $self->[$CONFIG]{$key} unless defined $value;
	$self->[$CONFIG]{$key} = $value;
}

sub create {
    my ($class, $config, $columns, $filename) = @_;

    $config = {} unless defined $config;
    my ($File_permission_mode, $Fast_write)
        = @$config{'File_permission_mode', 'Fast_write'};
    $File_permission_mode = 0666 unless defined $File_permission_mode;
    $Fast_write = 1 unless defined $Fast_write;

    die "columns argument $columns is not an array ref\n"
        unless ref($columns) eq 'ARRAY';

    # my $column_file = "$filename.columns";
    # my @columns = @$columns;
    # open(COLUMNS, ">$column_file")
    #    or die "Couldn't create '$column_file': $!";
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
        or die "Could not create '$filename': $!";

    $tie->{'c'} = join("\t", @$columns);

    my $self = [$filename, $columns, $column_index, $tie, $dbm, $config];
    bless $self, $class;
}


sub open_table {
    my ($class, $config, $filename) = @_;
    my ($Fast_write, $Read_only) = @$config{'Fast_write', 'Read_only'};
    my $tie = {};

    my $flags = GDBM_WRITER;

    if ($Read_only) {
        $flags = GDBM_READER;
    }
    else {
        $flags |= GDBM_FAST if $Fast_write;
    }

	my $dbm;
    my $failed = 0;

    while( $failed < 10 ) {
        $dbm = tie(%$tie, 'GDBM_File', $filename, $flags, 0600)
            and undef($failed), last;
        $failed++;
        select(undef,undef,undef,$failed * .100);
    }

    die("Could not tie to '$filename': $!")
        if $failed;

    my $columns = [split(/\t/, $tie->{'c'})];

    my $column_index = {};
    my $i;
    for ($i = 0;  $i < @$columns;  ++$i) {
        $column_index->{$columns->[$i]} = $i;
    }

    my $self = [$filename, $columns, $column_index, $tie, $dbm, $config];
    bless $self, $class;
}

sub close_table {
    my ($s) = @_;
	splice(@$s, $DBM, 1);
	my $ref = splice(@$s, $TIE_HASH, 1);
    untie %$ref or die "Could not close GDBM table $s->[$FILENAME]: $!\n";
}


sub columns {
    my ($s) = @_;
    return @{$s->[$COLUMN_NAMES]};
}


sub test_column {
    my ($s, $column) = @_;
    return $s->[$COLUMN_INDEX]{$column};
}

sub column_index {
    my ($s, $column) = @_;
    my $i = $s->[$COLUMN_INDEX]{$column};
    die "There is no column named '$column'" unless defined $i;
    return $i;
}

sub row_hash {
    my ($s, $key) = @_;
	my %row;
    @row{ @{$s->[$COLUMN_NAMES]} } = $s->row($key);
	return \%row;
}

sub unstuff_row {
    my ($s, $key) = @_;
    my $line = $s->[$TIE_HASH]{"k$key"};
    die "There is no row with index '$key'" unless defined $line;
    return map(unstuff($_), split(/\t/, $line, 9999));
}

sub thaw_row {
    my ($s, $key) = @_;
    my $line = $s->[$TIE_HASH]{"k$key"};
    die "There is no row with index '$key'" unless defined $line;
    return @{ Storable::thaw($line) };
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

sub stuff_row {
    my ($s, $key, @fields) = @_;
    my $line = join("\t", map(stuff($_), @fields));
    $s->[$TIE_HASH]{"k$key"} = $line;
}

sub freeze_row {
    my ($s, $key, @fields) = @_;
    $s->[$TIE_HASH]{"k$key"} = Storable::freeze(\@fields);
}

if($Storable) {
	*set_row = \&freeze_row;
	*row = \&thaw_row;
}
else {
	*set_row = \&stuff_row;
	*row = \&unstuff_row;
}


sub field {
    my ($s, $key, $column) = @_;
    return ($s->row($key))[$s->column_index($column)];
}

sub set_field {
    my ($s, $key, $column, $value) = @_;
    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to set $s->[$CONFIG]{name}::${column}::$key in read-only table");
		return undef;
	}
    my @row = $s->row($key);
    $row[$s->column_index($column)] = $value;
    $s->set_row($key, @row);
	$value;
}

sub inc_field {
    my ($s, $key, $column, $adder) = @_;
    my($value);
    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to set $s->[$CONFIG]{name}::${column}::$key in read-only table");
		return undef;
	}
    my @row = $s->row($key);
    $value = $row[$s->column_index($column)] += $adder;
    $s->set_row($key, @row);
    $value;
}

sub touch {
    my ($s) = @_;
    my $now = time();
    utime $now, $now, $s->[$FILENAME];
}

sub ref {
	return $_[0];
}

sub each_record {
    my ($s) = @_;
    my $key;

    for (;;) {
        $key = each %{$s->[3]};
        if (defined $key) {
            if ($key =~ s/^k//) {
                return ($key, $s->row($key));
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
    my $r = $s->[$DBM]->EXISTS("k$key");
    return $r;
}

*test_record = \&record_exists;

sub delete_record {
    my ($s, $key) = @_;
    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to delete row '$key' in read-only table $s->[$CONFIG]{name}");
		return undef;
	}

    delete $s->[$TIE_HASH]{"k$key"};
	1;
}

sub version { $Vend::Table::GDBM::VERSION }

1;
