# Setup.pm:  sets up application and configures modules
#
# $Id: Setup.pm,v 1.1 1996/02/26 22:00:32 amw Exp $
#
package Vend::Setup;

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
@EXPORT = qw(initialize_modules module setup_modules);

use strict;

my @Modules;

sub module {
    my ($module_name, $config_hash) = @_;

    push @Modules, $module_name;

    my $file = $module_name;
    $file =~ s,::,/,g;
    $file .= '.pm';
    require $file;

    $module_name->configure($config_hash)
        if defined &{$module_name.'::configure'};
}

sub initialize_modules {
    my $module;
    foreach $module (@Modules) {
        $module->initialize() if defined &{$module.'::initialize'};
    }
}

sub setup_modules {
    my $module;
    foreach $module (@Modules) {
        $module->setup() if defined &{$module.'::setup'};
    }
}

1;
