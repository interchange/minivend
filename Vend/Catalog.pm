# Catalog.pm: on-line ordering abstract class
#
# $Id: Catalog.pm,v 1.17 1995/12/04 20:23:38 amw Exp $
#
package Vend::Catalog;

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
use Vend::Directive qw(Default_page Shopping_list_page Order_subsequent);
use Vend::Dispatch;
use Vend::Form;
# use Vend::Orders;
use Vend::Page;
use Vend::Session;


sub init;                       # ()
sub shipping_cost;              # ()
sub item_price;                 # ($item)
sub item_description;           # ($item)
sub item_exists;                # ($item)
sub order_values;               # ($input, $quantities, $submitted)
sub validate_fields;            # ()
sub process_order;              # ($items)

sub create_table_placeholders {
    my ($class, $name, $table) = @_;

    my $column;
    foreach $column ($table->columns()) {
        my $ph = "$name-$column";
        define_placeholder "[$ph \$key]", $table->field_accessor($column);
    }

    # my $exists = sub {
    #     my ($key) = @_;
    #     return $table->record_exists($key);
    # };
    #
    # define_placeholder("[$name-exists \$key]", $exists);
}



## Ordered items

sub Item {
    Session->{items} = [] unless defined Session->{items};
    Session->{items};
}

## CURRENCY

# Return AMOUNT formatted as currency.

sub currency {
    my ($class, $amount) = @_;

    sprintf("%.2f", $amount);
}


sub shipping {
    my ($class) = @_;
    $class->currency($class->shipping_cost());
}


sub shopping_list_link {
    my ($class) = @_;

    if (@{Item()}) {
        return placeholder('the_shopping_list_link');
    }
    else {
        return '';
    }
}


## ORDER AN ITEM

# Returns an url to place an order for the product PRODUCT_CODE.
        
sub order_url {
    my ($class, $product) = @_;
    vend_url('order', {order => $product});
}


# Order an item with product code CODE.

sub action_order {
    my ($class, $action_name, $path, $args) = @_;
    my ($i, $found, $item);

    my $item_code = $args->{order};

    if (!defined($item_code) or $item_code eq '') {
	interaction_error("No product code specified for order\n");
	return;
    }

    if (not $class->item_exists($item_code)) {
	report_error("Attempt to order missing product code: $item_code\n");
	display_special_page('noproduct', $item_code);
	return;
    }

    # Item already on order form?
    undef $i;
    foreach $item (@{Item()}) {
	$i = $item, last if ($item->{code} eq $item_code);
    }

    if (defined $i) {
        $i->{quantity} = 1 if $i->{quantity} < 1;
    } else {
	push @{Item()}, {code => $item_code, quantity => 1};
    }

    $Vend::Message = '';
    display_page(Order_subsequent);
}


## ORDER PAGE

# Returns the total number of items ordered.

sub nitems {
    my ($class) = @_;
    my ($total, $item);

    $total = 0;
    foreach $item (@{Item()}) {
	$total += $item->{quantity};
    }
    $total;
}


# Returns the total cost of the items ordered, without shipping or tax.

sub total_item_cost {
    my ($class) = @_;
    my $total = 0;
    my ($item, $price);
    foreach $item (@{Item()}) {
        $price = $class->item_price($item->{code});
        $total += $item->{quantity} * $price;
    }
    return $total;
}


# Returns the total cost of items ordered.

sub total_cost {
    my ($class) = @_;
    return $class->total_item_cost();
}


## ORDER PAGE ITEM LIST

sub ordered_items {
    my ($class) = @_;
    my ($item);
    my $r = '';

    foreach $item (@{Item()}) {
        $r .= placeholder('ordered_item', $item->{code});
    }
    $r;
}


sub lookup_item {
    my ($class, $code) = @_;
    my $item;
    my $found = undef;

    foreach $item (@{Item()}) {
        $found = $item, last if ($item->{code} eq $code);
    }
    return $found;
}

sub item_quantity {
    my ($class, $code) = @_;
    my $item = $class->lookup_item($code);
    return defined $item ? $item->{quantity} : "";
}


sub quantity_name {
    my ($class, $code) = @_;

    'q.' . $code;
}


## order page processing

sub update_item_quantity {
    my ($class, $code, $quantity) = @_;
    my $item;

    $item = $class->lookup_item($code);

    if (defined $item) {
        $item->{quantity} = $quantity;
    }
    elsif ($class->item_exists($code)) {
        push @{Item()}, {code => $code, quantity => $quantity};
    }
    else {
        # do nothing
    }
}



# Process the completed order page.

sub process_flist {
    my ($class, $name, $path, $args, $input) = @_;

    my $quantities = {};
    my $submitted = undef;
    $class->order_values($input, $quantities, \$submitted);

    my $msg = '';
    my ($code, $quantity);
    while (($code, $quantity) = each %$quantities) {
        if (not $class->item_exists($code)) {
            # XXX product no longer available
            $msg .= "(Please note that the product $code is no longer available).\n";
        }
        if ($quantity !~ m/^\d+$/) {
            $msg .= "Please enter a number for the quantity you wish to order.\n";
            last;
        }
        $class->update_item_quantity($code, $quantity);
    }

    if ($msg ne '') {
	$Vend::Message = $msg;
        display_page(Shopping_list_page);
    } else {
	$class->dispatch_flist($submitted);
    }
}


sub dispatch_flist {
    my ($class, $submitted) = @_;

    if ($submitted eq 'order') {
	my $msg = $class->validate_fields();
	if ($msg ne '') {
	    $Vend::Message = $msg;
            display_page(Shopping_list_page);
	}
        else {
	    my $ok = $class->process_order(Item());
	    Session->{'items'} = [];
	    if ($ok) {
		display_page("confirm");
	    } else {
		display_page("failed");
	    }
	}
    }
    elsif ($submitted eq 'return') {
        # XXX
	display_page(Default_page);
    }
    elsif ($submitted eq 'refresh') {
        display_page(Shopping_list_page);
    }
    elsif ($submitted eq 'cancel'){
	Session->{'Item'} = [];
        # XXX
	display_page(Default_page);
    }
    else {
	interaction_error(
          "Submit value '$submitted' not recognized\n");
	return;
    }
}

1;
