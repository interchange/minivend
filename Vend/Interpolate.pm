# Interpolate.pm - Interpret MiniVend tags
# 
# $Id: Interpolate.pm,v 1.3 1996/05/18 20:02:39 mike Exp mike $
#
# Copyright 1996 by Michael J. Heins <mikeh@iac.net>
#
# $Log: Interpolate.pm,v $
# Revision 1.3  1996/05/18 20:02:39  mike
# Minivend 1.03 Beta 1
#
# Revision 1.2  1996/05/09 18:54:52  mike
# Initial integration of Search::Glimpse
#
# Revision 1.1  1996/05/08 22:10:15  mike
# Initial revision
#
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

package Vend::Interpolate;
require Exporter;
@ISA = qw(Exporter);

$VERSION = substr(q$Revision: 1.3 $, 10);

@EXPORT = qw (

interpolate_html
order_page
search_page
fly_page
shipping
custom_shipping
salestax
subtotal
tag_if
taxable_amount

);

use Carp;
use strict;
use Vend::Util;
use Vend::Data;
use Vend::Server;
use Vend::ValidCC;

sub tag_accessories {
	my($code) = @_;

	if(! defined $Vend::Accessories{'default'}) {
		if ( ! read_accessories() ) {
			logError("Accessory list failed, no accessories file, returning empty");
			return '';
		}
	}
	if(defined $Vend::Accessories{$code}) {
		return $Vend::Accessories{$code};
	}
	else {
		return $Vend::Accessories{'default'};
	}
}

# Returns 'CHECKED' when a value is present on the form
# Must match exactly, but NOT case-sensitive
# Defaults to 'on' for checkboxes
# Silently returns null string if illegal regex

sub tag_checked {
	my $field = shift;
	my $value = shift || 'on';
	my $r;

	#eval {/^$value$/} ;
	#return '' if $@;

	if($Vend::Session->{'values'}->{"\L$field"} =~ /^$value$/i) {
		$r = 'CHECKED';
	}
	else {$r = ''}
	$r;
}

# Returns 'SELECTED' when a value is present on the form
# Must match exactly, but NOT case-sensitive
# Silently returns null string if illegal regex

sub tag_selected {
	my $field = shift;
	my $value = shift || '';
	my $r;

	#eval {/^$value$/} ;
	#return '' if ( $@ or ! $value);

	if($Vend::Session->{'values'}->{$field} =~ /^$value$/i) {
		$r = 'SELECTED';
	}
	else {$r = ''}
	$r;
}


# Returns either a href to finish the ordering process (if at least
# one item has been ordered), or an empty string.
# If a secure order has been started (with a forms submission)
# then it will be given the secure URL

sub tag_finish_order {
	my($page) = shift;
    my($finish_order);

	return '' unless @$Vend::Items;

	unless (defined $page) {
		if ( $Vend::Session->{'scratch'}->{'mv_checkout'} ||= 0) {
			$page = $Vend::Session->{'scratch'}->{'mv_checkout'};
		}
		else { $page = $Config::CheckoutPage; }
	}

	if ($Vend::Session->{'secure'}) {
		$finish_order = '<a href="' . secure_vendUrl($page);
	}
	else {
		$finish_order = '<a href="' . vendUrl($page);
	}
	
	$finish_order .= '" TARGET="' . $Config::CheckoutFrame
			if $Vend::Session->{'frames'};

	$finish_order .= '">' . $Config::FinishOrder . "</a><p>";

}

# Returns an href to place an order for the product PRODUCT_CODE.
# If a secure order has been started (with a call to at least
# one secure_vendUrl), then it will be given the secure URL
# CUSTOM FOR BYTEDESIGN: If the page is passed, then it will
# be appended, preceded by '__', so proper page is tagged

sub tag_order {
    my($product_code,$page) = @_;
	my($r);

	unless(defined $page) {
		$page = 'order';
	}

	if ($Vend::Session->{'secure'}) {
    	$r  = '<a href="' . secure_vendUrl($page, $product_code);
	}
	else {
    	$r  = '<a href="' . vendUrl($page, $product_code);
	}
	$r .= '" TARGET="' . $Config::OrderFrame
		if $Vend::Session->{'frames'};
	$r .= '">';
}

