# Builtin.pm: defines placeholders available to all Vend applications
#
# $Id: Builtin.pm,v 1.11 1996/02/26 21:18:17 amw Exp $
#
package Vend::Builtin;

# Copyright 1995,1996 by Andrew M. Wilcox <awilcox@world.std.com>
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

my $Config;

sub External_URL { $Config->{'External_URL'} }

sub configure {
    my ($class, $config) = @_;
    $Config = $config;
}

use strict;
# use Vend::Directive qw(Default_page External_URL);
use Vend::Dispatch;
use Vend::Session;
use Vend::Page;


=head1 NAME

Vend::Builtin - Common placeholder definitions for all applications

=head1 FUNCTIONS

=head2 C<[message]>

Returns the contents of the global variable $Vend::Message, which is
used to display messages such as fields in the shopping list that have
to be filled in.

=cut

define_placeholder '[message]', sub {
    $Vend::Message;
};


=head2 C<[page-url "name"]>

Returns the URL which references the specified catalog page.
Names that start with a "/" are absolute names, rooted in the
C<Page-directory> as defined in the configuration file.
Names that don't start with a "/" are relative to the current
page being displayed.

Using a relative page name serves the same purpose as using a relative
URL in HTML.  The difference is that the location of the page is
determined by Vend instead of by the browser.  The page-url
placeholder always returns a fully qualified URL.

=cut

sub page_url_ph {
    my ($pg) = @_;
    return page_url($pg);
}

define_placeholder '[page-url $pg]', \&page_url_ph;


# =head2 C<[default-page-url]>
# 
# Returns a URL refering to the default page of the catalog.  The name
# of the default page is specified by the Default_page directive.
# 
# =cut
# 
# define_placeholder '[default-page-url]', sub {
#     vend_url(Default_page);
# };

=head2 C<[external-url $img]>

Inline images and other non-textual entities are served directly by
your HTTPD server and do not go through Vend.  You can set up an
C<External-directory> parallel to your C<Page-directory> structure, if
you wish.  This is particularly handy for inline images.  Absolute
names beginning with a "/" are rooted in the C<External-URL>.
Relative names, those which don't start with a "/", use the parallel
location to the page currently being displayed.

=cut

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

=head2 C<[value $field]>

Returns the value of the user-entered field.

=cut

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


=head2 C<[checked-if $field $value]>

This placeholder is used in a checkbox input field tag to include the
"checked" attribule.  Returns "checked" if the C<field> currently has
the specified C<value>, and returns nothing ("") if not.

=cut

define_placeholder '[checked-if $field $value]', \&checked_if;

sub checked_if {
    my ($field, $value) = @_;

    my $v = Value($field);
    return 'checked' if defined($v) and $v eq $value;
    return '';
}

1;
