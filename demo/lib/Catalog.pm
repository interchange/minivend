package Catalog;

use strict;
use Vend::Directive qw(App App_directory Data_directory Default_page
                       Order_subsequent Mail_order_to Shopping_list_page);
use Vend::Dispatch;
use Vend::Form;
use Vend::Page;
use Vend::Sendmail;
use Vend::Session;
use Vend::Shopcart qw(Shoplist cent_round currency
                      order_number option_list option_list_selected
                      add_url_ph shoplist_index_of
                      save_field_values);
require Vend::Table::GDBM;
use Vend::Util;


my ($Products, $Product_desc, $Product_price);

sub init {
    my $data = Data_directory;

    $Products = Vend::Table::GDBM->open_table({Read_only => 1},
                                              "$data/product.gdbm");

    # create_table_placeholders("product", $Products, "NA");
    $Product_desc = $Products->field_accessor("description");
    $Product_price = $Products->field_accessor("price");
}

sub product_code_exists {
    my ($product_code) = @_;
    return $Products->record_exists($product_code);
}

sub product_price {
    my ($product_code) = @_;
    return "NA" unless product_code_exists($product_code);
    return &$Product_price($product_code);
}

sub product_description {
    my ($product_code) = @_;
    return "NA" unless product_code_exists($product_code);
    return &$Product_desc($product_code);
}

sub product_field_ph {
    my ($product_code, $field_name) = @_;
    return "NA" unless product_code_exists($product_code);
    return $Products->field($product_code, $field_name);
}

sub shopping_list_link_ph {
    if (@{Shoplist()}) {
        return '[<a href="' . vend_url("/list") . '">Shopping List</a>]';
    }
    else {
        return '';
    }
}
    
sub in_state_checkbox_ph {
    my $in_state = Value('in_state');
    my $r = '<input type=checkbox name="in_state"';
    $r .= ' checked' if defined $in_state and $in_state eq 'on';
    $r .= '>';
    return $r;
}

sub handle_add_form {
    my ($name, $path, $args, $input) = @_;

    my $product_code = $args->{'product'};

    interaction_error("No product code specified for add to shopping list\n")
        if blank($product_code);

    unless (product_code_exists($product_code)) {
        display_special_page('noproduct', $product_code);
        die "Attempted to add missing product code '$product_code' to shopping list\n";
    }

    my ($submitted);
    form_fields($input, [['submit', \$submitted, ['submit', 'add']]]);

    my $item = {code => $product_code, quantity => 1};
    push @{Shoplist()}, $item;

    $Vend::Message = '';
    display_page(Shopping_list_page);
}

sub handle_add {
    my ($action_name, $path, $args) = @_;

    my $product_code = $args->{'product'};

    interaction_error("No product code specified for order\n")
        if blank($product_code);

    if (not product_code_exists($product_code)) {
	display_special_page('noproduct', $product_code);
	die "Attempted to add missing product code '$product_code' to shopping list\n";
    }

    # Item already on order form?
    my $i = shoplist_index_of($product_code);

    if (defined $i) {
        my $item = Shoplist->[$i];
        $item->{quantity} = 1 if $item->{quantity} < 1;
    } else {
	push @{Shoplist()}, {code => $product_code, quantity => 1};
    }

    $Vend::Message = '';
    display_page(Order_subsequent);
}

sub sales_tax {
    my ($subtotal) = @_;
    my $in_state = Value('in_state');
    if (defined $in_state and $in_state eq 'on') {
        return $subtotal * 0.05;
    }
    else {
        return 0;
    }
}

