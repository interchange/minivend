# Application: defines the configuration common to all applications
#
# $Id: Application.pm,v 1.1 1996/02/26 21:16:24 amw Exp $
#
package Vend::Application;

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
@EXPORT = qw(App app_config App_directory Data_directory Perl_program);

use strict;

my $Config;

sub App            { $Config->{'App'} }
sub App_directory  { $Config->{'App_directory'} }
sub Bin_directory  { $Config->{'Bin_directory'} }
sub Data_directory { $Config->{'Data_directory'} }
sub Perl_program   { $Config->{'Perl_program'} }

sub configure {
    my ($class, $config) = @_;
#    foreach $d (qw(App App_directory Data_directory Perl_program)) {
#        die "The $d directive is not specified" unless defined $config->{$d};
#    }
    $Config = $config;
}

sub setup {
    make_directory(Data_directory);
    make_directory(Bin_directory);
}

sub make_directory {
    my ($dir) = @_;

    if (! -e $dir) {
        print "Creating directory $dir\n";
        mkdir $dir, 0755
            or die "Can't create directory '$dir': $!\n";
    }
    elsif (! -d $dir) {
        die "Not a directory: '$dir'\n";
    }
    return 1;
}

sub app_config {
    return $Config;
}

1;
