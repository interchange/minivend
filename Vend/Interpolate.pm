# Interpolate.pm - Interpret MiniVend tags
# 
# $Id: Interpolate.pm,v 2.2 1996/09/08 08:27:58 mike Exp mike $
#
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

package Vend::Interpolate;
require Exporter;
@ISA = qw(Exporter);

$VERSION = substr(q$Revision: 2.2 $, 10);

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
tag_value
tag_default
tag_total_cost
tag_lookup
tag_data
taxable_amount

);

use Carp;
use Safe;
use strict;
use Vend::Util;
use Vend::Data;
use Vend::Server;
use Vend::ValidCC;
use Vend::PageBuild;
use Text::ParseWords;

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
	$field = lc $field;
	my $ref = $Vend::Session->{'values'}->{$field};
	$ref = lc $ref;
	
	my $r;

	if( $ref eq "\L$value" ) {
		$r = 'CHECKED';
	}
	else {$r = ''}
	$r;
}

# Returns 'SELECTED' when a value is present on the form
# Must match exactly, but NOT case-sensitive

sub tag_selected {
	my $field = shift;
	my $value = shift || '';
	$field = lc $field;
	my $ref = $Vend::Session->{'values'}->{$field};
	$ref = lc $ref;
	my $r;

	if( $ref eq "\L$value" ) {
		$r = 'SELECTED';
	}
	else {
		$r = ''
	}
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
		else { $page = $Vend::Cfg->{'CheckoutPage'}; }
	}

	if ($Vend::Session->{'secure'}) {
		$finish_order = '<a href="' . secure_vendUrl($page);
	}
	else {
		$finish_order = '<a href="' . vendUrl($page);
	}
	
	$finish_order .= '" TARGET="' . $Vend::Cfg->{'CheckoutFrame'}
			if $Vend::Session->{'frames'};

	$finish_order .= '">' . $Vend::Cfg->{'FinishOrder'} . "</a><p>";

}
# Returns an href to place an order for the product PRODUCT_CODE.
# If AlwaysSecure is set, goes by the page accessed, otherwise 
# if a secure order has been started (with a call to at least
# one secure_vendUrl), then it will be given the secure URL
 
sub tag_order {
    my($product_code,$page) = @_;
    my($r);

    unless(defined $page) {
        $page = 'order';
    }   

    if ($Vend::Cfg->{'AlwaysSecure'}) {
        if (defined $Vend::Cfg->{'AlwaysSecure'}->{$page}) {
            $r  = '<a href="' . secure_vendUrl($page, $product_code);
        }       
        else {
            $r  = '<a href="' . vendUrl($page, $product_code);
        }   
    }
    elsif ($Vend::Session->{'secure'}) {
        $r  = '<a href="' . secure_vendUrl($page, $product_code);
    }
    else {  
        $r  = '<a href="' . vendUrl($page, $product_code);
    }
    
    $r .= '" TARGET="' . $Vend::Cfg->{'OrderFrame'}
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
					 mv_alinkcolor ALINK mv_background BACKGROUND );
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
			$r .= qq| $color{$var}="| . ${$Vend::Cfg->{Color}->{$var}}[$scheme] . '"'
				if defined ${$Vend::Cfg->{Color}->{$var}}[$scheme]
					&&  ${$Vend::Cfg->{Color}->{$var}}[$scheme] !~ /\bnone\b/;
		}
	}
	$r .= '>';
}