# Returns a body tag with a user-entered, a set color scheme, or the default
sub tag_body {
    my($scheme) = @_;
	my $r = '<BODY';
	my ($var,$tag);
	#return '<BODY>' unless (int($scheme) < 16 and int($scheme) > 1);

	my %color = qw( mv_bgcolor BGCOLOR mv_textcolor TEXT
					mv_linkcolor LINK mv_vlinkcolor VLINK
					mv_background BACKGROUND );
	if (defined $Vend::Session->{'values'}->{mv_resetcolors}
			and $Vend::Session->{'values'}->{mv_resetcolors}) {
		delete $Vend::Session->{'values'}->{mv_customcolors};
		undef $Vend::Session->{'values'}->{mv_resetcolors};
	}
	if (defined $Vend::Session->{'values'}->{mv_customcolors}) {
		foreach $var (keys %color) {
			$r .= qq| $color{$var}="| . $Vend::Session->{'values'}->{$var} . '"'
				if $Vend::Session->{'values'}->{$var};
		}
	}
	else {
		foreach $var (keys %color) {
			$r .= qq| $color{$var}="| . ${Config::Color->{$var}}[$scheme] . '"'
				if defined ${Config::Color->{$var}}[$scheme]
					&&  ${Config::Color->{$var}}[$scheme] !~ /\bnone\b/;
		}
	}
	$r .= '>';
}

# Sets the value of a scratchpad field
sub set_scratch {
	my($var,$val) = @_;
    $Vend::Session->{'scratch'}->{$var} = $val;
	'';
}

# Returns the value of a scratchpad field named VAR.
sub tag_scratch {
    my($var) = @_;
    my($value);

    if (defined ($value = $Vend::Session->{'scratch'}->{$var})) {
		return $value;
    }
	else {
		return "";
    }
}

# Returns the text of a configurable database field or a 
# variable
sub tag_data {
	my($selector,$field,$key) = @_;
	if(defined $Vend::Database{$selector}) {
		my $db = $Vend::Database{$selector};
		return database_field($db,$key,$field);
	}
	elsif($selector eq 'session') {
		return (! defined $Vend::Session->{$field}
			? '' :  $Vend::Session->{$field} );
	}
	elsif($selector eq 'config') {
		no strict 'refs';
		return (! defined ${'Config::' . $field}
			? 'BAD CONFIG TERM' :  ${'Config::' . $field} );
	}
	elsif($selector eq 'scratch') {
		return (! defined $Vend::Session->{'scratch'}->{$field}
				? '' :  $Vend::Session->{'scratch'}->{$field});
	}
	elsif($selector =~ /^value/) {
		return (! defined $Vend::Session->{'values'}->{$field}
				? '' :  $Vend::Session->{'values'}->{$field} );
	}
	elsif($selector =~ /^salestax/) {
		return (! defined $Vend::SalesTax{$field}
				? '' :  $Vend::SalesTax{$field} );
	}
	else {
		return ("Bad data '$selector' '$field' '$key'");
	}
}

# Returns the text of a user entered field named VAR.
sub tag_value {
    my($var) = @_;
    my($value);

    if (defined ($value = $Vend::Session->{'values'}->{$var})) {
	return $value;
    } else {
	return "";
    }
}

# Returns an href which will call up the specified PAGE.

sub tag_page {
    my($page) = @_;

    '<a href="' . vendUrl($page) . '">';
}

# Returns an href which will call up the specified PAGE with TARGET reference.
# If target ends with '__secure', will call the SecureURL

sub tag_pagetarget {
    my($page,$target) = @_;
    my($r);
	unless ($target =~ s/__secure$//i) {
    	$r  = '<a href="' . vendUrl($page);
	}
	else {
    	$r  = '<a href="' . secure_vendUrl($page);
	}
    $r .= '" TARGET="' . $target
        if $Vend::Session->{'frames'};
    $r .= '">';
}

# Returns an href which will call up the specified PAGE.

sub tag_area {
    my($area) = @_;

    vendUrl($area);
}

# Returns an href which will call up the specified PAGE with TARGET reference.

sub tag_areatarget {
    my($area,$target) = @_;
	my($r);
    $r  = vendUrl($area);
	$r .= '" TARGET="' . $target
		if $Vend::Session->{'frames'};
	$r;
}

# Sets the frames feature to on, returns empty string
sub tag_frames_on {
    $Vend::Session->{'frames'} = 1;
	return '';
}

# Sets the frames feature to on, returns empty string
sub tag_frames_off {
    $Vend::Session->{'frames'} = 0;
	return '';
}

# Sets the frame base, can't coexist with other base tags
sub tag_frame_base {
	my($baseframe) = shift;
    if ($Vend::Session->{'frames'}) {
		'<BASE TARGET="' . $baseframe .'">';
	}
	else {
		return '';
	}
}

# Returns a random message or image
sub tag_random {
	my $random = int rand(scalar(@Config::Random));
    if (defined $Config::Random[$random]) {
		return $Config::Random[$random];
	}
	else {
		return '';
	}
}

