# Table/DBI.pm: access a table stored in an DBI/DBD Database
#
# $Id: DBI.pm,v 1.14 1998/01/31 05:22:52 mike Exp $
#
# Copyright 1996-1998 by Michael J. Heins <mikeh@minivend.com>
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
$VERSION = substr(q$Revision: 1.14 $, 10);

use Carp;
use strict;

# 0: table name
# 1: key name
# 2: database object
# 3: Array of column names
# 4: each reference (transitory)

my ($TABLE, $KEY, $DBI, $NAME, $CONFIG, $EACH) = (0 .. 5);

my %Cattr = ( qw(
					PRINTERROR     	PrintError
					AUTOCOMMIT     	AutoCommit
				) );

my %Dattr = ( qw(
					WARN			Warn
					CHOPBLANKS		ChopBlanks	
					COMPATMODE		CompatMode	
					INACTIVEDESTROY	InactiveDestroy	
					PRINTERROR     	PrintError
					RAISEERROR     	RaiseError
					AUTOCOMMIT     	AutoCommit
					LONGTRUNCOK    	LongTruncOk
					LONGREADLEN    	LongReadLen
				) );

#my %Dattr = ( qw( AUTOCOMMIT AutoCommit	) );
					
sub find_dsn {
	my ($config) = @_;
	my($param, $value, $cattr, $dattr, @out);
	my($user,$pass,$dsn,$driver);
	my $i = 0;
	foreach $param (qw! DSN USER PASS !) {
		$out[$i++] = $config->{ $param } || undef;
	}
	foreach $param (keys %$config) {
		if(defined $Dattr{$param}) {
			$dattr = { AutoCommit => 1, PrintError => 1 }
				unless defined $dattr;
			$dattr->{$Dattr{$param}} = $config->{$param};
		}
		next unless defined $Cattr{$param};
		$cattr = {} unless defined $cattr;
		$cattr->{$Cattr{$param}} = $config->{$param};
	}
	$out[3] = $cattr || undef;
	$out[4] = $dattr || undef;
# DEBUG
#    if (::debug(0x4) and defined $dattr) {
#		my $msg = "connect args were: ";
#		my @dbg = @out;
#		pop @dbg;
#		for(keys %$dattr) {
#			push @dbg, "$_=$dattr->{$_}";
#		}
#		$msg .= join "|", @dbg, "\n";
#		Vend::Util::logDebug($msg);
#	}
# END DEBUG
	@out;
}

sub create_table {
    my ($class, $config, $filename, $columns) = @_;

    return $class->create($columns, $filename, $config);
}

sub config {
	my $s = shift;
	return undef
		unless defined $s->[$CONFIG]->{$_[0]};
	$s->[$CONFIG]->{$_[0]};
}
	

