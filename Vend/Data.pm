# $Id: Data.pm,v 2.11 1997/01/07 01:16:56 mike Exp $

package Vend::Data;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(

close_products
close_database
column_exists
database_field
database_key_exists
db_column_exists
open_databases
import_database
import_products
msql_query
product_code_exists
product_description
product_field
product_price
products_ref
read_accessories
read_pricing
read_salestax
read_shipping

);

use strict;
use Carp;
use File::Basename;
use Vend::Util;
use Vend::Table::Import qw(import_ascii_delimited import_quoted);


BEGIN {
	if(defined $Msql::Version or $Global::Msql) {
		require Vend::Table::Msql;
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

my $New_product_dbm; 
my $New_database_dbm; 
my $New_table_msql; 
my ($Products, $Product_desc, $Product_price);

sub database_key_exists {
    my ($db,$key) = @_;
    return $db->record_exists($key);
}

sub product_code_exists {
    my ($product_code) = @_;
    return $Products->record_exists($product_code);
}

sub product_price {
    my ($product_code, $q) = @_;
    return "NA" unless product_code_exists($product_code);
	my($price);
    if($Vend::Cfg->{'PriceBreaks'}) {
		$price = quantity_price($product_code, &$Product_price($product_code), $q)
			/ $Vend::Cfg->{'PriceDivide'};
	}
	else {
		$price = &$Product_price($product_code)
			/ $Vend::Cfg->{'PriceDivide'};
	}
	return international_number($price) if $Vend::Cfg->{Locale};
	return $price;
}

sub open_databases {
	my ($file);
	my $type = '';
	my $d = $Vend::Cfg->{'Database'};
    for (keys %{$d}) {
		$file = $d->{$_}->{'file'};
		$type = $d->{$_}->{'type'};
		my $save = $;
		$ = 0;
		$Vend::Database{$_} = import_database($file, $type);
		$ = $save;
	}
}

sub product_description {
    my ($product_code) = @_;
    return "NA" unless product_code_exists($product_code);
    return &$Product_desc($product_code);
}

sub database_field {
    my ($db, $key, $field_name) = @_;

	# Uncomment this for return of NA when no key
    # return "NA" unless database_key_exists($db,$key);
    # return "NA" unless defined db_column_exists($db,$field_name);

	# Uncomment this for return of no value
    return '' unless database_key_exists($db,$key);
    return '' unless  defined db_column_exists($db,$field_name);

    return $db->field($key, $field_name);
}

sub product_field {
    my ($product_code, $field_name) = @_;
    return "NA" unless product_code_exists($product_code);
    return "NA" unless defined column_exists($field_name);
    return $Products->field($product_code, $field_name);
}

sub msql_query {
	my $catalog = { Catalog => $Vend::Cfg->{MsqlDB} };
	"\L$_[0]" eq 'array' and
		return uneval Vend::Table::Msql::array_query($_[1], $catalog);
	"\L$_[0]" eq 'hash' and
		return uneval Vend::Table::Msql::hash_query($_[1], $catalog);
	"\L$_[0]" eq 'param' and
		return Vend::Table::Msql::param_query($_[1], $catalog);
	"\L$_[0]" eq 'set' and
		return Vend::Table::Msql::set_query($_[1], $catalog);
	"\L$_[0]" eq 'html' and
		return Vend::Table::Msql::html_query($_[1], $catalog);
	"\L$_[0]" eq 'list' and
		return tag_msql_list(
							$_[1],
							Vend::Table::Msql::array_query($_[2], $catalog)
							);
	# shouldn't reach this if proper tag
	logError("Bad Msql query selector: '$_[0]'\n");
	return '';
}

sub column_exists {
    my ($field_name) = @_;
    return $Products->test_column($field_name);
}

sub db_column_exists {
    my ($db,$field_name) = @_;
    return $db->test_column($field_name);
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
                                           $New_table_msql,
                                           [@columns]);
}

sub create_product_msql {
    my (@columns) = @_;
    return Vend::Table::Msql->create_table({Catalog => $Vend::Cfg->{MsqlDB}},
                                           'product',
                                           [@columns]);
}

sub create_database_gdbm {
    my (@columns) = @_;
    return Vend::Table::GDBM->create_table({Fast_write => 1},
                                           $New_database_dbm,
                                           [@columns]);
}

sub create_product_mem {
    my (@columns) = @_;
    return Vend::Table::InMemory->create_table([@columns]);
}

sub create_product_dbfile {
    my (@columns) = @_;
    return Vend::Table::DB_File->create_table( {}, $New_product_dbm,
                                           [@columns]);
}

sub create_product_gdbm {
    my (@columns) = @_;
    return Vend::Table::GDBM->create_table({Fast_write => 1},
                                           $New_product_dbm,
                                           [@columns]);
}

sub import_products {
    my ($config) = @_;

    my $data = $Vend::Cfg->{'ProductDir'};
	my $delimiter = $Vend::Cfg->{'Delimiter'} || "\t";

    my $product_txt = "$data/products.asc";
	my $product_dbm;
	my $memory;
	my $create_sub;
	my $no_import = 0;

	if($Global::Msql and $Vend::Cfg->{MsqlProducts} ) {
		$New_table_msql = 'product';
    	$product_dbm = "$data/product.msql";
    	$New_product_dbm = "$data/new.product.msql";
		my $now = time;
		if (-f $product_dbm or ! -f $product_txt) {
			$no_import = 1;
		}
		else {
			open(Vend::Data::TMP, ">$New_product_dbm");
			print Vend::Data::TMP "\n";
			close(Vend::Data::TMP);
		}
    	$create_sub = \&create_product_msql;
	}
    elsif($Global::GDBM) {
		$New_product_dbm = "$data/new.product.gdbm";
    	$product_dbm = "$data/product.gdbm";
    	$create_sub = \&create_product_gdbm;
	}
    elsif($Global::DB_File) {
		$New_product_dbm = "$data/new.product.db";
    	$product_dbm = "$data/product.db";
    	$create_sub = \&create_product_dbfile;
	}
    else {
    	$New_product_dbm = "$data/product.mem";
		if($Products = $Vend::Cfg->{MemoryDatabase}->{$New_product_dbm}) {
			$no_import = 1;
		}
		$memory = 1;
    	$create_sub = \&create_product_mem;
	}

  IMPORT: {
	last IMPORT if $no_import;
    if (! defined $product_dbm
		or ! -e $product_dbm
        or file_modification_time($product_txt) >
            file_modification_time($product_dbm)) {

        warn ("Importing product table from $product_txt\n");
        $Products = import_ascii_delimited($product_txt, $delimiter, $create_sub)
			unless $delimiter eq 'CSV';
        $Products = import_quoted($product_txt, $create_sub)
			if $delimiter eq 'CSV';
		if(defined $memory) {
			unless (ref $Vend::Cfg->{MemoryDatabase}) {
				$Vend::Cfg->{MemoryDatabase} = {};
			}
			$Vend::Cfg->{MemoryDatabase}->{$New_product_dbm} = $Products;
		}
		if(defined $product_dbm) {
        	rename($New_product_dbm, $product_dbm)
            	or die "Couldn't move '$New_product_dbm' to '$product_dbm': $!\n";
		}
    }
  }

	if($Global::Msql and $Vend::Cfg->{MsqlProducts} ) {
		close_products() if defined $Products;
    	$Products = Vend::Table::Msql->open_table(
				{Catalog => $Vend::Cfg->{MsqlDB}}, 'product');
	}
    elsif($Global::GDBM) {
		close_products() if defined $Products;
		undef $Products;
    	$Products = Vend::Table::GDBM->open_table({Read_only => 1},
                                              "$data/product.gdbm");
	}
    elsif($Global::DB_File) {
		close_products() if defined $Products;
		undef $Products;
    	$Products = Vend::Table::DB_File->open_table({Read_only => 1},
                                              "$data/product.db")
	}
    $Product_desc = $Products->field_accessor($Vend::Cfg->{'DescriptionField'});
    $Product_price = $Products->field_accessor($Vend::Cfg->{'PriceField'});
}   

sub close_database {
	my(@dbrefs) = @_;
	my($db);
	@dbrefs = (values %$Vend::Database) unless scalar @dbrefs;
	foreach $db	(@dbrefs) {
    	$db->close_table()
			or die "Could not untie database: $!\n";
	}
}

## PRODUCTS
sub close_products {
		undef $Product_price;
		undef $Product_desc;
    	$Products->close_table()
			or die "Could not untie products database.\n";
}

sub products_ref {
	$Products;
}

## PRODUCTS

# Read in the shipping file.

sub read_shipping {
    my($code, $desc, $min, $criterion, $max, $cost);

    open(Vend::SHIPPING,"$Vend::Cfg->{'ProductDir'}/shipping.asc")
	|| do {
		logError("Could not open shipping: $!");
		return undef;
		};
	$Vend::Cfg->{'Shipping_desc'} = {};
	$Vend::Cfg->{'Shipping_criterion'} = {};
	$Vend::Cfg->{'Shipping_min'} = {};
	$Vend::Cfg->{'Shipping_max'} = {};
	$Vend::Cfg->{'Shipping_cost'} = {};
    while(<Vend::SHIPPING>) {
		chomp;
		($code, $desc, $criterion, $min, $max, $cost) = split(/\t/);
		$Vend::Cfg->{'Shipping_desc'}->{$code} = $desc;
		$Vend::Cfg->{'Shipping_criterion'}->{$code} = $criterion;
		$Vend::Cfg->{'Shipping_min'}->{$code} = $min;
		$Vend::Cfg->{'Shipping_max'}->{$code} = $max;
		$Vend::Cfg->{'Shipping_cost'}->{$code} = $cost;
    }
    close Vend::SHIPPING;
	1;
}

# Read in the accessories file.

sub read_accessories {
    my($code, $accessories);

    open(Vend::ACCESSORIES,"$Vend::Cfg->{'ProductDir'}/accessories.asc")
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
		$Vend::Accessories{$code} = $accessories;
    }
    close Vend::ACCESSORIES;
	1;
}

