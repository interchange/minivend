# $Id: Data.pm,v 1.10 1997/06/27 11:32:10 mike Exp mike $

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
msql_query
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
@EXPORT_OK = qw(update_productbase);

use strict;
use Carp;
use File::Basename;
use Vend::Util;
use Vend::Interpolate;
use Vend::Table::DummyDB;
use Vend::Table::Import qw(import_ascii_delimited import_quoted);


BEGIN {
	if(defined $Msql::Version or $Global::Msql) {
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
	else {
		require Vend::Table::InMemory;
	}
}

my $New_database_dbm; 
my $New_table_sql; 
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
#print("Calling tie_database $name $data->{name}, $data->{file}, $data->{type}\n" ) if $Global::DEBUG;
		$Vend::Database{$name} =
			import_database($data->{file}, $data->{type}, $data->{name});
	}
	update_productbase();
}

sub dummy_database {
	my ($name, $data);
    while (($name,$data) = each %{$Vend::Cfg->{Database}}) {
#print("Calling dummy_database $name $data->{name}, $data->{file}, $data->{type}\n" ) if $Global::DEBUG;
		$Vend::Database{$name} = new Vend::Table::DummyDB $data;
	}
	update_productbase();
}

sub update_productbase {

	if(defined $_[0]) {
		return unless ( defined $Vend::Productbase{$_[0]} or
						$_[0] eq 'pricing' );
	}
#print("Update productbase " . ($_[0] || '') . "\n" ) if $Global::DEBUG;
	undef @Vend::Productbase;
	for(@{$Vend::Cfg->{ProductFiles}}) {
		unless ($Vend::Database{$_}) {
		  die "$_ not a database, cannot use as products file\n";
		}
		$Vend::Productbase{$_} = $Vend::Database{$_};
		$Vend::Basefinder{$Vend::Database{$_}} = $_;
		push @Vend::Productbase, $Vend::Database{$_};
	}
	$Vend::Cfg->{Pricing} = $Vend::Database{pricing}
		if $Vend::Database{pricing};
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
	return international_number($price) if $Vend::Cfg->{Locale};
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
    return '' unless $db->record_exists($key);
    return '' unless defined $db->test_column($field_name);
    return $db->field($key, $field_name);
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


	my ($real, $ref) = $db->record_exists($key);

	$db = $ref if defined $ref;

	# Create it if it doesn't exist
	unless ($real) {
		my @fields;
		my $count = $db->columns();
		@fields = ('') x $count;
		$db->set_row($key, @fields);
	}

    return undef unless defined $db->test_column($field_name);
    return $db->set_field($key, $field_name, $value);
}

sub product_field {
    my ($field_name, $code, $base) = @_;
	my ($db);
    #return "NA" unless $db = product_code_exists_ref($code, $base || undef);
    #return "NA" unless defined $db->test_column($field_name);
    return "" unless $db = product_code_exists_ref($code, $base || undef);
    return "" unless defined $db->test_column($field_name);
    return $db->field($code, $field_name);
}

sub sql_query {
	defined $_[3] and return msql_query(@_);
	return dbi_query(@_);
};

sub dbi_query {
	my $catalog = { Catalog => $Vend::Cfg->{SqlDB} };
	"\L$_[0]" eq 'array' and
		return uneval Vend::Table::DBI::array_query($_[2], $catalog);
	"\L$_[0]" eq 'hash' and
		return uneval Vend::Table::DBI::hash_query($_[2], $catalog);
	"\L$_[0]" eq 'param' and
		return Vend::Table::DBI::param_query($_[2], $catalog);
	"\L$_[0]" eq 'set' and
		return Vend::Table::DBI::set_query($_[2], $catalog);
	"\L$_[0]" eq 'html' and
		return Vend::Table::DBI::html_query($_[2], $catalog);
	"\L$_[0]" eq 'list' and
		return Vend::Interpolate::tag_sql_list(
							$_[2],
							Vend::Table::DBI::array_query($_[1], $catalog)
							);
	# shouldn't reach this if proper tag
	logError("Bad SQL query selector: '$_[0]'");
	return '';
}