# Returns a help item by name, if it exists
sub tag_help {
	my($help) = shift;
	# Move this to control section?
	if (defined $Vend::Session->{'values'}->{mv_helpon}
			and $Vend::Session->{'values'}->{mv_helpon}) {
		delete $Vend::Session->{'values'}->{mv_helpoff};
		undef $Vend::Session->{'values'}->{mv_helpon};
	}
	return '' if defined $Vend::Session->{'values'}->{'mv_helpoff'};
    if (defined $Config::Help{$help}) {
		return $Config::Help{$help};
	}
	else {
		return '';
	}
}

# Returns a buttonbar by number
sub tag_buttonbar {
	my($buttonbar) = shift;
    if (defined $Config::ButtonBar[$buttonbar]) {
		return $Config::ButtonBar[$buttonbar];
	}
	else {
		return '';
	}
}

# Returns an href to call up the last page visited.

sub tag_last_page {
    tag_page($Vend::Session->{'page'});
}

# Returns the shipping charges.

sub tag_shipping_desc {
	my $mode = 	shift ||
				$Vend::Session->{'values'}->{'mv_shipmode'} ||
				'default';
	return '' unless defined $Vend::Shipping_desc{$mode};
	$Vend::Shipping_desc{$mode};
}

# Returns the shipping charges.

sub tag_shipping {
	my $mode = @_;
    currency(shipping($mode));
}

# Returns the total cost of items ordered.

sub tag_total_cost {
    my($total, $i);
	my $shipping = shipping();

    $total = subtotal();

    $total += $shipping;
    $total += salestax();
    currency($total);
}

# Returns the href to process the completed order form or do the search.

sub tag_process_target {
	my($frame,$security) = @_;
	my $frametag = '';

	if($Vend::Session->{'frames'}) {
    	$frametag = '" TARGET="'. $frame;
	}

	if ("\L$security" eq 'secure') {
    	secure_vendUrl('process') . $frametag;
	}
	else {
    	vendUrl('process') . $frametag;
	}
}

sub tag_process_search {
	if($Vend::Session->{'frames'}) {
    	vendUrl('process') . '" TARGET="'. $Config::SearchFrame;
	}
	else {
    	vendUrl('process');
	}
}

sub tag_process_order {
	my $frametag = '';

	if($Vend::Session->{'frames'}) {
    	$frametag = '" TARGET="_self' ;
	}

	if ($Vend::Session->{'secure'}) {
    	secure_vendUrl('process') . $frametag;
	}
	else {
    	vendUrl('process') . $frametag;
	}
}

sub tag_if {
	my($cond,$body) = @_;
	my($base, $term, $op, $operator, $comp, $else);
	my $status = 0;
	
	if ($body =~ s#\[else\]([\s\S]*?)\[/else\]##ige) {
		$else = $1;
	}
	else { $else = '' }

	($base, $term, $operator, $comp) = split /\s+/, $cond, 4;

	unless(defined $operator) {
		$operator = '';
		$comp = '';
	}
	die qq%"Bad [if $cond]"], died%
		unless (defined $term or $cond eq 'validcc');

	$base = lc $base;

	if($base eq 'session') {
		$op =	qq%\$Vend::Session->{$term}%;
		$op .=	qq%	$operator $comp%
				if $comp;
		eval { $status = eval $op };
		die qq%"Bad [if $cond]"], died%
			if $@;
	}
	elsif($base eq 'scratch') {
		$op =	qq%\$Vend::Session->{'scratch'}->{$term}%;
		$op .=	qq%	$operator $comp%
				if $comp;
		eval { $status = eval $op };
		die qq%"Bad [if $cond]"], died%
			if $@;
	}
	elsif($base =~ /^value/) {
		$op =	qq%\$Vend::Session->{'values'}->{$term}%;
		$op .=	qq%	$operator $comp%
				if $comp;
		eval { $status = eval $op};
		die qq%"Bad [if $cond]"], died%
			if $@;
	}
	elsif($base eq 'file') {
		$op =~ s/[^rwxezfdTsB]//g;
		$op = substr($op,0,1) || 'f';
		$op = qq|-$op "$term"|;
		eval { $status = eval $op };
		die qq%"Bad [if $cond]"], died%
			if $@;
	}
	elsif($base eq 'validcc') {
		no strict 'refs';
		$status = ValidCreditCard($term, $operator, $comp);
	}
    elsif($base eq 'config') {
        no strict 'refs';
        eval { $status = eval "${'Config::' . $term} $op $comp"};
        die qq%"Bad [if $cond]"], died%
            if $@;
    }
	elsif($base =~ /^pric/) {
		$op = qq%\$Vend::Pricing{$term}%;
		$op .=	qq%	$operator $comp%
				if $comp;
		eval { $status = eval $op};
		die qq%"Bad [if $cond]"], died%
			if $@;
	}
	elsif($base =~ /^accessor/) {
		$op = qq%\$Vend::Accessories{$term}%;
		$op .=	qq%	$operator $comp%
				if $comp;
		eval { $status = eval $op};
		die qq%"Bad [if $cond]"], died%
			if $@;
	}
	elsif($base =~ /^salestax/) {
		$op = qq%\$Vend::SalesTax{$term}%;
		$op .=	qq%	$operator $comp%
				if $comp;
		eval { $status = eval $op};
		die qq%"Bad [if $cond]"], died%
			if $@;
	}
	elsif($base =~ /^ship/) {
		$op = qq%\$Vend::Shipping_desc{$term}%;
		$op .=	qq%	$operator $comp%
				if $comp;
		eval { $status = eval $op};
		die qq%"Bad [if $cond]"], died%
			if $@;
	}
	else {
		die qq%"Bad [if $cond]"], died%;
	}
		
	$status ? interpolate_html($body) : interpolate_html($else);
}

	
	