# Sets the value of a scratchpad field
sub tag_discount {
	my($code,$value) = @_;
    $Vend::Session->{'discount'}->{$code} = $value;
	delete $Vend::Session->{'discount'}->{$code}
		unless (defined $value and $value);
	'';
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

sub tag_lookup {
	my($selector,$field,$key,$rest) = shellwords($_[0]);
	return $rest if (defined $rest and $rest);
	return tag_data($selector,$field,$key);
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
		return (! defined $Vend::Cfg->{$field}
			? 'BAD CONFIG TERM' : $Vend::Cfg->{$field}  );
	}
	elsif($selector eq 'discount') {
		return (! defined $Vend::Session->{'discount'}->{$field}
				? '' :  $Vend::Session->{'discount'}->{$field});
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
		return (! defined $Vend::Cfg::->{SalesTaxTable}->{$field}
				? '' : $Vend::Cfg::->{SalesTaxTable}->{$field} );
	}
	else {
		logError("Bad data '$selector' '$field' '$key'");
		return '';
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

# Returns the text of a user entered field named VAR.
# Same as tag value except returns 'default' if not present
sub tag_default {
    my($var) = @_;
    my($value);

    if (defined ($value = $Vend::Session->{'values'}->{$var}) and $value) {
	return $value;
    } else {
	return "default";
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
	my $random = int rand(scalar(@{$Vend::Cfg->{'Random'}}));
    if (defined $Vend::Cfg->{'Random'}->[$random]) {
		return $Vend::Cfg->{'Random'}->[$random];
	}
	else {
		return '';
	}
}

# Returns a rotating message or image
sub tag_rotate {
	my $ceiling = defined $Vend::Cfg->{'Rotate'}
				  ? scalar(@{$Vend::Cfg->{'Rotate'}}) - 1
				  : return '';
    my $rotate;
	$rotate = $Vend::Session->{'rotate'} ||= 0;
	if(++$Vend::Session->{'rotate'} > $ceiling) {
		$Vend::Session->{'rotate'} = 0;
	}
	return $Vend::Cfg->{'Rotate'}->[$rotate];
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
    if (defined $Vend::Cfg->{'Help'}->{$help}) {
		return $Vend::Cfg->{'Help'}->{$help};
	}
	else {
		return '';
	}
}

# Returns a buttonbar by number
sub tag_buttonbar {
	my($buttonbar) = shift;
    if (defined $Vend::Cfg->{'ButtonBars'}->[$buttonbar]) {
		return $Vend::Cfg->{'ButtonBars'}->[$buttonbar];
	}
	else {
		return '';
	}
}

# Returns an href to call up the last page visited.

sub tag_last_page {
	my $target;
    my $page = $Vend::Session->{'page'};
    return tag_page($page);
}

# Returns the shipping charges.

sub tag_shipping_desc {
	my $mode = 	shift ||
				$Vend::Session->{'values'}->{'mv_shipmode'} ||
				'default';
	return '' unless defined $Vend::Cfg->{'Shipping_desc'}->{$mode};
	$Vend::Cfg->{'Shipping_desc'}->{$mode};
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
    	vendUrl('process') . '" TARGET="'. $Vend::Cfg->{'SearchFrame'};
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

sub tag_perl {
	my($args,$body) = @_;
	my ($result,$file);
	my(@share);
	
	%Vend::Interpolate::Safe = ();
	@share = split /\s+/, $args;
	my $safe = new Safe;
	for(@share) {
		if( /^value/) {
			$Vend::Interpolate::Safe{'values'} = $Vend::Session->{'values'};
		}
		elsif(/^scratch/) {
			$Vend::Interpolate::Safe{'scratch'} = $Vend::Session->{'scratch'};
		}
		elsif(/^file/) {
			$file = 1;
		}
		elsif(/^discount/) {
			$Vend::Interpolate::Safe{'discount'} = $Vend::Session->{'discount'};
		}
		elsif(/^config/) {
			$Vend::Interpolate::Safe{'config'} = $Vend::Cfg;
		}
		elsif(/^browser/) {
			$Vend::Interpolate::Safe{'browser'} = $Vend::Session->{'browser'};
		}
		elsif(/^frames/) {
			$Vend::Interpolate::Safe{'frames'} = $Vend::Session->{'frames'};
		}
		elsif(/^items/) {
			$Vend::Interpolate::Safe{'items'} = [@{$Vend::Items}];
		}
	}
	$safe->share('%Safe');

	unless(defined $file) {
		$result = $safe->reval($body);
	}
	else {
		$result = $safe->rdo($body);
	}
		
	if ($@) {
		logGlobal("Safe: $@\n");
		return '';
	}
	undef %Vend::Interpolate::Safe;
	return $result;
}

sub tag_calc {
	my($body) = @_;
	my($else);
	my $status = 0;
	my $safe = new Safe;
	
	if ($body =~ s#\[else\]([\s\S]*?)\[/else\]##ige) {
		$else = $1;
	}
	else { $else = '0' }

	$status = $safe->reval($body);
	if ($@) {
		logGlobal("Safe: $@\n");
		return $else;
	}
	return $status ? $status : $else;
}

sub tag_if {
	my($cond,$body) = @_;
	my($base, $term, $op, $operator, $comp, $else);
	my $status = 0;
	my $safe = new Safe;
	
	if ($body =~ s#\[else\]([\s\S]*?)\[/else\]##ige) {
		$else = $1;
	}
	else { $else = '' }

	($base, $term, $operator, $comp) = split /\s+/, $cond, 4;

	unless(defined $operator) {
		$operator = '';
		$comp = '';
	}
	unless (defined $term or $cond eq 'validcc') {
		logError qq%"Bad [if $cond]"] from $Vend::SessionID%;
		return $else;
	}

	$base = lc $base;

	undef $@;
	if($base eq 'session') {
		$op =	qq%"$Vend::Session->{$term}"%;
		$op .=	qq%	$operator $comp%
				if $comp;
	}
	elsif($base eq 'scratch') {
		$op =	qq%"$Vend::Session->{'scratch'}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if $comp;
	}
	elsif($base eq 'explicit') {
		$op =	qq%"$term"%;
		$op .=	qq%	$operator $comp%
				if $comp;
	}
	elsif($base =~ /^value/) {
		$op =	qq%"$Vend::Session->{'values'}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if $comp;
	}
	elsif($base eq 'discount') {
		$op =	qq%"$Vend::Session->{'discount'}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if $comp;
	}
	elsif($base eq 'file') {
		$op =~ s/[^rwxezfdTsB]//g;
		$op = substr($op,0,1) || 'f';
		$op = qq|-$op "$term"|;
		$status = eval {$op};
	}
	elsif($base eq 'validcc') {
		no strict 'refs';
		$status = ValidCreditCard($term, $operator, $comp);
	}
    elsif($base eq 'config') {
		$op = qq%"$Vend::Cfg->{$term}"%;
		$op .=	qq%	$operator $comp%
				if $comp;
    }
	elsif($base =~ /^pric/) {
		$op = qq%"$Vend::Cfg->{'Pricing'}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if $comp;
	}
	elsif($base =~ /^accessor/) {
		$op = qq%"$Vend::Accessories{$term}"%;
		$op .=	qq%	$operator $comp%
				if $comp;
	}
	elsif($base =~ /^salestax/) {
		$op = qq%"$Vend::Cfg::->{SalesTaxTable}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if $comp;
	}
	elsif($base =~ /^ship/) {
		$op = qq%"$Vend::Cfg->{'Shipping_desc'}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if $comp;
	}
	else {
		$@ = "No such comparison available";
	}

	RUNSAFE: {
		#$status = eval "$op"
		$status = $safe->reval($op)
			unless ($@ or $status);
		if ($@) {
			logError qq%"Bad [if $cond]"] from $Vend::SessionID: $@%;
			return $else;
		}
	}
	$status ? interpolate_html($body) : interpolate_html($else);
}

	
	
sub tag_secure_order {
	my $r = '';
	my $message = $Vend::Cfg->{'SecureOrderMsg'};
	my $target = '';

	$target = '" TARGET="' . $Vend::Cfg->{'OrderFrame'}
		if $Vend::Session->{'frames'};

	unless($Vend::Session->{'secure'}) {
		$r = 	'<A HREF="' .
				secure_vendUrl('account') . $target .
				'">' . $message . '</A>';
	}

	$r;

}

sub pull_if {
	my($string) = @_;
	$string =~ s:\[else\]([\S\s]*?)\[/else\]::i;
	return $string;
}

sub pull_else {
	my($string) = @_;
	my($r);
	if($string =~ s:\[else\]([\S\s]*?)\[/else\]::i) {
		$r = $1;
	}
	else {
		$r = '';
	}
	$r;
}

# Evaluates the [...] tags.

sub interpolate_html {
    my($html) = @_;
    my($codere) = '[\w-_#/.]+';
    my($coderex) = '[\w-_:#=/.]+';
    my($codelist) = '[\w-_:,#=/.]+';


    $html =~ s:\[\s*(\d?)\s*(\[[\s\S]*?\])\s*\1\s*\]:interpolate_html($2):ige;
    $html =~ s:\[item[-_]list\]([\000-\377]*?)\[/item[-_]list\]:
              tag_item_list($1):ige;
    $html =~ s:\[loop\s+([^\]]+)\]([\000-\377]*?)\[/loop\]:
              tag_loop_list($1,$2):ige;
    $html =~ s:\[default\s+($codere)\]:tag_default($1):igeo;
    $html =~ s:\[value\s+($codere)\]:tag_value($1):igeo;
    $html =~ s:\[scratch\s+($codere)\]:tag_scratch($1):igeo;
	$html =~ s:\[calc\]([\s\S]*?)\[/calc\]:tag_calc($1):ige;
	$html =~ s#\[if\s+([^\]]+)\]([\s\S]*?)\[/if\]#
				  tag_if($1,$2)#ige;
	$html =~ s#\[lookup\s+([^\]]+)\]#tag_lookup($1)#ige;
	$html =~ s#\[set\s+([A-za-z_0-9]+)\]([\s\S]*?)\[/set\]#
				  set_scratch($1,$2)#ige;
    $html =~ s:\[data\s+($codere)\s+($codere)(\s+)?($codere)?\]:
					tag_data($1,$2,$4):igeo;
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
    $html =~ s:\[rotate\]:tag_rotate():ige;

	$html =~ s:\[checked\s+($codere)(\s+)?($codere)?\]:tag_checked($1,$3):igeo;
	$html =~ s:\[selected\s+($codere)\s+($codere)\]:tag_selected($1,$2):igeo;

    $html =~ s:\[accessories\s+($codere)\]:tag_accessories($1):igeo;
    $html =~ s:\[field\s+($codere)\s+($codere)\]:product_field($2,$1):igeo;
	$html =~ s#\[static\s+($codere)\]([\s\S]*?)\[/static\]#
				  fake_html($2,$1)#ige;

    $html =~ s:\[pagetarget\s+($coderex)\s+($codere)\]:tag_pagetarget($1,$2):igeo;

    $html =~ s:\[area\s+($coderex)\]:tag_area($1):igeo;

    $html =~ s:\[areatarget\s+($coderex)\s+($codere)\]:tag_areatarget($1,$2):igeo;

    $html =~ s:\[page\s+($coderex)\]:tag_page($1):igeo;
    $html =~ s:\[/page(target)?\]:</a>:ig;

    $html =~ s:\[last[-_]page\]:tag_last_page():ige;
	$html =~ s:\[perl(\s+)?([^\]]+)?\]([\s\S]*?)\[/perl\]:tag_perl($2,$3):ige;
    $html =~ s:\[/last[-_]page\]:</a>:ig;

    $html =~ s:\[order\s+($codere)(\s+)?($codere)?\]:tag_order($1,$3):igeo;
    $html =~ s:\[/order\]:</a>:ig;


    $html =~ s:\[nitems\]:tag_nitems():ige;
	$html =~ s#\[discount\s+($codere)\]([\s\S]*?)\[/discount\]#
				  tag_discount($1,$2)#ige;
    $html =~ s#\[subtotal\]#currency(subtotal())#ige;
    $html =~ s#\[shipping\]#currency(shipping())#ige;
    $html =~ s#\[shipping[-_]desc(ription)?\]#tag_shipping_desc()#ige;
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
	$html =~ s#(<i\w+\s+[^>]*?src=")([^/])#$1 . $Vend::Cfg->{ImageDir} . $2#ige
		if $Vend::Cfg->{ImageDir};

	# Abortive try to get server to parse doc
	#$html =~ s&(<!--#)&$Vend::Tag_SSI = 1; $1&ige
	#	if $Vend::Cfg->{AllowSSI};

    $html;
}

