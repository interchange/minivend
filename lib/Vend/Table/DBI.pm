# Table/DBI.pm: access a table stored in an DBI/DBD Database
#
# $Id: DBI.pm,v 1.25 1999/02/15 08:51:44 mike Exp mike $
#
# Copyright 1996-1999 by Michael J. Heins <mikeh@minivend.com>
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
$VERSION = substr(q$Revision: 1.25 $, 10);

use strict;

# 0: table name
# 1: key name
# 2: database object
# 3: Array of column names
# 4: Configuration hash
# 5: each reference (transitory)

use vars qw($TABLE $KEY $DBI $NAME $CONFIG $EACH);
($TABLE, $KEY, $DBI, $NAME, $CONFIG, $EACH) = (0 .. 5);

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

sub config {
	my ($self, $key, $value) = @_;
	return $self->[$CONFIG]{$key} unless defined $value;
	$self->[$CONFIG]{$key} = $value;
}

sub create {
    my ($class, $config, $columns, $tablename) = @_;

	my @call = find_dsn($config);
	my $dattr = pop @call;
	my $db = DBI->connect( @call )
		or die "DBI connect failed: $DBI::errstr\n";

	if($config->{HANDLE_ONLY}) {
		return bless [$tablename, undef, $db, undef, $config], $class;
	}

    die "columns argument $columns is not an array ref\n"
        unless ref($columns) eq 'ARRAY';

	if(defined $dattr) {
		for(keys %$dattr) {
			$db->{$_} = $dattr->{$_};
		}
	}

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
		if(defined $config->{COLUMN_DEF}->{$cols[$i]}) {
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
		or warn "$DBI::errstr\n";

# DEBUG
#Vend::Util::logDebug
#("cols: '" . (join "','", @cols) . "'\n")
#	if ::debug(0x4);
# END DEBUG
	my $query = "create table $tablename ( \n";
	$query .= join ",\n", @cols;
	$query .= "\n)\n";
	
	$db->do($query)
		or warn "DBI: Create table '$tablename' failed: $DBI::errstr\n";
#	::logError("table $tablename created: $query");
	::logError( Vend::Util::errmsg('Table/DBI.pm:1', "table %s created: %s" , $tablename, $query) );

	$db->do("create index ${key}_idx on $tablename ($key)")
#		or ::logError("table $tablename index failed: $DBI::errstr");
		or ::logError( Vend::Util::errmsg('Table/DBI.pm:2', "table %s index failed: %s" , $tablename, $DBI::errstr) );

	$config->{NAME} = $columns;

    my $self = [$tablename, $key, $db, $columns, $config];
    bless $self, $class;
}

sub open_table {
    my ($class, $config, $tablename) = @_;
	
    my @call = find_dsn($config);
    my $dattr = pop @call;
    my $db = DBI->connect( @call )
		or die "$tablename: $DBI::errstr\n";

	if($config->{HANDLE_ONLY}) {
		return bless [$tablename, undef, $db, undef, $config], $class;
	}
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

	$cols = $config->{NAME} || [list_fields($db, $tablename)];

	$config->{COLUMN_NAMES} = lc (join " ", '', @$cols, '')
		unless defined $config->{COLUMN_NAMES};

	$config->{NUMERIC} = {} unless $config->{NUMERIC};

	die "DBI: no column names returned for $tablename\n"
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

	return 1 if index($s->[$CONFIG]->{COLUMN_NAMES}, " \L$column ") != -1;
	return undef;
}

sub quote {
	my($s, $value, $field) = @_;
	return $s->[$DBI]->quote($value)
		unless $field and $s->numeric($field);
	return $value;
}

sub numeric {
	return exists $_[0]->[$CONFIG]->{NUMERIC}->{$_[1]};
}

sub inc_field {
    my ($s, $key, $column, $value) = @_;
	$key = $s->[$DBI]->quote($key)
		unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
    my $sth = $s->[$DBI]->prepare(
		"select $column from $s->[$TABLE] where $s->[$KEY] = $key");
    die "inc_field: $DBI::errstr\n" unless defined $sth;
    $sth->execute();
    $value += ($sth->fetchrow_array)[0];
	$value = $s->[$DBI]->quote($value)
		unless exists $s->[$CONFIG]{NUMERIC}{$column};
    $sth = $s->[$DBI]->do("update $s->[$TABLE] SET $column=$value where $s->[$KEY] = $key");
    $value;
}

sub column_index {
    my ($s, $column) = @_;

	my $i = 0;
	my $col;

	for(@{$s->[$NAME]}) {
		($i++, next) unless "\L$_" eq "\L$column";
		$col = $i;
		last;
	}

	return undef unless $col;
	
	return $col - 1;

}

*column_exists = \&column_index;

sub field_accessor {
    my ($s, $column) = @_;
    return sub {
        my ($key) = @_;
		$key = $s->[$DBI]->quote($key)
			unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
        my $sth = $s->[$DBI]->prepare
			("select $column from $s->[$TABLE] where $s->[$KEY] = $key")
				or die $DBI::errstr;
		($sth->fetchrow)[0];
    };
}

sub set_row {
    my ($s, @fields) = @_;
	my @cols = @{$s->[$CONFIG]->{NAME}};
	
	my $i = 0;

	while(scalar @cols < scalar @fields) {
		my $val = pop @fields;
		my $t = $s->[$TABLE]; my $f = $fields[0];
		::logError( Vend::Util::errmsg('Table/DBI.pm:3', "set_row %s: field with value '%s' removed from record '%s'" , $t, $val, $f) );
	}

	while(scalar @cols > scalar @fields) {
		push @fields, '';
	}

	for(@fields) {
		$_ = $s->[$DBI]->quote($_)
			unless exists $s->[$CONFIG]->{NUMERIC}->{$cols[$i++]};
	}

	my $values = join ',', @fields;

    $s->[$DBI]->do("delete from $s->[$TABLE] where $s->[$KEY] = $fields[0]");
    $s->[$DBI]->do("insert into $s->[$TABLE] VALUES ($values)")
		or die "$DBI::errstr\n";
}

sub row_hash {
    my ($s, $key) = @_;
	$key = $s->[$DBI]->quote($key)
		unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
    my $sth = $s->[$DBI]->prepare(
		"select * from $s->[$TABLE] where $s->[$KEY] = $key");
    $sth->execute()
		or die("execute error: $DBI::errstr");
	return $sth->fetchrow_hashref();
}

sub field_settor {
    my ($s, $column) = @_;
    return sub {
        my ($key, $value) = @_;
		$value = $s->[$DBI]->quote($value)
			unless exists $s->[$CONFIG]->{NUMERIC}->{$column};
		$key = $s->[$DBI]->quote($key)
			unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
        $s->[$DBI]->do("update $s->[$TABLE] SET $column=$value where $s->[$KEY] = $key");
    };
}

sub field {
    my ($s, $key, $column) = @_;
	$key = $s->[$DBI]->quote($key)
		unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
    my $sth = $s->[$DBI]->prepare(
		"select $column from $s->[$TABLE] where $s->[$KEY] = $key");
    $sth->execute()
		or die("execute error: $DBI::errstr");
	my $data = ($sth->fetchrow_array())[0];
	return '' unless $data =~ /\S/;
	$data;
}

sub set_field {
    my ($s, $key, $column, $value) = @_;

    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to set $s->[$CONFIG]{name}::${column}::$key in read-only table");
		return undef;
	}
	$key = $s->[$DBI]->quote($key)
		unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
	$value = $s->[$DBI]->quote($value)
		unless exists $s->[$CONFIG]->{NUMERIC}->{$column};
    $s->[$DBI]->do("update $s->[$TABLE] SET $column = $value where $s->[$KEY] = $key")
		or die "$DBI::errstr\n";
	$value;
}