sub ordered_items_ph {
    my ($r, $subtotal, $i, $item, $code, $quantity, $price, $amount);

    $r = qq(<input type=hidden name=product_codes value=")
         . join(',', map($_->{'code'}, @{Shoplist()}))
         . qq(">\n);

    $r .=
'<table border>
  <tr><th>Quantity</th><th>Product</th><th>Description</th>
      <th>Price Per</th><th>Amount</th>
  </tr>
';

    $subtotal = 0;
    foreach $i (0 .. $#{Shoplist()}) {
          $item = Shoplist->[$i];
        $code = $item->{'code'};
        $quantity = $item->{'quantity'};
        $price = product_price($code);
        $amount = cent_round($quantity * $price);
        $subtotal += $amount;

        $r .= join('',
'  <tr><td><input type="text" name="', "i$i.quantity", '" ',
            'value="', $quantity, '" size=4></td>', "\n",
'      <td>', $code, "</td>\n",
'      <td>', product_description($code), "</td>\n",
'      <td align=right>', currency($price), "</td>\n",
'      <td align=right>', currency($amount), "</td>\n",
'  </tr>', "\n");
    }

    $subtotal = cent_round($subtotal);
    my $sales_tax = sales_tax($subtotal);
    my $total = cent_round($subtotal + $sales_tax);

    $r .= join('',
'  <tr><td colspan=4 align=right>Subtotal:</td>', "\n",
'      <td align=right>', currency($subtotal), '</td>', "\n",
'  </tr>', "\n",

'  <tr><td colspan=4 align=right>Sales tax:</td>', "\n",
'      <td align=right>', currency($sales_tax), '</td>', "\n",
'  </tr>', "\n",

'  <tr><td colspan=4 align=right>Total:</td>', "\n",
'      <td align=right>', currency($total), '</td>', "\n",
'  </tr>', "\n",
"</table>\n");

    return $r;
}
      
sub handle_shoplist {
    my ($name, $path, $args, $input) = @_;
    my (@codes, $i, $product_code, $quantity, $v, $item);

    @codes = grep(product_code_exists($_),
                  split(/,/, get_required_field($input, 'product_codes')));

    @{Shoplist()} = ();
    foreach $i (0 .. $#codes) {
        $product_code = $codes[$i];

        $quantity = get_required_field($input, "i$i.quantity");
        if ($quantity =~ m/(\d+)/) {
            $quantity = $1;
        }
        else {
            $quantity = 1;
        }
        next if $quantity == 0;

        $item = {code => $product_code, quantity => $quantity};
        push @{Shoplist()}, $item;
    }

    my $submit_button;
    order_values($input, \$submit_button);
    dispatch_shoplist($submit_button);
}


sub dispatch_shoplist {
    my ($submit_button) = @_;

    if ($submit_button eq 'order') {
	my $msg = validate_fields();
	if ($msg ne '') {
	    $Vend::Message = $msg;
            display_page(Shopping_list_page);
	}
        else {
	    process_order();
            @{Shoplist()} = ();
	}
    }
    elsif ($submit_button eq 'return') {
	display_page(Default_page);
    }
    elsif ($submit_button eq 'refresh') {
        display_page(Shopping_list_page);
    }
    elsif ($submit_button eq 'cancel'){
        @{Shoplist()} = ();
	display_page(Default_page);
    }
    else {
	interaction_error("Submit value '$submit_button' not recognized\n");
    }
}


sub order_values {
    my ($input, $submitted) = @_;

    save_field_values($input,
                      qw(in_state phone name email addr town state zip
                         country payby));

    form_fields($input,[['submit', $submitted,
                         ['submit', 'refresh'],
                         ['submit', 'order'],
                         ['submit', 'return']]]);
}

sub validate_fields {
    my @m = ();
    my $msg = '';

    @m = ();

    if (blank(Value('name'))) { push @m, "your name" }
    my $done_addr = 0;
    if (blank(Value('addr'))) {
        push @m, "your shipping address";
        $done_addr = 1;
    }
    if (!$done_addr and blank(Value('town'))) {
        push @m, "your town in the shipping address";
        $done_addr = 1;
    }
    if (!$done_addr and blank(Value('state'))) {
        push @m, "your state or province in the shipping address";
        $done_addr = 1;
    }
    if (!$done_addr and blank(Value('zip'))) {
        push @m, "your zip or postal code in the shipping address";
        $done_addr = 1;
    }
    if (blank(Value('payby'))) {
        push @m, "your preferred payment method";
    }
    if (@m) {
        $msg = "<strong><em>Please enter " . combine(@m) . " on this order form.</em></strong><p>\n";
    }
    $msg;
}

sub order_sheet {
    my ($order_number) = @_;

    my $date = localtime();
    my $session = session_id();
    my $v = Value();

    my $sheet = <<"END";
  Order date: $date
Order number: $order_number

            Name: $v->{name}

Shipping address: $v->{addr}
Town, State, Zip: $v->{town}, $v->{state}, $v->{zip}
         Country: $v->{country}

          Pay By: $v->{payby}
END

    my $total_width = 79;
    my $quantity_width = 3;
    my $item_width = 8;
    my $price_width = 8;
    my $description_width = $total_width - $quantity_width - 1
        - $item_width - 1 - $price_width - 1 - $price_width - 1;

    my $widths = [$quantity_width, $item_width, $description_width, $price_width,
                  $price_width];
    $sheet .= fill_table($widths,
                         [qw(| | | | |)],
                         ['Q', 'Product', 'Description', 'Price Per',
                           'Amount'],
                         '',
                         ' ',
                         "\n",
                         1);

    $sheet .= "-" x $quantity_width . " " . "-" x $item_width . " "
             . "-" x $description_width . " " . "-" x $price_width . " "
             . "-" x $price_width . "\n";       

    my $aligns = [qw(> < < > >)];
    my $line;

    my $sl = Shoplist();
    my ($i, $item, $code, $quantity, $desc, $price, $amount);
    my $subtotal = 0;
    for $i (0 .. $#$sl) {
        $item = $sl->[$i];
	$code = $item->{code};
	$quantity = $item->{quantity};
        $desc = product_description($code);
	$price = product_price($code);
        $amount = cent_round($quantity * $price);
        $subtotal += $amount;
        $line = [$quantity, $code, $desc, currency($price), currency($amount)];
        $sheet .= fill_table($widths, $aligns, $line, '', ' ', "\n", 0);
    }
    $subtotal = cent_round($subtotal);

    $sheet .= '-' x $total_width . "\n";
    $sheet .= fill_table([$total_width - $price_width - 1, $price_width],
                         ['>', '>'],
                         ['Subtotal:', currency($subtotal)],
                         '', ' ', "\n", 0);

    return $sheet;
}


sub process_order {
    my $order_number = order_number();
    my $sheet = order_sheet($order_number);
    send_mail(Mail_order_to, App . " Order $order_number", $sheet);
    display_page("confirm");
}

define_placeholder '[add-url $product]',  \&add_url_ph;
define_placeholder '[currency $x]', \&currency;
define_placeholder '[in-state-checkbox]', \&in_state_checkbox_ph;
define_placeholder '[ordered-items]', \&ordered_items_ph;
define_placeholder '[product-field $p $f]', \&product_field_ph;
define_placeholder '[product-price $p]', \&product_price;
define_placeholder '[product-description $p]', \&product_description;
define_placeholder '[shopping-list-link]', \&shopping_list_link_ph;

specify_action "add", \&handle_add;
specify_form "hlist", \&handle_shoplist;

1;