sub create {
    my ($class, $columns, $tablename, $config) = @_;

	my @call = find_dsn($config);
	my $dattr = pop @call;
	my $db = DBI->connect( @call )
		or croak "DBI connect failed: $DBI::errstr\n";
# DEBUG
#Vend::Util::logDebug
#("trying to create $tablename\n")
#	if ::debug(0x4);
#$db->trace(2) if ::debug(0x4);
#Vend::Util::logDebug
#("connected\n")
#	if ::debug(0x4);
# END DEBUG
    croak "columns argument $columns is not an array ref\n"
        unless ref($columns) eq 'ARRAY';

	if(defined $dattr) {
		for(keys %$dattr) {
			$db->{$_} = $dattr->{$_};
		}
	}

# DEBUG
#Vend::Util::logDebug
#("ChopBlanks: '" . $db->{ChopBlanks} . "'\n")
#	if ::debug(0x4);
# END DEBUG

    my ($i, $key, $keycol, $first);
	my(@cols);

	# Call the first column 'code' unless it is set
	# explicitly by NAME or FIRST_COLUMN_NAME
	if(defined $config->{NAME}) {
		$first = $config->{NAME}->[0] || 'code';
	}
	else {
		$first = $config->{FIRST_COLUMN_NAME} || 'code';
	}

	$key = $config->{KEY} || $first;

	unshift @$columns, $first;

# DEBUG
#	if(::debug(0x4) and defined $config->{COLUMN_DEF}) {
#		my $msg;
#		for (keys %{$config->{COLUMN_DEF}}) {
#			$msg .= "def $_=$config->{COLUMN_DEF}->{$_}\n";
#		}
#		logDebug($msg);
#	}
# END DEBUG

    for ($i = 0;  $i < @$columns;  $i++) {
        $cols[$i] = $$columns[$i];
		if(defined $config->{KEY}) {
			$keycol = $i if $cols[$i] eq $key;
		}
        if ($cols[$i] =~ / +/) {
			# do nothing
		}
		elsif(defined $config->{COLUMN_DEF}->{$cols[$i]}) {
			$cols[$i] .= " " . $config->{COLUMN_DEF}->{$cols[$i]};
		}
		else {
			$cols[$i] .= " char(128)";
		}
		$$columns[$i] = $cols[$i];
		$$columns[$i] =~ s/\s+.*//;
    }

	$keycol = 0 unless defined $keycol;

	$cols[$keycol] =~ s/\s+.*/ char(16)/
			unless defined $config->{COLUMN_DEF}->{$key};

	$db->do("drop table $tablename")
		or carp "$DBI::errstr\n";

# DEBUG
#Vend::Util::logDebug
#("cols: '" . (join "','", @cols) . "'\n")
#	if ::debug(0x4);
# END DEBUG
	my $query = "create table $tablename ( \n";
	$query .= join ",\n", @cols;
	$query .= "\n)\n";
	
	$db->do($query)
		or croak "DBI: Create table '$tablename' failed: $DBI::errstr\n";
	::logError("table $tablename created: $query");

	$db->do("create index ${key}_idx on $tablename ($key)")
		or ::logError("table $tablename index failed: $DBI::errstr");
# DEBUG
#Vend::Util::logDebug
#("Created table, I think.\n")
#	if ::debug(0x4);
# END DEBUG

	$config->{NAME} = $columns;

    my $self = [$tablename, $key, $db, $columns, $config];
    bless $self, $class;
}

sub open_table {
    my ($class, $config, $tablename) = @_;
	
    my @call = find_dsn($config);
    my $dattr = pop @call;
    my $db = DBI->connect( @call )
		or croak "$DBI::errstr\n";
# DEBUG
#$db->trace(2) if $Global::DEBUG & $GLOBAL::DHASH{DATA};
# END DEBUG
	my $key;
	my $cols;

	if(defined $dattr) {
		for(keys %$dattr) {
			$db->{$_} = $dattr->{$_};
		}
	}
# DEBUG
#Vend::Util::logDebug
#("ChopBlanks: '" . $db->{ChopBlanks} . "'\n")
#	if ::debug(0x4);
# END DEBUG

	$cols = $config->{NAME} || [list_fields($db, $tablename)];

	$config->{NUMERIC} = {} unless $config->{NUMERIC};

	croak "DBI: no column names returned for $tablename\n"
			unless defined $$cols[1];

	# Check if we have a non-first-column key
	$key = $config->{KEY} || $$cols[0];
	$config->{FIRST_COLUMN_NAME} = $$cols[0];

	my $dbref = [$tablename, $key, $db, $cols, $config];
	bless $dbref, $class;
}

sub close_table {
	$_[0]->[$DBI]->disconnect();
}

sub columns {
    my @cols = @{$_[0]->[$NAME]};
	shift @cols;
	@cols;
}

sub test_column {
    my ($s, $column) = @_;

	my $i = 0;
	my $col;

	for(@{$s->[$NAME]}) {
		($i++, next) unless "\L$_" eq "\L$column";
		$col = $i;
	}
# DEBUG
#Vend::Util::logDebug
#("test_column: returning '$col' from $s->[$TABLE]\n")
#	if ::debug(0x4);
# END DEBUG
	return undef unless defined $col;

	return $col - 1;

}

sub quote {
	return $_[0]->[$DBI]->quote($_[1]);
}

sub numeric {
# DEBUG
#Vend::Util::logDebug
#("called numeric with @_: status=")
#	if ::debug(0x4);
# END DEBUG
	my $status = exists $_[0]->[$CONFIG]->{NUMERIC}->{$_[1]};
# DEBUG
#Vend::Util::logDebug
#("$status\n")
#	if ::debug(0x4);
# END DEBUG
	return exists $_[0]->[$CONFIG]->{NUMERIC}->{$_[1]};
}

