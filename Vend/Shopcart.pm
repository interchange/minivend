# Shopcart.pm: utility functions for the shopping cart
#
# $Id: Shopcart.pm,v 1.1 1996/01/30 23:09:24 amw Exp $
#
package Vend::Shopcart;

# Copyright 1996 by Andrew M. Wilcox <awilcox@maine.com>
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
@EXPORT_OK = qw(Shoplist cent_round currency create_table_placeholders
                order_number option_list option_list_selected
                get_field get_required_field add_url_ph shoplist_index_of
                save_field_values);

use strict;
use Vend::Directive qw(Data_directory);
use Vend::Dispatch;
use Vend::lock;
use Vend::Page;
use Vend::Session;

=head2 C<Shoplist()>

Returns the array ref for the shopping list from the session.

=cut

sub Shoplist {
    return \@{Session->{'shoplist'}};
}


=head2 C<cent_round($amount)>

Returns the passed amount rounded to the nearest cent.

=cut

sub cent_round {
    my ($p) = @_;
    return int(100.0 * $p + 0.5) / 100.0;
}


=head2 C<currency($amount)

Returns the passed amount formatted as currency, including the dollar
sign.

=cut

sub currency {
    my ($p) = @_;
    return sprintf('$%.2f', $p);
}


=head2 C<create_table_placeholders($name, $table, $na)>

Create placeholders to access table field values.  $name contains the
name for the table, and $table contains the table object.  For each
field in the table, this method creates a placeholder
[NAME-FIELD $key] which returns the field value.  $na is the value
to return if the key is not present.

=cut

sub create_table_placeholders {
    my ($name, $table, $na) = @_;

    my $column;
    foreach $column ($table->columns()) {
        my $ph = "[$name-$column \$key]";
        my $sub = table_field_accessor($table, $column, $na);
        define_placeholder $ph, $sub;
    }
}


=head2 C<table_field_accessor($table, $field_name, $na)>

This method is called by create_table_placeholders() for each field in
the table.  It returns a code ref which will return the field value.

=cut

sub table_field_accessor {
    my ($table, $field_name, $na) = @_;
    my $field_accessor = $table->field_accessor($field_name);

    return sub {
        my ($product_code) = @_;
        return $na unless defined $product_code;
        return &$field_accessor($product_code)
            if $table->record_exists($product_code);
        return $na;
    };
}

sub syserr {
    my ($action, $fn) = @_;

    die "Couldn't $action '$fn':\n$!\n";
}


=head2 C<order_number()>

Returns a unique order sequence integer.

=cut

sub order_number {
    my ($seq);
    my $fn = Data_directory . "/sequence";
    no strict 'subs';

    open(SEQ, "+>>$fn") or syserr 'open order sequence file', $fn;
    lockfile(\*SEQ);
    seek(SEQ, 0, 0) or syserr 'seek', $fn;
    $seq = <SEQ>;
    if (defined $seq) {
        chomp($seq);
        ++$seq;
    }
    else {
        $seq = 1;
    }
    seek(SEQ, 0, 0) or syserr 'seek', $fn;
    truncate(SEQ, 0) or syserr 'truncate', $fn;
    print SEQ "$seq\n" or syserr 'write to', $fn;
    unlockfile(\*SEQ);
    close(SEQ) or syserr 'close', $fn;
    $seq;
}


=head2 C<add_url_ph($product_code)>

Returns an url to add the product $product_code to the shopping list.

=cut

sub add_url_ph {
    my ($product_code) = @_;
    return vend_url('add', {product => $product_code});
}

=head2 C<shopcart_index_of($product_code)>

Returns the index of the product on the shopping list, or undef if the
product is not on the shopping list.

=cut

sub shoplist_index_of {
    my ($product_code) = @_;
    my $sl = Shoplist();
    my $found = undef;
    my $i;
    foreach $i (0 .. $#$sl) {
        $found = $i, last if ($sl->[$i]{'code'} eq $product_code);
    }
    return $found;
}


=head2 C<option_list(@options)>

Returns a string of option values for use with a <select> tag.  For
example, if passed ('A', 'B'), will return:

    <option value="A">A<option value="B">B

=cut

sub option_list {
    return join('', map('<option value="'. $_ . '">' . $_, @_));
}


=head2 C<option_list_selected($selected_option, @options)>

Returns an option list for use with the <select> tag, with one value
selected.

=cut

sub option_list_selected {
    my ($selected, @options) = @_;

    return join('',
                map(qq(<option value="$_") .
                      ($_ eq $selected ? ' selected' : '') .
                      '>' . $_,
                    @options));
}


=head2 C<get_field($input, $field_name)>

Returns the value of the $field_name from the form $input.  Returns
undef if the field was not passed in from the form.

=cut

sub get_field {
    my ($input, $field_name) = @_;

    my $value_list = $input->{$field_name};
    return undef unless defined $value_list;
    report_error("More than one value passed for form variable '$field_name'")
        if (@$value_list > 1);
    return $value_list->[0];
}


sub save_field_values {
    my ($input, @field_names) = @_;
    my ($field_name, $v);

    foreach $field_name (@field_names) {
        $v = get_field($input, $field_name);
        Value->{$field_name} = (defined $v ? $v : '');
    }
}


=head2 C<get_required_field($input, $field_name)>

Returns the value of the $field_name from the form $input.  Raises
an error if the field was not passed in from the form.

=cut


sub get_required_field {
    my ($input, $field_name) = @_;
    my $value = get_field($input, $field_name);
    interaction_error("Missing form field '$field_name'")
        unless defined $value;
    return $value;
}

1;