sub tag_secure_order {
	my $r = '';
	my $message = $Config::SecureOrderMsg;
	my $target = '';

	$target = '" TARGET="' . $Config::OrderFrame
		if $Vend::Session->{'frames'};

	unless($Vend::Session->{'secure'}) {
		$r = 	'<A HREF="' .
				secure_vendUrl('account') . $target .
				'">' . $message . '</A>';
	}

	$r;

}

# Evaluates the [...] tags.

sub interpolate_html {
    my($html) = @_;
    my($codere) = '[\w-_#/.]+';
    my($coderex) = '[\w-_:#=/.]+';

    $html =~ s:\[(\[[\s\S]*?\])\]:interpolate_html($1):ige;
    $html =~ s:\[value\s+($codere)\]:tag_value($1):igeo;
    $html =~ s:\[scratch\s+($codere)\]:tag_scratch($1):igeo;
	$html =~ s#\[if\s+([^\]]+)\]([\s\S]*?)\[/if\]#
				  tag_if($1,$2)#ige;
	$html =~ s#\[set\s+([A-za-z_0-9]+)\]([\s\S]*?)\[/set\]#
				  set_scratch($1,$2)#ige;
	$html =~ s:\[file\s+($codere)\]:readfile($1):igeo;

    $html =~ s:\[finish[-_]order(\s+)?($codere)?\]:tag_finish_order($2):igeo;

    $html =~ s:\[frames[-_]on\]:tag_frames_on():ige;
    $html =~ s:\[frames[-_]off\]:tag_frames_off():ige;

    $html =~ s:\[secure[-_]order\]:tag_secure_order():ige;
    $html =~ s:\[framebase\s+($codere)\]:tag_frame_base($1):igeo;
    $html =~ s:\[body\s+($codere)\]:tag_body($1):igoe;
    $html =~ s:\[help\s+($codere)\]:tag_help($1):igoe;
    $html =~ s:\[buttonbar\s+($codere)\]:tag_buttonbar($1):igoe;
    $html =~ s:\[random\]:tag_random():ige;

	$html =~ s:\[checked\s+($codere)(\s+)?($codere)?\]:tag_checked($1,$3):igeo;
	$html =~ s:\[selected\s+($codere)\s+($codere)\]:tag_selected($1,$2):igeo;

    $html =~ s:\[item[-_]list\]([\000-\377]*?)\[/item[-_]list\]:
              tag_item_list($1):ige;

    $html =~ s:\[pagetarget\s+($coderex)\s+($codere)\]:tag_pagetarget($1,$2):igeo;
    $html =~ s:\[/pagetarget\]:</a>:ig;

    $html =~ s:\[area\s+($coderex)\]:tag_area($1):igeo;

    $html =~ s:\[areatarget\s+($coderex)\s+($codere)\]:tag_areatarget($1,$2):igeo;

    $html =~ s:\[page\s+($coderex)\]:tag_page($1):igeo;
    $html =~ s:\[/page\]:</a>:ig;

    $html =~ s:\[last[-_]page\]:tag_last_page():ige;
    $html =~ s:\[/last[-_]page\]:</a>:ig;

    $html =~ s:\[order\s+($codere)(\s+)?($codere)?\]:tag_order($1,$3):igeo;
    $html =~ s:\[/order\]:</a>:ig;

    $html =~ s:\[accessories\s+($codere)\]:tag_accessories($1):igeo;
    $html =~ s:\[data\s+($codere)\s+($codere)(\s+)?($codere)?\]:
					tag_data($1,$2,$4):igeo;
    $html =~ s:\[field\s+($codere)\s+($codere)\]:product_field($2,$1):igeo;

    $html =~ s:\[nitems\]:tag_nitems():ige;
    $html =~ s#\[subtotal\]#currency(subtotal())#ige;
    $html =~ s#\[shipping\]#currency(shipping())#ige;
    $html =~ s#\[shipping[-_]desc(ription)?\]#(tag_shipping_desc())#ige;
    $html =~ s#\[salestax\]#currency(salestax())#ige;
    $html =~ s#\[total[-_]cost\]#tag_total_cost()#ige;
    $html =~ s#\[price\s+($codere)\]#currency(product_price($1))#igoe;
    $html =~ s#\[description\s+($codere)\]#
               product_description($1)#igoe;
	$html =~ s:\[row\s+(\d+)\]([\s\S]*?)\[/row\]:tag_row($1,$2):ige;

    $html =~ s#\[process[-_]order\]#tag_process_order()#ige;
    $html =~ s#\[process[-_]search\]#tag_process_search()#ige;
    $html =~ s#\[process[-_]target\s+($codere)(\s+)?($codere)?\]#
				tag_process_target($1,$3)#igoe;
    $html;
}

