# Table/Msql.pm: access a table stored in an Msql Database
#
# $Id: Msql.pm,v 1.8 1997/09/08 04:24:49 mike Exp $
#

# Basic schema
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Coding
# Copyright 1996 by Michael J. Heins <mikeh@iac.net>
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

package Vend::Table::Msql;
$VERSION = substr(q$Revision: 1.8 $, 10);

use Carp;
use strict;
use Msql;

$Msql::QUIET = 1;

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

my ($FILENAME, $COLUMN_NAMES, $COLUMN_INDEX, $TIE_HASH, $DBM) = (0 .. 4);

sub create_table {
    my ($class, $config, $filename, $columns) = @_;

    return $class->create($columns, $filename, $config);
}

sub opendb {
	Msql->connect();
}

sub drop_table {
	my ($db, $table) = @_;
    if(grep $_ eq $table, $db->list_tables) {
        $db->query("drop table $table")
            or croak "The '$table' table could not be overwritten.\n";
    }
}

sub test_version {
	my ($db) = @_;

    drop_table($db, 'mv_test_version');

    my $query = <<EOF;
create table mv_test_version ( code char(14) primary key, testdata char(4) )
EOF
    my ($status, $rc);
    eval { $status = $db->query($query) };

    if(! $status or $@) {
		$rc = 2;
	}
	else {
		$rc = 1;
	}
    drop_table($db, 'mv_test_version');
	return $rc;
}


sub config { return undef }

sub ref {
	return $_[0];
}

sub create {
    my ($class, $columns, $tablename, $config) = @_;

	$config = { Catalog => 'minivend' }
		unless defined $config;
	
	my $db = opendb();

	$db->selectdb($config->{Catalog})
		or croak "The '$config->{Catalog}' Msql database is not present.\n";

    croak "columns argument $columns is not an array ref\n"
        unless ref($columns) eq 'ARRAY';

    my $column_index = {};
    my ($i,$key,$query,$version);
	my(@cols);
	unshift @$columns, 'code';

	# See if we are Msql 1 or 2;

	$version = test_version($db)
				or croak ("Couldn't check mSQL version.\n");

    for ($i = 0;  $i < @$columns;  ++$i) {
        $cols[$i] .= $columns->[$i];
        $cols[$i] .= " char(128)" unless $cols[$i] =~ / +/;
		$key = $columns->[$i] if $cols[$i] =~ s/\s+primary\s+key$//i;
    }

	if(! $key) {
		$cols[0] .= ' primary key' if $version == 1;
		$key = $columns->[0];
		carp "Msql: column 0 overridden and made primary key.\n";
	}

	drop_table($db, $tablename);

	$query = "create table $tablename ( \n";
	$query .= join ",\n", @cols;
	$query .= "\n)\n";
	::logError("table $tablename created: $query");
	
	$db->query($query)
		or croak "Msql: Create table '$tablename' failed: "
					. $db->errmsg() . "\n";

	if($version > 1) {
		$query = "create index ${key}_idx on $tablename ($key)";
	
		$db->query($query)
			or croak $db->errmsg();
	}

	
    my $self = [$tablename, $key, $db];
    bless $self, $class;
}

sub get_msql {
	my $class = shift;
	bless [@_], $class;
}

sub open_table {
    my ($class, $config, $tablename) = @_;
	my $db = opendb();
	$db->selectdb($config->{Catalog})
		or croak "The '$config->{Catalog}' Msql database is not present.\n";
	my $key;
	my $sth_query = $db->query("select * from $tablename")
		or croak $db->errmsg();
	my $sth_listf = $db->listfields($tablename)
		or croak $db->errmsg();

	$key = $sth_listf->name()->[0];

 	for (1..$sth_query->numfields -1) {
		# whatever we do to the one statementhandle, the other one has
		# to behave exactly the same way
		if ($sth_listf->is_pri_key()->[$_]) {
			$key = $sth_listf->name()->[$_];
			last;
		} 
    }

	my $dbref = [$tablename, $key, $db];
	bless $dbref, $class;
	
}