# Trims the description output for the order and search pages
# Trims from $Vend::Cfg->{'DescriptionTrim'} onward
sub trim_desc {
	my($desc) = @_;
	if($Vend::Cfg->{'DescriptionTrim'}) {
		$desc =~ s/$Vend::Cfg->{'DescriptionTrim'}(.*)//;
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
	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};
	my $linkdir = $Vend::Cfg->{'ItemLinkDir'};

    foreach $item (@$obj) {
		chomp($item);
		($code, $link) = split(/\s+/,$item, 2);
		$link = $code if is_yes($Vend::Cfg->{'UseCode'});

		# Uncomment next line to ignore non-database items
		# next unless product_code_exists($code);

		$count++;

	    $run = $text;
		$run =~ s#\[if[-_]field\s+($codere)\]([\s\S]*?)\[/if[-_]field\]#
				  product_field($code,$1)	?	pull_if($2)
											:	pull_else($2)#ige;
	    $run =~ s:\[item[-_]increment\]:$count:ig;
	    $run =~ s:\[item[-_]code\]:$code:ig;
	    $run =~ s:\[item[-_]field\s+($codere)\]:product_field($code,$1):ige;
		$run =~ s:\[item[-_]data\s+($codere)\s+($codere)\]:
							tag_data($1,$2,$code):igeo;
	    $run =~ s:\[item[-_]description\]:trim_desc(product_description($code)):ige;
	    $run =~ s#\[item[-_]link\]#"[page $linkdir$link]"
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
	my($text,$args) = @_;
	return tag_loop_list(@_) if defined $args;
	my($r, $i, $item, $modifier, $price, $link, $code, $quantity, $linkvalue, $run);
	my($codere) = '[\w-_#/.]+';
	$r = "";
	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};
	my $linkdir = $Vend::Cfg->{'ItemLinkDir'};
	foreach $i (0 .. $#$Vend::Items) {
		$item = $Vend::Items->[$i];
		$code = $item->{'code'};
		$quantity = $item->{'quantity'};
		$modifier = $item->{'modifier'};
		$price = product_price($code);

		$run = $text;
		$run =~ s#\[if[-_]field\s+($codere)\]([\s\S]*?)\[/if[-_]field\]#
				  product_field($code,$1)	?	pull_if($2)
											:	pull_else($2)#ige;
		$run =~ s:\[item[-_]increment\]:$i + 1:ige;
		$run =~ s:\[item[-_]accessories\]:tag_accessories($code):ige;
		$run =~ s:\[item[-_]data\s+($codere)\s+($codere)\]:
							tag_data($1,$2,$code):igeo;
		$run =~ s:\[item[-_]quantity\]:$quantity:ig;
		$run =~ s:\[item[-_]modifier\s+(\w+)\]:$item->{$1}:ig;
		$run =~ s:\[quantity[-_]name\]:quantity$i:ig;
		$run =~ s:\[modifier[-_]name\s+(\w+)\]:$1$i:ig;
		$run =~ s:\[item[-_]subtotal\]:currency($price * $quantity):ige;
		$run =~ s:\[item[-_]code\]:$code:ig;
		$run =~ s:\[item[-_]field\s+($codere)\]:product_field($code,$1):ige;
		$run =~ s:\[item[-_]description\]:trim_desc(product_description($code)):ige;
		$run =~ s#\[item[-_]link\]#"[page $linkdir$code]"
				  . $linkvalue . '[/page]'#ige;
		$run =~ s:\[item[-_]price\]:currency($price):ige;
		$run =~ s:\[item[-_]price\s+(\d+)\]:
					currency(product_price($code,$1)):ige;

		$r .= $run;
	}
	$r;
}