# Trims the description output for the order and search pages
# Trims from $Config::DescriptionTrim onward
sub trim_desc {
	my($desc) = @_;
	if($Config::DescriptionTrim) {
		$desc =~ s/$Config::DescriptionTrim(.*)//;
	}
	$desc;
}
	

## ORDER PAGE

sub tag_search_list {
    my($text,$obj,$q) = @_;
    my($r, $i, $item, $code, $link);
	my($linkvalue, $run, $count);
    my($codere) = '[\w-_#/.]+';

	# get the number to start the increment from
	$count = $q->global('first_match');

    $r = "";
	$linkvalue = $Config::ItemLinkValue;

    foreach $item (@$obj) {
		chomp($item);
		($code, $link) = split(/\s+/,$item, 2);
		$link = $code if is_yes($Config::UseCode);

		# Uncomment next line to ignore non-database items
		# next unless product_code_exists($code);

		$count++;

	    $run = $text;
	    $run =~ s#\[if[-_]field\s+($codere)\]([\s\S]*?)\[/if([-_]field)?\]#
				  product_field($code,$1) ? $2 : ''#ige;
	    $run =~ s:\[item[-_]increment\]:$count:ig;
	    $run =~ s:\[item[-_]code\]:$code:ig;
	    $run =~ s:\[item[-_]field\s+($codere)\]:product_field($code,$1):ige;
		$run =~ s:\[item[-_]data\s+($codere)\s+($codere)\]:
							tag_data($1,$2,$code):igeo;
	    $run =~ s:\[item[-_]description\]:trim_desc(product_description($code)):ige;
	    $run =~ s#\[item[-_]link\]#"[page $Config::ItemLinkDir$link]"
	  			. $linkvalue . '[/page]'#ige;
	    $run =~ s:\[item[-_]price(\s+)?(\d+)?\]:
					currency(product_price($code,$2)):ige;

	  $r .= $run;
    }
    $r;
}

sub tag_more_list {
	my($r,$q,$target) = @_;
	my($arg,$inc,$last,$m);
	my($adder,$current,$pages);
	my $next_tag = '';
	my $list = '';
	my $first = $q->global('first_match');
	my $mod   = $q->global('search_mod');
	my $chunk = $q->global('match_limit');
	my $total = $q->global('matches');
	my $next = $q->global('next_pointer');

	$target = defined $target 
			? qq|" TARGET="$target|
			: qq|" TARGET="_self|;

	if($chunk >= $total) {
		return '';
	}

	$adder = ($total % $chunk) ? 1 : 0;
	$pages = int($total / $chunk) + $adder;
	$current = int($next / $chunk) || $pages;


	if($first) {
		$arg .= $first - $chunk;
		$arg .= ':';
		$arg .= $first - 1;
 		$arg .= ":$chunk:$mod";
		$list .= '<A HREF="';
		$list .= vendUrl('search', $arg);
		$list .= $target;
		$list .= '">';
		$list .= 'Previous</A>';
	}
	
	if($next) {
		$last = $next + $chunk - 1;
		$last = $last > ($total - 1) ? $total - 1 : $last;
		$arg = "$next:$last:$chunk:$mod";
		$next_tag .= '<A HREF="';
		$next_tag .= vendUrl('search', $arg);
		$next_tag .= $target;
		$next_tag .= '">';
		$next_tag .= 'Next</A>';
	}
	
	foreach $inc (1..$pages) {
		$next = ($inc-1) * $chunk;
		$last = $next + $chunk - 1;
		$last = ($last+1) < $total ? $last : ($total - 1);
		if($inc == $current) {
			$list .= qq|<STRONG>$inc</STRONG> |;
		}
		else {
			$arg = "$next:$last:$chunk:$mod";
			$list .= '<A HREF="';
			$list .= vendUrl('search', $arg);
			$list .= $target;
			$list .= '">';
			$list .= qq|$inc</A> |;
		}
	}

	$list .= $next_tag;

	$first = $first + 1;
	$last = $first + $chunk - 1;
	$last = $last > $total ? $total : $last;
	$m = $first . '-' . $last; 
	$r =~ s/\[more\]/$list/ige;
	$r =~ s/\[matches\]/$m/ige;

	$r;

}

