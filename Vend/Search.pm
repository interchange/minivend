# Search.pm:  build and execute a search expression
#
# $Id: Search.pm,v 1.3 1995/10/31 14:10:32 amw Exp $
#
package Vend::Search;

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
@EXPORT = qw(search);

use strict;

my $debug = 0;

sub search {
    my ($options, $fh, $todo, @words) = @_;
    my $and = $options->{'and'} || 0;
    my $substr = $options->{'substr'} || 0;
    my $ignore_case = $options->{'ignore_case'} || 0;
    my $limit = $options->{'limit'} || 10;

    my $word;
    my @wwords = ();
    foreach $word (@words) {
        push @wwords, $word if defined $word and $word ne '';
    }

    my $expr;
    if ($and) {
        $expr = join(' && ', map {
            my $e = quotemeta($_);
            $e = '\b'.$e.'\b' if not $substr;
            $e = 'm/'.$e.'/';
            $e = $e.'i' if $ignore_case;
            $e;
        } @wwords);
    }        
    else {
        $expr = '('.join('|', map(quotemeta($_), @wwords)).')';
        $expr = '\b'.$expr.'\b' if not $substr;
        $expr = 'm/'.$expr.'/';
        $expr = $expr.'i' if $ignore_case;
    }

    my $code = "while (<$fh>) {\n";
    $code .=   "  if ($expr) {\n";
    $code .=   "     $todo\n";
    $code .=   "     last if ++\$count >= \$limit;\n";
    $code .=   "  }\n";
    $code .=   "}\n";

    print $code, "\n" if $debug;
    my $count = 0;
    eval $code;
    die $@ if $@;
    return $count;
}

1;
