# Table/LDAP.pm: LDAP pseudo-table
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

package Vend::Table::LDAP;
@ISA = qw/Vend::Table::Common/;
$VERSION = substr(q$Revision$, 10);
use strict;

use vars qw(
				$CONFIG
				$FILENAME
				$COLUMN_NAMES
				$COLUMN_INDEX
				$KEY_INDEX
				$TIE_HASH
				$EACH
			);
(
	$CONFIG,
	$FILENAME,
	$COLUMN_NAMES,
	$COLUMN_INDEX,
	$KEY_INDEX,
	$TIE_HASH,
	$EACH,
	) = (0 .. 6);

sub import_db {
	my($s) = @_;
	my @caller = caller();
#::logDebug("importing, caller=@caller TIE_HASH index=$TIE_HASH TIE_HASH value=$s->[$TIE_HASH]");
	my $db = Vend::Data::import_database($s->[0], 1);
#::logDebug("failed to import " . ::uneval($s)) if ! $db;
	return undef if ! $db;
	$Vend::Database{$s->[0]{name}} = $db;
	Vend::Data::update_productbase($s->[0]{name});
	return $db;
}

sub config {
	my ($self, $key, $value) = @_;
	return $self->[$CONFIG]{$key} unless defined $value;
	$self->[$CONFIG]{$key} = $value;
}

sub close_table {
	my ($s) = @_;
#::logDebug("closing LDAP table");
	return 1 if ! defined $s->[$TIE_HASH];
#::logDebug("closing LDAP table $s->[$FILENAME]");
	$s->[$TIE_HASH]->unbind;
}

sub open_table {
	my ($class, $config, $tablename) = @_;
#::logDebug("LDAP open_table $tablename" . ::uneval($config));
	my $tablename = $config->{name};
	my $base = $config->{BASE_DN};
	my $host = $config->{LDAP_HOST};
	my $port = 389;
	($host, $port) = split /:/, $host if ($host =~ /:/);
	my $ldap = Net::LDAP->new($host, port => $port) or die "Unable to connect to LDAP server $host:$port\n";
	$ldap->bind(
		dn => $config->{BIND_DN},
		password => $config->{BIND_PW},
	);
	my $m = $ldap->search(
		base => $base,
		filter => "(&(objectclass=mv_database)(db=$tablename))",
	);
#::logDebug('after search m=' . ::uneval($m));
	my $c = $m->count;
	my $co = $m->code;
#::logDebug("count=$c code=$co");
#	die "Unable to find database $tablename count=$c code=$co)" unless ($m->count > 0);
	my $e = $m->entry(0);
#::logDebug('after entry e=' . ::uneval($e));
	my $columns = $e->get('columns');
	my $ki = $e->get('key');
	unshift @$columns, pop @$ki;
	@$columns = map { lc $_ } @$columns;
#::logDebug('columns=' . ::uneval($columns));
    my $column_index = Vend::Table::Common::create_columns($columns, $config);
	my $s = [
				$config,
				$config->{name},
				$columns,
				$column_index,
				$config->{KEY_INDEX},
				$ldap
			];
	return bless $s, $class;
}

sub create {
    my ($class, $config, $columns, $tablename) = @_;

    $config = {} unless defined $config;

    die "columns argument $columns is not an array ref\n"
        unless CORE::ref($columns) eq 'ARRAY';
	my $base = $config->{BASE_DN};
	my $host = $config->{LDAP_HOST};
	my $port = 389;
	($host, $port) = split /:/, $host if ($host =~ /:/);
    my $column_index = Vend::Table::Common::create_columns($columns, $config);
	my $ldap = Net::LDAP->new($host, port => $port) or die "Unable to connect to LDAP server $host:$port\n";
#::logDebug("created object " . ::uneval($ldap));
	$ldap->bind(
		dn => $config->{BIND_DN},
		password => $config->{BIND_PW},
	);
#::logDebug("bound object");
	my (@tmpcols) = @$columns;
	shift @tmpcols;
	require Net::LDAP::Entry;
	my $e = Net::LDAP::Entry->new;
	$e->dn('db=' . $config->{name} . ', ' . $base);
	$e->add( 'objectclass' => 'mv_database',
			'db' => $config->{name},
			'key' => $config->{KEY},
			'columns' => \@tmpcols,
	);
	my $m = $ldap->add($e);
#::logDebug("added entry");
    my $s = [
				$config,
				$config->{name},
				$columns,
				$column_index,
				$config->{KEY_INDEX},
				$ldap,
			];
#::logDebug("Created database $config->{name}" . ::uneval($s));
#::logDebug("Created database $config->{name}");
    bless $s, $class;
}

