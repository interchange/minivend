# Orders.pm:  process a completed order
#
# $Id: Orders.pm,v 1.12 1995/11/28 19:02:37 amw Exp $
#
package Vend::Orders;

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
@EXPORT = qw(mail_order);

use strict;
use Vend::Directive qw(App App_directory Data_directory Mail_order_to);
use Vend::Dispatch;
use Vend::lock;
use Vend::Log;
use Vend::Sendmail;
use Vend::Session;


sub syserr {
    my ($action, $fn) = @_;

    die "Couldn't $action '$fn':\n$!\n";
}


sub order_sequence {
    my ($class) = @_;
    my ($seq);
    my $fn = Data_directory . "/sequence";
    no strict 'subs';

    open(Vend::Orders::SEQ, "+>>$fn") or syserr 'open order sequence file', $fn;
    lockfile(\*Vend::Orders::SEQ);
    seek(Vend::Orders::SEQ, 0, 0) or syserr 'seek', $fn;
    $seq = <Vend::Orders::SEQ>;
    if (defined $seq) {
        chomp($seq);
        ++$seq;
    }
    else {
        $seq = 1;
    }
    seek(Vend::Orders::SEQ, 0, 0) or syserr 'seek', $fn;
    truncate(Vend::Orders::SEQ, 0) or syserr 'truncate', $fn;
    print Vend::Orders::SEQ "$seq\n" or syserr 'write to', $fn;
    unlockfile(\*Vend::Orders::SEQ);
    close(Vend::Orders::SEQ) or syserr 'close', $fn;
    $seq;
}


sub report_field {
    my ($class, $name, $seen, $sequence) = @_;
    my ($value);

    if    ($name =~ m/^date$/i)     { $value = localtime() }
    elsif ($name =~ m/^sequence$/i) { $value = $sequence }
    elsif ($name =~ m/^session$/i)  { $value = session_id() }
    else {
	$value = Value->{$name};
	if (defined $value) {
	    $$seen{$name} = 1;
	} else {
	    $value = "<no input box>";
	}
    }
    $value;
}

sub order_body {
    my ($class, $seen, $sequence) = @_;
    my ($fn, $body);

    $fn = App_directory . "/report";
    if (!open(Vend::Orders::IN, $fn)) {
	report_error("Could not open report file '$fn': $!\n");
	return undef;
    }
    {
	local($/);
	undef $/;
	$body = <Vend::Orders::IN>;
    }
    close(Vend::Orders::IN);

    $body =~ s/\$(\w+)/$class->report_field($1, $seen, $sequence)/ge;

    $body;
}

sub quantity_name     { 'Quantity' }
sub quantity_width    { 3 }
sub item_name         { 'Item' }
sub item_width        { 16 }
sub description_name  { 'Description' }
sub price_name        { 'Price' }
sub pxq_name          { 'PxQ' }
sub price_width       { 8 }
sub total_width       { 78 }

sub center {
    my ($str, $width) = @_;
    my $l = length($str);
    if ($l < $width) {
        $str = " " x (($width - $l)/2) . $str;
        $str = $str . " " x ($width - length($str));
    }
    elsif ($l > $width) {
        $str = substr($str, 0, $width);
    }
    return $str;
}

sub order_list {
    my ($class, $catalog, $items) = @_;
    my ($body, $i, $item, $code, $quantity, $desc, $price);
    my $quantity_width = $class->quantity_width();
    my $item_width = $class->item_width();
    my $price_width = $class->price_width();
    my $description_width = $class->total_width() - $quantity_width - 1
        - $item_width - 1 - $price_width - 1 - $price_width - 1;

    $body = center($class->quantity_name(), $quantity_width) . " "
        . center($class->item_name(), $item_width) . " "
        . center($class->description_name(), $description_width) . " "
        . center($class->price_name(), $price_width) . " "
        . center($class->pxq_name(), $price_width) . "\n"
        . "-" x $quantity_width . " " . "-" x $item_width . " "
        . "-" x $description_width . " " . "-" x $price_width . " "
        . "-" x $price_width . "\n";       

    my $format = '%'.$quantity_width.'s %-'.$item_width.'s '.
        '%-'.$description_width.'s %'.$price_width.'s %'.$price_width."s\n";
    foreach $item (@$items) {
	$code = $item->{code};
	$quantity = $item->{quantity};
        $desc = substr($catalog->item_description($code),
                       0,
                       $description_width);
	$price = $catalog->item_price($code);
	$body .= sprintf($format,
			 $quantity,
			 $code,
			 $desc,
                         $catalog->currency($price),
			 $catalog->currency($quantity * $price) );
    }

    $body;
}

sub order_total {
    my ($class, $catalog) = @_;
    my $t = "\n";
    my $s = $catalog->currency($catalog->shipping_cost());
    $t .= "Shipping: " . $s . "\n" if $s != 0;
    $t .= "   Total: " . $catalog->total_cost() . "\n";
}


# Email the processed order.

sub order_report {
    my ($class, $catalog, $items, $sequence) = @_;
    my ($body, $i, $code, $ok, $seen, $blankline, $key, $value);

    $seen = {};
    $body = $class->order_body($seen, $sequence);
    return undef unless defined $body;

    $blankline = 0;
    while (($key, $value) = each %{Value()}) {
	if (!$$seen{$key}) {
	    if (!$blankline) {
		$body .= "\n";
		$blankline = 1;
	    }
	    $body .= "$key: $value\n" if defined $value;
	}
    }

    $body .= "\n" . $class->order_list($catalog, $items);

    $body .= $class->order_total($catalog);
}

sub mail_order {
    my ($class, $catalog, $items) = @_;
    my $sequence = $class->order_sequence();
    my $report = $class->order_report($catalog, $items, $sequence);
    return undef unless defined $report;
    my $ok = send_mail(Mail_order_to, App." Order $sequence", $report);
    return $ok;
}

1;
