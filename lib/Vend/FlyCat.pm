#!/usr/bin/perl
#
# $Id: FlyCat.pm,v 1.3 1999/02/15 08:51:00 mike Exp mike $
#
# Copyright 1998-1999 by Michael J. Heins <mikeh@iac.net>
#
# **** ALL RIGHTS RESERVED ****

package Vend::FlyCat;

$VERSION = substr(q$Revision: 1.3 $, 10);
$DEBUG = 0;

use vars qw! $VERSION $DEBUG @S_FIELDS @B_FIELDS @P_FIELDS %S_to_B %B_to_S!;

use Vend::Data;
use Vend::Util;
use strict;

=head1 NAME

FlyCart.pm -- MiniVend Functions for non-database shopping cart

=head1 SYNOPSIS

check_items();
flycat_die();

=head1 DESCRIPTION

=cut

=head1 METHODS


=cut

use vars qw/ @Item_map $Item_map /;

my $CODE			= 0;
my $DESCRIPTION		= 1;
my $PRICE			= 2;
my $QUANTITY		= 3;
my $SHIPCOST		= 4;
my $INSURANCE		= 5;
my $UNIT_MEASURE	= 6;
my $WEIGHT			= 7;
my $URL				= 8;
my $TF				= 9;
my $SF				= 10;

my %Fmap = (
				 TF => 9,
				 SF => 10,
			 );


$Item_map = 'cartmap';
@Item_map = (
				'rect increase 0,0 55,35',
				'rect decrease 56,0 115,35',
				'rect remove 116,0 200,35',
				'default noaction',
	);

sub find_item {
	my $item = shift;
	my $flycat_db = $Vend::Cfg->{Variable}{MV_FLYCAT_DB} || 'products';
	if($CGI::values{i_code}) {
		return($CGI::values{i_code}, $CGI::values{i_line});
	}
	elsif ($item =~ /^/) {
		my ($p_code, $p_i, $p_price);
		my ($code,$price);
		(undef,$code,undef,$price) = split(/\s*^\s*/, $item);
		my $i = 0;
		my $ref;
		foreach $ref (@{$Vend::Items}) {
			if($code eq $ref->{'code'}) {
				$p_code	= $code;
				$p_i = $i + 1;
				last;
			}
			elsif($ref->{'base'} eq $code) {
				$p_price = Vend::Interpolate::tag_data(
								$flycat_db, 'price', $ref->{'code'});
				$p_code = $ref->{'code'};
				$p_i = $i + 1;
				next unless $p_price = $price;
				last;
			}
		}
		return ($p_code, $p_i);
	}
	return undef;
}

sub store_id {
	my $store = shift;
	$store =~ s/[\^\0].*//;
	return $store;
}

sub redirect {
	my $url = shift || 
		Vend::Interpolate::tag_data('vendor',
									'url' ,
									$Vend::Cfg->{Variable}{STORE_ID})
					|| return '/oops';
	$::Values->{fc_redirect} = $url;
	return '/redirect';
}