sub tag_loop_list {
	my($list,$text) = @_;
	my($r, $i, $link, $code, $linkvalue, $run);
	my($codere) = '[\w-_#/.]+';
	my(@list);
	$r = "";
	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};
	my $linkdir = $Vend::Cfg->{'ItemLinkDir'};
	$list =~ s/\s+$//;
	@list = split /\s*[,\0]\s*/, $list;
	$i = 1;
	foreach $code (@list) {
		$run = $text;
		$run =~ s#\[if[-_]field\s+($codere)\]([\s\S]*?)\[/if[-_]field\]#
				  product_field($code,$1)	?	pull_if($2)
											:	pull_else($2)#ige;
		$run =~ s:\[loop[-_]increment\]:$i:ige;
		$run =~ s:\[loop[-_]accessories\]:tag_accessories($code):ige;
		$run =~ s:\[loop[-_]data\s+($codere)\s+($codere)\]:
							tag_data($1,$2,$code):igeo;
		$run =~ s:\[loop[-_]code\]:$code:ig;
		$run =~ s:\[loop[-_]field\s+($codere)\]:product_field($code,$1):ige;
		$run =~ s:\[loop[-_]description\]:trim_desc(product_description($code)):ige;
		$run =~ s#\[loop[-_]link\]#"[page $linkdir$code]"
				  . $linkvalue . '[/page]'#ige;
		$run =~ s:\[loop[-_]price(\s+)?(\d+)?\]:
					currency(product_price($code,$2)):ige;

		$r .= $run;
		$i++;
	}
	$r;
}

