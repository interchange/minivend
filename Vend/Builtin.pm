# Builtin.pm: defines placeholders available to all Vend applications
#
# $Id: Builtin.pm,v 1.9 1995/11/28 18:30:21 amw Exp $
#
package Vend::Builtin;

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

use strict;
use Vend::Directive qw(Default_page External_URL);
use Vend::Dispatch;
use Vend::Session;
use Vend::Page;


define_placeholder '[message]', sub {
    $Vend::Message;
};

define_placeholder '[page-url $pg]', sub {
    my ($pg) = @_;
    my ($path, $base);

    if (($path) = ($pg =~ m!^/(.*)!)) {
        return vend_url($path);
    }
    
    ($base) = (page_name() =~ m!^(.*)/!);
    if (defined $base) {
        return vend_url($base . "/" . $pg);
    } else {
        return vend_url($pg);
    }
};

define_placeholder '[default-page-url]', sub {
    vend_url(Default_page);
};

define_placeholder '[external-url $img]', sub {
    my ($img) = @_;
    my ($path, $base);

    if (($path) = ($img =~ m!^/(.*)!)) {
        return External_URL . "/$path";
    }
    
    ($base) = (page_name() =~ m!^(.*)/!);
    if (defined $base) {
        return External_URL . "/$base/$img";
    } else {
        return External_URL . "/$img";
    }
};

# Returns the text of the user entered field.

define_placeholder '[value $field]', sub {
    my ($field) = @_;

    my $value = Value->{$field};
    if (defined $value) {
        # $value =~ s/^\s+//;
        # $value =~ s/\s+$//;
	return $value;
    } else {
	return "";
    }
};


define_placeholder '[checked-if $field $value]', \&checked_if;

sub checked_if {
    my ($field, $value) = @_;

    my $v = Value($field);
    return 'checked' if defined($v) and $v eq $value;
    return '';
}

1;
