# Data.pm - Minivend databases
#
# $Id: Data.pm,v 1.52 1999/02/15 08:50:59 mike Exp mike $
# 
# Copyright 1996-1999 by Michael J. Heins <mikeh@iac.net>
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation and modified by the MiniVend license;
# either version 2 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

package Vend::Data;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(

close_database
column_exists
database_field
database_ref
database_exists_ref
database_key_exists
db_column_exists
export_database
import_database
increment_field
item_description
item_field
item_price
item_subtotal
sql_query
open_database
product_code_exists_ref
product_code_exists_tag
product_description
product_field
product_price
read_accessories
read_pricing
read_salestax
read_shipping
set_field

);
@EXPORT_OK = qw(update_productbase column_index);

use strict;
use File::Basename;
use Vend::Util;
use Vend::Interpolate;
use Vend::Table::DummyDB;
use Vend::Table::Import qw(import_ascii_delimited import_quoted);

File::Basename::fileparse_set_fstype($);

BEGIN {
	if($Global::DBI) {
		require Vend::Table::DBI;
	}
	if($Global::GDBM) {
		require Vend::Table::GDBM;
	}
	if($Global::DB_File) {
		require Vend::Table::DB_File;
	}
	require Vend::Table::InMemory;
}

my ($Products, $Item_price);

sub database_exists_ref {
	return $_[0] if ref $_[0];
	return $Vend::Database{$_[0]} || undef;
}

sub database_key_exists {
    my ($db,$key) = @_;
    return $db->record_exists($key);
}

sub product_code_exists_ref {
    my ($code, $base) = @_;
	my($ref,$real,$dummy);
	if(defined $base and $base) {
		return undef unless $ref = $Vend::Productbase{$base};
		($real, $dummy) = $ref->record_exists($code);
		return $Vend::Productbase{$base} if $real;
		return 0;
	}

	foreach $ref (@Vend::Productbase) {
		($real, $dummy) = $ref->record_exists($code);
		return $dummy || $ref  if $real;
	}
	return 0;
}

sub product_code_exists_tag {
    my ($code, $base) = @_;
	if($base) {
		return undef unless $Vend::Productbase{$base};
		return $base if $Vend::Productbase{$base}->record_exists($code);
		return 0;
	}
	my ($ref, $real, $dummy);
	foreach $ref (@Vend::Productbase) {
		($real, $dummy) = $ref->record_exists($code);
		next unless $real;
		$base = $dummy || $ref;
		return $Vend::Basefinder{$base};
	}
	return 0;
}

sub open_database {
	return tie_database() if $_[0] || $Global::AcrossLocks;
	dummy_database();
}

sub tie_database {
	my ($name, $data);
    while (($name,$data) = each %{$Vend::Cfg->{Database}}) {
# DEBUG
#Vend::Util::logDebug
#("Calling tie_database $name $data->{name}, $data->{file}, $data->{type}\n")
#	if ::debug(0x4);
# END DEBUG
		if( $data->{type} =~ /^[87]$/ or $data->{MEMORY} ) {
			$Vend::Database{$name} = 
				import_database($data->{file},$data->{type},$data->{name});
		}
		else {
			$Vend::Database{$name} = new Vend::Table::DummyDB $data;
		}
	}
	update_productbase();
}

sub dummy_database {
	my ($name, $data);
    while (($name,$data) = each %{$Vend::Cfg->{Database}}) {
# DEBUG
#Vend::Util::logDebug
#("dummy_database $name, $data\n")
#	if ::debug(0x4);
# END DEBUG
		$Vend::UPPERCASE{$name} = 1
			if $data->{UPPERCASE};
		$Vend::Database{$name} = new Vend::Table::DummyDB $data;
	}
	update_productbase();
}

sub update_productbase {

	if(defined $_[0]) {
		return unless ( defined $Vend::Productbase{$_[0]} or
						$_[0] eq $Vend::Cfg->{PriceDatabase} );
	}
# DEBUG
#Vend::Util::logDebug
#("Update productbase " . ($_[0] || '') . "\n")
#	if ::debug(0x4);
# END DEBUG
	undef @Vend::Productbase;
	for(@{$Vend::Cfg->{ProductFiles}}) {
		unless ($Vend::Database{$_}) {
		  die "$_ not a database, cannot use as products file\n";
		}
		$Vend::Productbase{$_} = $Vend::Database{$_};
		$Vend::Basefinder{$Vend::Database{$_}} = $_;
		push @Vend::Productbase, $Vend::Database{$_};
	}
	$Vend::Cfg->{Pricing} = $Vend::Database{$Vend::Cfg->{PriceDatabase}}
		if $Vend::Database{$Vend::Cfg->{PriceDatabase}};
	$Products = $Vend::Productbase[0];

}

sub product_price {
    my ($code, $q, $base) = @_;

	$base = $Vend::Basefinder{$base}
		if ref $base;

	return item_price(
		{
			code		=> $code,
			quantity	=> $q || 1,
			mv_ib		=> $base || undef,
		},
		$q
	);
}

sub product_description {
    my ($code, $base) = @_;
    #return "NA" unless $base = product_code_exists_ref($code, $base || undef);
    return "" unless $base = product_code_exists_ref($code, $base || undef);
    return database_field($base, $code, $Vend::Cfg->{DescriptionField});
}

sub database_field {
    my ($db, $key, $field_name) = @_;
    $db = database_exists_ref($db) or return '';
	$db = $db->ref;
    return '' unless $db->test_record($key);
    return '' unless defined $db->test_column($field_name);
    return $db->field($key, $field_name);
}

sub database_row {
    my ($db, $key, $field_name) = @_;
    $db = database_exists_ref($db) or return '';
	$db = $db->ref;
    return '' unless $db->test_record($key);
    return $db->row_hash($key);
}