sub close_table {
	undef $_[0];
	1;
}

sub touch {return ''}

# Now supported
sub each_record {
    my ($s) = @_;
	my ($table,$key,$db, $each) = @$s;
	unless(defined $each) {
#print("Each not defined -- listing table $table for $db\n") if $Global::DEBUG;
		$each = $db->query("select * from $table")
			or croak $db->errmsg();
		push @$s, $each;
	}
	my @cols = $each->fetchrow;
#print("Cols for Msql each_record:\n--\n@cols\n--\n") if $Global::DEBUG;
	pop(@$s) unless(scalar @cols);
	return @cols;
}

sub columns {
    my ($s) = @_;
	my $sth = $s->[2]->listfields($s->[0]);
    my @cols = $sth->name();
	shift @cols;
	return @cols;
}


sub test_column {
    my ($s, $column) = @_;

	my $sth = $s->[2]->listfields($s->[0]);
	(::logGlobal("test_column: " . $s->[2]->errmsg()), return '')
		unless defined $sth;

	my(@names) = $sth->name();

	my $i = 0;
	my $col;

	for(@names) {
		($i++, next) unless $_ eq $column;
		$col = $i;
	}

	return undef unless defined $col;
	return $col - 1;

}

sub column_index {
    my ($s, $column) = @_;

	my $sth = $s->[2]->listfields($s->[0]);
	my(@names) = $sth->name();

	my $i = 0;
	my $col;

	for(@names) {
		($i++, next) unless $_ eq $column;
		$col = $i;
	}

    unless($col) {
		croak "There is no column named '$column'\n";
		return undef;
	}
	return $col;

}

sub field_accessor {
    my ($s, $column) = @_;
    return sub {
        my ($key) = @_;
        my $sth = $s->[2]->query("select $column from $s->[0] where $s->[1] = '$key'");
		(::logGlobal("field_accessor:" . $s->[2]->errmsg()), return '')
			unless defined $sth;
		($sth->fetchrow)[0];
    };
}

sub param_query {
	my($s, $text, $config) = @_;
	my ($r,$sth);
	$config = $Vend::Cfg->{MsqlDB} if $config eq 'products';
	my $db = opendb();
	$db->selectdb($config)
		or croak "The '$config' Msql database is not present.\n";
    eval { $sth = $db->query($text) };
	(::logGlobal("Bad mSQL query --\n$text"), return '')
		if $@;
	(::logError("param_query:" . $db->errmsg()), return '')
		unless defined $sth;
	my(@row);
	my(@out);
	while(@row = $sth->fetchrow()) {
		push @out, @row;
	}
	$r = '"';
	for(@out) { s/"/\\"/g }
	$r .= join '" "', @out;
	$r .= '"';
}

sub array_query {
    my($s, $text, $config) = @_;
    my ($sth);
    $config = $Vend::Cfg->{MsqlDB} if $config eq 'products';
    my $db = opendb();
    $db->selectdb($config)
        or croak "The '$config' Msql database is not present.\n";

    eval { $sth = $db->query($text) };
	(::logGlobal("Bad mSQL query --\n$text"), return '')
		if $@;
	(::logError("array_query:" . $db->errmsg()), return '')
		unless defined $sth;
	my(@row);
	my(@out);
	while(@row = $sth->fetchrow()) {
		push @out, [@row];
	}
	return \@out;
}

sub hash_query {
    my($s, $text, $config) = @_;
    my ($i,$sth);
    $config = $Vend::Cfg->{MsqlDB} if $config eq 'products';
    my $db = opendb();
    $db->selectdb($config)
        or croak "The '$config' Msql database is not present.\n";

    eval { $sth = $db->query($text) };
	(::logGlobal("Bad mSQL query --\n$text"), return '')
		if $@;
	(::logError("hash_query:" . $db->errmsg()), return '')
		unless defined $sth;
	my(@row);
	my(%out);
	my(@name) = $sth->name();
	while(@row = $sth->fetchrow()) {
		my $o = {};
		for($i = 0; $i < @name; $i++) {
			$o->{$name[$i]} = $row[$i];
		}
		$out{$row[0]} = $o;
	}
	return \%out;
}