# Displays a search page with the special [search-list] tag evaluated.

sub search_page {

	my($q,$o) = @_;
    my($page);

	if (($page = $q->global('search_page')) ) {
    	$page = readin($page);
	}
	elsif($Vend::Cfg->{'FrameSearchPage'} && $Vend::Session->{'frames'}) {
    	$page = readin($Vend::Cfg->{'FrameSearchPage'});
	}
    else {
    	$page = readin($Vend::Cfg->{'Special'}->{'search'});
	}

 	unless (defined $page) {
		logError("Missing special page: $page\n");
		logGlobal("Missing special page: $page in $Vend::Cfg->{Catalog}\n");
		return main::response('plain', "No search page defined!");
	}

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
    my($page,$selector);
    my($codere) = '[\w-_#/.]+';

    if($selector = $Vend::Cfg->{'PageSelectField'}) {
		if(column_exists($selector)) {
			$selector = product_field($code, $selector);
		}
		else {
			logError("The PageSelectField column $selector doesn't exist.") ;
		}
	}

	$selector = $Vend::Cfg->{'Special'}->{'flypage'}
		unless $selector;

	if(product_code_exists($code)) {
    	$page = readin($selector);
	}

    return undef unless defined $page;
	$page =~ s#\[if[-_]field\s+($codere)\]([\s\S]*?)\[/if[-_]field\]#
			  product_field($code,$1)	?	pull_if($2)
			  							:	pull_else($2)#ige;
    $page =~ s!\[item[-_]code\]!$code!ig;
    $page =~ s!\[item[-_]description\]!product_description($code)!ige;
    $page =~ s!\[item[-_]price\]!product_price($code)!ige;
	$page =~ s:\[item[-_]price\s+(\d+)\]:
					currency(product_price($code,$1)):ige;
	$page =~ s:\[item[-_]field\s+($codere)\]:product_field($code,$1):ige;
	$page =~ s:\[item[-_]data\s+($codere)\s+($codere)\]:
							tag_data($1,$2,$code):igeo;

    $page;
}