sub check_items {
	use strict;
	my $flycat_db = $Vend::Cfg->{Variable}{MV_FLYCAT_DB} || 'products';
	my($db) = Vend::Data::database_exists_ref($flycat_db);
	$db = $db->ref();
	my @base;
	my @code;
	my @opt;
	my @quantity;
	my $options;
	my $store;
	my @item;
	my %used;
	my $action;

	# Set insurance scan
	$Vend::Session->{'values'}{mv_handling} = 'insurance';

	my @current_items = grep $_, split /\0/, $Vend::Session->{current_items};
	for(@current_items) {
		@item = split /\^/, $_;
		$db->set_row(@item);
#::logGlobal("current item: ", @item);
	}

	# Examine any item strings to see if they might be a new
	# item, either 'sku' or 'sku_something'
	my @itemlist;
	for (keys %CGI::values) {
		push(@itemlist, $_) if /^sku(_.*)?$/;
		$options = 1 if /^mod\d+/;
	}

	# Determine the store ID either from the form or from the session
	$store = store_id ($CGI::values{$itemlist[0]}) || $Vend::Session->{fc_store} 
		or flycat_die("Can't find store ID.");
	$Vend::Cfg->{Variable}{STORE_ID} = $Vend::Session->{fc_store} = $store;

	$Vend::Items = Vend::Cart::get_cart($store);

	my ($msg);

	if(defined $CGI::values{"$Item_map.x"}) {
		my @map;
		if($CGI::values{"$Item_map.map"}) {
			@map = $CGI::values{"$Item_map.map"};
		}
		else {
			@map = join "\0", @Item_map;
		}
		$action = Vend::Imagemap::action_map(
				$CGI::values{"$Item_map.x"},
				$CGI::values{"$Item_map.y"},
				@map);
		
		my ($code, $line) = find_item(@itemlist);
		my $ref = $Vend::Items->[$line - 1]
			or flycat_die("Shopping cart is corrupted -- no item $code at line $line.");
		unless($ref->{'code'} eq $code) {
			flycat_die("Shopping cart code doesn't match line number.");
		}
		if($action eq 'increase') {
			$ref->{quantity}++;
		}
		elsif($action eq 'decrease') {
			$ref->{quantity}--;
		}
		elsif($action eq 'remove') {
			$ref->{quantity} = 0;
		}
		else {
#::logGlobal("No action '$action'.", $CGI::values{"$Item_map.x"}, $CGI::values{"$Item_map.y"});
		}
		
		Vend::Cart::toss_cart($Vend::Items);

		return redirect()
			if ! scalar @{$Vend::Items};
		return "/ord/basket";
	}

	return undef if $CGI::values{mv_nextpage}
				and $CGI::values{mv_todo} eq 'return';

	my $id;


	ADDITEM:
	foreach $id (@itemlist) {
		my $addl = '';
		$id =~ /(_.*)/ and $addl = $1;
		my $item = $CGI::values{$id};
		if($options) {
			for( 1 .. 16 ) {
				next unless defined $CGI::values{"mod$_$addl"};
#::logGlobal("set option mod$_$addl to ", $CGI::values{"mod$_$addl"});
				$opt[$_] = $CGI::values{"mod$_$addl"};
			}
		}
		($store,@item) = split /[\^\0]/, $item;

		my $unique = '';

		if(@item) {
#::logGlobal("parsing item:", @item);
			$Vend::Session->{current_items} .= "\0" . join "^", @item;
			if($options) {
				my $i = -1;
				for (@item) {
					$i++;
					next unless /^mod(\d+)$addl/;
					if($i == 2) {
#::logGlobal("set $id pricing");
						my $price = 0;
						$item[$DESCRIPTION] .= " ";
						while (s/^mod(\d+)$addl//) {
#::logGlobal("update $id with option $1");
							my $string = $opt[$1] || next;
#::logGlobal("found option $string $string");
							$string =~ /^=error=/i
								and return flycat_die($string);
							$string =~ /(.*)\s+-\s+\$?([\d.]+)*/
								or return flycat_die("Badly formatted option.");
							$price += $2;
#::logGlobal("option $string $string matched, price += $2 = $price ");
							my $extra = $1;
							$item[ $DESCRIPTION ] .= "-$extra";
							$extra =~ tr/A-Za-z0-9//cd;
							$unique .= "-$extra";
						}
						$item[ $PRICE ] = $price;
					}
					else {
						$_ = $opt[$1];
					}
				}
			}

			# discount, won't be added to cart
			if( index("\L$item[$CODE]", '=discount=') == 0 ) {
				$item[$CODE] =~ s/^=discount=\s*//i;
				my $type = $item[$CODE] || 'ENTIRE_ORDER';
				
				$Vend::Session->{discount}->{$type} =
														'$s * ( 1 - ' .
														$item[$PRICE] .
														' / 100)';
				$Vend::Session->{fc_discount} = $item[$DESCRIPTION];
				$Vend::Session->{fc_member} = $opt[1] || $CGI::values{mod1};
				next ADDITEM;
			}
			# Handle Taxfree and shipping free
			while($item[$CODE] =~ s/^=(\w+)=//) {
				$item[$Fmap{$1}] = 1;
			}

			push(@base, $item[$CODE]);
			my $code = $item[$CODE] . $unique;
#::logGlobal("found item $code:" , @item);
			push(@code, $code);
			$item[$CODE] = $code;

			$item[ $QUANTITY ] = 1
				unless $item[$QUANTITY]
						and	$item[$QUANTITY] =~ /^\d+$/;

			push(@quantity, $item[$QUANTITY]);
			$db->set_row(@item);
			push @current_items, join "^", @item;
		}
	} # End ADDITEM

	if(@code) {
#::logGlobal("formatting items for order:", @code);
#::logGlobal("formatting items bases are:", @base);
#::logGlobal("formatting items quans are:", @quantity);
		$CGI::values{mv_order_item} = join "\0", @code;
		$CGI::values{mv_order_base} = join "\0", @base;
		$CGI::values{mv_order_quantity} = join "\0", @quantity;
		$CGI::values{mv_orderpage} = 'ord/basket';
	}
	elsif (defined $CGI::values{'checkout.x'}) {
		$CGI::values{mv_orderpage} = 'ord/checkout';
	}

	$CGI::values{mv_doit} = 'refresh' unless $CGI::values{mv_doit};

	$Vend::Cfg->{UseModifier} = ['base'];
	$Vend::Session->{current_items} = join "\0", @current_items;
	if ( $CGI::values{'mv_order_item'} ) {
		::add_items(
				delete $CGI::values{mv_order_item},
				delete $CGI::values{mv_order_quantity},
				);
	}

	return;
}

sub flycat_die {
	my $message = shift;
	$message =~ s/^=error=\s*//i;
	$Vend::Session->{'fc_error'} = $message;
	return '/oops';
}

1;