sub inc_field {
    my ($s, $key, $column, $value) = @_;
	$key = $s->[$DBI]->quote($key)
		unless defined $s->[$CONFIG]->{NUMERIC}->{$key};
	$value = $s->[$DBI]->quote($value)
		unless defined $s->[$CONFIG]->{NUMERIC}->{$column};
    my $sth = $s->[$DBI]->prepare(
		"select $column from $s->[$TABLE] where $s->[$KEY] = $key");
    croak "inc_field: $DBI::errstr\n" unless defined $sth;
    $sth->execute();
    $value += ($sth->fetchrow_array)[0];
    undef $sth;
	$value =~ s/\s+$//;
    $sth = $s->[$DBI]->do("update $s->[$TABLE] SET $column=$value where $s->[$KEY] = $key");
    $value;
}

sub column_index {
    my ($s, $column) = @_;

	my $i = 0;
	my $col;

	for(@{$s->[$NAME]}) {
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
		$key = $s->[$DBI]->quote($key)
			unless defined $s->[$CONFIG]->{NUMERIC}->{$key};
        my $sth = $s->[$DBI]->prepare
			("select $column from $s->[$TABLE] where $s->[$KEY] = $key")
				or croak $DBI::errstr;
		($sth->fetchrow)[0];
    };
}

