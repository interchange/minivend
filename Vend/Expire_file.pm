# Expire_file: creates the "expire" program to expire old sessions
#
# $Id: Expire_file.pm,v 1.1 1996/02/26 21:30:56 amw Exp $
#
package Vend::Expire_file;

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

use strict;
use Vend::Application;

sub setup {
    my $c = app_config();
    my ($Bin_directory, $Config_file, $Perl_program, $Vend_lib) =
        @$c{qw(Bin_directory Config_file Perl_program Vend_lib)};

    my $fn = "$Bin_directory/expire";

    print "Creating $fn\n";
    open(OUT, ">$fn") or die "Can't create '$fn': $!\n";

    print OUT <<"END";
#!$Perl_program -w
use lib '$Vend_lib';
use Vend::Setup;
require '$Config_file';
Vend::Session::expire_sessions();
exit 0;
END

    chmod 0755, $fn or die "Can't chmod '$fn': $!\n";
}

1;