sub order_page
{
    my($which) = @_;
    my($page);

	$which = $Vend::Cfg->{'Special'}->{'order'} unless defined $which;

	if($which eq $Vend::Cfg->{'Special'}->{'order'} and
	   $Vend::Cfg->{'FrameOrderPage'} and
	   $Vend::Session->{'frames'}) {
    	$page = readin($Vend::Cfg->{'FrameOrderPage'});
	}
    else {
    	$page = readin($which);
	}

 	unless (defined $page) {
		logError("Missing special page: $which\n");
		logGlobal("Missing special page: $which in $Vend::Cfg->{Catalog}\n");
		return main::response('plain', "No search page defined!");
	}
    main::response('html',interpolate_html($page));
}

sub shipping {
	if($Vend::Cfg->{'CustomShipping'}) {
		return custom_shipping();
	}
	else { $Vend::Cfg->{'Shipping'}; }
}

sub apply_discount {
	my($product_code, $subtotal, $quantity) = @_;

	my($formula, $cost);
	my(@formulae);
	my $safe = new Safe;

	# Check for individual item discount
	push(@formulae, $Vend::Session->{'discount'}->{$product_code})
		if defined $Vend::Session->{'discount'}->{$product_code};
	# Check for all item discount
	push(@formulae, $Vend::Session->{'discount'}->{ALL_ITEMS})
		if defined $Vend::Session->{'discount'}->{ALL_ITEMS};

	# Calculate any formalas found
	foreach $formula (@formulae) {
		next unless $formula;
		$formula =~ s/\$q/$quantity/g; 
		$formula =~ s/\$s/$subtotal/g; 
		$cost = $safe->reval($formula);
		if($@) {
			logError
				"Discount ALL_ITEMS has bad formula. Returning normal subtotal.";
			next;
		}
		$subtotal = $cost;
	}
	$subtotal;
}

