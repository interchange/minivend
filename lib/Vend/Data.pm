# Data.pm - Minivend databases
#
# $Id: Data.pm,v 1.40 1998/07/04 21:57:12 mike Exp mike $
# 
# Copyright 1996-1998 by Michael J. Heins <mikeh@iac.net>
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
use Carp;
use File::Basename;
use File::Spec;
use Vend::Util;
use Vend::Interpolate;
use Vend::Table::DummyDB;
use Vend::Table::Import qw(import_ascii_delimited import_quoted);

File::Basename::fileparse_set_fstype($);

BEGIN {
	if(defined $Msql::VERSION or $Global::Msql) {
		require Vend::Table::Msql;
	}
	if($Global::DBI) {
		require Vend::Table::DBI;
	}
	if($Global::GDBM) {
		require Vend::Table::GDBM;
	}
	elsif($Global::DB_File) {
		require Vend::Table::DB_File;
	}
	require Vend::Table::InMemory;
}

my $New_database_dbm; 
my $New_table_sql; 
my $New_name_sql; 
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
	return tie_database() if $Global::AcrossLocks;
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
		$Vend::Database{$name} =
			import_database($data->{file}, $data->{type}, $data->{name});
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
		if($data->{type} eq '8' and ! $data->{NAME}) {
			$Vend::Database{$name} = 
				import_database($data->{file},$data->{type},$data->{name});
		}
		else {
			$Vend::Database{$name} = new Vend::Table::DummyDB $data;
		}
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

	unless (ref $base) {
		return "" unless $base = product_code_exists_ref($code, $base || undef);
	}

	my($price);
    if($Vend::Cfg->{PriceBreaks}) {
		$price = quantity_price(
					$code,
					database_field($base,$code,$Vend::Cfg->{PriceField}),
					$q)
				 / $Vend::Cfg->{PriceDivide};
	}
	else {
		$price = database_field($base,$code,$Vend::Cfg->{PriceField})
				/ $Vend::Cfg->{PriceDivide};
	}
	#return international_number($price) if $Vend::Cfg->{Locale};
	return $price;
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

sub set_field {
    my ($db, $key, $field_name, $value) = @_;

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
	if($msql) {
		$table = $table || $Vend::Cfg->{MsqlDB};
		$db = Vend::Table::Msql::get_msql('Vend::Table::Msql', $table);
	}
	else {
		$table = 'products' unless defined $table;
		$db = $Vend::Database{$table}
			or croak "dbi_query: unknown base table $table.\n";
		$db = $db->ref();
	}

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

	$type eq 'array' and
		return uneval $db->array_query($query, $table, $config, @arg);
	$type eq 'hash' and
		return uneval $db->hash_query($query, $table, $config, @arg);
	$type eq 'param' and
		return $db->param_query($query, $table, $config, @arg);
	$type eq 'set' and
		return $db->set_query($query, $table, $config, @arg);
	$type eq 'html' and
		return $db->html_query($query, $table, $config, @arg);
	$type eq 'list' and
		return Vend::Interpolate::tag_sql_list(
							$list,
							$db->array_query($query, $table, $config, @arg)
							);
	# shouldn't reach this if proper tag
#	logError("Bad SQL query selector: '$type' for $table");
	logError( errmsg('Data.pm:1', "Bad SQL query selector: '%s' for %s" , $type, $table) );
	return '';
}