sub new {
	my ($class, $obj) = @_;
	bless [$obj], $class;
}

sub field {
	my ($s, $key, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
#::logDebug("LDAP field $key $column");
	my $ki = $s->[$CONFIG]->{KEY};
	my $n = $s->[$FILENAME];
	my $b = $s->[$CONFIG]->{BASE_DN};
	my $m = $s->[$TIE_HASH]->search(
		base => "db=$n, $b",
		filter => "(&(objectclass=mv_data)($ki=$key))",
	);
	die "There is no row with index '$key'" unless ($m->count > 0);
	my $e = $m->entry(0);
	my $d = $e->get($column);
	return (pop @$d);
}

sub row {
    my ($s, $key) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
	my $rh = row_hash($key);
	my @a = ();
	@a = @$rh->{@{$s->[$COLUMN_NAMES]}};
    return @a;
}

sub row_hash {
    my ($s, $key) = @_;
#::logDebug("LDAP row_hash $key");
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
	my $ki = $s->[$CONFIG]->{KEY};
   	my $n = $s->[$FILENAME];
	my $b = $s->[$CONFIG]->{BASE_DN};
	my $m = $s->[$TIE_HASH]->search(
		base => "db=$n, $b",
		filter => "(&(objectclass=mv_data)($ki=$key))",
	);
    die "There is no row with index '$key'" unless ($m->count > 0);
	my $e = $m->entry(0);
	my %row;
	my $c;
	foreach $c (@{$s->[$COLUMN_NAMES]})
	{
		my $d = $e->get($c);
		$row{$c} = pop @$d;
	}
    return \%row;
}

*row_array = \&row;

sub columns {
    my ($s) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    return @{$s->[$COLUMN_NAMES]};
}


sub field_settor {
    my ($s, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    return sub {
        my ($key, $value) = @_;
		my $n = $s->[$FILENAME];
		my $b = $s->[$CONFIG]->{BASE_DN};
		my $ki = $s->[$CONFIG]->{KEY};
		my $code;
		if ($s->record_exists($key)) {
        	my $m = $s->[$TIE_HASH]->modify(
				dn => "$ki=$key, db=$n, $b",
				modify => [ $column => $value ],
			);
			$code = $m->code;
		}
		else {
			my $m = $s->[$TIE_HASH]->add(
				dn => "$ki=$key, db=$n, $b",
				attr => [ objectclass => 'mv_data',
					  db => $n,
					  $ki => $key,
					  $column => $value ],
			);
			$code = $m->code;
		}
		$code and die "Failed to set row $ki=$key: $code";
		return undef;
    };
}

sub set_field {
    my ($s, $key, $column, $value) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to set $s->[$CONFIG]{name}::${column}::$key in read-only table");
		return undef;
	}
    my %row;
	my $code;
	my $ki = $s->[$CONFIG]->{KEY};
	my $n = $s->[$CONFIG]{name};
	my $b = $s->[$CONFIG]->{BASE_DN};
	my $m;
#::logDebug("DN is db=$n, $b" );
	if($s->record_exists($key)) {
		$m = $s->[$TIE_HASH]->modify(
			"$ki=$key, db=$n, $b",
			replace => {$column => $value},
		);
		$code = $m->code;
	}
	else {
		$m = $s->[$TIE_HASH]->add(
			dn => "$ki=$key, db=$n, $b",
			attr => [
						objectclass => 'mv_data',
						db => $n,
						$ki => $key,
						$column => $value,
					],
		);
		$code = $m->code;
	}
	$code and die "Failed to set row $ki=$key: $value errnum=$code errstr=" . $m->error() . "\n";;
	$value;
}

sub set_row {
    my ($s, @fields) = @_;
#	my $x = 0;
#	my $subname;
#	while ((undef, undef, undef, $subname) = caller($x++))
#	{
#::logDebug("x=$x subname=$subname");
#	}
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
	my $ki = $s->[$CONFIG]->{KEY};
	my $n = $s->[$FILENAME];
	my $b = $s->[$CONFIG]->{BASE_DN};
	my $key = $fields[$ki];
	my @fh = ( objectclass => 'mv_data',
			   db => $n, );
	my $f;
	my $x = 0;
	foreach $f (@{$s->[$COLUMN_NAMES]})
	{
		push @fh, $f, $fields[$x++];
	}
	my $code;
	my $op;
	if($s->record_exists($key)) {
		$op = 'modify';
		my $m = $s->[$TIE_HASH]->modify(
			dn => "$ki=$key, db=$n, $b",
			replace => \@fh,
		);
		$code = $m->code;
	}
	else {
		$op = 'add';
		my $m = $s->[$TIE_HASH]->add(
			dn => "$ki=$key, db=$n, $b",
			attr => \@fh,
		);
		$code = $m->code;
	}
	$code and die "Failed to set row $ki=$key code=$code op=$op";
	$ki;
}

sub inc_field {
    my ($s, $key, $column, $adder) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
	my $f = field($key, $column);
	$f += $adder;
	set_field($key, $column, $f);
}

sub each_record {
    my ($s) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    my $key;
	my @r;
	my $ki = $s->[$CONFIG]->{KEY};
	unless (defined $s->[$EACH]) {
		my $n = $s->[$CONFIG]->{name};
		my $b = $s->[$CONFIG]->{BASE_DN};
#::logDebug("DN is db=$n, $b" );
		my $m = $s->[$TIE_HASH]->search(
			base => "db=$n, $b",
			filter => "(objectclass=mv_data)",
		);
		my $ref = $m->as_struct;
#::logDebug("count is " . $m->count() );
		my $data;
		my $repos = {};
		my $i = 0;
		my @repos;
		my @names = @{$s->[$COLUMN_NAMES]};
		for(;;) {
			last unless defined ($data = $m->entry($i++));
			my $k = $data->get($ki)->[0];
			my (@record) = $k;
			for(@names) {
				push @record, $data->get($_);
			}
			push @repos, \@record;
		}
		$s->[$EACH] = \@repos;
#::logDebug("each is " . ::uneval($s->[$EACH]) );
	}
	my $val;
	unless (defined $s->[$EACH][0]) {
		undef $s->[$EACH];
		return ();
	}
	return @{ shift @{$s->[$EACH]} };
}

sub each_nokey {
    my (@ary) = each_record(@_);
	shift @ary;
	return @ary;
}

sub record_exists {
    my ($s, $key) = @_;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
	my $ki = $s->[$CONFIG]->{KEY};
   	my $n = $s->[$CONFIG]{name};
	my $b = $s->[$CONFIG]->{BASE_DN};
	my $m = $s->[$TIE_HASH]->search(
		base => "db=$n, $b",
		filter => "(&(objectclass=mv_data)($ki=$key))",
	);
	if ($m->count > 0)
	{
#::logDebug("$ki=$key, db=$n, $b exists");
	}
    return $m->count;
}

*test_record = \&record_exists;

sub delete_record {
    my ($s, $key) = @_;
#    delete($s->[$TIE_HASH]{$key});
#::logDebug("delete $key not impl.");
}

sub clear_table {
    my ($s) = @_;
#::logDebug("clear table not impl.");
}

sub touch {
	1
}

sub ref {
	my $s = shift;
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
	return $s;
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
e:logDebug("opt is: " . Vend::Util::uneval($opt));
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

# Unfortunate hack need for Safe searches
*column_index	= \&Vend::Table::Common::column_index;
*numeric		= \&Vend::Table::Common::numeric;

1;