sub ref {
	return $_[0];
}

sub test_record { 1 }

sub record_exists {
    my ($s, $key) = @_;
	$key = $s->[$DBI]->quote($key)
		unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
	my $query = "select $s->[$KEY] from $s->[$TABLE] where $s->[$KEY] = $key";
	my $sth = $s->[$DBI]->prepare($query);
    $sth->execute() or die $DBI::errstr;
    $sth->fetchrow_arrayref or return undef;
	return 1;
}

sub delete_record {
    my ($s, $key) = @_;

    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to delete record '$key' from read-only database $s->[$CONFIG]{name}");
		return undef;
	}
	$key = $s->[$DBI]->quote($key)
		unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
    $s->[$DBI]->do("delete from $s->[$TABLE] where $s->[$KEY] = $key");
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
		or die $DBI::errstr;

	# Wish we didn't have to do this, but we cache the columns
	$sth->execute		or die "$DBI::errstr\n";

	@fld = @{$sth->{NAME}};

	die "DBI: can't find field names.\n"
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
eval {
	my $sth = $dbh->prepare(<<EOF);
	SELECT 1
	FROM tables
WHERE table_name = '$name'
EOF

	die "$DBI::errstr\n" unless $sth;
	$sth->execute() or die "$DBI::errstr\n";
	if(@row = $sth->fetchrow_array()) {
		$rc = $row[0];
	}
	$sth->finish() or die "$DBI::errstr\n";
};
	$rc;
}