sub increment_field {
    my ($db, $key, $field_name, $adder) = @_;

    my ($real, $ref) = $db->record_exists($key);
    return undef unless $real;
	$db = $ref if defined $ref;
    return undef unless defined $db->test_column($field_name);
    return $db->inc_field($key, $field_name, $adder);
}

sub call_method {
	my($base, $method, @args) = @_;

	my $db = ref $base ? $base : $Vend::Database{$base};
	$db = $db->ref();

	no strict 'refs';
	$db->$method(@args);
}

sub import_text {
	my ($table, $type, $options, $text) = @_;
#::logGlobal("Called import_text: table=$table type=$type opt=" . Data::Dumper::Dumper($options) . " text=$text");
	my ($delimiter, $record_delim) = find_delimiter($type);
	my $db = $Vend::Database{$table}
		or die ("Non-existent table '$table'.\n");
	$db = $db->ref();

	my @columns;
	@columns = ('code', $db->columns());

	if($options->{'continue'}) {
		$options->{CONTINUE} = uc $options->{'continue'};
		$options->{SEPARATOR} = uc $options->{separator}
			if defined $options->{separator};
	}

	my $sub = sub { return $db };
	my $now = time();
	my $fn = $Vend::Cfg->{ScratchDir} . "/import.$$.$now";
	$text =~ s/^\s+//;
	$text =~ s/\s+$//;

	if($delimiter eq 'CSV') {
		my $add = '"';
		$add .= join '","', @columns;
		$add .= '"';
		$text = "$add\n$text";
	}
	else {
		$options->{'field_names'} = \@columns;
		$options->{'delimiter'} = $delimiter;
	}

	if($options->{'file'}) {
		$fn = $options->{'file'};
		if( $Global::NoAbsolute) {
			die "No absolute file names like '$fn' allowed.\n"
				if Vend::Util::file_name_is_absolute($fn);
		}
	}
	else {
		Vend::Util::writefile($fn, $text)
			or die ("Cannot write temporary import file $fn: $!\n");
	}

	my $save = $/;
	$/ = $record_delim if defined $record_delim;
	$options->{Object} = $db;
	if($delimiter ne 'CSV') {
		import_ascii_delimited($fn, $options);
	}
	else {
		import_quoted($fn, $options);
	}
	$/ = $save;
	unlink $fn unless $options->{'file'};
	return 1;
}

sub set_field {
    my ($db, $key, $field_name, $value, $append) = @_;

	$db = $db->ref;

	# Create it if it doesn't exist
	unless ($db->record_exists($key)) {
# DEBUG
#Vend::Util::logDebug
#("Creating empty record $key\n")
#	if ::debug(0x1);
# END DEBUG
		my @fields;
		my $count = scalar $db->columns();
		@fields = ('') x $count;
		$db->set_row($key, @fields);
	}
	elsif ($append) {
		$value = $db->field($key, $field_name) . $value;
	}

    return undef unless defined $db->test_column($field_name);
    return $db->set_field($key, $field_name, $value);
}

sub product_field {
    my ($field_name, $code, $base) = @_;
	my ($db);
    return "" unless $db = product_code_exists_ref($code, $base || undef);
    return "" unless defined $db->test_column($field_name);
    return $db->field($code, $field_name);
}

my %T;

TAGBUILD: {

	my @th = (qw!

		arg
		/arg
		control
		/control
		query
		/query

	! );

	my $tag;
	for (@th) {
		$tag = $_;
		s/(\w)/[\u$1\l$1]/g;
		s/[-_]/[-_]/g;
		$T{$tag} = "\\[$_";
	}
}

sub sql_query {
	my($type, $internal_query, $query, $msql, $table, $list) = @_;
	my ($db);

	$table = 'products' unless defined $table;
	$db = $Vend::Database{$table}
		or die "dbi_query: unknown base table $table.\n";
	$db = $db->ref();

	$type = lc $type;

	if (defined $list) {
		$query = $internal_query if $internal_query and $type ne 'list';
		$query .= $list;
	}

	my @arg;
	while ($query =~ s:$T{'arg'}\](.*?)$T{'/arg'}\]::o) {
		push(@arg, $1);
	}

	my $config = {};
	while ($query =~ s:$T{'control'}\s+([\w][-\w]*)\]([\000-\377]*?)$T{'/control'}\]::) {
		$config->{uc $1} = $2;
	}

	if($type eq 'list') {
		$list = $query;
		$query = $internal_query;
		push(@arg, $1) while $query =~ s:$T{'arg'}\](.*?)$T{'/arg'}\]::o;
		$list =~ s:$T{'query'}\]([\000-\377]+)$T{'/query'}\]::o and $query = $1;
	}

	$type eq 'list' and
		return Vend::Interpolate::tag_sql_list(
							$list,
							$db->array_query($query, $table, $config, @arg)
							);
	$type eq 'array' and
		return uneval $db->array_query($query, $table, $config, @arg);
	$type eq 'hash' and
		return uneval $db->hash_query($query, $table, $config, @arg);
	$type eq 'set' and
		return $db->set_query($query, $table, $config, @arg);
	$type eq 'html' and
		return $db->html_query($query, $table, $config, @arg);
	$type eq 'param' and
		return $db->param_query($query, $table, $config, @arg);
	# shouldn't reach this if proper tag
#	logError("Bad SQL query selector: '$type' for $table");
	logError( errmsg('Data.pm:1', "Bad SQL query selector: '%s' for %s" , $type, $table) );
	return '';
}

sub column_index {
    my ($field_name) = @_;
    return undef unless defined $Products->test_column($field_name);
    return $Products->column_index($field_name);
}

sub column_exists {
    my ($field_name) = @_;
    return $Products->test_column($field_name);
}

sub db_column_exists {
    my ($db,$field_name) = @_;
    return defined $db->test_column($field_name);
}