sub param_query {
	my($s, $text, $table) = @_;
	my $db = $s->[$DBI];
    my $sth = $db->prepare($text)
		or croak "$DBI::errstr\n";
	my(@row);
	my(@out);
    $sth->execute() or croak $DBI::errstr;
	while(@row = $sth->fetchrow_array()) {
		push @out, @row;
	}
	my $r = '"';
	for(@out) { s/\s+$//; s/"/\\"/g }
	$r .= join '" "', @out;
	$r .= '"';
}

sub array_query {
	my($s, $text, $table) = @_;
# DEBUG
#Vend::Util::logDebug
#("array_query: $text\n")
#	if ::debug(0x4);
# END DEBUG
	my $db = $s->[$DBI];
    my $sth = $db->prepare($text)
		or croak "$DBI::errstr\n";
    $sth->execute() or croak $DBI::errstr;
	return $sth->fetchall_arrayref;
}

sub hash_query {
	my($s, $text, $table) = @_;
# DEBUG
#Vend::Util::logDebug
#("hash_query: $text\n")
#	if ::debug(0x4);
# END DEBUG
	my $db = $s->[$DBI];
	my $key = $s->[$KEY];
    my $sth = $db->prepare($text)
		or croak "$DBI::errstr\n";
    $sth->execute() or croak $DBI::errstr;
	my $out = {};
	my $ref;
	while($ref = $sth->fetchrow_hashref()) {
		$out->{$ref->{$key}} = $ref;
	}
	return $out;
}

sub html_query {
	my($s, $text, $table) = @_;
	my $db = $s->[$DBI];
    my $sth = $db->prepare($text)
		or croak "$DBI::errstr\n";
	my(@row);
    $sth->execute() or croak $DBI::errstr;
	my $r = '<TR>';
	for(@{$sth->{NAME}}) {
		$r .= "<TH><B>$_</B></TH>";
	}
	$r .= '</TR>';
	while(@row = $sth->fetchrow_array()) {
		$r .= "<TR>";
		for(@row) {
			$r .= "<TD>$_</TD>";
		}
		$r .= "</TR>";
	}
	$r;
}

sub set_query {
	my($s, $text, $table) = @_;
	$s->[$DBI]->do($text)
		or croak "$DBI::errstr\n";
	return '';
}

sub touch {return ''}

# Now supported
sub each_record {
    my ($s) = @_;
    my ($table,$key,$db,$cols,$config,$each) = @$s;
    unless(defined $each) {
# DEBUG
#Vend::Util::logDebug
#("Each not defined -- listing table $table for $db\n")
#	if ::debug(0x4);
# END DEBUG
        $each = $db->prepare("select * from $table")
            or croak $DBI::errstr;
        push @$s, $each;
		$each->execute();
    }
    my @cols;
    @cols = $each->fetchrow_array;
# DEBUG
#Vend::Util::logDebug
#("Cols for DBI each_record:\n--\n" . (join "|", @cols) . "\n--\n")
#	if ::debug(0x4);
# END DEBUG
    pop(@$s) unless(scalar @cols);
    return @cols;
}

sub field_settor {
    my ($s, $column) = @_;
    return sub {
        my ($key, $value) = @_;
		$value = $s->[$DBI]->quote($value)
			unless defined $s->[$CONFIG]->{NUMERIC}->{$column};
		$key = $s->[$DBI]->quote($key)
			unless defined $s->[$CONFIG]->{NUMERIC}->{$key};
        $s->[$DBI]->do("update $s->[$TABLE] SET $column=$value where $s->[$KEY] = $key");
    };
}

sub set_row {
    my ($s, @fields) = @_;
	my @cols = @{$s->[$CONFIG]->{NAME}};
	
	my $i = 0;
	for(@fields) {
		$_ = $s->[$DBI]->quote($_)
			unless defined $s->[$CONFIG]->{NUMERIC}->{$cols[$i++]};
	}

	while(scalar @cols < scalar @fields) {
		my $val = pop @fields;
		my $t = $s->[$TABLE]; my $f = $fields[0];
		::logError("set_row $t: field with value '$val' removed from record '$f'");
	}

	while(scalar @cols > scalar @fields) {
		push @fields, '';
	}

	my $values = join ',', @fields;
# DEBUG
#Vend::Util::logDebug
#("Got to set_row\n$values\n")
#	if ::debug(0x4);
# END DEBUG
    $s->[$DBI]->do("delete from $s->[$TABLE] where $s->[$KEY] = $fields[0]");
    $s->[$DBI]->do("insert into $s->[$TABLE] VALUES ($values)")
		or croak "$DBI::errstr\n";
}

sub field {
    my ($s, $key, $column) = @_;
	$key = $s->[$DBI]->quote($key) 
			unless defined $s->[$CONFIG]->{NUMERIC}->{$key};
    my $sth = $s->[$DBI]->prepare(
		"select $column from $s->[$TABLE] where $s->[$KEY] = $key");
    $sth->execute()
		or croak("execute error: $DBI::errstr");
	my $data = ($sth->fetchrow_array())[0];
# DEBUG
#Vend::Util::logDebug
#("retrieve field: col=$column key=$key data=$data\n")
#	if ::debug(0x4);
# END DEBUG
	return '' unless $data =~ /\S/;
	$data;
}

sub set_field {
    my ($s, $key, $column, $value) = @_;
	$key = $s->[$DBI]->quote($key)
		unless defined $s->[$CONFIG]->{NUMERIC}->{$key};
	$value = $s->[$DBI]->quote($value)
		unless defined $s->[$CONFIG]->{NUMERIC}->{$column};
    $s->[$DBI]->do("update $s->[$TABLE] SET $column = $value where $s->[$KEY] = $key")
		or croak "$DBI::errstr\n";
	$value;
}

sub ref {
	return $_[0];
}

#sub record_exists { 1 }

sub record_exists {
    my ($s, $key) = @_;
# DEBUG
#Vend::Util::logDebug
#("call object $s with arg $key -- key name is '$s->[$KEY]'\n")
#	if ::debug(0x4);
# END DEBUG
	my $query = "select $s->[$KEY] from $s->[$TABLE] where $s->[$KEY] = '$key'";
	my $sth = $s->[$DBI]->prepare($query);
    $sth->execute() or croak $DBI::errstr;
    $sth->fetchrow_arrayref or return undef;
	return 1;
}

sub delete_record {
    my ($s, $key) = @_;

    $s->[$DBI]->do("delete from $s->[$TABLE] where $s->[$KEY] = '$key'");
}

sub list_fields {
	my($db, $name) = @_;
# DEBUG
#Vend::Util::logDebug
#("DBI list_fields call: @_\n")
#	if ::debug(0x4);
# END DEBUG
	my @fld;

	my $sth = $db->prepare("select * from $name")
		or croak $DBI::errstr;

	# Wish we didn't have to do this, but we cache the columns
	$sth->execute		or croak "$DBI::errstr\n";

	@fld = @{$sth->{NAME}};

	croak "DBI: can't find field names.\n"
		unless @fld > 1;
# DEBUG
#Vend::Util::logDebug
#("DBI list_fields: @fld\n")
#	if ::debug(0x4);
# END DEBUG
	@fld;
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
	if(@row = $sth->fetchrow_array()) {
		$rc = $row[0];
	}
	$sth->finish() or croak "$DBI::errstr\n";
	$rc;
}

sub version { $Vend::Table::DBI::VERSION }

1;
