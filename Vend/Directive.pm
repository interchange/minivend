# Directive.pm: provides access to configuration directives
#
# $Id: Directive.pm,v 1.6 1996/01/30 23:17:30 amw Exp $
#
package Vend::Directive;

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

use Carp;
use strict;
no strict 'refs';

=head1 NAME

Vend::Directive - Access configuration directives

=head1 SYNOPSIS

    use Vend::Directive qw(Data_directory Mail_order_to);

=head1 DESCRIPTION

For each directive listed, a subroutine is created in the caller's
namespace which returns the value of the configuration directive of
the same name.

=cut

sub import {
    my ($package) = caller;
    my $val;
    shift @_;
    foreach (@_) {
        $val = $main::Config->{$_};
        carp "The '$_' directive is not defined" unless defined $val;
        *{ $package . "::" . $_ } = access($val);
    }
}

sub access {
    my ($value) = @_;

    return sub { $value };
}

1;