sub html_query {
    my($s, $text, $config) = @_;
    my ($r,$i,$sth);
    $config = $Vend::Cfg->{MsqlDB} if $config eq 'products';
    my $db = opendb();
    $db->selectdb($config)
        or croak "The '$config' Msql database is not present.\n";
    eval { $sth = $db->query($text) };
	(::logGlobal("Bad mSQL query --\n$text"), return '')
		if $@;
	(::logError("html_query:" . $db->errmsg()), return '')
		unless defined $sth;
	my(@row);
	my(@name) = $sth->name();
	$r = '<TR>';
	for(@name) {
		$r .= "<TH><B>$_</B></TH>";
	}
	$r .= '</TR>';
	while(@row = $sth->fetchrow()) {
		$r .= "<TR>";
		for(@row) {
			$r .= "<TD>$_</TD>";
		}
		$r .= "</TR>";
	}
	$r;
}

sub set_query {
    my($s, $text, $config) = @_;
    my ($r,$sth,$result);
    $config = $Vend::Cfg->{MsqlDB} if $config eq 'products';
    my $db = opendb();
    $db->selectdb($config)
        or croak "The '$config' Msql database is not present.\n";
    eval { $result = $db->query($text) };
	(::logGlobal("Bad mSQL query --\n$text"), return '')
		if $@;
	::logError("set_query:" . $db->errmsg()) unless defined $result;
	return '';
}

sub field_settor {
    my ($s, $column) = @_;
    return sub {
        my ($key, $value) = @_;
        $s->[2]->query("update $s->[0] SET $column='$value' where $s->[1] = '$key'");
    };
}

sub set_row {
    my ($s, $key, @fields) = @_;
	my($i);

	my $sth = $s->[2]->listfields($s->[0])
		or croak $s->[2]->errmsg();
	my(@type) = $sth->type;

	unshift(@fields, $key);
	for($i = 0; $i < $sth->numfields; $i++) {
		if ($type[$i] == Msql::CHAR_TYPE) {
			$fields[$i] = $s->[2]->quote($fields[$i]);
		}
##print("field=$fields[$i]\n") if $Global::DEBUG;
	}

	my $values = join ", ", @fields;
    $s->[2]->query("delete from $s->[0] where $s->[1] = '$key'");
    $s->[2]->query("insert into $s->[0] VALUES ($values)")
		or croak $s->[2]->errmsg();
}

sub field {
    my ($s, $key, $column) = @_;
    my $sth = $s->[2]->query("select $column from $s->[0] where $s->[1] = '$key'");
	croak $s->[2]->errmsg . ": $!\n" unless defined $sth;
	($sth->fetchrow)[0];
}

sub set_field {
    my ($s, $key, $column, $value) = @_;
    my $sth = $s->[2]->query("update $s->[0] SET $column='$value' where $s->[1] = '$key'");
	$value;
}

sub inc_field {
    my ($s, $key, $column, $value) = @_;
    my $sth = $s->[2]->query("select $column from $s->[0] where $s->[1] = '$key'");
	(::logError("inc_field: " . $s->[2]->errmsg()), return '')
		unless defined $sth;
	$value += ($sth->fetchrow)[0];
	undef $sth;
    $sth = $s->[2]->query("update $s->[0] SET $column='$value' where $s->[1] = '$key'");
	$value;
}

sub record_exists {
    my ($s, $key) = @_;
    my $what = ($s->[2]->query("select * from $s->[0] where $s->[1] = '$key'"));
	(::logGlobal("Bad mSQL query --\n$_[0]\n" . $s->[2]->errmsg()), return undef)
		unless defined $what;
    return defined $what;
}

sub delete_record {
    my ($s, $key) = @_;

    $s->[2]->query("delete from $s->[0] where $s->[1] = '$key'");
}

sub version { $Vend::Table::Msql::VERSION }

1;
