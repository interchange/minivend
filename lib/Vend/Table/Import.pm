# Table/Import.pm: import a table
#
# $Id: Import.pm,v 1.6 1997/05/02 05:50:23 mike Exp $
#
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# $Log: Import.pm,v $
# Revision 1.6  1997/05/02 05:50:23  mike
# *** empty log message ***
#
# Revision 1.4  1996/10/19 18:54:10  mike
# MV 202a, interim
#
# Revision 1.3  1996/09/08 08:29:46  mike
# Removed hiding scope declaration
#
# Revision 1.1  1996/08/09 22:21:11  mike
# Initial revision
#
# Revision 1.6  1996/05/18 20:02:39  mike
# Minivend 1.03 Beta 1
#
# Revision 1.5  1996/04/22 05:18:48  mike
# Annotation of Andrew's version 1.4
#
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

package Vend::Table::Import;
$VERSION = substr(q$Revision: 1.6 $, 10);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(import_csv import_quoted import_ascii_delimited);
use strict;
use Vend::Table::Quoted qw(read_quoted_fields);
use Vend::Util;

sub import_csv {
    my ($source, $create) = @_;

    die "The source file '$source' does not exist\n" unless -e $source;

    open(Vend::Table::Import::IN, "+<$source")
		or die "Can't open '$source' for reading: $!\n";
	lockfile(\*Vend::Table::Import::IN, 1, 1) or die "lock\n";
    my @columns = read_quoted_fields(\*IN);
    die "$source is empty\n" unless @columns;
    shift @columns;

    my $out = &$create(@columns);
    my (@fields,$key);
    while (@fields = read_quoted_fields(\*IN)) {
        $out->set_row(@fields);
    }
	unlockfile(\*Vend::Table::Import::IN) or die "unlock\n";
    close(Vend::Table::Import::IN);
    $out->close_table();
	return $out;
}

sub import_quoted { return import_csv(@_) }


sub import_ascii_delimited {
    my ($infile, $delimiter, $create) = @_;
    $delimiter = quotemeta($delimiter);

    open(Vend::Table::Import::IN, "+<$infile")
		or die "Couldn't open '$infile': $!\n";
	lockfile(\*Vend::Table::Import::IN, 1, 1) or die "lock\n";

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

	unlockfile(\*Vend::Table::Import::IN) or die "unlock\n";
    close(Vend::Table::Import::IN);
    $out->close_table();
    return $out;
}

sub version { $Vend::Table::Import::VERSION }

1;
