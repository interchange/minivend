# Table/DBI.pm: access a table stored in an DBI/DBD Database
#
# $Id: DBI.pm,v 1.3 1997/05/22 07:00:32 mike Exp $
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

package Vend::Table::DBI;
$VERSION = substr(q$Revision: 1.3 $, 10);

use Carp;
use strict;
use DBI;

my $Db;
$Db = DBI->install_driver($Global::DBDtype);

my @Hex_string;
{
    my $i;
    foreach $i (0..255) {
        $Hex_string[$i] = sprintf("%02X", $i);
    }
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
	my ($config) = @_;
	croak "Need a host and database!\n" unless ref $config;
	if($Global::DBDtype eq 'mSQL') {
		return $Db->connect($config->{Host}, $config->{Catalog});
	}
	elsif($Global::DBDtype eq 'Solid') {
		return $Db->connect("", "mike", "gsfrkc", $Global::DBDtype);
	}
	else {
#print("Connected to Pg.\n") if $Global::DEBUG;
		return $Db->connect($config->{Catalog}, '', '', $Global::DBDtype);
	}
}

sub create {
    my ($class, $columns, $tablename, $config) = @_;

	$config = { Host => 'localhost', Catalog => 'minivend' }
		unless defined $config;
	
	my $db = opendb($config)
		or croak "The '$config->{Catalog}' database is not present: $DBI::errstr\n";

    croak "columns argument $columns is not an array ref\n"
        unless ref($columns) eq 'ARRAY';

    my ($i,$key);
	my(@cols);
	unshift @$columns, 'CODE';
    for ($i = 0;  $i < @$columns;  $i++) {
        $cols[$i] .= $$columns[$i];
        $cols[$i] .= " char(64)" unless $cols[$i] =~ / +/;
		$key = $$columns[$i] if $cols[$i] =~ /\s+int\s+primary\s+key$/i;
    }

	if(! $key) {
		$cols[0] =~ s/\s+.*/ char(14) primary key/
			if $Global::DBDtype eq 'mSQL';
		$key = $columns->[0];
		carp "DBI: column 0 overridden and made primary key.\n"
			if $Global::DBDtype eq 'mSQL';
	}

	if($Global::DBDtype eq 'mSQL'
			and grep $_ eq $tablename, $db->func('_ListTables')) {
		$db->do("drop table $tablename") 
			or croak
			"The '$tablename' table could not be overwritten.\n$DBI::errstr\n";
	}

	if($Global::DBDtype eq 'Solid' and table_exists($db, $tablename)) {
		$db->do("drop table $tablename") 
			or croak
			"The '$tablename' table could not be overwritten.\n$DBI::errstr\n";
	}
#print("cols: '" . (join "','", @cols) . "'\n") if $Global::DEBUG;
	my $query = "create table $tablename ( \n";
	$query .= join ",\n", @cols;
	$query .= "\n)\n";
	::logError("table $tablename created: $query");
	
	$db->do($query)
		or croak "DBI: Create table '$tablename' failed: "
					. $DBI::errstr . "\n";
#print("Created table, I think.\n") if $Global::DEBUG;
    my $self = [$tablename, $key, $db];
    bless $self, $class;
}


sub open_table {
    my ($class, $config, $tablename) = @_;
	$config = { Host => 'localhost', Catalog => 'minivend' }
		unless defined $config;
	my $db = opendb($config)
		or croak "The '$config->{Catalog}' database is not present.\n";
	my $key;
	if($Global::DBDtype eq 'mSQL') {
		my $ref = $db->func($tablename, '_ListFields')
			or croak "No fields in database $config->{Catalog}?\n";
		my @keys = @{$ref->{IS_PRI_KEY}};
		my $i = 0;
		for (@keys) {
			($i++, next) unless $_;
			$key = $ref->{NAME}->[$i];
		}
		croak "DBI: no primary key for $tablename\n"
			unless defined $key;
	}
	else {
		my @keys = list_fields($db, $tablename);
		$key = $keys[0];
		croak "DBI: no primary key for $tablename\n"
			unless defined $key;
	}

#print("Opened table, I think.\n") if $Global::DEBUG;
	my $dbref = [$tablename, $key, $db];
	bless $dbref, $class;
}