sub custom_shipping {
	my($mode) = $Vend::Session->{'values'}->{'mv_shipmode'} || 'default';
	my($field) = $Vend::Cfg->{'CustomShipping'};
	my($code, $i, $total, $cost, $multiplier, $formula);
	my $safe = new Safe;

	if(defined $Vend::Cfg->{'Shipping_criterion'}->{$mode}) {
		$field = $Vend::Cfg->{'Shipping_criterion'}->{$mode};
	}

	eval {/$mode/; 1;};
	if ($@) {
		logError("Bad shipping mode '$mode', returning 0");
		return 0;
	}
			
	if(! defined $Vend::Cfg->{'Shipping_cost'}->{'default'}) {
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
	foreach $code (sort keys %{$Vend::Cfg->{'Shipping_cost'}}) {
		next unless $code =~ /^$mode\d+/i;
		if(	$total <= $Vend::Cfg->{'Shipping_max'}->{$code} and
			$total >= $Vend::Cfg->{'Shipping_min'}->{$code} ) {
			# unless field begins with 'x' or 'f', straight cost is returned
			# - otherwise the quantity is multiplied by the cost or a formula
			# is applied
			if ($Vend::Cfg->{'Shipping_cost'}->{$code} =~ /^x\s*/i) {
				$multiplier = $Vend::Cfg->{'Shipping_cost'}->{$code};
				$multiplier =~ s/^x\s*//i;
				return $multiplier * $total;
			}
			elsif ($Vend::Cfg->{'Shipping_cost'}->{$code} =~ /^\s*f\s*(.*)/i) {
				$formula = $1;
				$formula = interpolate_html($formula);
				$formula =~ s/\bx\b/$total/g;
				$cost = $safe->reval($formula);
				if($@) {
					logError("Shipping mode '$mode' has bad formula. Returning 0");
					return 0;
				}
				return $cost;
			}
			elsif ($Vend::Cfg->{'Shipping_cost'}->{$code} =~ /^\s*u/i) {
				my $what = interpolate_html($Vend::Cfg->{'Shipping_cost'}->{$code});
				$what =~ m:u\s*([-\w]+)\s+([-\w]+):i;
				my $type = $1;
				my $zip = $2;
				$cost = tag_ups($type,$zip,$total) and return $cost;
				
			}
			else {
				return $Vend::Cfg->{'Shipping_cost'}->{$code};
			}
		}
	}

	# If we got here, the mode and quantity fit was not found
	logError("Custom shipping: no match found for\n" .
			 "mode '$mode', quantity '$total', returning 0");
	return 0;
}

sub taxable_amount {
    my($taxable, $i, $code, $tmp, $quantity);

	return subtotal() unless $Vend::Cfg->{'NonTaxableField'};

    $taxable = 0;

	eval { column_exists($Vend::Cfg->{'NonTaxableField'}) };

	if($@) {
		logError("NonTaxableField '$Vend::Cfg->{'NonTaxableField'}' doesn't exist!");
		return subtotal();
	}

    foreach $i (0 .. $#$Vend::Items) {
		$code =	$Vend::Items->[$i]->{'code'};
		$quantity = $Vend::Items->[$i]->{'quantity'};
		next if is_yes( product_field($code, $Vend::Cfg->{'NonTaxableField'}) );
		$tmp = $quantity * product_price($code);
		unless (defined $Vend::Session->{'discount'}) {
			$taxable += $tmp;
		}
		else {
			$taxable += apply_discount($code, $tmp, $quantity);
		}
    }

	$taxable;
}

# Calculate the sales tax
sub salestax {
	my($amount) = shift || taxable_amount();
	my($r, $code);
	my(@code) = map { $Vend::Session->{'values'}->{$_} }
					split /\s*,\s*/,$Vend::Cfg->{'SalesTax'};
					

	if(! defined $Vend::Cfg->{SalesTaxTable}->{'default'}) {
		if ( ! read_salestax() ) {
			logError("Sales tax failed, no tax file, returning 0");
			return 0;
		}
	}

	CHECKSHIPPING: {
		last CHECKSHIPPING unless $Vend::Cfg->{'TaxShipping'};
		foreach $code (@code) {
			next unless defined $Vend::Cfg->{SalesTaxTable}->{$code};
			next unless $Vend::Cfg->{'TaxShipping'} =~ /\b\Q$code\E\b/i;
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
		if(defined $Vend::Cfg->{SalesTaxTable}->{$code}) {
			$r = $amount * $Vend::Cfg->{SalesTaxTable}->{$code};
			last;
		}
		else {
			$r = $amount * $Vend::SalesTax{'default'};
		}
	}

	$r;
}

# Returns just subtotal of items ordered, with discounts
# applied
sub subtotal {
    my($subtotal, $i, $code, $tmp, $cost, $formula);
	my $discount = defined $Vend::Session->{'discount'};
	my $safe = new Safe;

    $subtotal = 0;
	$tmp = 0;
    foreach $i (0 .. $#$Vend::Items) {
		$code = $Vend::Items->[$i]->{'code'};
		$tmp = $Vend::Items->[$i]->{'quantity'} *
			product_price($code);
		if($discount) {
			$subtotal +=
				apply_discount($code, $tmp, $Vend::Items->[$i]->{'quantity'});
		}
		else { $subtotal += $tmp }
    }
	if (defined $Vend::Session->{'discount'}->{ENTIRE_ORDER}) {
		$formula = $Vend::Session->{'discount'}->{ENTIRE_ORDER};
		$formula =~ s/\$q/tag_nitems()/eg; 
		$formula =~ s/\$s/$subtotal/g; 
		$cost = $safe->reval($formula);
		if($@) {
			logError
				"Discount ENTIRE_ORDER has bad formula. Returning normal subtotal.";
			$cost = $subtotal;
		}
		$subtotal = $cost;
	}
    $subtotal;
}

sub tag_ups {
	my($type,$zip,$weight) = @_;
	my(@data);
	my(@fieldnames);
	my($i,$point,$zone);

	unless (defined $Vend::Database{$type}) {
		logError("UPS lookup called, no type file loaded for '$type'");
		return undef;
	}
	unless ($Vend::Cfg->{'UpsZoneFile'}) {
		logError("UPS lookup called, no zone file defined");
		return undef;
	}
	@Vend::UPS = split(/\n/, readfile($Vend::Cfg->{'UpsZoneFile'})) unless @Vend::UPS;
	unless (defined @Vend::UPS) {
		logError("UPS lookup called, zone file not found");
		return undef;
	}
	$zip = substr($zip, 0, 3);
	$zip =~ s/^0+//;
	@fieldnames = split /\t/, $Vend::UPS[0];
	for($i = 2; $i < @fieldnames; $i++) {
		next unless $fieldnames[$i] eq $type;
		$point = $i;
		last;
	}

	unless (defined $point) {
		logError("UPS lookup failed, type '$type' not found");
		return undef;
	}

	for(@Vend::UPS[1..$#Vend::UPS]) {
		@data = split /\t/, $_;
		next unless ($zip >= $data[0] and $zip <= $data[1]);
		$zone = $data[$point];
		return 0 unless $zone ||= 0;
		last;
	}

	my $cost = tag_data($type,$zone,$weight);
	$cost;

}


1;
