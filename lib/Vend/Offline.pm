#
# Offline.pm - Offline database build module for MiniVend
#
# $Id: Offline.pm,v 1.4 1997/11/03 11:31:32 mike Exp mike $
# 
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
# Copyright 1996,1997 by Michael J. Heins <mikeh@iac.net>
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

package Vend::Offline;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(

close_products
close_database
column_exists
database_field
database_key_exists
db_column_exists
open_database
import_database
import_products
product_code_exists
product_description
product_field
database_ref

);

use strict;
use Carp;
use File::Basename;
use Vend::Util;
use Vend::Table::Import qw(import_ascii_delimited import_quoted);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.4 $, 10);


BEGIN {
	if($Global::GDBM) {
		require Vend::Table::GDBM;
	}
	elsif($Global::DB_File) {
		require Vend::Table::DB_File;
	}
	else {
		die "No DBM defined! Offline import not necessary.\n";
	}
}

my $New_product_dbm; 
my $New_database_dbm; 
my ($Products);

sub database_key_exists {
    my ($db,$key) = @_;
    return $db->record_exists($key);
}

sub product_code_exists {
    my ($product_code) = @_;
    return $Products->record_exists($product_code);
}

sub open_database {
	my ($file,$type);
	my $d = $Vend::Cfg->{'Database'};
    for (keys %{$d}) {
		$file = $d->{$_}->{'file'};
		$type = $d->{$_}->{'type'};
		$Vend::Database{$_} = import_database($file, $type);
	}
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
    my ($field_name, $product_code) = @_;
    return "NA" unless product_code_exists($product_code);
    return "NA" unless defined column_exists($field_name);
    return $Products->field($product_code, $field_name);
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

    my $data = $Vend::Cfg->{'OfflineDir'};
	my $delimiter = $Vend::Cfg->{'Delimiter'} || "\t";

    my $product_txt = "$data/products.asc";
	my $product_dbm;
	my $create_sub;

	if($Vend::Cfg->{'PriceBreaks'}) {
		read_pricing();
	}

    if($Global::GDBM) {
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
    	$create_sub = \&create_product_mem;
	}

    if (! defined $product_dbm
		or ! -e $product_dbm
        or file_modification_time($product_txt) >
            file_modification_time($product_dbm)) {

        warn "Importing product table from $product_txt\n";
        $Products = import_ascii_delimited($product_txt, $delimiter, $create_sub)
			unless $delimiter eq 'CSV';
        $Products = import_quoted($product_txt, $create_sub)
			if $delimiter eq 'CSV';
		if(defined $product_dbm) {
        	rename($New_product_dbm, $product_dbm)
            	or die "Couldn't move '$New_product_dbm' to '$product_dbm': $!\n";
		}
    }


    if($Global::GDBM) {
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
    	$Products->close_table()
			or die "Could not untie products database.\n";
}

sub database_ref {
    my $db = $_[0] || $Products;
    if (ref ($db) =~ /dummy/i) {
        $db = $db->import_db($db);
    }
    $db;
}

sub import_pricing {

	my $delimiter = "\t";

	my $data = $Vend::Cfg->{'OfflineDir'};

    my $database_txt = "$Vend::Cfg->{'OfflineDir'}/pricing.asc";
    my ($base,$path,$tail) = fileparse $database_txt, '\.[^/.]+$';
	$path =~ s:^\./?::;

	unless($path) {
		$data = $Vend::Cfg->{'OfflineDir'};
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
    	$create_sub = \&create_database_mem;
	}

    if (! defined $database_dbm
		or ! -e $database_dbm
        or file_modification_time($database_txt) >
            file_modification_time($database_dbm)) {

        warn "Importing Pricing table from $database_txt\n";
        $db = import_ascii_delimited($database_txt, $delimiter, $create_sub);
		if(defined $database_dbm) {
        	rename($New_database_dbm, $database_dbm)
            	or die "Couldn't move '$New_database_dbm' to '$database_dbm': $!\n";
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


sub import_database {
    my ($database,$type) = @_;
	my $delimiter = $Vend::Cfg->{'Delimiter'};
	my $record_delim;

	croak "import_database: No database name!\n"
		unless $database;

	$type = 1 unless defined $type;

	$delimiter = "\n" 
		if $type == 2;
	$record_delim = ""
		if $type == 2;
	$delimiter = "\n%%\n"
		if $type == 3;
	$record_delim = "\n%%%\n"
		if $type == 3;
	$delimiter = "CSV" 
		if $type == 4;
	$delimiter = '\|' 
		if $type == 5;
	$delimiter = "\t" 
		if $type == 6;

	my $data;

    my $database_txt = $database;
    my ($base,$path,$tail) = fileparse $database_txt, '\.[^/.]+$';
	$path =~ s:^\./?::;

	unless($path) {
		$data = $Vend::Cfg->{'OfflineDir'};
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
    	$create_sub = \&create_database_mem;
	}

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


1;
__END__
