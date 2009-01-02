#!/usr/bin/perl
#
# MiniVend version 2.02
#
# $Id: Cart.pm,v 1.1 1996/10/30 04:22:28 mike Exp $
#
# This program is largely based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Enhancements made by and
# Copyright 1996 by Michael J. Heins <mikeh@iac.net>
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

package Vend::Cart;
@ISA = qw(Exporter);
@EXPORT = qw(get_cart set_cart sort_cart toss_cart);
@EXPORT_OK = qw(create add set);

$VERSION = substr(q$Revision: 1.1 $, 10);
$DEBUG   = 0;

use Carp;
use vars qw($DEBUG $VERSION);
use strict;
use Vend::Util 'logError';

sub create {
    my($name, @attributes) = @_;
	croak "New shopping cart $name defined with no name.\n"
		unless defined $name;
	return $Vend::Session->{'carts'}->{$name} = [];
}

sub add {
	my($s, %item) = @_;
	my $found = -1;
	my $i;
	
	! defined $item{'code'} or $item{'code'} eq ''
		and croak "Vend::Cart: add empty item?";

	$item{'quantity'} ||= 1;
	$item{'quantity'} < 1 and die "Can't order negative number.\n";
	
	INC: {
		last INC if $item{Separate};

		foreach $i (0 .. $#$s) {
		    if ($s->[$i]->{'code'} eq $item{'code'}) {
				$found = $i;
				delete $item{'code'};
			}
		}

	}

	if($found == -1) {
		push @$s, \%item;
	}
	else {
		for (keys %item) {
			($s->[$i]->{$_} = $item{$_}, next)
				unless $_ eq 'quantity';
			$s->[$i]->{'quantity'} += $item{$_};
		}
	}
}


sub set {
	my($s, $cursor, $keep, %item) = @_;
	my $found = -1;
	my $i;
	
	CHECK: {
		last CHECK if $cursor >= 0;
		die "Vend::Cart -- can't set item without code.\n"
			unless $item{'code'};
		foreach $i (0 .. $#$s) {
		    if ($$s->[$i]->{'code'} eq $item{'code'}) {
				$cursor = $i;
			}
		}
	}

	return $s->add(%item)
		unless defined $s->[$cursor];
	unless ($keep) {
		die "Vend::Cart -- can't set item without code.\n"
			unless $item{'code'};
		$s->[$cursor] = {%item};
	}
	else {
		@{$s->[$cursor]}{keys %item} = values %item;
	}
	return $cursor;
}

sub sort_cart {
	my($s, $field, $option) = @_;

	unless (defined $s->[0]->{$field}) {
		logError "Vend::Cart: sort on non-existent attribute '$_'.";
		$field = 'code';
	}
	my $code = <<'EOF';
sub {   $s->[$a]->{$field} cmp $s->[$b]->{$field}  }
EOF

	if(defined $option) {
		$option =~ /r/i and $code =~ tr/ab/ba/;
		$option =~ /n/i and $code =~ s/ cmp / <=> /;
		$option =~ /i/i and $code =~ s/\$field/lc \$field/g;
	}
	my $routine = eval $code;
	@$s = sort $routine 0 .. $#$s;

	1;
}
	
# If the user has put in "0" for any quantity, delete that item
# from the order list.
sub toss_cart {
	my($s) = @_;
	my $i;
    DELETE: for (;;) {
        foreach $i (0 .. $#$s) {
            if ($s->[$i]->{'quantity'} == 0) {
                splice(@$s, $i, 1);
                next DELETE;
            }
        }
        last DELETE;
    }

    1;
}

sub set_cart {
	my($cart) = @_;
	defined $cart and defined $Vend::Session->{'carts'}->{$cart}
	    and return $Vend::Items = $Vend::Session->{'carts'}->{$cart};
	return $Vend::Items;
}

sub get_cart {
	my($cart,@options) = @_;
	if(defined $cart and defined $Vend::Session->{'carts'}->{$cart}) {
	    return $Vend::Session->{'carts'}->{$cart};
	}
	elsif(defined $cart) {
		return create $cart;
	}
	return $Vend::Items;
}

1;