sub tag_column {
	my($spec,$text) = @_;
	my($append,$f,$i,$line,$usable);
	my(%def) = qw(
					width 0
					spacing 1
					gutter 2
					wrap 1
					align left
				);
	my(%spec)	= ();
	my(@out)	= ();
	my(@lines)	= ();
	
	$spec =~ s/\n/\s/g;
	$spec =~ s/^\s+//;
	$spec =~ s/\s+$//;
	$spec = lc $spec;

	$spec =~ s/\s*=\s*/=/;
	$spec =~ s/^(\d+)/width=$1/;
	%spec = split /[\s=]+/, $spec;

	for(keys %def) {
		$spec{$_} = $def{$_} unless defined $spec{$_};
	}

	$text =~ s/^\s+\n?//;
	$text =~ s/\s+\n?$//;
	$text =~ s/\s*\n\s*/ /;

	$usable = $spec{'width'} - $spec{'gutter'};
	return "BAD_WIDTH" if  $usable < 1;
	
	if($spec{'align'} =~ /^l/) {
		$f = sub {
					$_[0] .
					' ' x ($usable - length($_[0])) .
					' ' x $spec{'gutter'};
					};
	}
	elsif($spec{'align'} =~ /^r/) {
		$f = sub {
					' ' x ($usable - length($_[0])) .
					$_[0] .
					' ' x $spec{'gutter'};
					};
	}
	elsif($spec{'align'} =~ /^i/) {
		$spec{'wrap'} = 0;
		$usable = 9999;
		$f = sub { @_ };
	}
	else {
		return "BAD JUSTIFICATION SPECIFICATION: $spec{'align'}";
	}

	$append = '';
	if($spec{'spacing'} > 1) {
		$append .= "\n" x ($spec{'spacing'} - 1);
	}

	if(is_yes($spec{'wrap'}) and length($text) > $usable) {
		@lines = wrap($text,$usable);
		#$Text::Wrap::columns = $usable;
		#$text = Text::Wrap::wrap("",$append,$text);
	}
	elsif($spec{'align'} =~ /^i/) {
		$lines[0] = ' ' x $spec{'width'};
		$lines[1] = $text . ' ' x $spec{'gutter'};
	}
	else {
		$lines[0] = substr($text,0,$usable);
	}

	foreach $line (@lines) {
		push @out , &{$f}($line);
		for($i = 1; $i < $spec{'spacing'}; $i++) {
			push @out, '';
		}
	}
	@out;
}
	
sub tag_row {
    my($width,$text) = @_;
	my($col,$spec);
	my(@lines);
	my(@len);
	my(@out);
	my($i,$j,$k);
	my($x,$y,$line);

	$i = 0;
	while( $text =~ s:	\[col(umn)?\s+
				 		([^\]]+)
				 		\]
				 		([\s\S]*?)
				 		\[/col(umn)?\] ::xi    ) {
		$spec = $2;
		$col = $3;
		$lines[$i] = [];
		@{$lines[$i]} = tag_column($spec,$col);
		# Discover X dimension
		@len[$i] = length(${$lines[$i]}[0]);
		if(${$lines[$i]}[1] =~ /^<\s*input\s+/i) {
			shift @{$lines[$i]};
		}
		$i++;
	}
	my $totlen = 0;
	for(@len) { $totlen += $_ }
	if ($totlen > $width) {
		return " B A D   R O W  S P E C I F I C A T I O N - columns too wide.\n"
	}

	# Discover y dimension
	$j = $#{$lines[0]};
	for ($k = 1; $k < $i; $k++) {
		$j = $#{$lines[$k]} > $j ? $#{$lines[$k]} : $j;
	}

	for($y = 0; $y <= $j; $y++) {
		$line = '';
		for($x = 0; $x < $i; $x++) {
			if(defined ${$lines[$x]}[$y]) {
				$line .= ${$lines[$x]}[$y];
				$line =~ s/\s+$//
					if ($i - $x) == 1;
			}
			elsif (($i - $x) > 1) {
			  	$line  .= ' ' x $len[$x];
			}
			else {
				$line =~ s/\s+$//;
			}
		}
		push @out, $line;
	}
	join "\n", @out;
}