sub close_table {
	undef $_[0];
	1;
}


sub columns {
    my ($s) = @_;
	return list_fields($s->[2], $s->[0]);
}

#sub columns {
#    my ($s) = @_;
#	my $ref = $s->[2]->func($s->[0], '_ListFields');
#    return @{$ref->{NAME}};
#}


sub test_column {
    my ($s, $column) = @_;

	#my $ref = $s->[2]->func($s->[0], '_ListFields');
	my @cols = list_fields($s->[2], $s->[0]);
	(::logGlobal("test_column: " . $DBI::errstr), return '')
		unless @cols;

	my $i = 0;
	my $col;

	for(@cols) {
	#for(@{$ref->{NAME}}) {
		($i++, next) unless $_ eq $column;
		$col = $i;
	}

#print("test_column: returning '$col' from $s->[0]") if $Global::DEBUG;
	return $col - 1;

}

sub column_index {
    my ($s, $column) = @_;

	#my $ref = $s->[2]->func($s->[0], '_ListFields');
	my @cols = list_fields($s->[2], $s->[0]);

	my $i = 0;
	my $col;

	for(@cols) {
	#for(@{$ref->{NAME}}) {
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
        my $ref = $s->[2]->prepare
			("select $column from $s->[0] where $s->[1] = '$key'");
		(::logGlobal("field_accessor:" . $DBI::errstr), return '')
			unless defined $ref;
		($ref->fetchrow)[0];
    };
}

sub param_query {
	my($text, $config) = @_;
	my ($r,$ref);
	$config = { Host => 'localhost', Catalog => 'minivend' }
		unless ref $config;
	my $db = opendb($config)
		or croak "The '$config->{Catalog}' database is not present.\n";
    eval { $ref = $db->do($text) };
	(::logGlobal("Bad DBI query --\n$text"), return '')
		if $@;
	(::logError("param_query:" . $DBI::errstr), return '')
		unless defined $ref;
	my(@row);
	my(@out);
	while(@row = $ref->fetchrow()) {
		push @out, @row;
	}
	$r = '"';
	for(@out) { s/"/\\"/g }
	$r .= join '" "', @out;
	$r .= '"';
}

sub array_query {
    my($text, $config) = @_;
    my ($r,$ref);
    $config = { Host => 'localhost', Catalog => 'minivend' }
        unless ref $config;
    my $db = opendb($config)
        or croak "The '$config->{Catalog}' database is not present.\n";
    eval { $ref = $db->do($text) };
    (::logGlobal("Bad DBI query --\n$text"), return '')
        if $@;
    (::logError("param_query:" . $DBI::errstr), return '')
        unless defined $ref;
	my(@row);
	my(@out);
	while(@row = $ref->fetchrow()) {
		push @out, [@row];
	}
	return \@out;
}

sub hash_query {
    my($text, $config) = @_;
    my ($i,$ref);
    my $db = opendb();
    $db->selectdb($config->{Catalog})
        or croak "The '$config->{Catalog}' SQL database is not present.\n";
    eval { $ref = $db->do($text) };
	(::logGlobal("Bad SQL query --\n$text"), return '')
		if $@;
	(::logError("hash_query: $DBI::errstr"), return '')
		unless defined $ref;
	my(@row);
	my(%out);
	my(@name) = $ref->name();
	while(@row = $ref->fetchrow()) {
		my $o = {};
		for($i = 0; $i < @name; $i++) {
			$o->{$name[$i]} = $row[$i];
		}
		$out{$row[0]} = $o;
	}
	return \%out;
}