# OLDSQL

use vars qw/$mv_sql_hash
            $mv_sql_hash_order
            $mv_sql_array
            @mv_sql_param
            %mv_sql_names/;

sub substitute_arg {
	my ($s, $query, @arg) = @_;
	my ($tmp, $arg);
	foreach $arg (@arg) {
		$query =~
			s{  (\w+)									# a field name
				(
					\s+like\s+			|       		# substring
					\s*[!=><][=><]?\s*	|				# compare
					\s+between\s+		|				# range
					\s+in[(\s]+							# enumerated
				)
				'?(%?)%s(%?)'?									# The parameter
			}{$1 . $2 . $s->quote("$3$arg$4", $1)}ixe 
	or

		$query =~ s/'(%?)%s(%?)'/$s->[$DBI]->quote("$1$arg$2")/e 
	or
		defined $s->[$CONFIG]->{QUOTEALL}
			and $query =~ s/(([^%])%s)/$s->[$DBI]->quote($arg)/e
	or
		$query =~ s/([^%])%s/$1$arg/;
	}
	return $query;
}

sub param_query {
    my($s, $text, $table, $config, @arg) = @_;

    if($s->[$CONFIG]{Read_only} and $text !~ /^\s*select\s+/i) {
		::logError("Attempt to write read-only database $s->[$CONFIG]{name} with query '$text'");
		return undef;
	}

    $text = $s->substitute_arg($text, @arg) if @arg;

	my $db = $s->[$DBI];
    my $sth = $db->prepare($text)
		or die "$table: $DBI::errstr\n";
	my(@row);
	my(@out);
    $sth->execute() or die $DBI::errstr;
	while(@row = $sth->fetchrow_array()) {
		push @out, @row;
	}
	my $r = '"';
	if(CORE::ref $config and $config->{PERL}) {
		@mv_sql_param = @out;
		return unless $config->{BOTH};
	}
	for(@out) { s/\s+$//; s/"/\\"/g }
	$r .= join '" "', @out;
	$r .= '"';
	return $r;
}

sub array_query {
	my($s, $text, $table, $config, @arg) = @_;

    if($s->[$CONFIG]{Read_only} and $text !~ /^\s*select\s+/i) {
		::logError("Attempt to write read-only database $s->[$CONFIG]{name} with query '$text'");
		return undef;
	}

	$text = $s->substitute_arg($text, @arg) if @arg;
	my $db = $s->[$DBI];
    my $sth = $db->prepare($text)
		or die "$table: $DBI::errstr\n";
    $sth->execute() or die $DBI::errstr;
    my $i = 0;
    %mv_sql_names = map { (lc $_, $i++) } @{$sth->{NAME}};
	my $out = $sth->fetchall_arrayref;
	if(CORE::ref $config and $config->{PERL}) {
		$mv_sql_array = $out;
		return unless $config->{BOTH};
	}
	return $out;
}

sub hash_query {
    my($s, $text, $table, $config, @arg) = @_;

    if($s->[$CONFIG]{Read_only} and $text !~ /^\s*select\s+/i) {
		::logError("Attempt to write read-only database $s->[$CONFIG]{name} with query '$text'");
		return undef;
	}

    $text = $s->substitute_arg($text, @arg) if @arg;

	my $key = $s->[$KEY];
    my $sth = $s->[$DBI]->prepare($text)
		or die "$table: $DBI::errstr\n";
    $sth->execute() or die $DBI::errstr;
	my $out = {};
	my @out;
	my $tkey;
	my $ref;
	while($ref = $sth->fetchrow_hashref()) {
		$tkey = $ref->{$key};
		push (@out, $tkey);
		$out->{$tkey} = $ref;
	}
	if(CORE::ref $config and $config->{PERL}) {
		$mv_sql_hash = $out;
		$mv_sql_hash_order = \@out;
		return unless $config->{BOTH};
	}
	return $out;
}

sub html_query {
    my($s, $text, $table, $config, @arg) = @_;

    if($s->[$CONFIG]{Read_only} and $text !~ /^\s*select\s+/i) {
		::logError("Attempt to write read-only database $s->[$CONFIG]{name} with query '$text'");
		return undef;
	}
   
    $text = $s->substitute_arg($text, @arg) if @arg;

	my $db = $s->[$DBI];
    my $sth = $db->prepare($text)
		or die "$table: $DBI::errstr\n";
	my(@row);
    $sth->execute() or die $DBI::errstr;
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
	if (CORE::ref $config) {
		defined $config->{TR} and $r =~ s/<TR>/<TR $config->{TR}>/g;
		defined $config->{TH} and $r =~ s/<TH>/<TH $config->{TH}>/g;
		defined $config->{TD} and $r =~ s/<TD>/<TD $config->{TD}>/g;
	}
	$r;
}

sub set_query {
	my($s, $text, $table, $config, @arg) = @_;

    if($s->[$CONFIG]{Read_only} and $text !~ /^\s*select\s+/i) {
		::logError("Attempt to write read-only database $s->[$CONFIG]{name} with query '$text'");
		return undef;
	}

	$config = {} unless CORE::ref $config;
	$text = $s->substitute_arg($text, @arg) if @arg;
	my $rc = $s->[$DBI]->do($text);
	unless (defined $config->{IF} || defined $config->{ELSE}) {
		die "$table: $DBI::errstr\n" unless defined $rc;
		return '';
	}
	$rc = 0 if $rc eq '0E0';
	return $config->{COUNT} . $rc if defined $config->{COUNT};
	return $rc ? ($config->{IF} || '') : ($config->{ELSE} || '');
}

# END OLDSQL

sub touch {return ''}

# Now supported, including qualification
sub each_record {
    my ($s, $qual) = @_;
#::logError("qual=$qual");
    my ($table,$key,$db,$cols,$config,$each) = @$s;
    unless(defined $each) {
        $each = $db->prepare("select * from $table" . ($qual || '') )
            or die $DBI::errstr;
        push @$s, $each;
		$each->execute();
    }
    my @cols;
    @cols = $each->fetchrow_array;
    pop(@$s) unless(scalar @cols);
    return @cols;
}

sub sprintf_substitute {
	my ($s, $query, $fields, $cols) = @_;
	my ($tmp, $arg);
	my $i;
	if(defined $cols->[0]) {
		for($i = 0; $i <= $#$fields; $i++) {
			$fields->[$i] = $s->quote($fields->[$i], $cols->[$i])
				if defined $cols->[0];
		}
	}
	return sprintf $query, @$fields;
}

sub query {
    my($s, $opt, $text, @arg) = @_;

    if($s->[$CONFIG]{Read_only} and $text !~ /^\s*select\s+/i) {
		::logError("Attempt to write read-only database $s->[$CONFIG]{name} with query '$text'");
		return undef;
	}
	
	$opt->{table} = $s->[$NAME] if ! defined $opt->{table};
	$opt->{query} = $text if ! $opt->{query};

	if(defined $opt->{values}) {
		# do nothing
		@arg = $opt->{values} =~ /['"]/
				? ( Text::ParseWords::shellwords($opt->{values})  )
				: (grep /\S/, split /\s+/, $opt->{values});
		@arg = @{$::Values}{@arg};
	}

	my @cols;
	if($opt->{columns}) {
		@cols = grep /\S/, split /\s+/, $opt->{columns};
	}

	my $query;
    $query = ! scalar @arg
			? $opt->{query}
			: $s->sprintf_substitute ($opt->{query}, \@arg, \@cols);

	my(@row);
	my(@out);
    my $sth;
	my $ref;
	my $db = $s->[$DBI];
	my $return;

eval {
    if($s->[$CONFIG]{Read_only} and $query !~ /^\s*select\s+/i) {
		die ("Attempt to write read-only database $s->[$CONFIG]{name}");
	}
    $sth = $db->prepare($query)
		or die $DBI::errstr;
    $sth->execute() or die $DBI::errstr;
	if($opt->{arrayref} || $opt->{list}) {
		$ref =
			$Vend::Tmp->{$opt->{arrayref}}
			= $sth->fetchall_arrayref();
	}
	elsif ($opt->{hashref}) {
		$ref =
			$Vend::Tmp->{$opt->{hashref}}
			= $sth->fetchall_hashref();
	}
};
	if($@) {
		::logError("DBI query failed for $opt->{table}: $@\nquery was: $query");
		$return = $opt->{failure} || undef;
	}

	if ($opt->{list}) {
		return Vend::Interpolate::tag_sql_list($text, $ref);
	}
	if($opt->{text}) {
		return $Vend::Util->uneval($ref);
	}
	return $opt->{success};
}

sub version { $Vend::Table::DBI::VERSION }

1;
