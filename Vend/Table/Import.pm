# Table/Import.pm: import a table
#
# $Id: Import.pm,v 1.2 1995/10/31 14:18:46 amw Exp $
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
@EXPORT = qw(import_ascii_delimited);

use strict;

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
            \@fields = split(/$delimiter/, \$_);
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