sub tag_item_list {
	my($text) = @_;
	my($r, $i, $item, $price, $link, $code, $quantity, $linkvalue, $run);
	my($codere) = '[\w-_#/.]+';

	$r = "";
	$linkvalue = $Config::ItemLinkValue;
	foreach $i (0 .. $#$Vend::Items) {
		$item = $Vend::Items->[$i];
		$code = $item->{'code'};
		$quantity = $item->{'quantity'};
		$price = product_price($code);

		$run = $text;
		$run =~ s#\[if[-_]field\s+($codere)\]([\s\S]*?)\[/if([-_]field)?\]#
				  product_field($code,$1) ? $2 : ''#ige;
		$run =~ s:\[item[-_]increment\]:$i + 1:ige;
		$run =~ s:\[item[-_]quantity\]:$quantity:ig;
		$run =~ s:\[quantity[-_]name\]:quantity$i:ig;
		$run =~ s:\[item[-_]subtotal\]:currency($price * $quantity):ige;
		$run =~ s:\[item[-_]code\]:$code:ig;
		$run =~ s:\[item[-_]field\s+($codere)\]:product_field($code,$1):ige;
		$run =~ s:\[item[-_]data\s+($codere)\s+($codere)\]:
							tag_data($1,$2,$code):igeo;
		$run =~ s:\[item[-_]description\]:trim_desc(product_description($code)):ige;
		$run =~ s:\[item[-_]accessories\]:tag_accessories($code):ige;
		$run =~ s#\[item[-_]link\]#"[page $Config::ItemLinkDir$code]"
				  . $linkvalue . '[/page]'#ige;
		$run =~ s:\[item[-_]price\]:currency($price):ige;
		$run =~ s:\[item[-_]price\s+(\d+)\]:
					currency(product_price($code,$1)):ige;

		$r .= $run;
	}
	$r;
}

# Displays the order page with the special [search-list] tag evaluated.

sub search_page {

	my($q,$o) = @_;
    my($page);

	if (($page = $q->global('search_page')) ) {
    	$page = readin($page);
	}
	elsif($Config::FrameSearchPage && $Vend::Session->{'frames'}) {
    	$page = readin($Config::FrameSearchPage);
	}
    else {
    	$page = readin($Config::Special{'search'});
	}

    die "Missing special page: $page\n" unless defined $page;
	# passing the list reference here
    $page =~ s:\[search[-_]list\]([\000-\377]*?)\[/search[-_]list\]:
              tag_search_list($1,$o,$q):ige;
    $page =~ s:\[more[-_]list\]([\000-\377]*?)\[/more[-_]list\]:
              tag_more_list($1,$q):ige;
    main::response('html',interpolate_html($page));
}


# Tries to display the on-the-fly page if page is missing
sub fly_page
{
	my($code) = @_;
	$code =~ s:.*/::;
    my($page);
    my($codere) = '[\w-_#/.]+';

	if(is_yes($Config::UseCode) && product_code_exists($code)) {
    	$page = readin($Config::Special{'flypage'});
	}

    return undef unless defined $page;
	$page =~ s#\[if[-_]field\s+($codere)\]([\s\S]*?)\[/if([-_]field)?\]#
				  product_field($code,$1) ? $2 : ''#ige;
    $page =~ s!\[item[-_]code\]!$code!ig;
    $page =~ s!\[item[-_]description\]!product_description($code)!ige;
    $page =~ s!\[item[-_]price\]!product_price($code)!ige;
	$page =~ s:\[item[-_]price\s+(\d+)\]:
					currency(product_price($code,$1)):ige;
	$page =~ s:\[item[-_]field\s+($codere)\]:product_field($code,$1):ige;
	$page =~ s:\[item[-_]data\s+($codere)\s+($codere)\]:
							tag_data($1,$2,$code):igeo;

    interpolate_html($page);
}

sub order_page
{
    my($which) = @_;
    my($page);

	$which = $Config::Special{'order'} unless defined $which;

	if($which eq $Config::Special{'order'} and
	   $Config::FrameOrderPage and
	   $Vend::Session->{'frames'}) {
    	$page = readin($Config::FrameOrderPage);
	}
    else {
    	$page = readin($which);
	}

    die "Missing special page: $which\n" unless defined $page;
    main::response('html',interpolate_html($page));
}

sub shipping {
	if($Config::CustomShipping) {
		custom_shipping();
	}
	else { $Config::Shipping; }
}

