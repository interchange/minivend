# Table/Import.pm: import a table
#
# $Id: Import.pm,v 1.4 1996/03/12 16:18:52 amw Exp $
#
package Vend::Table::Import;

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
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(import_csv import_quoted import_ascii_delimited);

use strict;
use Vend::Table::Quoted qw(read_quoted_fields);
use Vend::Util;

sub import_csv {
    my ($source, $table_class, $table_file, $force, @options) = @_;

    die "The source file '$source' does not exist\n" unless -e $source;

    my $import = $force;
    $import = 1 unless $import or -e $table_file;
    $import = 1 unless $import or file_modification_time($source) <=
                                  file_modification_time($table_file);
    return unless $import;

    print "Importing product table '$source'\n";
    open(IN, $source) or die "Can't open '$source' for reading: $!\n";
    my @columns = read_quoted_fields(\*IN);
    die "$source is empty\n" unless @columns;
    shift @columns;

    my $new_table_file = "$table_file.new";
    my $db = $table_class->create([@columns], $new_table_file, @options);
    my @fields;
    while (@fields = read_quoted_fields(\*IN)) {
        $db->set_row(@fields);
    }
    close(IN);
    $db->close_table();

    rename($new_table_file, $table_file)
        or die "Can't move '$new_table_file' to '$table_file': $!\n";
}

sub import_quoted { return import_csv(@_) }


sub import_ascii_delimited {
    my ($infile, $delimiter, $create) = @_;
    my $delimiter = quotemeta($delimiter);

    open(IN, $infile) or die "Couldn't open '$infile': $!\n";
    
    my $field_names = <IN>;
    chomp $field_names;
    my @field_names = split(/$delimiter/, $field_names);
    shift @field_names;

    my $out = &$create(@field_names);

    my (@fields, $key);
    eval <<"END";
        while (<IN>) {
            chomp;
            \@fields = split(/$delimiter/, \$_, 99999);
            \$key = shift \@fields;
            \$out->set_row(\$key, \@fields);
        }
END
    die $@ if $@;

    close(IN);
    $out->close_table();
    return $out;
}

1;
