# Table/Common.pm: Common access methods for Interchange Databases
#
# $Id$
#
# Copyright (C) 1996-2000 Akopia, Inc. <info@akopia.com>
#
# This program was originally based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
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
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA.

$VERSION = substr(q$Revision$, 10);
use strict;

package Vend::Table::Common;
require Vend::DbSearch;
require Vend::TextSearch;
use Vend::Util;

use Exporter;
use vars qw($Storable $VERSION @EXPORT @EXPORT_OK);
@EXPORT = qw(create_columns import_ascii_delimited import_csv config columns);
@EXPORT_OK = qw(import_quoted read_quoted_fields);

use vars qw($FILENAME
			$COLUMN_NAMES
			$COLUMN_INDEX
			$KEY_INDEX
			$TIE_HASH
			$DBM
			$EACH
			$CONFIG);
(
	$CONFIG,
	$FILENAME,
	$COLUMN_NAMES,
	$COLUMN_INDEX,
	$KEY_INDEX,
	$TIE_HASH,
	$DBM,
	$EACH,
	) = (0 .. 7);

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

sub create_columns {
	my ($columns, $config) = @_;
	$config = {} unless $config;
    my $column_index = {};
	my $key;
#::logDebug("create_columns: " . ::uneval($config));

	if($config->{KEY}) {
		$key = $config->{KEY};
	}
	elsif (! defined $config->{KEY_INDEX}) {
		$config->{KEY_INDEX} = 0;
		$config->{KEY} = $columns->[0];
	}
    my $i;
	my $alias = $config->{FIELD_ALIAS} || {};
#::logDebug("field_alias: " . ::uneval($alias)) if $config->{FIELD_ALIAS};
    for ($i = 0;  $i < @$columns;  ++$i) {
        $column_index->{$columns->[$i]} = $i;
		defined $alias->{$columns->[$i]}
			and $column_index->{ $alias->{ $columns->[$i] } } = $i;
		next unless defined $key and $key eq $columns->[$i];
		$config->{KEY_INDEX} = $i;
		undef $key;
#::logDebug("set KEY_INDEX to $i: " . ::uneval($config));
    }

    die("Cannot find key column $config->{KEY} in $config->{name} ($config->{file}): $!")
        unless defined $config->{KEY_INDEX};

	return $column_index;
}