sub column_index {
    my ($field_name) = @_;
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


sub create_database_mem {
    my (@columns) = @_;
    return Vend::Table::InMemory->create_table([@columns]);
}

sub create_database_dbfile {
    my (@columns) = @_;
    return Vend::Table::DB_File->create_table( {},
											$New_database_dbm,
											[@columns]);
}

sub create_database_msql {
    my (@columns) = @_;
    return Vend::Table::Msql->create_table({Catalog => $Vend::Cfg->{MsqlDB}},
                                           $New_table_sql,
                                           [@columns]);
}

sub create_database_sql {
    my (@columns) = @_;
	my $def;

	my $obj = $Vend::Cfg->{Database}->{$New_name_sql};

	# HACK
	if(defined $Vend::FIRST_COLUMN_NAME) {
		$obj->{FIRST_COLUMN_NAME} = $Vend::FIRST_COLUMN_NAME;
		undef $Vend::FIRST_COLUMN_NAME;
	}

    return Vend::Table::DBI->create_table(
											$Vend::Cfg->{Database}->{$New_name_sql},
											$New_table_sql,
											[@columns],
										);
}

sub create_database_gdbm {
    my (@columns) = @_;
    return Vend::Table::GDBM->create_table({Fast_write => 1},
                                           $New_database_dbm,
                                           [@columns]);
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

	my $file = File::Spec->catfile($Vend::Cfg->{ProductDir}, "shipping.asc");
    open(Vend::SHIPPING, $file) or do {
#				logError("Could not open shipping file $file: $!")
				logError( errmsg('Data.pm:2', "Could not open shipping file %s: %s" , $file, $!) )
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
		next unless /\S/;
		($mode, $desc, $criterion, $min, $max, $cost) = split(/\t/);
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

	my $file = File::Spec->catfile($Vend::Cfg->{ProductDir}, 'accessories.asc');
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

	my $file = File::Spec->catfile($Vend::Cfg->{ProductDir}, "salestax.asc");
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
		($code, $percent) = split(/\s+/);
		$Vend::Cfg->{SalesTaxTable}->{"\U$code"} = $percent;
    }
    close Vend::SALESTAX;

	if(not defined $Vend::Cfg->{SalesTaxTable}->{'default'}) {
		$Vend::Cfg->{SalesTaxTable}->{'default'} = 0;
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

	if($Vend::Cfg->{AdminDatabase}->{$name} and ! check_security ($database, 2)) {
		croak  "Attempt to access protected database by $CGI::host\n";
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

	croak "import_database: No database name!\n"
		unless $database;


# DEBUG
#Vend::Util::logDebug
#("start=$database_txt path='$path' base='$base' tail='$tail'\n")
#	if ::debug(0x4);
# END DEBUG

	my $database_dbm;
	my $db;
	my $create_sub;

	my $no_import = defined $Vend::Cfg->{NoImport}->{$name};

	$base = $obj->{'name'};
	$dir = $obj->{'dir'} if defined $obj->{'dir'};
  IMPORT: {
	last IMPORT if $no_import;
	last IMPORT if defined $obj->{IMPORT_ONCE} and $obj->{'dir'};

    $database_txt = $database;

	($base,$path,$tail) = fileparse $database_txt, '\.[^/.]+$';

	if(File::Spec->file_name_is_absolute($database_txt)) {
		$dir = $path;
	}
	else {
		$dir = $Vend::Cfg->{DataDir} || $Global::ConfigDir;
		$database_txt = File::Spec->catfile($dir,$database_txt);
	}

	$obj->{'dir'} = $dir;
	if($type == 8) {
		$New_table_sql = $base;
		$New_name_sql = $name;
    	$database_dbm = File::Spec->catfile($dir,"$base.sql");
    	$New_database_dbm = File::Spec->catfile($dir,"new_$base.sql");
		if ($no_import or -f $database_dbm or ! -f $database_txt) {
			$no_import = 1;
		}
		else {
			open(Vend::Data::TMP, ">$New_database_dbm");
			print Vend::Data::TMP "\n";
			close(Vend::Data::TMP);
		}
    	$create_sub = \&create_database_sql;
		$change_delimiter = $obj->{DELIMITER} if defined $obj->{DELIMITER};
	}
	elsif($type == 7) {
		$New_table_sql = $base;
		$New_name_sql = $name;
    	$database_dbm = File::Spec->catfile($dir,"$base.sql");
    	$New_database_dbm = File::Spec->catfile($dir,"new_$base.sql");
		if ($no_import or -f $database_dbm or ! -f $database_txt) {
			$no_import = 1;
		}
		else {
			open(Vend::Data::TMP, ">$New_database_dbm");
			print Vend::Data::TMP "\n";
			close(Vend::Data::TMP);
		}
    	$create_sub = \&create_database_msql;
		$change_delimiter = $obj->{DELIMITER} if defined $obj->{DELIMITER};
	}
	elsif ($obj->{MEMORY}) {
    	$New_database_dbm = File::Spec->catfile($dir,"$base.mem");
    	$create_sub = \&create_database_mem;
		$cacheable = 1;
	}
    elsif($Global::GDBM) {
    	$database_dbm = File::Spec->catfile($dir,"$base.gdbm");
    	$New_database_dbm = File::Spec->catfile($dir,"new_$base.gdbm");
    	$create_sub = \&create_database_gdbm;
		$cacheable = 1 if $Global::AcrossLocks;
	}
    elsif($Global::DB_File) {
    	$database_dbm = File::Spec->catfile($dir,"$base.db");
    	$New_database_dbm = File::Spec->catfile($dir,"new_$base.db");
    	$create_sub = \&create_database_dbfile;
		$cacheable = 1 if $Global::AcrossLocks;
	}
    else {
    	$New_database_dbm = File::Spec->catfile($dir,"$base.mem");
    	$create_sub = \&create_database_mem;
		$cacheable = 1;
	}
	if (defined $Vend::ForceImport{$name}) {
		undef $database_dbm;
		delete $Vend::ForceImport{$name};
	}
	last IMPORT if $no_import;
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
        $db = import_ascii_delimited($database_txt, $obj, $create_sub)
			unless $delimiter eq 'CSV';
        $db = import_quoted($database_txt, $create_sub)
			if $delimiter eq 'CSV';

		$/ = $save;
		if(defined $database_dbm) {
			$db->close_table() if defined $db;
			undef $db;
        	rename($New_database_dbm, $database_dbm)
            	or die "Couldn't move '$New_database_dbm' to '$database_dbm': $!\n";
		}
    }
  }


	my $read_only = ! defined $Vend::WriteDatabase{$name};
	if($type == 8) {
		my $cols = $obj->{NAME} || undef;
# DEBUG
#Vend::Util::logDebug
#("columns from config: @{$cols}\n")
#	if ::debug(0x4) and $cols;
# END DEBUG
		$db->close_table() if defined $db;
    	$db = Vend::Table::DBI->open_table(
					$obj,
					$base);

		unless (defined $cols) {
			$obj->{NAME} = $db->[3];
		}
			
# DEBUG
#Vend::Util::logDebug
#("Opening DBI: object '$db'\n")
#	if ::debug(0x4);
# END DEBUG
	}
	elsif($type == 7) {
		$db->close_table() if defined $db;
    	$db = Vend::Table::Msql->open_table(
				{Catalog => $Vend::Cfg->{MsqlDB}}, $base);
	}
    elsif($obj->{MEMORY}) {
		# do nothing
	}
    elsif($Global::GDBM) {
		$db->close_table if defined $db;
		undef $db;
# DEBUG
#Vend::Util::logDebug
#("Opening GDBM: RO=$read_only\n")
#	if ::debug(0x4);
# END DEBUG
    	$db = Vend::Table::GDBM->open_table({Read_only => $read_only},
									  File::Spec->catfile($dir,"$base.gdbm")
									  );
	}
    elsif($Global::DB_File) {
		$db->close_table() if defined $db;
		undef $db;
    	$db = Vend::Table::DB_File->open_table({Read_only => $read_only},
									  File::Spec->catfile($dir,"$base.db")
									  );
	}

	if(defined $cacheable) {
		$Vend::Cfg->{SaveDatabase}->{$name} = $db;
	}

	$Vend::Basefinder{$db} = $name;

	$db;
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
		or croak "Bad database '$db'.\n";


	my $sql = 0;
	# Some things not supported for SQL types -- can 
	# usually do with [msql set] or [msql list] and [tag log ...]
	if ($ref->{'type'} == 7 or $ref->{'type'} == 8) {
		$sql = 1;
	}

	my ($delim, $record_delim) = find_delimiter($type || $ref->{'type'});

	$file = $file || $ref->{'file'};

	unless($file =~ m!^([A-Za-z]:)?/!) {
		$file = File::Spec->catfile( $Vend::Cfg->{DataDir}, $file);
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
		logError( errmsg('Data.pm:7', "Adding field %s" , $_) );
		push @cols, $_;
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
	   		croak "Couldn't open $file: $!\n";
	lockfile(\*Vend::Data::EXPORT, 1, 1)
		or croak "Couldn't exclusive lock $file: $!\n";
	open(Vend::Data::EXPORT, "+>$file") or
	   	croak "Couldn't write $file: $!\n";
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
		or croak "Couldn't unlock $file: $!\n";
	close(Vend::Data::EXPORT)
		or croak "Couldn't close $file: $!\n";
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

sub build_item_price {

###
my $code = <<'EOF';
	sub {
	my($item, $quantity) = @_;
	my ($price, $base);
	$quantity = $quantity || undef;
	$base = product_code_exists_ref($item->{code}, $item->{mv_ib});
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
			croak "Must have price adjustment database '" .
						$Vend::Cfg->{CommonAdjust} . "' defined.\n"
				unless defined $Vend::Database{$Vend::Cfg->{CommonAdjust}};
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
	if($Vend::Cfg->{Locale} or $Vend::Cfg->{PriceDivide} != 1) {
		$code .= <<'EOF';
$price = $price / $Vend::Cfg->{PriceDivide};
EOF
###
	}
	if($Vend::Cfg->{Locale}) {
###
		$code .= <<'EOF';
return international_number($price);
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
	&{$Vend::Cfg->{ItemPriceRoutine}}($_[0], $_[1] || undef);
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