sub msql_query {
	my $catalog = { Catalog => $Vend::Cfg->{MsqlDB} };
	"\L$_[0]" eq 'array' and
		return uneval Vend::Table::Msql::array_query($_[2], $catalog);
	"\L$_[0]" eq 'hash' and
		return uneval Vend::Table::Msql::hash_query($_[2], $catalog);
	"\L$_[0]" eq 'param' and
		return Vend::Table::Msql::param_query($_[2], $catalog);
	"\L$_[0]" eq 'set' and
		return Vend::Table::Msql::set_query($_[2], $catalog);
	"\L$_[0]" eq 'html' and
		return Vend::Table::Msql::html_query($_[2], $catalog);
	"\L$_[0]" eq 'list' and
		return Vend::Interpolate::tag_sql_list(
							$_[2],
							Vend::Table::Msql::array_query($_[1], $catalog)
							);
	# shouldn't reach this if proper tag
	logError("Bad Msql query selector: '$_[0]'");
	return '';
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
    return Vend::Table::DBI->create_table({ Host => $Vend::Cfg->{SqlHost},
											Catalog => $Vend::Cfg->{SqlDB} },
                                           $New_table_sql,
                                           [@columns]);
}

sub create_database_gdbm {
    my (@columns) = @_;
    return Vend::Table::GDBM->create_table({Fast_write => 1},
                                           $New_database_dbm,
                                           [@columns]);
}

