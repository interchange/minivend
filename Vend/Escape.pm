# Escape.pm:  escapes dangerous characters in file names
#
# $Id: Escape.pm,v 1.4 1996/02/26 22:13:37 amw Exp $
#
package Vend::Escape;

# Copyright 1995, 1996 by Andrew M. Wilcox <awilcox@world.std.com>
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
@EXPORT = qw(escape_filename unescape_filename);

my $Ok_in_filename = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' .
    'abcdefghijklmnopqrstuvwxyz' .
    '0123456789' .
    ':-_.$';
my @Translate;

{
    my ($i, $a, $t);

    foreach $i (0..255) {
        $a = chr($i);
        if (index($Ok_in_filename,$a) == -1) {
	    $t = '%' . sprintf( "%02X", $i );
        } else {
	    $t = $a;
        }
        $Translate[$i] = $t;
    }
}

# Replace any characters that might not be safe in a filename (especially
# shell metacharacters) with the %HH notation.

sub escape_filename {
    my ($in) = @_;
    my ($c, $r);

    $in =~ s/([^\Q$Ok_in_filename\E])/$Translate[ord($1)]/geo;
    $in =~ m/(.*)/;
    return $1;
}

# Replace the escape notation %HH with the actual characters.

sub unescape_filename {
    my($in) = @_;

    $in =~ s/%(..)/chr(hex($1))/ge;
    $in;
}

1;
