# Require.pm:  gathers compile time warnings and includes them in the error
#
# $Id: Require.pm,v 1.3 1995/10/31 14:09:11 amw Exp $
#
package Vend::Require;

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
@EXPORT = qw(Require);

sub Require {
    my ($file) = @_;

    my @warnings = ();
    my $saved_eval_error = $@;
    {
        local $SIG{'__WARN__'} = sub { push @warnings, $_[0]; };
        eval { require $file };
    }
    my $eval_error = $@;
    $@ = $saved_eval_error;

    if ($eval_error) {
        my $msg = join('', @warnings) . $eval_error;
        die $msg;
    }
    else {
        foreach (@warnings) { warn $_ };
    }
}

1;