sub html_query {
    my($text, $config) = @_;
    my ($r,$i,$ref);
    my $db = opendb();
    $db->selectdb($config->{Catalog})
        or croak "The '$config->{Catalog}' SQL database is not present.\n";
    eval { $ref = $db->do($text) };
	(::logGlobal("Bad SQL query --\n$text"), return '')
		if $@;
	(::logError("html_query: $DBI::errstr"), return '')
		unless defined $ref;
	my(@row);
	my(@name) = $ref->name();
	$r = '<TR>';
	for(@name) {
		$r .= "<TH><B>$_</B></TH>";
	}
	$r .= '</TR>';
	while(@row = $ref->fetchrow()) {
		$r .= "<TR>";
		for(@row) {
			$r .= "<TD>$_</TD>";
		}
		$r .= "</TR>";
	}
	$r;
}

sub set_query {
    my($text, $config) = @_;
    my ($r,$ref,$result);
    my $db = opendb();
    $db->selectdb($config->{Catalog})
        or croak "The '$config->{Catalog}' SQL database is not present.\n";
    eval { $result = $db->do($text) };
	(::logGlobal("Bad SQL query --\n$text"), return '')
		if $@;
	::logError("set_query: $DBI::errstr") unless defined $result;
	return '';
}

# not supported
sub each_record {
    return undef;
}

sub field_settor {
    my ($s, $column) = @_;
    return sub {
        my ($key, $value) = @_;
        $s->[2]->do("insert into $s->[0] ($column) VALUES ($value) where $s->[1] = '$key'");
    };
}

sub set_row {
    my ($s, $key, @fields) = @_;
	for(@fields) {
		s/'/\\'/g;
	}
	#::logGlobal("Got to set_row");
	my $values = "'" . (join "', '", $key, @fields) . "'";
    $s->[2]->do("delete from $s->[0] where $s->[1] = '$key'");
    $s->[2]->do("insert into $s->[0] VALUES ($values)")
		or croak "$DBI::errstr\n";
}

sub field {
    my ($s, $key, $column) = @_;
    my $ref = $s->[2]->prepare("select $column from $s->[0] where $s->[1] = '$key'");
    $ref->execute()
		or (::logGlobal("execute error: $DBI::errstr"), return '');
#print("field: col=$column key=$key err=$DBI::errstr") if $Global::DEBUG;
	my $data = ($ref->fetchrow())[0];
#print("field: col=$column key=$key err=$DBI::errstr") if $Global::DEBUG;
	$data;
}

sub set_field {
    my ($s, $key, $column, $value) = @_;
    my $ref = $s->[2]->do("insert into $s->[0] ($column) VALUES ($value) where $s->[1] = '$key'");
	$value;
}

sub ref {
	return $_[0];
}

sub record_exists {
    my ($s, $key) = @_;
    my $what = ($s->[2]->do("select * from $s->[0] where $s->[1] = '$key'"));
	(::logGlobal("Bad SQL query --\n$_[0]\n$DBI::errstr" ), return undef)
		unless defined $what;
    return defined $what;
}

sub delete_record {
    my ($s, $key) = @_;

    $s->[2]->do("delete from $s->[0] where $s-[1] = '$key'");
}

sub list_fields {
	my($db, $name) = @_;
	my $sth = $db->prepare("select * from $name");
	$sth->execute();

	# DEBUG
	#my $msg = "names: '";
	#$msg .= join "','", @{$sth->{NAME}};
	#$msg .= "'";
	#::logGlobal($msg);

	my @fld = @{$sth->{NAME}};
	return @fld;
}

sub table_exists {
	my ($dbh, $name) = @_;
	my($rc, @row);
	my $sth = $dbh->prepare(<<EOF);
	SELECT 1
	FROM tables
WHERE table_name = '$name'
EOF

	croak "$DBI::errstr\n" unless $sth;
	$sth->execute() or croak "$DBI::errstr\n";
	if(@row = $sth->fetchrow()) {
		$rc = $row[0];
	}
	$sth->finish() or croak "$DBI::errstr\n";
	$rc;
}

sub version { $Vend::Table::DBI::VERSION }

1;