sub close_database {
	my($db, $name);
	undef $Products;
	while( ($name)	= each %Vend::Database ) {
    	$Vend::Database{$name}->close_table()
			unless defined $Vend::Cfg->{SaveDatabase}->{$name};
		delete $Vend::Database{$name};
	}
	undef %Vend::WriteDatabase;
	undef %Vend::Basefinder;
}

sub database_ref {
	my $db = $_[0] || $Products;
	if (ref ($db) =~ /dummy/i) {
		$db = $db->import_db($db);
	}
	$db;
}

## PRODUCTS

# Read in the shipping file.

sub make_three {
	my $zone = shift;
	while ( length($zone) < 3 ) {
		$zone = "0$zone";
	}
	return $zone;
}

sub read_shipping {
    my($code, $desc, $min, $criterion, $max, $cost, $mode);

	my $file = $Vend::Cfg->{Special}{'shipping.asc'}
				|| Vend::Util::catfile($Vend::Cfg->{ProductDir},'shipping.asc');
    open(Vend::SHIPPING, $file) or do {
			logError( errmsg('Data.pm:2',
								"Could not open shipping file %s: %s" , $file, $!
							)
					)
				if $Vend::Cfg->{CustomShipping};
			return undef;
		};
	$Vend::Cfg->{Shipping_desc} = {};
	$Vend::Cfg->{Shipping_criterion} = {};
	$Vend::Cfg->{Shipping_min} = {};
	$Vend::Cfg->{Shipping_max} = {};
	$Vend::Cfg->{Shipping_cost} = {};
	my %seen;
	my $append = '00000';
    while(<Vend::SHIPPING>) {
		chomp;
		if(s/\\$//) {
			$_ .= <Vend::SHIPPING>;
			redo;
		}
		elsif (s/<<(\w+)$//) {
			my $mark = $1;
			my $line = $_;
			$line .= Vend::Config::read_here(\*Vend::SHIPPING, $mark);
			$_ = $line;
			redo;
		}
		next unless /\S/;
		($mode, $desc, $criterion, $min, $max, $cost) = split(/\t/, $_, 6);
		$code = defined $seen{$mode} ? $mode . $append++ : $mode; 
		$seen{$code} = 1;
# DEBUG
#Vend::Util::logDebug
#("reading shipping code $code\n")
#	if ::debug(0x4);
# END DEBUG
		$Vend::Cfg->{Shipping_desc}->{$code} = $desc;
		$Vend::Cfg->{Shipping_criterion}->{$code} = $criterion;
		$Vend::Cfg->{Shipping_min}->{$code} = $min;
		$Vend::Cfg->{Shipping_max}->{$code} = $max;
		$Vend::Cfg->{Shipping_cost}->{$code} = $cost;
		if ($cost =~ s/^\s*c\s+(\w+)\s*//) {
			my $zone = $1;
			next if defined $Vend::Cfg->{Shipping_zone}{$zone};
			my $ref;
			if ($cost =~ /^{[\000-\377]+}$/ ) {
				eval { $ref = eval $cost };
			}
			else {
				$ref = {};
				my($name, $file, $length, $multiplier) = split /\s+/, $cost;
				$ref->{zone_name} = $name || undef;
				$ref->{zone_file} = $file if $file;
				$ref->{mult_factor} = $multiplier if defined $multiplier;
				$ref->{str_length} = $length if defined $length;
			}
			if ($@
				or ref($ref) !~ /HASH/
				or ! $ref->{'zone_name'}) {
#				logError("Bad shipping configuration for mode $code, skipping.");
				logError( errmsg('Data.pm:3', "Bad shipping configuration for mode %s, skipping." , $code) );
				$Vend::Cfg->{Shipping_cost}->{$code} = 0;
				next;
			}
			$ref->{zone_key} = $zone;
			$ref->{str_length} = 3 unless defined $ref->{str_length};
			$ref->{zone_file} = $Vend::Cfg->{ProductDir} . "/" . $ref->{zone_name}
					unless defined $ref->{zone_file};
			$Vend::Cfg->{Shipping_zone}{$zone} = $ref;
		}
		elsif ($cost =~ s/^\s*g\s+//) {
			$Vend::Cfg->{Shipping_options}->{mv_global} = {}
				unless defined $Vend::Cfg->{Shipping_options}{mv_global};
			if ($cost =~ /\bpricedivide[\s=]*(\d*)/i) {
				my $set = length($1) ? $1 : 1;
				$Vend::Cfg->{Shipping_options}{mv_global}{PriceDivide} = $set;
			}
		}
		elsif ($cost =~ s/^\s*o\s+//) {
			$Vend::Cfg->{Shipping_options}->{$mode} = {}
				unless defined $Vend::Cfg->{Shipping_options}{$mode};
			if ($cost =~ /\bpricedivide[\s=]*(\d*)/i) {
				my $set = length($1) ? $1 : 1;
				$Vend::Cfg->{Shipping_options}{$mode}{PriceDivide} = $set;
			}
		}
    }
    close Vend::SHIPPING;
	if($Vend::Cfg->{UpsZoneFile} and ! defined $Vend::Cfg->{Shipping_zone}{'u'} ) {
		$Vend::Cfg->{Shipping_zone}{'u'} = {
				zone_file	=> $Vend::Cfg->{UpsZoneFile},
				zone_key	=> 'u',
				zone_name	=> 'UPS',
				};
	}
	UPSZONE: {
		my $zone;
		foreach $zone (keys %{$Vend::Cfg->{Shipping_zone}}) {
			my $ref = $Vend::Cfg->{Shipping_zone}{$zone};
			my @zone = split(/[\r\n]+/, readfile($ref->{zone_file}) );
			unless (@zone) {
#				logError("Bad shipping file for zone '$zone', lookup disabled.");
				logError( errmsg('Data.pm:4', "Bad shipping file for zone '%s', lookup disabled." , $zone) );
				next;
			}
			if($zone[0] !~ /\t/) {
				@zone = grep /\S/, @zone;
				@zone = grep /^[^"]/, @zone;
				$zone[0] =~ s/[^\w,]//g;
				$zone[0] =~ s/^\w+/low,high/;
				@zone = grep /,/, @zone;
				$zone[0] =~	s/\s*,\s*/\t/g;
				for(@zone[1 .. $#zone]) {
					s/^\s*(\w+)\s*,/make_three($1) . ',' . make_three($1) . ','/e;
					s/^\s*(\w+)\s*-\s*(\w+),/make_three($1) . ',' . make_three($2) . ','/e;
					s/\s*,\s*/\t/g;
				}
			}
			$ref->{zone_data} = \@zone;
# DEBUG
#Vend::Util::logDebug
#("\nZone fields: $zone[0]")
#	if ::debug(0x4);
# END DEBUG
		}
	}
	1;
}

# Read in the accessories file.

sub read_accessories {
    my($code, $accessories);

	my $file = $Vend::Cfg->{Special}{'accessories.asc'}
				|| Vend::Util::catfile($Vend::Cfg->{ProductDir}, 'accessories.asc');
    open(Vend::ACCESSORIES, $file) or return undef;
    while(<Vend::ACCESSORIES>) {
		chomp;
		tr/\r//d;
		if (s/\\\s*$//) { # handle continues
	        $_ .= <Vend::ACCESSORIES>;
			redo;
		}
		($code, $accessories) = split(/\t/, $_, 2);
		$Vend::Cfg->{Accessories}->{$code} = $accessories;
    }
    close Vend::ACCESSORIES;
	1;
}

# Read in the sales tax file.
sub read_salestax {
    my($code, $percent);

	my $file = Vend::Util::catfile($Vend::Cfg->{ProductDir}, "salestax.asc");
	$Vend::Cfg->{SalesTaxTable} = {};
    open(Vend::SALESTAX, $file) or do {
#					logError("Could not open salestax file $file: $!")
					logError( errmsg('Data.pm:5', "Could not open salestax file %s: %s" , $file, $!) )
						if $Vend::Cfg->{SalesTax};
					return undef;
				};
    while(<Vend::SALESTAX>) {
		chomp;
		tr/\r//d;
		($code, $percent) = split(/\s+/, $_, 2);
		$Vend::Cfg->{SalesTaxTable}->{"\U$code"} = $percent;
    }
    close Vend::SALESTAX;

	if(not defined $Vend::Cfg->{SalesTaxTable}->{'DEFAULT'}) {
		$Vend::Cfg->{SalesTaxTable}->{'DEFAULT'} = 0;
	}

	1;
}

# Read in the pricing file, if it exists
sub read_pricing {
    my($code, @breaks);
	if($Vend::Cfg->{PriceBreaks} || $Vend::Cfg->{PriceAdjustment}) {
		die "No price database '$Vend::Cfg->{PriceDatabase}' defined, PriceBreaks or PriceAdjustment enabled.\n"
			 unless $Vend::Cfg->{Database}->{$Vend::Cfg->{PriceDatabase}};
	}
	return ( build_item_price(), build_quantity_price() );
}

sub quantity_price {
	my ($code,$one,$quan) = @_;

# DEBUG
#Vend::Util::logDebug
#("Called quantity price for '$code' '$one' '$quan'\n")
#	if ::debug(0x1);
# END DEBUG
	return $one unless
			database_key_exists($Vend::Cfg->{Pricing}, $code);
	my(@prices);

	my $fn = ! $Vend::Cfg->{Locale} ? 'price' : $Vend::Cfg->{PriceField};
	@prices =
			split /\s/, database_field($Vend::Cfg->{Pricing}, $code, $fn);

	my ($break,$i,$price,$scratch);
	$price = $one;

	# Use the passed quantity if there
	$quan = 1 unless defined $quan && $quan;

	foreach $break (@{$Vend::Cfg->{PriceBreaks}}) {
		last if $break > $quan;
		$scratch = shift @prices;
		$price = $scratch if $scratch;
	}
	return $price;
}

my %Delimiter = (
	2 => ["\n", "\n\n"],
	3 => ["\n%%\n", "\n%%%\n"],
	4 => ["CSV","\n"],
	5 => ['|', "\n"],
	6 => ["\t", "\n"],
	7 => ["\t", "\n"],
	8 => ["\t", "\n"],
	LINE => ["\n", "\n\n"],
	'%%%' => ["\n%%\n", "\n%%%\n"],
	'%%' => ["\n%%\n", "\n%%%\n"],
	CSV => ["CSV","\n"],
	PIPE => ['|', "\n"],
	TAB => ["\t", "\n"],

	);

sub find_delimiter {
	my ($type) = @_;
	$type = $type || 1;
	return ($Vend::Cfg->{Delimiter}, "\n")
		if $type eq '1' || $type eq 'DEFAULT';

	return @{$Delimiter{$type}}
		if defined $Delimiter{$type}; 
	return ($Vend::Cfg->{FieldDelimiter}->{$type}, 
			$Vend::Cfg->{RecordDelimiter}->{$type});
}

my %db_config = (
		'DBI' => {
				qw/
					Extension			 sql
					RestrictedImport	 1
					Class                Vend::Table::DBI
				/
				},
		'MEMORY' => {
				qw/
					Cacheable			 1
					Class                Vend::Table::InMemory
				/
				},
		'GDBM' => {
				qw/
					TableExtension		 .gdbm
					Extension			 gdbm
					Class                Vend::Table::GDBM
				/
				},
		'DB_FILE' => {
				qw/
					TableExtension		 .db
					Extension			 db
					Class                Vend::Table::DB_File
				/
		},
	);

sub import_database {
    my ($database,$type,$name) = @_;

	my $obj;
	if(ref $database) {
		$obj = $database;
		$database = $obj->{'file'};
		$type     = $obj->{'type'};
		$name     = $obj->{'name'};
	}
	else {
		$obj = $Vend::Cfg->{Database}->{$name};
	}

	if($Vend::Cfg->{AdminDatabase}->{$name} and
		! check_security (
						$database,
						2,
						Vend::Util::check_gate($name,$Vend::Cfg->{ProductDir}),
					)
			)
	{
		logError("Attempt to access protected database by $CGI::host");
		logGlobal("Attempt to access protected database by $CGI::host");
		return undef;
	}
	else {
# DEBUG
#Vend::Util::logDebug
#("Skipped security check for database $name\n")
#	if ::debug(0x4);
# END DEBUG
	}

	return $Vend::Cfg->{SaveDatabase}->{$name}
		if defined $Vend::Cfg->{SaveDatabase}->{$name};
# DEBUG
#Vend::Util::logDebug
#("Import db: dir=$Vend::Cfg->{DataDir} name=$name db=$database type=$type\n")
#	if ::debug(0x4);
# END DEBUG

	my ($delimiter, $record_delim, $change_delimiter, $cacheable);
	my ($base,$path,$tail,$dir,$database_txt);

	$delimiter = $Vend::Cfg->{Delimiter};

	die "import_database: No database name!\n"
		unless $database;


# DEBUG
#Vend::Util::logDebug
#("start=$database_txt path='$path' base='$base' tail='$tail'\n")
#	if ::debug(0x4);
# END DEBUG

	my $database_dbm;
	my $new_database_dbm;
	my $table_name;
	my $new_table_name;
	my $class_config;
	my $db;

	my $no_import = defined $Vend::Cfg->{NoImport}->{$name};

	if (defined $Vend::ForceImport{$name}) {
		undef $no_import;
		delete $Vend::ForceImport{$name};
	}

	$base = $obj->{'name'};
	$dir = $obj->{'dir'} if defined $obj->{'dir'};

	$class_config = $db_config{$obj->{Class} || $Global::Default_database};

	$table_name     = $name;

  IMPORT: {
	last IMPORT if $no_import and $obj->{'dir'};
	last IMPORT if defined $obj->{IMPORT_ONCE} and $obj->{'dir'};

    $database_txt = $database;

	($base,$path,$tail) = fileparse $database_txt, '\.[^/.]+$';

	if(Vend::Util::file_name_is_absolute($database_txt)) {
		if ($Global::NoAbsolute) {
			my $msg = errmsg('Data.pm:10',
							"Security violation for NoAbsolute, trying to import %s",
							$database_txt);
			logError( $msg );
			die "Security violation.\n";
		}
		$dir = $path;
	}
	else {
		$dir = $Vend::Cfg->{DataDir} || $Global::ConfigDir;
		$database_txt = Vend::Util::catfile($dir,$database_txt);
	}

	$obj->{'dir'} = $dir;

	$obj->{ObjectType} = $class_config->{Class};

	if($class_config->{Extension}) {
		$database_dbm = Vend::Util::catfile(
												$dir,
												"$base."     .
												$class_config->{Extension}
											);
		$new_database_dbm =  Vend::Util::catfile(
												$dir,
												"new_$base."     .
												$class_config->{Extension}
											);
	}

	if($class_config->{TableExtension}) {
		$table_name     = $database_dbm;
		$new_table_name = $new_database_dbm;
	}
	else {
		$table_name = $new_table_name = $base;
	}

	if ($class_config->{RestrictedImport}) {
		if (-f $database_dbm or ! -f $database_txt) {
			$no_import = 1;
		}
		else {
			open(Vend::Data::TMP, ">$new_database_dbm");
			print Vend::Data::TMP "\n";
			close(Vend::Data::TMP);
		}
	}

	last IMPORT if $no_import;

	$change_delimiter = $obj->{DELIMITER} if defined $obj->{DELIMITER};

    if (! defined $database_dbm
		or ! -e $database_dbm
        or file_modification_time($database_txt) >
            file_modification_time($database_dbm)) {
		
        warn "Importing $obj->{'name'} table from $database_txt\n";

		$type = 1 unless $type;
		($delimiter, $record_delim) = find_delimiter($change_delimiter || $type);
		$obj->{'delimiter'} = $delimiter;
# DEBUG
#Vend::Util::logDebug
#("Type: $type delimiter: '$delimiter'\n")
#	if ::debug(0x4);
# END DEBUG
		my $save = $/;
		$/ = $record_delim if defined $record_delim;
        $db = $delimiter ne 'CSV'
			? import_ascii_delimited($database_txt, $obj, $new_table_name)
        	: import_quoted($database_txt, $obj, $new_table_name);

		$/ = $save;
		if(defined $database_dbm) {
			$db->close_table() if defined $db;
			undef $db;
			unlink $database_dbm if $Global::Windows;
        	rename($new_database_dbm, $database_dbm)
            	or die "Couldn't move '$new_database_dbm' to '$database_dbm': $!\n";
		}
    }
  }

	my $read_only = ! defined $Vend::WriteDatabase{$name};

		
    if($class_config->{Extension}) {

		$obj->{Read_only} = $read_only;
		$obj->{db_file} = $table_name unless $obj->{db_file};
		$obj->{db_text} = $database_txt unless $obj->{db_text};
    	$db = $class_config->{Class}->open_table( $obj, $table_name );
		$obj->{NAME} = $db->[3] unless defined $obj->{NAME};

# DEBUG
#Vend::Util::logDebug
#("Opening GDBM: RO=$read_only\n")
#	if ::debug(0x4);
# END DEBUG
		if($@) {
			die $@ unless $no_import;
			if(! -f $database_dbm) {
				$Vend::ForceImport{$obj->{'name'}} = 1;
				return import_database($obj);
			}
		}
	}

	if(defined $cacheable) {
		$Vend::Cfg->{SaveDatabase}->{$name} = $db;
	}

	$Vend::Basefinder{$db} = $name;

	$db;
}   

sub index_database {
	my($dbname, $opt) = @_;

	return undef unless defined $dbname;

	my $db;
	$db = database_exists_ref($dbname)
		or do {
			logError( errmsg('Data.pm:6',
						"Vend::Data export: non-existent database %s",
						$db)
					);
			return undef;
		};

	$db = $db->ref();

	my $ext = $opt->{extension} || 'idx';

	my $db_fn = $db->config('db_file');
	my $bx_fn = $opt->{basefile} || $db->config('db_text');
	my $ix_fn = "$bx_fn.$ext";
	my $type  = $opt->{type} || $db->config('type');

#::logGlobal(
#	"dbname=$dbname db_fn=$db_fn bx_fn=$bx_fn ix_fn=$ix_fn\n" .
#	"options: " . Vend::Util::uneval($opt) . "\n"
#	);

	if(		! -f $bx_fn
				or 
			file_modification_time($db_fn)
				>
            file_modification_time($bx_fn)		)
	{
		export_database($dbname, $bx_fn, $type);
	}

	if(		-f $ix_fn
				and 
			file_modification_time($ix_fn)
				>=
            file_modification_time($bx_fn)		)
	{
		# We didn't need to index if got here
		return;
	}

	my $c = {
				mv_list_only	 => 1,
				mv_search_file => $bx_fn,
			};

	Vend::Scan::find_search_params(
			$c,
			Vend::Interpolate::escape_scan($opt->{spec}),
			);
	
	$c->{mv_matchlimit} = 100000
		unless defined $c->{mv_matchlimit};
	my $f_delim = $c->{mv_return_delim} || "\t";
	my $r_delim = $c->{mv_record_delim} || "\n";

	my @fn;
	if($c->{mv_return_fields}) {
		@fn = split /\s*[\0,]+\s*/, $c->{mv_return_fields};
	}

#::logGlobal(
#	"search options: " . Vend::Util::uneval($c) . "\n"
#	);

	open(Vend::Data::INDEX, "+<$ix_fn") or
		open(Vend::Data::INDEX, "+>$ix_fn") or
	   		die "Couldn't open $ix_fn: $!\n";
	lockfile(\*Vend::Data::INDEX, 1, 1)
		or die "Couldn't exclusive lock $ix_fn: $!\n";
	open(Vend::Data::INDEX, "+>$ix_fn") or
	   	die "Couldn't write $ix_fn: $!\n";

	if(@fn) {
		print INDEX " ";
		print INDEX join $f_delim, @fn;
		print INDEX $r_delim;
	}
	print INDEX join $r_delim, @{Vend::Scan::perform_search($c)};

	unlockfile(\*Vend::Data::INDEX)
		or die "Couldn't unlock $ix_fn: $!\n";
	close(Vend::Data::INDEX)
		or die "Couldn't close $ix_fn: $!\n";
	return;
}

sub export_database {
	my($db, $file, $type, $field, $delete) = @_;
	my(@data);
	return undef unless defined $db;

	$db = database_exists_ref($db)
		or do {
#			logError("Vend::Data export: non-existent database $db");
			logError( errmsg('Data.pm:6', "Vend::Data export: non-existent database %s" , $db) );
			return undef;
		};

	$db = $db->ref();

	my $ref;
	$ref = $Vend::Cfg->{Database}->{$Vend::Basefinder{$db}}
		or die "Bad database '$db'.\n";


	my $sql = 0;
	# Some things not supported for SQL types -- can 
	# usually do with [sql set] or [sql list] and [tag log ...]
	if ($ref->{'type'} == 8) {
		$sql = 1;
	}

	my ($delim, $record_delim) = find_delimiter($type || $ref->{'type'});

	$file = $file || $ref->{'file'};

	unless($file =~ m!^([A-Za-z]:)?/!) {
		$file = Vend::Util::catfile( $Vend::Cfg->{DataDir}, $file);
	}

	my @cols = $db->columns();

	my $first_name = 'code';

	my ($notouch, $nuke);
	if($sql) {
		# do nothing about delete and add
		# not supported for those types

		# But put the proper first column name if there
		$first_name = $ref->{FIRST_COLUMN_NAME} 
									if defined $ref->{FIRST_COLUMN_NAME};
	}
	elsif ($field and ! $delete) {
#		logError("Adding field $_");
		logError( errmsg('Data.pm:7', "Adding field %s" , $field) );
		push @cols, $field;
		$notouch = 1;
	}
	elsif ($field and $delete) {
#		logError("Deleting $field...");
		logError( errmsg('Data.pm:8', "Deleting %s..." , $field) );
		my @new = @cols;
		@cols = ();
		my $i = 0;
		for(@new) {
			unless ($_ eq $field) {
				push @cols, $_;
			}
			else {
				$nuke = $i;
				$notouch = 1;
#				logError("Deleting field $_");
				logError( errmsg('Data.pm:9', "Deleting field %s" , $_) );
			}
			$i++;
		}
	}

	my $tempdata;
	open(Vend::Data::EXPORT, "+<$file") or
	   open(Vend::Data::EXPORT, "+>$file") or
	   		die "Couldn't open $file: $!\n";
	lockfile(\*Vend::Data::EXPORT, 1, 1)
		or die "Couldn't exclusive lock $file: $!\n";
	open(Vend::Data::EXPORT, "+>$file") or
	   	die "Couldn't write $file: $!\n";
	if($delim eq 'CSV') {
		$delim = '","';
		print Vend::Data::EXPORT qq%"$first_name","%;
		print Vend::Data::EXPORT join $delim, @cols;
		print Vend::Data::EXPORT qq%"\n%;
		while( (@data) = $db->each_record() ) {
			print Vend::Data::EXPORT '"';
			splice(@data, $nuke, 1) if defined $nuke;
			$tempdata = join $delim, @data;
			$tempdata =~ tr/\n/\r/;
			print Vend::Data::EXPORT $tempdata;
			print Vend::Data::EXPORT qq%"\n%;
		}
	}
	elsif ($delim eq "\n" and $ref->{CONTINUE} eq 'NOTES') {
		my $sep = pop @cols;
		my $nf  = pop @cols;
		print Vend::Data::EXPORT join "\n", $first_name, @cols;
		print Vend::Data::EXPORT "\n$nf $sep\n\n";
		my $i;
		while( (@data) = $db->each_record() ) {
			splice(@data, $nuke, 1) if defined $nuke;
			print Vend::Data::EXPORT "$first_name: ";
			print Vend::Data::EXPORT shift(@data);
			print Vend::Data::EXPORT "\n";
			# Yes, we don't want the last field yet. 8-)
			for($i = 0; $i < $#data; $i++) {
				print Vend::Data::EXPORT
					"$cols[$i]: $data[$i]\n" unless $data[$i] eq '';
			}
			print Vend::Data::EXPORT "\n";
			print Vend::Data::EXPORT pop(@data);
			print Vend::Data::EXPORT "\n$sep\n";
		}
	}
	else {
		print Vend::Data::EXPORT join $delim, $first_name, @cols;
		print Vend::Data::EXPORT $record_delim;
		while( (@data) = $db->each_record() ) {
			splice(@data, $nuke, 1) if defined $nuke;
			$tempdata = join $delim, @data;
			if($record_delim eq "\n") {
				$tempdata =~ tr/\n/\r/;
			}
			print Vend::Data::EXPORT $tempdata;
			print Vend::Data::EXPORT $record_delim;
		}
	}
	unlockfile(\*Vend::Data::EXPORT)
		or die "Couldn't unlock $file: $!\n";
	close(Vend::Data::EXPORT)
		or die "Couldn't close $file: $!\n";
	$db->touch() unless defined $notouch;
	1;
}

sub build_quantity_price {
	my $code = <<'EOF';
sub {
my ($code,$one,$quan) = @_;
return $one unless database_key_exists($Vend::Cfg->{Pricing}, $code);
my(@prices) = split /\s/, database_field($Vend::Cfg->{Pricing}, $code, 'price');
my($break,$i,$price,$scratch);
$price = $one;
unless (defined $quan) {
  $quan = 0;
EOF

	if ($Vend::Cfg->{MixMatch}) {
		$code .= <<'EOF';
  for(@{$Vend::Items}) {
	  $quan += $_->{quantity};
  }
EOF
	}		
	else {
		$code .= <<'EOF';
  for(@{$Vend::Items}) {
	$quan += $_->{quantity} if $_->{code} eq $code;
  }
EOF
	}

	$code .= <<'EOF';
 }

foreach $break (@{$Vend::Cfg->{PriceBreaks}}) {
	last if $break > $quan;
	$scratch = shift @prices;
	$price = $scratch if $scratch;
}
	return $price;
}
EOF

	my $sub = eval $code;
	die "Bad quantity_price routine:\n\n$@\n" if $@;
	return $sub;
}

sub chain_cost {
	my ($item, $raw) = @_;
	return $raw if $raw =~ /^[\d.]*$/;
	my $price;
	my $final = 0;
	my $its = 0;
	my @p;
	$raw =~ s/^\s+//;
	$raw =~ s/\s+$//;
	if($raw =~ /^\[\B/ and $raw =~ /\]$/) {
		my $ref = Vend::Interpolate::tag_calc($raw);
		@p = @{$ref} if ref $ref;
	}
	else {
		@p = Text::ParseWords::shellwords($raw);
	}
	if(scalar @p > 16) {
			::logError('Too many chained cost levels for item ' .  uneval($item) );
			return undef;
	}

#::logGlobal("chain_cost item = " . uneval ($item) );
	my ($chain, $percent);
	my $passed_key;
	my $want_key;
CHAIN:
	foreach $price (@p) {
		if($its++ > 20) {
			::logError('Too many chained cost levels for item ' .  uneval($item) );
			last CHAIN;
		}
		$price =~ s/^\s+//;
		$price =~ s/\s+$//;
		if ($want_key) {
			$passed_key = $price;
			undef $want_key;
			next CHAIN;
		}
		if ($price =~ s/^;//) {
			next if $final;
		}
		$chain = $price =~ s/,$// ? 1 : 0 unless $chain;
		if ($price =~ /^ \(  \s*  (.*)  \s* \) \s* $/x) {
			$price = $1;
			$want_key = 1;
		}
		if ($price =~ s/^([^-+\d.].*)//s) {
			my $mod = $1;
			if($mod =~ s/^\$(\d|$)/$1/) {
				$price = $item->{mv_price} || $mod;
				redo CHAIN;
			}
			elsif($mod =~ /^(\w*):([^:]+)(:(\S*))?$/) {
				my ($table,$field,$key) = ($1, $2, $4);
				if($passed_key) {
					(! $key   and $key   = $passed_key)
						or 
					(! $field and $field = $passed_key)
						or 
					(! $table and $table = $passed_key);
					undef $passed_key;
				}
				my @breaks;
				if($field =~ /,/ || $field =~ /\.\./) {
					my (@tmp) = split /,/, $field;
					for(@tmp) {
						if (/(.+)\.\.+(.+)/) {
							push @breaks, $1 .. $2;
						}
						else {
							push @breaks, $_;
						}
					}
				}
				if(@breaks) {
					my $attribute = 'quantity';
					$attribute = shift @breaks  if $breaks[0] !~ /\d/;

					$field = shift @breaks;
					my $test = $field;
					$test =~ s/\D+//;
					redo CHAIN if $item->{$attribute} < $test;
					for(@breaks) {
						$test = $_;
						$test =~ s/\D+//;
						last if $test > $item->{$attribute};
						$field = $_;
					}
				}
				$price = database_field(
						($table || $item->{mv_ib} || $Vend::Cfg->{ProductFiles}[0]),
											($key || $item->{code}),
											$field
										);
				redo CHAIN;
			}
			elsif ($mod =~ s/^[&]//) {
				my $adj;
				$Vend::Interpolate::item = $item;
				$Vend::Interpolate::s = $final;
				$Vend::Interpolate::q = $item->{quantity};
				$price = Vend::Interpolate::tag_calc($mod);
				undef $Vend::Interpolate::item;
				redo CHAIN;
			}
			elsif ($mod =~ s/^=([\d.]*)=([^=]+)//) {
				$final += $1 if $1;
				my ($attribute, $table, $field, $key) = split /:/, $2;
				$item->{$attribute} and
					do {
						$key = $field ? $item->{$attribute} : $item->{'code'};
						$price = database_field( ( $table ||
													$item->{mv_ib} ||
													$Vend::Cfg->{ProductFiles}[0]),
												$key,
												($field || $item->{$attribute})
										);
						redo CHAIN;
					};
			}
			elsif($mod =~ /^\s*[[_]+/) {
				$::Scratch->{'mv_item_object'} = $Vend::Interpolate::item = $item;
				$Vend::Interpolate::s = $final;
				$Vend::Interpolate::q = $item->{quantity};
				$price = Vend::Interpolate::interpolate_html($mod);
				undef $::Scratch->{'mv_item_object'};
				undef $Vend::Interpolate::item;
				redo CHAIN;
			}
			elsif($mod =~ s/^>>+//) {
				# This can point to a new mode for shipping
				# or taxing
				$final = $mod;
				last CHAIN;
			}
			else {
				$passed_key = $mod;
				next CHAIN;
			}
		}
		elsif($price =~ s/%$//) {
			$price = $final * ($price / 100); 
		}
		elsif($price =~ s/\s*\*$//) {
			$final *= $price;
			undef $price;
		}
		$final += $price if $price;
		last if ($final and !$chain);
		undef $chain;
		undef $passed_key;
#::logGlobal("chain_cost intermediate '$final'");
	}
#::logGlobal("chain_cost returning '$final'");
	return $final;
}

sub build_item_price {

###
my $code = <<'EOF';
	sub {
	my($item, $quantity, $noformat) = @_;
	return $item->{mv_cache_price}
		if ! $quantity and defined $item->{mv_cache_price};
	my ($price, $base, $adjusted);
	$item = { 'code' => $item, 'quantity' => ($quantity || 1) } unless ref $item;
	$base = product_code_exists_ref($item->{code}, $item->{mv_ib})
		or return undef;
	$price = database_field($base, $item->{code}, $Vend::Cfg->{PriceField});
EOF
###

	if($Vend::Cfg->{PriceBreaks}) {

###
$code .= <<'EOF';
	$price = &{$Vend::Cfg->{QuantityPriceRoutine}}($item->{code}, $price, $quantity || undef);
EOF
###

	}

	if($Vend::Cfg->{PriceAdjustment}) {

###
$code .= <<'EOF';
 for(@{$Vend::Cfg->{PriceAdjustment}}) {
		next unless $item->{$_};
EOF
###

		if($Vend::Cfg->{CommonAdjust}) {
			if (defined $Vend::Database{$Vend::Cfg->{CommonAdjust}}) {
###
$code .= <<'EOF';
	my $adder = database_field($Vend::Database{$Vend::Cfg->{CommonAdjust}},
							 $item->{$_}, $_ ) || 0;
	$price = 0 if $adder =~ s/^=//;
	$price = 0 if $adder =~ /^\s*\[/
				 and $Vend::Session->{'item_code'}     = $item->{'code'}
				 and $Vend::Session->{'item_quantity'} = $item->{'quantity'}
				 and $adder = interpolate_html($adder);
	$price += $adder;
EOF
###
			}
			else {
$code .= <<'EOF';
$price = chain_cost($item,$price || $Vend::Cfg->{CommonAdjust});
EOF
###
			}
		}
		else {
###
$code .= <<'EOF';
	my $adder = database_field($Vend::Cfg->{Pricing},
							 $item->{code}, $item->{$_} ) || 0;
	$price = 0 if $adder =~ s/^=//;
	$price += $adder;
EOF
###
		}
###
$code .= <<'EOF';
 }
EOF
###

	}
	elsif ($Vend::Cfg->{CommonAdjust}) {
$code .= <<'EOF';
$price = chain_cost($item,$price || $Vend::Cfg->{CommonAdjust});
EOF
###
	}
		$code .= <<'EOF';
$price = $price / $Vend::Cfg->{PriceDivide};
$item->{mv_cache_price} = $price if ! $quantity and exists $item->{mv_cache_price};
EOF
###

	if($Vend::Cfg->{Locale}) {
###
		$code .= <<'EOF';
return international_number($price) unless $noformat;
return $price;
}
EOF
###

	}
	else {
###
		$code .= <<'EOF';
return $price;
}
EOF
###
	}
	my $sub = eval $code;
	die "Bad item_price routine:\n\n$@\n" if $@;
	return $sub;
}

sub item_price {
	&{$Vend::Cfg->{ItemPriceRoutine}}(@_);
}


sub item_description {
	return item_field($_[0], $Vend::Cfg->{DescriptionField});
}

sub item_field {
	my $base = $Vend::Database{$_[0]->{mv_ib}} || $Products;
	return database_field($base, $_[0]->{code}, $_[1]);
}

sub item_subtotal {
	item_price($_[0]) * $_[0]->{quantity};
}

1;

__END__
