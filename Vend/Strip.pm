# Strip.pm: strip placeholders from catalog pages for searching
#
# $Id: Strip.pm,v 1.1 1996/03/12 16:42:00 amw Exp $
#
package Vend::Strip;

# Copyright 1996 by Andrew M. Wilcox <awilcox@world.std.com>
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
@EXPORT = qw(write_stripped_pages);

use strict;
use Vend::Application;
use Vend::Page;

my ($Html, $Stripped_directory, %Directory);

sub write_stripped_pages {
    ($Stripped_directory, $Html) = @_;

    `rm -rf $Stripped_directory`;
    mkdir $Stripped_directory, 0700
        or die "Can't create '$Stripped_directory': $!\n";

    %Directory = ();
    page_iterate(\&write_stripped_page);
}

sub write_stripped_page {
    my ($filename, $page_name) = @_;

    my $out = join('/', map(escape_to_filename($_), split(/\//, $page_name)));

    my ($base) = ($out =~ m,^(.*?)/,);
    if (defined $base and not defined $Directory{$base}) {
        my $dir = "$Stripped_directory/$base";
        die "$dir is not a directory\n" if -e $dir and not -d $dir;
        if (! -e $dir) {
            print "Creating $dir\n";
            mkdir $dir, 0700 or die "Can't create directory '$dir': $!\n";
        }
        $Directory{$base} = 1;
    }

    my $out_fn = "$Stripped_directory/$out$Html";
    open(OUT, ">$out_fn") or die "Can't create '$out_fn': $!\n";
    print OUT strip_page($page_name);
    close(OUT);
}

1;