# Read in the sales tax file.
sub read_salestax {
    my($code, $percent);

    open(Vend::SALESTAX,"$Vend::Cfg->{'ProductDir'}/salestax.asc")
	|| do {
		logError("Could not open salestax.asc: $!");
		return undef;
		};
    while(<Vend::SALESTAX>) {
		chomp;
		($code, $percent) = split(/\s+/);
		$Vend::Cfg->{'SalesTaxTable'}->{$code} = $percent;
    }
    close Vend::SALESTAX;
	1;
}

# Read in the pricing file, if it exists
sub read_pricing {
	return undef unless $Vend::Cfg->{'PriceBreaks'};
    my($code, @breaks);
	my($test);

    open(Vend::PRICING,"$Vend::Cfg->{'ProductDir'}/pricing.asc")
	|| do {
		logError("Could not open pricing.asc: $!");
		return undef;
		};
	$test = <Vend::PRICING>;
	if($test =~ /^(sku|code)\t/i) {
		close Vend::PRICING;
		$Vend::Cfg->{'Pricing'} = import_pricing();
		$Vend::Cfg->{'PriceStyleNew'} = 1;
	}
	else {
		chomp($test);
		($code, @breaks) = split /\t/, $test;
		$Vend::Cfg->{'Pricing'}->{$code} = [@breaks];
		while(<Vend::PRICING>) {
			chomp;
			($code, @breaks) = split(/\t/);
			$Vend::Cfg->{'Pricing'}->{$code} = [@breaks];
		}
		close Vend::PRICING;
	}
	1;
}