sub separate_definitions {
	my ($options, $fields) = @_;
	for(@$fields) {
#::logDebug("separating '$_'");
		next unless s/\s+(.*)//;
#::logDebug("needed separation: '$_'");
		my $def = $1;
		my $fn = $_;
		unless(defined $options->{COLUMN_DEF}{$fn}) {
			$options->{COLUMN_DEF}{$fn} = $def;
		}
	}
	return;
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

sub autonumber {
	my $s = shift;
	my $start;
	return '' if not $start = $s->[$CONFIG]->{AUTO_NUMBER};
	local($/) = "\n";
	my $c = $s->[$CONFIG];
	if(! defined $c->{AutoNumberCounter}) {
		$c->{AutoNumberCounter} = new File::CounterFile
									"$c->{dir}/$c->{name}.autonumber", $start;
	}
	my $num;
	do {
		$num = $c->{AutoNumberCounter}->inc();
	} while $s->record_exists($num);
	return $num;
}

sub numeric {
	return exists $_[0]->[$CONFIG]->{NUMERIC}->{$_[1]};
}

sub quote {
	my($s, $value, $field) = @_;
	return $value if $s->numeric($field);
	$value =~ s/'/\\'/g;
	return "'$value'";
}

sub config {
	my ($s, $key, $value) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
	return $s->[$CONFIG]{$key} unless defined $value;
	$s->[$CONFIG]{$key} = $value;
}

sub import_db {
	my($s) = @_;
	my $db = Vend::Data::import_database($s->[0], 1);
	return undef if ! $db;
	$Vend::Database{$s->[0]{name}} = $db;
	Vend::Data::update_productbase($s->[0]{name});
	if($db->[$CONFIG]{export_now}) {
		Vend::Data::export_database($db);
		delete $db->[$CONFIG]{export_now};
	}
	return $db;
}

sub close_table {
    my ($s) = @_;
	return 1 if ! defined $s->[$TIE_HASH];
#::logDebug("closing table $s->[$FILENAME]");
	undef $s->[$DBM];
    untie %{$s->[$TIE_HASH]}
		or die "Could not close DBM table $s->[$FILENAME]: $!\n";
	undef $s->[$TIE_HASH];
#::logDebug("closed table $s->[$FILENAME], self=" . ::uneval($s));
}

sub filter {
	my ($s, $ary, $col, $filter) = @_;
	my $column;
	for(keys %$filter) {
		next unless defined ($column = $col->{$_});
		$ary->[$column] = Vend::Interpolate::filter_value(
								$filter->{$_},
								$ary->[$column],
								$_,
						  );
	}
}

sub columns {
    my ($s) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    return @{$s->[$COLUMN_NAMES]};
}

sub test_column {
    my ($s, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    return $s->[$COLUMN_INDEX]{$column};
}

sub column_index {
    my ($s, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    my $i = $s->[$COLUMN_INDEX]{$column};
    die "There is no column named '$column'" unless defined $i;
    return $i;
}

*test_record = \&record_exists;

sub record_exists {
    my ($s, $key) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    # guess what?  The GDBM "exists" function got renamed to "EXISTS" 
    # in 5.002.
    my $r = $s->[$DBM]->EXISTS("k$key");
    return $r;
}

sub row_hash {
    my ($s, $key) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
	my %row;
    @row{ @{$s->[$COLUMN_NAMES]} } = $s->row($key);
	return \%row;
}

sub unstuff_row {
    my ($s, $key) = @_;
    my $line = $s->[$TIE_HASH]{"k$key"};
    die "There is no row with index '$key'" unless defined $line;
    return map(unstuff($_), split(/\t/, $line, 9999))
		unless $s->[$CONFIG]{FILTER_FROM};
	my @f = map(unstuff($_), split(/\t/, $line, 9999));
	$s->filter(\@f, $s->[$COLUMN_INDEX], $s->[$CONFIG]{FILTER_FROM});
	return @f;
}

sub thaw_row {
    my ($s, $key) = @_;
    my $line = $s->[$TIE_HASH]{"k$key"};
    die "There is no row with index '$key'" unless defined $line;
    return (@{ Storable::thaw($line) })
		unless $s->[$CONFIG]{FILTER_FROM};
#::logDebug("filtering.");
	my $f = Storable::thaw($line);
	$s->filter($f, $s->[$COLUMN_INDEX], $s->[$CONFIG]{FILTER_FROM});
	return @{$f};
}

sub field_accessor {
    my ($s, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    my $index = $s->column_index($column);
    return sub {
        my ($key) = @_;
        return ($s->row($key))[$index];
    };
}

sub row_settor {
    my ($s, @cols) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
	my @index;
	my $key_idx = $s->[$KEY_INDEX] || 0;
	#shift(@cols);
	for(@cols) {
     	push @index, $s->column_index($_);
	}
#::logDebug("settor index=@index");
    return sub {
        my (@vals) = @_;
		my @row;
		my $key = $vals[$key_idx];
		eval {
			@row = $s->row($key);
		};
        @row[@index] = @vals;
#::logDebug("setting $key indices '@index' to '@vals'");
        $s->set_row(@row);
    };
}

sub field_settor {
    my ($s, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    my $index = $s->column_index($column);
    return sub {
        my ($key, $value) = @_;
        my @row = $s->row($key);
        $row[$index] = $value;
        $s->set_row(@row);
    };
}

sub stuff_row {
    my ($s, @fields) = @_;
	my $key = $fields[$s->[$KEY_INDEX]];
	$fields[$s->[$KEY_INDEX]] = $key = $s->autonumber()
		if ! $key;
	$s->filter(\@fields, $s->[$COLUMN_INDEX], $s->[$CONFIG]{FILTER_TO})
		if $s->[$CONFIG]{FILTER_TO};
    $s->[$TIE_HASH]{"k$key"} = join("\t", map(stuff($_), @fields));
	return $key;
}

sub freeze_row {
    my ($s, @fields) = @_;
	my $key = $fields[$s->[$KEY_INDEX]];
#::logDebug("freeze key=$key");
	$fields[$s->[$KEY_INDEX]] = $key = $s->autonumber()
		if ! $key;
	$s->filter(\@fields, $s->[$COLUMN_INDEX], $s->[$CONFIG]{FILTER_TO})
		if $s->[$CONFIG]{FILTER_TO};
	$s->[$TIE_HASH]{"k$key"} = Storable::freeze(\@fields);
	return $key;
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
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    return ($s->row($key))[$s->column_index($column)];
}

sub set_field {
    my ($s, $key, $column, $value) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to set $s->[$CONFIG]{name}::${column}::$key in read-only table");
		return undef;
	}
    my @row;
	if($s->record_exists($key)) {
		@row = $s->row($key);
	}
	else {
		$row[$s->[$KEY_INDEX]] = $key;
	}
    $row[$s->column_index($column)] = $value;
    $s->set_row(@row);
	$value;
}

sub inc_field {
    my ($s, $key, $column, $adder) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    my($value);
    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to set $s->[$CONFIG]{name}::${column}::$key in read-only table");
		return undef;
	}
    my @row = $s->row($key);
	my $idx = $s->column_index($column);
#::logDebug("ready to increment key=$key column=$column adder=$adder idx=$idx row=" . ::uneval(\@row));
    $value = $row[$s->column_index($column)] += $adder;
    $s->set_row(@row);
    return $value;
}

sub touch {
    my ($s) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    my $now = time();
    utime $now, $now, $s->[$FILENAME];
}

sub ref {
	my $s = shift;
	return $s if defined $s->[$TIE_HASH];
	return $s->import_db();
}

sub sort_each {
	my($s, $sort_field, $sort_option) = @_;
	if(length $sort_field) {
		my $opt = {};
		$opt->{to} = $sort_option
			if $sort_option;
		$opt->{ml} = 99999;
		$opt->{st} = 'db';
		$opt->{tf} = $sort_field;
		$opt->{query} = "select * from $s->[$CONFIG]{name}";
		$s->[$EACH] = $s->query($opt);
		return;
	}
}

sub each_sorted {
	my $s = shift;
	if(! defined $s->[$EACH][0]) {
		undef $s->[$EACH];
		return ();
	}
	my $k = $s->[$EACH][0][$s->[$KEY_INDEX]];
	return ($k, @{shift @{ $s->[$EACH] } });
}

sub each_record {
    my ($s) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    my $key;

	return $s->each_sorted() if defined $s->[$EACH];
    for (;;) {
        $key = each %{$s->[$TIE_HASH]};
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

my $sup;
my $restrict;
my $rfield;
my $rsession;

sub each_nokey {
    my ($s) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    my ($key);

	if (
		! defined $restrict
		and 
		$restrict = ($Vend::Cfg->{TableRestrict}{$s->config('name')} || 0)
		)
	{
		$sup =  ! defined $Global::SuperUserFunction
					||
				$Global::SuperUserFunction->();
		if($sup) {
			$restrict = 0;
		}
		else {
			($rfield, $rsession) = split /\s*=\s*/, $restrict;
			$s->test_column($rfield) and $rfield = $s->column_index($rfield)
				or $restrict = 0;
			$rsession = $Vend::Session->{$rsession};
		}
	}

    for (;;) {
        $key = each %{$s->[$TIE_HASH]};
#::logDebug("each_nokey: $key field=$rfield sup=$sup");
		if(! defined $key) {
			undef $restrict;
			return ();
		}
		$key =~ s/^k// or next;
		if($restrict) {
			my (@row) = $s->row($key);
##::logDebug("each_nokey: '$row[$rfield]' eq '$rsession' ??");
			next if $row[$rfield] ne $rsession;
			return @row;
		}
		return $s->row($key);
    }
}

sub delete_record {
    my ($s, $key) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to delete row '$key' in read-only table $s->[$CONFIG]{name}");
		return undef;
	}

#::logDebug("delete row $key from $s->[$FILENAME]");
    delete $s->[$TIE_HASH]{"k$key"};
	1;
}

sub sprintf_substitute {
	my ($s, $query, $fields, $cols) = @_;
	return sprintf $query, @$fields;
}

sub query {
    my($s, $opt, $text, @arg) = @_;

    if(! ref $opt) {
        unshift @arg, $text;
        $text = $opt;
        $opt = {};
    }

	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
	$opt->{query} = $opt->{sql} || $text if ! $opt->{query};

#::logDebug("receieved query. object=" . ::uneval($opt));

	if(defined $opt->{values}) {
		# do nothing
		@arg = $opt->{values} =~ /['"]/
				? ( Text::ParseWords::shellwords($opt->{values})  )
				: (grep /\S/, split /\s+/, $opt->{values});
		@arg = @{$::Values}{@arg};
	}

	if($opt->{type}) {
		$opt->{$opt->{type}} = 1 unless defined $opt->{$opt->{type}};
	}

	my $query;
    $query = ! scalar @arg
			? $opt->{query}
			: sprintf_substitute ($s, $opt->{query}, \@arg);

	my $codename = defined $s->[$CONFIG]{KEY} ? $s->[$CONFIG]{KEY} : 'code';
	my $ref;
	my $relocate;
	my $return;
	my $spec;
	my $stmt;
	my $update;
	my %nh;
	my @na;
	my @out;

	if($opt->{STATEMENT}) {
		 $stmt = $opt->{STATEMENT};
		 $spec = $opt->{SPEC};
#::logDebug('rerouted. Command is ' . $stmt->command());
	}
	else {
		eval {
			($spec, $stmt) = Vend::Scan::sql_statement($query, $ref);
		};
		if(! CORE::ref $spec) {
			::logError("Bad SQL, query was: $query");
			return ($opt->{failure} || undef);
		}
		my @additions = grep length($_) == 2, keys %$opt;
		if(@additions) {
			@{$spec}{@additions} = @{$opt}{@additions};
		}
	}
	my @tabs = @{$spec->{fi}};
	for (@tabs) {
		s/\..*//;
	}
	if (! defined $s || $tabs[0] ne $s->[$CONFIG]{name}) {
		unless ($s = $Vend::Database{$tabs[0]}) {
			::logError("Table %s not found in databases", $tabs[0]);
			return $opt->{failure} || undef;
		}
#::logDebug("rerouting to $tabs[0]");
		$opt->{STATEMENT} = $stmt;
		$opt->{SPEC} = $spec;
		return $s->query($opt, $text);
	}

eval {

	if($stmt->command() ne 'SELECT') {
		if(defined $s and $s->[$CONFIG]{Read_only}) {
			die ("Attempt to write read-only database $s->[$CONFIG]{name}");
		}
		$update = $stmt->command();
	}
	my @vals = $stmt->row_values();
	
	@na = @{$spec->{rf}}     if $spec->{rf};

	$spec->{fn} = [$s->columns];
	if(! @na) {
		@na = ! $update || $update eq 'INSERT' ? '*' : $codename;
	}
	@na = @{$spec->{fn}}       if $na[0] eq '*';
	$spec->{rf} = [@na];

#::logDebug("tabs='@tabs' columns='@na' vals='@vals' update=$update"); 

    my $search;
    if ("\L$opt->{st}" eq 'db' ) {
		for(@tabs) {
			s/\..*//;
		}
        $search = new Vend::DbSearch;
#::logDebug("created DbSearch object: " . ::uneval($search));
	}
	else {
        $search = new Vend::TextSearch;
#::logDebug("created TextSearch object: " . ::uneval($search));
    }

	my %fh;
	my $i = 0;
	%nh = map { (lc $_, $i++) } @na;
	$i = 0;
	%fh = map { ($_, $i++) } @{$spec->{fn}};

#::logDebug("field hash: " . Vend::Util::uneval(\%fh)); 
	for ( qw/rf sf/ ) {
		next unless defined $spec->{$_};
		map { $_ = $fh{$_} } @{$spec->{$_}};
	}

	if($update) {
#::logDebug("Updating, update=$update");
#		$relocate = $stmt->{MV_VALUE_RELOCATE}
#			if defined $stmt->{MV_VALUE_RELOCATE};
		$opt->{row_count} = 1;
		die "Reached update query without object"
			if ! $s;
#		if($relocate) {
#			my $code = splice(@vals, $stmt->{MV_VALUE_RELOCATE}, 1);
#			unshift(@vals, $code) if $update ne 'UPDATE';
##::logDebug("relocating values col=$relocate: columns='@na' vals='@vals'"); 
#		}
#		elsif (!defined $relocate) {
#			die "Must have code field to insert"
#				 if $update eq 'INSERT';
#			unshift(@na, $codename);
##::logDebug("NOT defined relocating values col=$relocate: columns='@na' vals='@vals'"); 
#		}
		my $sub = $update eq 'DELETE'
					? sub { delete_record($s, @_) }
					: $s->row_settor(@na);
#::logDebug("Update operation is $update, sub=$sub");
		die "Bad row settor for columns @na"
			if ! $sub;
		if($update eq 'INSERT') {
			&$sub(@vals);
			$ref = [$vals[0]];
		}
		else {
#::logDebug("Supposed to search..., spec=" . ::uneval($spec));
			$ref = $search->array($spec);
#::logDebug("Returning ref=" . ::uneval($ref));
			for(@{$ref}) {
				&$sub($_->[0], @vals);
			}
		}
	}
	elsif ($opt->{hashref}) {
		$ref = $Vend::Interpolate::Tmp->{$opt->{hashref}} = $search->hash($spec);
	}
	else {
#::logDebug(	" \$Vend::Interpolate::Tmp->{$opt->{arrayref}}");
		$ref = $Vend::Interpolate::Tmp->{$opt->{arrayref}} = $search->array($spec);
		$opt->{object} = $search;
		$opt->{prefix} = 'sql' unless defined $opt->{prefix};
	}
};
#::logDebug("search spec: " . Vend::Util::uneval($spec));
#::logDebug("name hash: " . Vend::Util::uneval(\%nh));
#::logDebug("ref returned: " . substr(Vend::Util::uneval($ref), 0, 100));
#::logDebug("opt is: " . Vend::Util::uneval($opt));
	if($@) {
		::logError("MVSQL query failed for $opt->{table}: $@\nquery was: $query");
		$return = $opt->{failure} || undef;
	}

	return scalar @{$ref || []}
		if $opt->{row_count};
	return Vend::Interpolate::region($opt, $text)
		if $opt->{list};
	return Vend::Interpolate::html_table($opt, $ref, \@na)
		if $opt->{html};
	return Vend::Util::uneval($ref)
		if $opt->{textref};
	return wantarray ? ($ref, \%nh, \@na) : $ref;
}

sub import_csv {
    my ($source, $options, $table_name) = @_;

    die "The source file '$source' does not exist\n" unless -e $source;

    open(IN, "+<$source")
		or die "Can't open '$source' read/write: $!\n";
	lockfile(\*IN, 1, 1) or die "lock\n";
    my @field_names = read_quoted_fields(\*IN);
    die "$source is empty\n" unless @field_names;

	# This pulls COLUMN_DEF out of a field name
	# remains in ASCII file, though
	separate_definitions($options,\@field_names);
#::logDebug("field names: @field_names");

	no strict 'refs';
	my $out;
	if($options->{ObjectType}) {
#::logDebug("object type: $options->{ObjectType}");
		$out = &{"$options->{ObjectType}::create"}(
									$options->{ObjectType},
									$options,
									\@field_names,
									$table_name,
								);
	}
	else {
#::logDebug("pre-existing object: $options->{Object}");
		$out = $options->{Object};
	}
    my (@fields,$key);
    while (@fields = read_quoted_fields(\*IN)) {
#::logDebug("fields: @fields");
        $out->set_row(@fields);
    }
	delete $out->[$CONFIG]{Clean_start};
	unlockfile(\*IN) or die "unlock\n";
    close(IN);
	return $out;
}

sub import_quoted {
	return import_csv(@_)
}

my %Sort = (

    ''  => sub { $a cmp $b              },
    none    => sub { $a cmp $b              },
    f   => sub { (lc $a) cmp (lc $b)    },
    fr  => sub { (lc $b) cmp (lc $a)    },
    n   => sub { $a <=> $b              },
    nr  => sub { $b <=> $a              },
    r   => sub { $b cmp $a              },
    rf  => sub { (lc $b) cmp (lc $a)    },
    rn  => sub { $b <=> $a              },
);

sub import_ascii_delimited {
    my ($infile, $options, $table_name) = @_;
	my ($format);

	my $delimiter = quotemeta($options->{'delimiter'});
	$format = uc ($options->{CONTINUE} || 'NONE');

    open(IN, "+<$infile")
		or die "Couldn't open '$infile' read/write: $!\n";
	lockfile(\*IN, 1, 1) or die "lock\n";

	my $field_hash;
	my $para_sep;
	my $codere = '[\w-_#/.]+';
	my $idx = 0;

	my($field_count, @field_names);
	
	if($options->{hs}) {
		my $i = 0;
		<IN> while $i++ < $options->{hs};
	}
	if($options->{field_names}) {
		@field_names = @{$options->{field_names}};

		# This pulls COLUMN_DEF out of a field name
		# remains in ASCII file, though
		separate_definitions($options,\@field_names);

		if($options->{CONTINUE} eq 'NOTES') {
			$para_sep = $options->{NOTES_SEPARATOR} ||$options->{SEPARATOR} || "\f";
			$field_hash = {};
			for(@field_names) {
				$field_hash->{$_} = $idx++;
			}
			$idx = $#field_names;
		}
	}
	else {
		my $field_names = <IN>;
		chomp $field_names;
		$field_names =~ s/\s+$// unless $format eq 'NOTES';
		@field_names = split(/$delimiter/, $field_names);

		# This pulls COLUMN_DEF out of a field name
		# remains in ASCII file, though
		separate_definitions($options,\@field_names);

#::logDebug("field names: @field_names");
		if($format eq 'NOTES') {
			$field_hash = {};
			for(@field_names) {
				s/:.*//;	
				if(/\S[ \t]+/) {
					die "Only one notes field allowed in NOTES format.\n"
						if $para_sep;
					$para_sep = $_;
					$_ = '';
				}
				else {
					$field_hash->{$_} = $idx++;
				}
			}
			my $msg;
			@field_names = grep $_, @field_names;
			$para_sep =~ s/($codere)[\t ]*(.)/$2/;
			push(@field_names, ($1 || 'notes_field'));
			$idx = $#field_names;
			$para_sep = $options->{NOTES_SEPARATOR} || "\f";
		}
	}

	local($/) = "\n" . $para_sep ."\n"
		if $para_sep;

	$field_count = scalar @field_names;

	no strict 'refs';
    my $out;
	if($options->{ObjectType}) {
		$out = &{"$options->{ObjectType}::create"}(
									$options->{ObjectType},
									$options,
									\@field_names,
									$table_name,
								);
	}
	else {
		$out = $options->{Object};
	}
	my $fields;
    my (@fields, $key);
	my @addl;
	my $excel = '';
	my $excel_addl = '';

	if($options->{EXCEL}) {
	#Fix for quoted includes supplied by Larry Lesczynski
		$excel = <<'EndOfExcel';
			if(/"[^\t]*(?:,|"")/) {
				for (@fields) {
					next unless /[,"]/;
					s/^"//;
					s/"$//;
					s/""/"/g;
				}
			}
EndOfExcel
		$excel_addl = <<'EndOfExcel';
			if(/"[^\t]*(?:,|"")/) {
				for (@addl) {
					next unless /,/;
					s/^"//;
					s/"$//;
				}
			}
EndOfExcel
	}
	
	my $index = '';
	my @fh; # Array of file handles for sort
	my @fc; # Array of file handles for copy when symlink fails
	my @i;  # Array of field names for sort
	my @o;  # Array of sort options
	my %comma;
	if($options->{INDEX}) {
		my @f; my $f;
		my @n;
		my $i;
		@f = split /[\s,]+/, $options->{INDEX};
		foreach $f (@f) {
			my $found = 0;
			$i = 0;
			if( $f =~ s/:(.*)//) {
				my $option = $1;
				push @o, $1;
			}
			else {
				push @o, '';
			}
			for(@field_names) {
				if($_ eq $f) {
					$found++;
					push(@i, $i);
					push(@n, $f);
					last;
				}
				$i++;
			}
			(pop(@o), next) unless $found;
		}
		if(@i) {
			require IO::File;
			my $fh;
			my $f_string = join ",", @i;
			@f = ();
			for($i = 0; $i < @i; $i++) {
				my $fnum = $i[$i];
				$fh = new IO::File "> $infile.$i[$i]";
				die "Couldn't create $infile.$i[$i]: $!\n"
					unless defined $fh;
				eval {
					unlink "$infile.$n[$i]" if -l "$infile.$n[$i]";
					symlink "$infile.$i[$i]", "$infile.$n[$i]";
				};
				push @fc, ["$infile.$i[$i]", "$infile.$n[$i]"]
					if $@;
				push @fh, $fh;
				if($o[$i] =~ s/c//) {
					$index .= <<EndOfIndex;
			map { print { \$fh[$i] } "\$_\\t\$fields[0]\\n" } split /\s*,\s*/, \$fields[$fnum];
EndOfIndex
				}
				else {
					$index .= <<EndOfIndex;
			print { \$fh[$i] } "\$fields[$fnum]\\t\$fields[0]\\n";
EndOfIndex
				}
			}
		}
	}

my %format = (

	NOTES => <<EndOfRoutine,
        while (<IN>) {
            chomp;
			\@fields = ();
			s/\\r?\\n\\r?\\n([\\000-\\377]*)//
				and \$fields[$idx] = \$1;

			while(s!($codere):[ \\t]*(.*)\\n?!!) {
				next unless defined \$field_hash->{\$1};
				\$fields[\$field_hash->{\$1}] = \$2;
			}
			$index
            \$out->set_row(\@fields);
        }
EndOfRoutine

	LINE => <<EndOfRoutine,
        while (<IN>) {
            chomp;
			\$fields = \@fields = split(/$delimiter/, \$_, $field_count);
			$index
			push (\@fields, '') until \$fields++ >= $field_count;
            \$out->set_row(\@fields);
        }
EndOfRoutine

	NONE => <<EndOfRoutine,
        while (<IN>) {
            chomp;
            \$fields = \@fields = split(/$delimiter/, \$_, 99999);
			$excel
			$index
            push (\@fields, '') until \$fields++ >= $field_count;
            \$out->set_row(\@fields);
        }
EndOfRoutine

	UNIX => <<EndOfRoutine,
        while (<IN>) {
            chomp;
			if(s/\\\\\$//) {
				\$_ .= <IN>;
				redo;
			}
			elsif (s/<<(\\w+)\$//) {
				my \$mark = \$1;
				my \$line = \$_;
				\$line .= Vend::Config::read_here(\\*IN, \$mark);
				\$_ = \$line;
				redo;
			}

            \$fields = \@fields = split(/$delimiter/, \$_, 99999);
			$excel
			$index
            push (\@fields, '') until \$fields++ >= $field_count;
            \$out->set_row(\@fields);
        }
EndOfRoutine

	DITTO => <<EndOfRoutine,
        while (<IN>) {
            chomp;
			if(/^$delimiter/) {
				\$fields = \@addl = split /$delimiter/, \$_, 99999;
				shift \@addl;
				$excel_addl
				my \$i;
				for(\$i = 0; \$i < \@addl; \$i++) {
					\$fields[\$i] .= "\n\$addl[\$i]"
						if \$addl[\$i] ne '';
				}
			}
			else {
				\$fields = \@fields = split(/$delimiter/, \$_, 99999);
				$excel
				$index
				push (\@fields, '') until \$fields++ >= $field_count;
			}
            \$out->set_row(\@fields);
        }
EndOfRoutine

);

    eval $format{$format};
    die $@ if $@;
	if(@fh) {
		my $no_sort;
		my $sort_sub;
		my $ftest = Vend::Util::catfile($Vend::Cfg->{ScratchDir}, 'sort.test');
		my $cmd = "echo you_have_no_sort_but_we_will_cope | sort -f -n -o $ftest";
		system $cmd;
		$no_sort = 1 if ! -f $ftest;
		
		my $fh;
		my $i;
		for ($i = 0; $i < @fh; $i++) {
			close $fh[$i] or die "close: $!";
			unless ($no_sort) {
				$o[$i] = "-$o[$i]" if $o[$i];
				$cmd = "sort $o[$i] -o $infile.$i[$i] $infile.$i[$i]";
				system $cmd;
			}
			else {
				$fh = new IO::File "$infile.$i[$i]";
				my (@lines) = <$fh>;
				close $fh or die "close: $!";
				my $option = $o[$i] || 'none';
				@lines = sort { &{$Sort{$option}} } @lines;
				$fh = new IO::File ">$infile.$i[$i]";
				print $fh @lines;
				close $fh or die "close: $!";
			}
		}
	}
	if(@fc) {
		require File::Copy;
		for(@fc) {
			File::Copy::copy(@{$_});
		}
	}
	delete $out->[$CONFIG]{Clean_start};
	unlockfile(\*IN) or die "unlock\n";
    close(IN);
    return $out;
}

my $white = ' \t';

sub read_quoted_fields {
    my ($filehandle) = @_;
    local ($_, $.);
    while(<$filehandle>) {
        s/[\r\n\cZ]+$//g;           # ms-dos cruft
        next if m/^[$white]*$/o;     # skip blank lines
        my @f = parse($_, $.);
#::logDebug("read: '" . join("','", @f) . "'");
        return parse($_, $.);
    }
    return ();
}

sub parse {
    local $_ = $_[0];
    my $linenum = $_[1];

    my $expect = 1;
    my @a = ();
    my $x;
    while ($_ ne '') {
        if    (m# \A ([$white]+) (.*) #ox) { }
        elsif (m# \A (,[$white]*) (.*) #ox) {
            push @a, '' if $expect;
            $expect = 1;
        }
        elsif (m# \A ([^",$white] (?:[$white]* [^,$white]+)*) (.*) #ox) {
            push @a, $1;
            $expect = 0;
        }
        elsif (m# \A " ((?:[^"] | (?:""))*) " (?!") (.*) #x) {
            ($x = $1) =~ s/""/"/g;
            push @a, $x;
            $expect = 0;
        }
        elsif (m# \A " #x) {
            die "Unterminated quote at line $linenum\n";
        }
        else { die "Can't happen: '$_'" }
        $_ = $2;
    }
    $expect and push @a, '';
    return @a;
}

eval join('',<DATA>) || die $@ unless caller();
1;

__DATA__

my @tests =
  (
   '' => [''],
   ',' => ['', ''],
   'a' => ['a'],
   ',a' => ['', 'a'],
   'a,' => ['a', ''],
   ',,' => ['', '', ''],
   ' a , b , c ' => ['a', 'b', 'c'],
   '""' => [''],
   '" a , b "' => [' a , b '],
   "1,\t2, 3 " => ['1', '2', '3'],
   ' a b c , d e f ' => ['a b c', 'd e f'],
   ' " a"",b ",c' => [' a",b ', 'c'],
   );

my $errors = 0;
my ($in, $out, @a, @b);
while (($in, $out) = splice(@tests, 0, 2)) {
    @a = @$out;
    @b = parse($in);
    if (@a != @b or grep($_ ne shift @a, @b)) {
        print "'$in' parsed as ",
              join(' ',map("<$_>",@b)),
              " instead of the expected ",
              join(' ',map("<$_>",@$out)), "\n";
        ++$errors;
    }
}
print "All tests successful\n" unless $errors;
1;
