# Session.pm:  tracks session information between requests
#
# $Id: Session.pm,v 1.1 1996/02/26 21:46:00 amw Exp $
#
package Vend::Session;

# Copyright 1996 by Andrew M. Wilcox <awilcox@maine.com>
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
@EXPORT = qw(dump_sessions close_session expire_sessions open_session
             new_session session_id Session Value);

use strict;

sub configure {
    my ($class, $config) = @_;
    my $implementation = $config->{'Implementation'};

    my $impl_module = $implementation;
    $impl_module =~ s,::,/,g;

    require "$impl_module.pm";
    # $implementation->import();
    really_configure('Vend::Session', $config);
}

1;