sub quantity_price {
	my ($code,$one,$quan) = @_;
	my $new = defined $Vend::Cfg->{'PriceStyleNew'};

	if($new) {
		return $one unless
			database_key_exists($Vend::Cfg->{'Pricing'}, $code);
	}
	else {
		return $one unless
			$Vend::Cfg->{'Pricing'}->{$code};
	}
	my(@prices);

	if(defined $Vend::Cfg->{'PriceStyleNew'}) {
		@prices =
			split /\s/, database_field($Vend::Cfg->{'Pricing'}, $code, 'price');
	}
	else {
		@prices = @{$Vend::Cfg->{'Pricing'}->{$code}};
	}

	my ($break,$i,$price,$scratch);
	$price = $one;

	# Use the passed quantity if there
	unless(defined $quan) {
		$quan	= $Vend::Cfg->{'MixMatch'}
				? tag_nitems()
				: tag_item_quantity($code);
	}

	foreach $break (@{$Vend::Cfg->{'PriceBreaks'}}) {
		last if $break > $quan;
		$scratch = shift @prices;
		$price = $scratch if $scratch;
	}
	return $price;
}

sub import_pricing {

	my $delimiter = "\t";

	my $no_import;
	my $memory;

	my $data = $Vend::Cfg->{'ProductDir'};

    my $database_txt = "$Vend::Cfg->{'ProductDir'}/pricing.asc";
    my ($base,$path,$tail) = fileparse $database_txt, '\.[^/.]+$';
	$path =~ s:^\./?::;

	unless($path) {
		$data = $Vend::Cfg->{'DataDir'};
		$database_txt = "$data/$database_txt";
	}

	$data =~ s:/$:: ;

	my $database_dbm;
	my $db;
	my $create_sub;

    if($Global::GDBM) {
		$New_database_dbm = "$data/new.$base.gdbm";
    	$database_dbm = "$data/$base.gdbm";
    	$create_sub = \&create_database_gdbm;
	}
    elsif($Global::DB_File) {
		$New_database_dbm = "$data/new.$base.db";
    	$database_dbm = "$data/$base.db";
    	$create_sub = \&create_database_dbfile;
	}
    else {
		$New_database_dbm = "$data/new.$base.mem";
		if(ref ($db = $Vend::Cfg->{MemoryDatabase}->{$New_database_dbm})) {
			$no_import = 1;
		}
		$memory = 1;
    	$create_sub = \&create_database_mem;
	}

   IMPORTPRICE: {
   	last IMPORTPRICE if $no_import;
    if (! defined $database_dbm
		or ! -e $database_dbm
        or file_modification_time($database_txt) >
            file_modification_time($database_dbm)) {

        warn "Importing pricing table from $database_txt\n";
        $db = import_ascii_delimited($database_txt, $delimiter, $create_sub);
		if(defined $database_dbm) {
        	rename($New_database_dbm, $database_dbm)
            	or die "Couldn't move '$New_database_dbm' to '$database_dbm': $!\n";
		}
		if(defined $memory) {
			$Vend::Cfg->{MemoryDatabase}->{$New_database_dbm} = $db;
		}
    }
   }


    if($Global::GDBM) {
		close_database($db) if defined $db;
		undef $db;
    	$db = Vend::Table::GDBM->open_table({Read_only => 1},
                                              "$data/$base.gdbm");
	}
    elsif($Global::DB_File) {
		close_database($db) if defined $db;
		undef $db;
    	$db = Vend::Table::DB_File->open_table({Read_only => 1},
                                              "$data/$base.db");
	}

	$db;
}   