sub custom_shipping {
	my($mode) = $Vend::Session->{'values'}->{'mv_shipmode'} || 'default';
	my($field) = $Config::CustomShipping;
	my($code, $i, $total, $cost, $multiplier, $formula);

	if(! defined $mode) {
		logError("Custom shipping called with no mode, returning 0");
		return 0;
	}
	else {
		eval {/$mode/; 1;};
		if ($@) {
			logError("Bad shipping mode '$mode', returning 0");
			return 0;
		}
	}
			
	if(! defined $Vend::Shipping_cost{'default'}) {
		if ( ! read_shipping() ) {
			logError("Custom shipping called, no shipping file, returning 0");
			return 0;
		}
	}

	# Uses the quantity on the order form if the field is 'quantity',
	# otherwise goes to the database.
    $total = 0;
	if($field eq 'quantity') {
    	foreach $i (0 .. $#$Vend::Items) {
			$total = $total + $Vend::Items->[$i]->{$field};
    	}
	}
	else {
		eval { column_exists $field };
		if($@) {
			logError("Custom shipping field '$field' doesn't exist. Returning 0");
			return 0;
		}
    	foreach $i (0 .. $#$Vend::Items) {
			$total += product_field($Vend::Items->[$i]->{'code'}, $field) *
						$Vend::Items->[$i]->{'quantity'};
			
		}
	}
			

	# We will return from this loop if a match is found
	foreach $code (sort keys %Vend::Shipping_cost) {
		next unless $code =~ /^$mode/i;
		if(	$total >= $Vend::Shipping_min{$code} and
			$total <= $Vend::Shipping_max{$code} ) {
			# unless field begins with 'x' or 'f', straight cost is returned
			# - otherwise the quantity is multiplied by the cost or a formula
			# is applied
			if ($Vend::Shipping_cost{$code} =~ /^x\s*/i) {
				$multiplier = $Vend::Shipping_cost{$code};
				$multiplier =~ s/^x\s*//i;
				return $multiplier * $total;
			}
			elsif ($Vend::Shipping_cost{$code} =~ /^\s*f\s*(.*)/i) {
				$formula = $1;
				$formula = interpolate_html($formula);
				$formula =~ s/x/$total/g;
				$cost = eval {$formula};
				if($@) {
					logError("Shipping mode '$mode' has bad formula. Returning 0");
					return 0;
				}
				return eval $formula;
			}
			else {
				return $Vend::Shipping_cost{$code};
			}
		}
	}

	# If we got here, the mode and quantity fit was not found
	logError("Custom shipping: no match found for\n" .
			 "mode '$mode', quantity '$total', returning 0");
	return 0;
}

sub taxable_amount {
    my($taxable, $i);

	return subtotal() unless $Config::NonTaxableField;

    $taxable = 0;

	eval { column_exists($Config::NonTaxableField) };

	if($@) {
		logError("NonTaxableField '$Config::NonTaxableField' doesn't exist!");
		return subtotal();
	}

    foreach $i (0 .. $#$Vend::Items) {
		next if is_yes( product_field(	$Vend::Items->[$i]->{'code'}, 
										$Config::NonTaxableField		));
		$taxable += $Vend::Items->[$i]->{'quantity'} *
	    			product_price($Vend::Items->[$i]->{'code'});
    }

	$taxable;
}

# Calculate the sales tax
sub salestax {
	my($amount) = shift || taxable_amount();
	my($r, $code);
	my(@code) = map { $Vend::Session->{'values'}->{$_} }
					split /\s*,\s*/,$Config::SalesTax;
					

	if(! defined $Vend::SalesTax{'default'}) {
		if ( ! read_salestax() ) {
			logError("Sales tax failed, no tax file, returning 0");
			return 0;
		}
	}

	CHECKSHIPPING: {
		last CHECKSHIPPING unless $Config::TaxShipping;
		foreach $code (@code) {
			next unless defined $Vend::SalesTax{$code};
			next unless $Config::TaxShipping =~ /\b\Q$code\E\b/i;
			$amount += shipping();
			last;
		}
	}

	foreach $code (@code) {
		# Trim the zip+4
		$code =~ s/(\d{5})-\d+/$1/;
		# Make it upper case for state and overseas postal
		# codes, zips don't matter
		$code = uc $code;
		if(defined $Vend::SalesTax{$code}) {
			$r = $amount * $Vend::SalesTax{$code};
			last;
		}
		else {
			$r = $amount * $Vend::SalesTax{'default'};
		}
	}

	$r;
}

# Returns just subtotal of items ordered
sub subtotal {
    my($subtotal, $i);

    $subtotal = 0;
    foreach $i (0 .. $#$Vend::Items) {
    $subtotal += $Vend::Items->[$i]->{'quantity'} *
        product_price($Vend::Items->[$i]->{'code'});
    }

    $subtotal;
}

1;
