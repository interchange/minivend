package Catalog;
my $My_class = 'Catalog';
require Vend::Catalog;
@ISA = qw(Vend::Catalog);

use strict;
use Vend::Directive qw(App_directory);
use Vend::Dispatch;
use Vend::Form;
use Vend::Orders;
use Vend::Page;
use Vend::Session;
use Vend::Util;

my $Table_class = 'Vend::Table::InMemory';
use Vend::Table::Import;
require Vend::Table::InMemory;

my ($Products, $Product_price, $Product_description);

sub init {
    my $fn = App_directory . "/products";
    my $delimiter = "|";
    my $Table_class = $Table_class; # make available to closure
    my $create = sub {
        my (@columns) = @_;
        return $Table_class->create_table([@columns]);
    };
    $Products = import_ascii_delimited($fn, $delimiter, $create);
    $My_class->create_table_placeholders("product", $Products);
    $Product_price = $Products->field_accessor("price");
    $Product_description = $Products->field_accessor("description");
}

sub shipping_cost {
    my ($class) = @_;
    return 5.00;
}

sub item_price {
    my ($class, $item) = @_;
    return &$Product_price($item);
}

sub item_description {
    my ($class, $item) = @_;
    return &$Product_description($item);
}

sub item_exists {
    my ($class, $item) = @_;
    return $Products->record_exists($item);
}


# quanitites: hash ref
# submitted: scalar ref

sub order_values {
    my ($class, $input, $quantities, $submitted) = @_;

    my ($name, $email, $phone, $addr, $town, $state, $zip, $country, $payby);
    form_fields($input,
               [['dotted', $quantities, 'q'],
                ['value', \$phone, 'phone'],
                ['value', \$name, 'name'],
                ['value', \$email, 'email'],
                ['value', \$addr, 'addr'],
                ['value', \$town, 'town'],
                ['value', \$state, 'state'],
                ['value', \$zip, 'zip'],
                ['value', \$country, 'country'],
                ['value', \$payby, 'payby'],

                ['submit', $submitted,
                 ['submit', 'refresh'],
                 ['submit', 'order'],
                 ['submit', 'return']]
                ]);

    Value->{'name'} = $name;
    Value->{'email'} = $email;
    Value->{'phone'} = $phone;
    Value->{'addr'} = $addr;
    Value->{'town'} = $town;
    Value->{'state'} = $state;
    Value->{'zip'} = $zip;
    Value->{'country'} = $country;
    Value->{'payby'} = $payby;
}

sub validate_fields {
    my ($class) = @_;
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

sub process_order {
    my ($class, $items) = @_;
    Vend::Orders->mail_order($class, $items);
}

##

define_placeholder '[currency $x]',         sub { $My_class->currency(@_) };
define_placeholder '[shipping]',            sub { $My_class->shipping(@_) };
define_placeholder '[order-url $product]',  sub { $My_class->order_url(@_) };
define_placeholder '[nitems]',              sub { $My_class->nitems(@_) };
define_placeholder '[ordered-items]',       sub { $My_class->ordered_items(@_) };
define_placeholder '[item-quantity $code]', sub { $My_class->item_quantity(@_) };
define_placeholder '[quantity-name $code]', sub { $My_class->quantity_name(@_) };
define_placeholder '[shopping-list-link]',
    sub { $My_class->shopping_list_link(@_) };
define_placeholder '[total-cost]',
    sub { $My_class->currency($My_class->total_cost()) };
specify_action 'order',  sub { $My_class->action_order(@_) };
specify_form "flist",    sub { $My_class->process_flist(@_) };

1;