sub close_database {
	my($db, $name);
	while( ($name, $db)	= each %{$Vend::Database} ) {
		next if defined $Vend::Cfg->{SaveDatabase}->{$name};
    	$db->close_table()
			or die "Could not untie database: $!\n";
	}
	undef $Vend::Database;
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

sub read_shipping {
    my($code, $desc, $min, $criterion, $max, $cost);

    open(Vend::SHIPPING,"$Vend::Cfg->{ProductDir}/shipping.asc")
	|| do {
		logError("Could not open shipping: $!");
		return undef;
		};
	$Vend::Cfg->{Shipping_desc} = {};
	$Vend::Cfg->{Shipping_criterion} = {};
	$Vend::Cfg->{Shipping_min} = {};
	$Vend::Cfg->{Shipping_max} = {};
	$Vend::Cfg->{Shipping_cost} = {};
	UPSZONE: {
		if($Vend::Cfg->{UpsZoneFile}) {
			my @zone = split(/\n/, readfile($Vend::Cfg->{'UpsZoneFile'}) );
			unless (@zone) {
				logError("Bad UPS zone file, UPS lookup disabled.");
				last UPSZONE;
			}
			if($zone[0] !~ /\t/) {
				@zone = grep /\S/, @zone;
				@zone = grep /^[^"]/, @zone;
				$zone[0] =~ s/[^\w,]//g;
				$zone[0] =~ s/^\w+/low,high/;
				for(@zone) {
					s/^\s*(\d+)\s*,/$1,$1,/;
					s/^\s*(\d+)-(\d+),/$1,$2,/;
					s/\s*,\s*/\t/g;
				}
			}
			$Vend::Cfg->{UPSzone} = \@zone;
#print("\nZone fields: $zone[0]") if $Global::DEBUG;
		}
	}
	my %seen;
	my $append = '0000';
    while(<Vend::SHIPPING>) {
		chomp;
		next unless /\S/;
		($code, $desc, $criterion, $min, $max, $cost) = split(/\t/);
		$code = defined $seen{$code} ? $code . $append++ : $code; 
		$seen{$code} = 1;
#print "reading shipping code $code\n" if $Global::DEBUG;
		$Vend::Cfg->{Shipping_desc}->{$code} = $desc;
		$Vend::Cfg->{Shipping_criterion}->{$code} = $criterion;
		$Vend::Cfg->{Shipping_min}->{$code} = $min;
		$Vend::Cfg->{Shipping_max}->{$code} = $max;
		$Vend::Cfg->{Shipping_cost}->{$code} = $cost;
    }
    close Vend::SHIPPING;
	1;
}

# Read in the accessories file.

sub read_accessories {
    my($code, $accessories);

    open(Vend::ACCESSORIES,"$Vend::Cfg->{ProductDir}/accessories.asc")
	|| do {
		logError("Could not open accessories.asc: $!");
		return undef;
		};
    while(<Vend::ACCESSORIES>) {
		chomp;
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

    open(Vend::SALESTAX,"$Vend::Cfg->{ProductDir}/salestax.asc")
	|| do {
		logError("Could not open salestax.asc: $!");
		return undef;
		};
	$Vend::Cfg->{SalesTaxTable} = {};
    while(<Vend::SALESTAX>) {
		chomp;
		($code, $percent) = split(/\s+/);
		$Vend::Cfg->{SalesTaxTable}->{"\U$code"} = $percent;
    }
    close Vend::SALESTAX;
	1;
}

# Read in the pricing file, if it exists
sub read_pricing {
    my($code, @breaks);

	if($Vend::Cfg->{PriceBreaks} || $Vend::Cfg->{PriceAdjustment}) {
			die "No pricing database defined.\n"
				 unless $Vend::Cfg->{Database}->{pricing};
	}

	return ( build_item_price(), build_quantity_price() );
}

sub quantity_price {
	my ($code,$one,$quan) = @_;

#print("Called quantity price for '$code' '$one' '$quan'\n") if $Global::DEBUG;
	return $one unless
			database_key_exists($Vend::Cfg->{Pricing}, $code);
	my(@prices);

	@prices =
			split /\s/, database_field($Vend::Cfg->{Pricing}, $code, 'price');

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
	5 => ['\|', "\n"],
	6 => ["\t", "\n"],
	7 => ["\t", "\n"],
	8 => ["\t", "\n"],
	);

sub find_delimiter {
	my ($type) = @_;
	$type = $type || 1;
	return ($Vend::Cfg->{Delimiter}, "\n")
		if $type == 1;

    if ($type > 1 and $type < 9) {
		return @{$Delimiter{$type}};
	}
	return ($Vend::Cfg->{FieldDelimiter}->{$type}, 
			$Vend::Cfg->{RecordDelimiter}->{$type});
}

sub import_database {
    my ($database,$type,$name) = @_;

	if($Vend::Cfg->{AdminDatabase}->{$name} and ! check_security ($database, 2)) {
		croak  "Attempt to access protected database by $CGI::host\n";
	}
	else {
#print("Skipped security check for database $name\n") if $Global::DEBUG;
	}

	return $Vend::Cfg->{SaveDatabase}->{$name}
		if defined $Vend::Cfg->{SaveDatabase}->{$name};
#print("Import database $name $database $type\n" ) if $Global::DEBUG;
	my $delimiter = $Vend::Cfg->{Delimiter};
	my ($record_delim, $cacheable);

	croak "import_database: No database name!\n"
		unless $database;


	my $data;

    my $database_txt = $database;
    my ($base,$path,$tail) = fileparse $database_txt, '\.[^/.]+$';
	$path =~ s:^\./?::;

	unless($path) {
		$data = $Vend::Cfg->{DataDir};
		$database_txt = "$data/$database_txt";
	}
	else {
		$data = $path;
	}

	$data =~ s:/$:: ;

	my $database_dbm;
	my $db;
	my $create_sub;
	my $no_import = 0;

	if($Global::Msql and $type == 7) {
		$New_table_sql = $base;
    	$database_dbm = "$data/$base.sql";
    	$New_database_dbm = "$data/new.$base.sql";
		my $now = time;
		if (-f $database_dbm or ! -f $database_txt) {
			$no_import = 1;
		}
		else {
			open(Vend::Data::TMP, ">$New_database_dbm");
			print Vend::Data::TMP "\n";
			close(Vend::Data::TMP);
		}
    	$create_sub = \&create_database_msql;
	}
	elsif($Global::DBI and $type == 8) {
		$New_table_sql = $base;
    	$database_dbm = "$data/$base.sql";
    	$New_database_dbm = "$data/new.$base.sql";
		my $now = time;
		if (-f $database_dbm or ! -f $database_txt) {
			$no_import = 1;
		}
		else {
			open(Vend::Data::TMP, ">$New_database_dbm");
			print Vend::Data::TMP "\n";
			close(Vend::Data::TMP);
		}
    	$create_sub = \&create_database_sql;
	}
    elsif($Global::GDBM) {
		$New_database_dbm = "$data/new.$base.gdbm";
    	$database_dbm = "$data/$base.gdbm";
    	$create_sub = \&create_database_gdbm;
		$cacheable = 1 if $Global::AcrossLocks;
	}
    elsif($Global::DB_File) {
		$New_database_dbm = "$data/new.$base.db";
    	$database_dbm = "$data/$base.db";
    	$create_sub = \&create_database_dbfile;
		$cacheable = 1 if $Global::AcrossLocks;
	}
    else {
    	$New_database_dbm = "$data/$base.mem";
    	$create_sub = \&create_database_mem;
		$cacheable = 1;
	}
	if (defined $Vend::ForceImport{$name}) {
		undef $database_dbm;
		delete $Vend::ForceImport{$name};
	}
  IMPORT: {
	last IMPORT if $no_import;
	last IMPORT if defined $Vend::Cfg->{NoImport}->{$name};
    if (! defined $database_dbm
		or ! -e $database_dbm
        or file_modification_time($database_txt) >
            file_modification_time($database_dbm)) {
		
        warn "Importing $base table from $database_txt\n";

		$type = 1 unless $type;
		($delimiter, $record_delim) = find_delimiter($type);
#print("Type: $type delimiter: '$delimiter'\n") if $Global::DEBUG;
		my $save = $/;
		$/ = $record_delim if defined $record_delim;
        $db = import_ascii_delimited($database_txt, $delimiter, $create_sub)
			unless $delimiter eq 'CSV';
        $db = import_quoted($database_txt, $create_sub)
			if $delimiter eq 'CSV';
		$/ = $save;
		if(defined $database_dbm) {
        	rename($New_database_dbm, $database_dbm)
            	or die "Couldn't move '$New_database_dbm' to '$database_dbm': $!\n";
		}
    }
  }


	my $read_only = ! defined $Vend::WriteDatabase{$name};
	if($Global::Msql and $type == 7) {
    	$db = Vend::Table::Msql->open_table(
				{Catalog => $Vend::Cfg->{MsqlDB}}, $base);
	}
	elsif($Global::DBI and $type == 8) {
    	$db = Vend::Table::DBI->open_table(
				{Host => $Vend::Cfg->{SqlHost}, Catalog => $Vend::Cfg->{SqlDB}}, $base);
#print("Opening DBI: object '$db'\n") if $Global::DEBUG;
	}
    elsif($Global::GDBM) {
		close_database($db) if defined $db;
		undef $db;
#print("Opening GDBM: RO=$read_only\n") if $Global::DEBUG;
    	$db = Vend::Table::GDBM->open_table({Read_only => $read_only},
                                              "$data/$base.gdbm");
	}
    elsif($Global::DB_File) {
		close_database($db) if defined $db;
		undef $db;
    	$db = Vend::Table::DB_File->open_table({Read_only => $read_only},
                                              "$data/$base.db");
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

	# Not supported for SQL types
	if (defined $type and ($type == 7 or $type == 8) ) {
		$Vend::Session->{errmsg} = "export_database: ASCII file export not supported for SQL types.";
		return undef;
	}

	$db = database_exists_ref($db) || return undef;

	my $ref;
	$ref = $Vend::Cfg->{Database}->{$Vend::Basefinder{$db}};
	croak "Bad database '$ref', name $Vend::Basefinder{$db}.\n" unless $ref;

	$db = $db->ref();

	my ($delim, $record_delim) = find_delimiter($type || $ref->{'type'});

	$file = $file || $ref->{'file'};

	unless($file =~ m!^([A-Za-z]:)?/!) {
		$file = "$Vend::Cfg->{DataDir}/$file";
	}

	my @cols = $db->columns();

	my ($notouch, $nuke);
	if ($field and ! $delete) {
		logError("Adding field $_");
		push @cols, $_;
		$notouch = 1;
	}
	elsif ($field and $delete) {
		logError("Deleting $field...");
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
				logError("Deleting field $_");
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
		print Vend::Data::EXPORT '"key","';
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
	else {
		print Vend::Data::EXPORT join $delim, 'key', @cols;
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
	$quantity = $quantity || $item->{quantity};
	$base = product_code_exists_ref($item->{code}, $item->{mv_ib});
	$price = database_field($base, $item->{code}, $Vend::Cfg->{PriceField});
EOF
###

	if($Vend::Cfg->{PriceBreaks}) {

###
$code .= <<'EOF';
	$price = &{$Vend::Cfg->{QuantityPriceRoutine}}($item->{code}, $price, $quantity);
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
				unless $Vend::Database{$Vend::Cfg->{CommonAdjust}};
###
$code .= <<'EOF';
	$price += database_field($Vend::Database{$Vend::Cfg->{CommonAdjust}},
							 $item->{$_}, $_ ) || 0;
EOF
###
		}
		else {
###
$code .= <<'EOF';
	$price += database_field($Vend::Cfg->{Pricing},
							 $item->{code}, $item->{$_} ) || 0;
EOF
###
		}
###
$code .= <<'EOF';
 }
EOF
###

	}
	if($Vend::Cfg->{PriceDivide} != 1) {
		$code .= <<EOF;
\$price = \$price / $Vend::Cfg->{PriceDivide};
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
	return item_price($_[0]) * $_[0]->{quantity};
}

1;

__END__