my %Delimiter = (
	2 => "\n",
	3 => "\n%%\n",
	4 => "CSV",
	5 => '\|',
	6 => "\t",
	7 => "\t",
	);
	

sub import_database {
    my ($database,$type) = @_;
	my $delimiter = $Vend::Cfg->{'Delimiter'};
	my $record_delim;
	my $memory;

	croak "import_database: No database name!\n"
		unless $database;


	$type = 1 unless $type;

	unless ($type == 1) {
		$record_delim = ""
			if $type == 2;
		$record_delim = "\n%%%\n"
			if $type == 3;
		$delimiter = $Delimiter{$type}
			or croak "Unknown database type $type.\n";
	}

	my $data;

    my $database_txt = $database;
    my ($base,$path,$tail) = fileparse $database_txt, '\.[^/.]+$';
	$path =~ s:^\./?::;

	unless($path) {
		$data = $Vend::Cfg->{'DataDir'};
		$database_txt = "$data/$database_txt";
	}

	$data =~ s:/$:: ;

	my $database_dbm;
	my $db;
	my $create_sub;
	my $no_import = 0;

	if($Global::Msql and $type == 7) {
		$New_table_msql = $base;
    	$database_dbm = "$data/$base.msql";
    	$New_database_dbm = "$data/new.$base.msql";
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
    elsif($Global::GDBM) {
		$New_database_dbm = "$data/new.$base.gdbm";
    	$database_dbm = "$data/$base.gdbm";
    	$create_sub = \&create_database_gdbm;
	}
    elsif($Global::DB_File) {
		$New_database_dbm = "$data/new.$base.db";
    	$database_dbm = "$data/$base.db";
    	$create_sub = \&create_database_dbfile;
	}
    else {
    	$New_database_dbm = "$data/$base.mem";
		if(ref ($db = $Vend::Cfg->{MemoryDatabase}->{$New_database_dbm})) {
			$no_import = 1;
		}
		$memory = 1;
    	$create_sub = \&create_database_mem;
	}

  IMPORT: {
	last IMPORT if $no_import;
    if (! defined $database_dbm
		or ! -e $database_dbm
        or file_modification_time($database_txt) >
            file_modification_time($database_dbm)) {

        warn "Importing $base table from $database_txt\n";
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
		if(defined $memory) {
			$Vend::Cfg->{MemoryDatabase}->{$New_database_dbm} = $db;
		}
    }
  }


	if($Global::Msql and $type == 7) {
    	$db = Vend::Table::Msql->open_table(
				{Catalog => $Vend::Cfg->{MsqlDB}}, $base);
	}
    elsif($Global::GDBM) {
		close_database($db) if defined $db;
		undef $db;
    	$db = Vend::Table::GDBM->open_table({Read_only => 1},
                                              "$data/$base.gdbm");
	}
    elsif($Global::DB_File) {
		close_database($db) if defined $db;
		undef $db;
    	$db = Vend::Table::DB_File->open_table({Read_only => 1},
                                              "$data/$base.db");
	}

	$db;
}   

sub tag_msql_list {
    my($text,$obj) = @_;
    my($r, $i, $item, $code, $db, $link);
	my($linkvalue, $run, $count);
    my($codere) = '[\w-_#/.]+';

	# get the number to start the increment from
	$count = 0;

    $r = "";
	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};
	my $linkdir = $Vend::Cfg->{'ItemLinkDir'};

    foreach $item (@$obj) {
		$code = $item->[0];

		# Uncomment next line to ignore non-database items
		# next unless product_code_exists($code);

		$count++;

	    $run = $text;
	    $run =~ s:\[msql[-_]param\s+(\d+)\]:$item->[$1]:ig;
		$run =~ s#\[if[-_]msql[-_]field\s+($codere)\]
						([\000-\377]*?)
				  \[/if[-_]msql[-_]field\]#
				  product_field($code,$1)	?	pull_if($2)
											:	pull_else($2)#xige;
		$run =~ s#\[if[-_]msql[-_]data\s+($codere)\s+($codere)\]
					([\000-\377]*?)
					\[/if[-_]msql[-_]data\]#
				  $db = $Vend::Database{$1};
				  database_field($db,$code,$2)	?	pull_if($3)
												:	pull_else($3)#xige;
	    $run =~ s:\[msql[-_]increment\]:$count:ig;
	    $run =~ s:\[msql[-_]code\]:$code:ig;
		$run =~ s:\[msql[-_]data\s+($codere)\s+($codere)\]:
							tag_data($1,$2,$code):igeo;
	    $run =~ s:\[msql[-_]description\]:trim_desc(product_description($code)):ige;
	    $run =~ s:\[msql[-_]field\s+($codere)\]:product_field($code,$1):ige;
	    $run =~ s#\[msql[-_]link\]#"[page $linkdir$link]"
	  			. $linkvalue . '[/page]'#ige;
	    $run =~ s:\[msql[-_]price(\s+)?(\d+)?\]:
					currency(product_price($code,$2)):ige;

	  $r .= $run;
    }
    $r;
}



1;
