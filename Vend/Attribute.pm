# Attribute.pm: product attribute class
#
# $Id: Attribute.pm,v 1.1 1996/03/12 16:22:08 amw Exp $
#
package Vend::Attribute;

# Copyright 1996 by Andrew M. Wilcox <awilcox@world.std.com>
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
use Vend::Dispatch;
use Vend::Form;
use Vend::Shopcart qw(option_list option_list_selected);
use Vend::Util qw(blank);

sub new {
    my $class = shift;
    my $db = shift or croak "No database specified";

    my ($attribute_name, $attribute_title, $attribute_plural);

    my $names = [];
    my $titles = {};
    my $plurals = {};
    my $field = {};

    while (@_) {
        $attribute_name = shift @_;
        $attribute_title = shift @_
            or croak "Title of attribute '$attribute_name' not specified";
        $attribute_plural = shift @_
            or croak "Plural of attribute '$attribute_name' not specified";

        push @$names, $attribute_name;
        $plurals->{$attribute_name} = $attribute_plural;
        $titles->{$attribute_name} = $attribute_title;
        $field->{$attribute_name} = $db->field_accessor($attribute_plural);
    }

    my $self = {db => $db,
                names => $names,
                titles => $titles,
                plurals => $plurals,
                field => $field,
               };
    return bless $self, $class;
}

sub attributes {
    my ($s) = @_;
    my $names = $s->{'names'};
    return @$names;
}

sub titles {
    my ($s) = @_;
    my $names = $s->{'names'};
    my $titles = $s->{'titles'};

    return map($titles->{$_}, @$names);
}


sub range {
    my ($s, $product_code, $attr) = @_;
    my $db = $s->{'db'};
    my $field = $s->{'field'};

    return () unless $db->record_exists($product_code);
    return split(/\s*,\s*/,
                 &{$field->{$attr}}($product_code));
}

sub has_attribute {
    my ($s, $product_code, $attr) = @_;
    return ($s->range($product_code, $attr)) != 0;
}

sub catalog_choice {
    my ($s, $product_code, $attribute) = @_;

    my @range = $s->range($product_code, $attribute);

    if (@range) {
        return "<select name=$attribute>"
            . option_list(@range)
            . "</select>";
    }
    else {
        return undef;
    }
}

sub add_form {
    my ($s, $product_code, $add_url, $button_title) = @_;
    my $names = $s->{'names'};

    my $r = "<form action=\"$add_url\" method=post>\n";
    my ($attribute, $select);
    foreach $attribute (@$names) {
        $select = $s->catalog_choice($product_code, $attribute);
        $r .= "  $select\n" if defined $select;
    }
    $r .= "  <input type=submit name=add value=\"$button_title\">\n";
    $r .= "</form>\n";
    return $r;
}

sub shoplist_choice {
    my ($s, $shoplist, $attribute, $i) = @_;

    my $product_code = $shoplist->[$i]{'code'};
    my $current_value = $shoplist->[$i]{$attribute};
    my @range = $s->range($product_code, $attribute);

    if (@range) {
        $current_value = $range[0] if blank($current_value);
        return qq(<select name="i$i.$attribute">)
               . option_list_selected($current_value, @range)
               . '</select>';
    }
    else {
        return '<br>';
    }
}

sub fetch_attributes {
    my ($s, $product_code, $prefix, $input) = @_;
    my $attribute_names = $s->{'names'};
    
    my $a = {};
    my ($attribute, $v);
    foreach $attribute (@$attribute_names) {
        $v = $s->fetch_attribute($product_code, $prefix, $input, $attribute);
        $a->{$attribute} = $v if defined $v;
    }
    return $a;
}

sub fetch_attribute {
    my ($s, $product_code, $prefix, $input, $attribute) = @_;

    my @range = $s->range($product_code, $attribute);
    if (@range) {
        my $value = get_required_field($input, $prefix . $attribute);
        interaction_error("'$value' is not a valid $attribute for '$product_code'")
            unless grep($_ eq $value, @range);
        return $value;
    }
    else {
        return undef;
    }
}

sub handle_add_form {
    my ($s, $shoplist, $name, $path, $args, $input) = @_;
    my $db = $s->{'db'};

    my $product_code = $args->{'product'};

    interaction_error("No product code specified for add to shopping list\n")
        if blank($product_code);
    unless ($db->record_exists($product_code)) {
        display_special_page('noproduct', $product_code);
        die "Attempted to add missing product code '$product_code' to shopping list\n";
    }

    my $attribute_value = $s->fetch_attributes($product_code, "", $input);

    my $submit;
    $submit = 'add' if defined $input->{'add'};

    my $item = {code => $product_code, quantity => 1, %$attribute_value};
    push @$shoplist, $item;
}

sub describe {
    my ($s, $product_code, $item) = @_;
    my $names = $s->{'names'};
    my ($name, @a);
    foreach $name (@$names) {
        push @a, $item->{$name} if $s->has_attribute($product_code, $name);
    }
    return join(', ', @a);
}

1;
