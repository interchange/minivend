# Interpolate.pm - Interpret MiniVend tags
# 
# $Id: Interpolate.pm,v 1.30 1997/11/08 16:43:57 mike Exp mike $
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

# AUTOLOAD
#use AutoLoader;
#require Exporter;
#@ISA = qw(Exporter AutoLoader);
#*AUTOLOAD = \&AutoLoader::AUTOLOAD;
# END AUTOLOAD

# NOAUTO
require Exporter;
@ISA = qw(Exporter);
# END NOAUTO

$VERSION = substr(q$Revision: 1.30 $, 10);

@EXPORT = qw (

cache_html
fly_page
interpolate_html
order_page
salestax
search_page
shipping
subtotal
tag_if
tag_perl
tag_total_cost
tag_sql_list
tag_value

);

use Carp;
use Safe;
use strict;
use Vend::Util;
use Vend::Data;
use Vend::Cart;
use Vend::Server;
use Vend::ValidCC;
# STATICPAGE
use Vend::PageBuild;
# END STATICPAGE
# NEWTAGS
use Vend::Parse;
# END NEWTAGS
use POSIX qw(ceil strftime);

use vars qw($New);

# AUTOLOAD
#use vars qw(
#$CacheInvalid
#%Comment_out
#$Force_old
#%T
#$Codere
#$Coderex
#$ready_safe
#@Opts
#@Flds
#%Sort
#%Sort_field
#);
# END AUTOLOAD

# AUTOLOAD
#$CacheInvalid = 1;
#$Force_old = 0;
#$ready_safe = new Safe;
# END AUTOLOAD

# NOAUTO
my $CacheInvalid = 1;
my $Force_old = 0;
my $ready_safe = new Safe;
# END NOAUTO


sub c_it {
	my($str) = @_;
	$str =~ s/([a-z])/ '[' . "\u$1\l$1" . ']'/ge;
	$str =~ s/([-_])/ '[-_]'/ge;
	$str;
}

# NOAUTO
my %T;
# END NOAUTO

TAGBUILD: {

	my @th = (qw!

		accessories
		alt
		area
		areatarget
		body
		buttonbar
		calc
		/calc
		cart
		checked
		comment
		/comment
		col
		/col
		condition
		/condition
		currency
		/currency
		data
		default
		description
		discount
		discount-price
		/discount
		else
		/else
		elsif
		/elsif
		field
		file
		finish-order
		framebase
		frames-off
		frames-on
		help
		if
		/if
		if-data
		/if-data
		if-field
		/if-field
		if-loop-data
		/if-loop-data
		if-loop-field
		/if-loop-field
		if-modifier
		/if-modifier
		if-msql-data
		/if-msql-data
		if-msql-field
		/if-msql-field
		include
		item-accessories
		item-code
		item-data
		item-description
		item-discount
		item-field
		item-increment
		item-link
		item-list
		/item-list
		item-modifier
		item-param
		item-price
		item-quantity
		item-subtotal
		last-page
		/last-page
		lookup
		loop
		/loop
		loop-accessories
		loop-change
		/loop-change
		loop-code
		loop-data
		loop-description
		loop-field
		loop-increment
		loop-link
		loop-price
		m
		matches
		modifier-name
		more
		more-list
		/more-list
		msql
		msql-code
		msql-data
		msql-description
		msql-field
		msql-increment
		msql-link
		msql-param
		msql-price
		mv
		/mv
		no-match
		/no-match
		new
		nitems
		nrf
		old
		order
		/order
		on-change
		/on-change
		page
		/page
		pagetarget
		/pagetarget
		perl
		/perl
		post
		/post
		price
		process-order
		process-search
		process-target
		quantity-name
		random
		rotate
		row
		/row
		salestax
		scratch
		search
		search-list
		/search-list
		selected
		set
		/set
		shipping
		shipping-desc
		sort
		/sort
		subtotal
		tag
		/tag
		then
		/then
		total-cost
		uniq
		value

	! );

	my $tag;
	for (@th) {
		$tag = $_;
		s/msql/m?sql/g;
		s/(\w)/[\u$1\l$1]/g;
		s/[-_]/[-_]/g;
		$T{$tag} = "\\[$_";
	}
}

# AUTOLOAD
#$Codere = '[\w-_#/.]+';
#$Coderex = '[\w-_:#=/.%]+';
#%Comment_out = ( '<' => '&lt;', '[' => '&#91;', '_' => '&#95;', );
# END AUTOLOAD

# NOAUTO
my $Codere = '[\w-_#/.]+';
my $Coderex = '[\w-_:#=/.%]+';
my %Comment_out = ( '<' => '&lt;', '[' => '&#91;', '_' => '&#95;', );
# END NOAUTO

sub comment_out {
	my ($bit) = @_;
	$bit =~ s/([[<_])/$Comment_out{$1}/ge;
	return '<!--' . $bit . '-->';
}

#
# This is one entry point for page display.
# Evaluates all of the MiniVend tags.
#

sub substitute_image {
	my ($text) = @_;

    if ($Vend::Cfg->{ImageDir}) {
        $$text =~ s#(<i\w+\s+[^>]*?src=")(?!http:)([^/][^"]+)#
                         $1 . $Vend::Cfg->{ImageDir} . $2#ige;
    }
    if($Vend::Cfg->{ImageAlias}) {
		for (keys %{$Vend::Cfg->{ImageAlias}} ) {
        	$$text =~ s#(<i\w+\s+[^>]*?src=")($_)#
                         $1 . ($Vend::Cfg->{ImageAlias}->{$2} || $2)#ige;
		}
    }
}

sub cache_html {
	my ($html) = @_;
	my ($name, @post);
	my ($bit, %post);
	my $it = 'POST1000';

	# Comment facility

	unless ($Global::DisplayComments) {
		1 while $html =~ s% $T{'comment'}\]				# tag
							(?![\000-\377]*$T{'comment'}\])   # ensure innermost
							[\000-\377]*?
							$T{'/comment'}\]%%xgo;
	}
	else {
		1 while $html =~ s% $T{'comment'}\]				# tag
							(?![\000-\377]*$T{'comment'}\])   # ensure innermost
							[\000-\377]*?
							$T{'/comment'}\]%comment_out($1)%xego;
	}

	$CacheInvalid = 0;

	local ($New) = $New || $Vend::Cfg->{NewTags};

	if($New) { $New = 0 if $html =~ s/\[(old|new)\]//i and lc $1 eq 'old' }
	else 	 { $New = 1 if $html =~ s/\[(old|new)\]//i and lc $1 eq 'new' }

print("New tags=$New\n") if $Global::DEBUG;

	# Substitute defines from configuration file
	$html =~ s#\@\@([A-Za-z0-9]\w+[A-Za-z0-9])\@\@#$Global::Variable->{$1}#ge;
	$html =~ s#__([A-Za-z0-9]\w+[A-Za-z0-9])__#$Vend::Cfg->{Variable}->{$1}#ge;

	# Uncomment to use parallel MV and HTML tags
	#$html =~ s#<!--\s*$T{'alt'}\]\s*-->[\000-\377]*?<!--\s*$T{'/alt'}\]\s*-->##o;
	#$html =~ s#<!--\s*\[mv\]\s*##;
	#$html =~ s#\[/mv\]\s*-->##;

    # Returns, could be recursive
    if($New) {
        my $parse = new Vend::Parse;
        $parse->parse($html) || logError "Couldn't parse page:\n$html";
        $html = $parse->{OUT};
        substitute_image(\$html);
		$CacheInvalid++ if $parse->{INVALID};
		$Vend::CachePage = $CacheInvalid ? undef : 1;
        return $html;
    }

    $html =~ s#$T{'post'}(\d*)]([\000-\377]*?)$T{'/post'}\1\]#
                            $name = $1 || $it++;
                            push(@post,$name);
                            $post{$name} = $2; 
                            '__-' . $name . '-__';
                                    #ge;

    if(@post) {
        $html = cache_scan_html($html);
        foreach $bit (@post) {
            $html =~ s/__-${bit}-__/$post{$bit}/e;
        }
    }

	return cache_scan_html($html);

}


#
# This is one entry point for page display.
# Evaluates all of the MiniVend tags.
#

sub interpolate_html {
	my ($html) = @_;
	my ($name, @post);
	my ($bit, %post);
	my $it = 'POST1000';

	# Comment facility
	1 while $html =~ s% $T{'comment'}\]				# tag
						(?![\000-\377]*$T{'comment'}\])   # ensure innermost
						[\000-\377]*?
						$T{'/comment'}\]%%xgo;
	$html =~ s/<!--+\[/[/g
		and $html =~ s/\]--+>/]/g;

	local ($New) = $New || $Vend::Cfg->{NewTags};

	if($New) { $New = 0 if $html =~ s/\[old\]//i }
	else 	 { $New = 1 if $html =~ s/\[new\]//i }

print("New tags=$New\n") if $Global::DEBUG;

	# Substitute defines from configuration file
	$html =~ s#\@\@([A-Za-z0-9]\w+[A-Za-z0-9])\@\@#$Global::Variable->{$1}#ge;
	$html =~ s#__([A-Za-z0-9]\w+[A-Za-z0-9])__#$Vend::Cfg->{Variable}->{$1}#ge;

    # Returns, could be recursive
	if($New) {
		my $parse;
		if(! defined $INC{'Vend/Parse.pm'}) {
			#called from safe_tag, no can do with Safe. Must use old.
		}
		else {
			$parse = new Vend::Parse;
			$parse->parse($html) || logError "Couldn't parse page:\n$html";
			$html = $parse->{OUT};
			substitute_image(\$html);
			return $html;
		}
	}

    $html =~ s#$T{'post'}(\d*)]([\000-\377]*?)$T{'/post'}\1\]# 
                            $name = $1 || $it++;
                            push(@post,$name);
                            $post{$name} = $2;
                            '__-' . $name . '-__';
                                    #ge;

    if(@post) {
        $html = scan_html($html);
        foreach $bit (@post) {
            $html =~ s/__-${bit}-__/$post{$bit}/e;
        }
    }

	return scan_html($html);

}

sub cache_scan_html {
    my($html) = @_;

    my($Codere) = '[\w-_#/.]+';
    my($Coderex) = '[\w-_:#=/.%]+';

	#my $j = 1;  #DEBUG
#print( "CacheInvalid" . $j++ . ": $CacheInvalid\n") if $Global::DEBUG;

	$html =~ s:$T{'tag'}([^\]]*)\]([\000-\377]*?)$T{'/tag'}\]:do_tag($1,$2):geo;
    $html =~ s:\[\s*(\d?)\s*(\[[\000-\377]*?\])\s*\1\s*\]:cache_scan_html($2):ge;

	$html =~ s:$T{'cart'}\s+(\w+)\]:tag_cart($1):geo
			and $CacheInvalid = 1;
	$html =~ s:$T{'search'}\s+($Coderex)\]:tag_search($1):geo;
    1 while $html =~ s% $T{'item-list'}(?:\s+)?($Codere)?\]		# tag
						(?![\000-\377]*$T{'item-list'}\])	# ensure innermost
						([\000-\377]*?)
						$T{'/item-list'}\]%
					 tag_item_list($1,$2)%xgeo;

    1 while $html =~ s:$T{'loop'}\s+
						([^\]]*)							# all args
							\]
						(?![\000-\377]*$T{'loop'}\s+)			# ensure innermost
						([\000-\377]*?)
						$T{'/loop'}\]:
              tag_loop_list($1,$2):xgeo;
    $html =~ s:$T{'default'}\s+([^\]]+)\]:tag_default($1):geo
				and $CacheInvalid = 1;
    $html =~ s!$T{'value'}\s+($Codere)(?:\s+)?($Codere)?\]!tag_value($1,$2)!geo
				and $CacheInvalid = 1;
    $html =~ s:$T{'scratch'}\s+([^\]]+)\]:tag_scratch($1):geo
				and $CacheInvalid = 1;

    1 while $html =~ s:$T{'calc'}\]
						(?![\000-\377]*$T{'calc'}\])			# ensure innermost
						([\000-\377]*?)
						$T{'/calc'}\]:
              	tag_calc($1):xgeo;

	1 while $html =~ s:$T{'if'}\s+
						([^\]]+[^\\])           # all args
						\]
						(?![\000-\377]*\[if\s+)				# ensure innermost
						([\000-\377]*?)
						$T{'/if'}\]:
				  tag_if($1,$2):xgeo;


	$html =~ s#$T{'lookup'}\s+([^\]]+)\]#tag_lookup(quoted_string($1))#geo
				and $CacheInvalid = 1;
	$html =~ s#$T{'set'}\s+([^\]]+)\]([\000-\377]*?)$T{'/set'}\]#
				  set_scratch($1,$2)#geo and $CacheInvalid = 1;
    $html =~ s:$T{'data'}\s+([^\]]+)\]:
					tag_data(quoted_string($1)):geo;
	$html =~ s#
				\[m?sql \s+ ($Codere) ([^\]]*) \]
				([\000-\377]*?)
				\[/(m)?sql(?:\s+)?($Codere)?\]#
				  $CacheInvalid = 1 if "\L$1" eq 'set';
				  sql_query($1,$2,$3,$4,$5)#geixo;

	$html =~ s!$T{'file'}\s+($Codere)\]!readfile($1, $Global::NoAbsolute)!geo;

    $html =~ s!$T{'finish-order'}(?:\s+)?($Codere)?\]!tag_finish_order($1)!geo;

    $html =~ s:$T{'frames-on'}\]:tag_frames_on():geo
			and $CacheInvalid = 1;
    $html =~ s:$T{'frames-off'}\]:tag_frames_off():geo
			and $CacheInvalid = 1;

    $html =~ s:$T{'framebase'}\s+($Codere)\]:tag_frame_base($1):geo;
    $html =~ s:$T{'body'}\s+($Codere)\]:tag_body($1):geo;
    $html =~ s:$T{'help'}\s+($Codere)\]:tag_help($1):geo;
    $html =~ s:$T{'buttonbar'}\s+($Codere)\]:tag_buttonbar($1):geo;
    $html =~ s:$T{'random'}\]:tag_random():geo;
    $html =~ s!$T{'rotate'}(?:\s+)?($Codere)?\]!tag_rotate($1)!geo;

	$html =~ s!$T{'checked'}\s+($Codere)(?:\s+)?($Codere)?(?:\s+)?($Codere)?\]!
					tag_checked($1,$2 || 'on', $3)!geo
			and $CacheInvalid = 1;
	$html =~ s!$T{'selected'}\s+($Codere)\s+($Codere)(?:\s+)?($Codere)?\]!
				tag_selected($1,$2,$3)!geo
			and $CacheInvalid = 1;

    $html =~ s:$T{'accessories'}\s+($Codere)(\s+[^\]]+)?\]:
					tag_accessories($1,'',$2):geo;
    $html =~ s:$T{'field'}\s+($Codere)\s+($Codere)\]:product_field($1,$2):geo;

    $html =~ s!$T{'pagetarget'}\s+($Coderex)\s+($Coderex)(?:\s+)?($Coderex)?\]!
					tag_pagetarget($1,$2,$3)!geo;

    $html =~ s!$T{'area'}\s+($Coderex)(?:\s+)?($Coderex)?\]!tag_area($1,$2)!geo;

    $html =~ s!$T{'areatarget'}\s+($Coderex)\s+($Coderex)(?:\s+)?($Coderex)?\]!
						tag_areatarget($1,$2,$3)!geo;

    $html =~ s!$T{'page'}\s+($Coderex)(?:\s+)?($Coderex)?\]!tag_page($1,$2)!geo;

    $html =~ s!$T{'last-page'}(?:\s+)?($Codere)?(?:\s+)?($Codere)?\]!
				tag_last_page($1,$2)!geo and $CacheInvalid = 1;

    $html =~ s:$T{'/pagetarget'}\]:</a>:go;
    $html =~ s:$T{'/page'}\]:</a>:go;
    $html =~ s:$T{'/order'}\]:</a>:go;
    $html =~ s:$T{'/last-page'}\]:</a>:go;

	$html =~ s~  $T{'perl'}  (?:\s+)?  ([^\]]+[^\\])?\]
					(?:<!--+\s*)?
					([\000-\377]*?)
					(?:-->\s*)?$T{'/perl'}\]
					~ tag_perl($1,$2) ~xgeo and $CacheInvalid = 1;

    $html =~ s!$T{'order'}\s+($Codere)(?:\s+)?($Codere)?(?:\s+)?($Codere)?\]!
					tag_order($1,$2,$3)!geo;


    $html =~ s!$T{'nitems'}(?:\s+)?($Codere)?\]!tag_nitems($1)!geo
			and $CacheInvalid = 1;
	$html =~ s#$T{'discount'}\s+($Codere)\]([\000-\377]*?)$T{'/discount'}\]#
				  tag_discount($1,$2)#geo
				  		and $CacheInvalid = 1;
    $html =~ s#$T{'subtotal'}(?:\s+)?($Codere)\]#currency(subtotal($1))#geo
			and $CacheInvalid = 1;
    $html =~ s#$T{'shipping-desc'}\w*(?:[\s]+)?($Codere)?\]#
					tag_shipping_desc($1)#geo;
    $html =~ s#$T{'shipping'}(?:\s+)?($Codere)?\]#currency(shipping($1))#geo
				and $CacheInvalid = 1;
    $html =~ s#$T{'salestax'}(?:\s+)?($Codere)?\]#currency(salestax('', $1))#geo
				and $CacheInvalid = 1;
    $html =~ s#$T{'total-cost'}(?:\s+)?($Codere)?\]#tag_total_cost($1)#geo
				and $CacheInvalid = 1;
    $html =~ s#$T{'price'}\s+($Codere)(?:\s+)?($Codere)?(?:\s+)?($Codere)?\]#
                currency(product_price($1,$2,$3))#geo;
	$html =~ s:$T{'currency'}\]([\000-\377]*?)$T{'/currency'}\]:currency($1):geo;
    $html =~ s#$T{'description'}\s+($Codere)\]# product_description($1)#goe;
	$html =~ s:$T{'row'}\s+(\d+)\]([\000-\377]*?)$T{'/row'}\]:tag_row($1,$2):geo;

    $html =~ s#$T{'process-order'}(?:\s+)?($Codere)?\]#tag_process_order($1)#geo;
    $html =~ s#$T{'process-search'}(?:\s+)?($Codere)?\]#tag_process_search($1)#geo;
    $html =~ s#$T{'process-target'}(?:\s+)?($Codere)?(?:\s+)?($Codere)?\]#
				tag_process_target($1,$2)#goe;

    substitute_image(\$html);

#print( "CacheInvalid" . $j++ . ": $CacheInvalid\n") if $Global::DEBUG;

	$Vend::CachePage = $CacheInvalid ? undef : 1;

	$html;

}

sub scan_html {
    my($html) = @_;

    my($Codere) = '[\w-_#/.]+';
    my($Coderex) = '[\w-_:#=/.%]+';

	$html =~ s:$T{'tag'}([^\]]*)\]([\000-\377]*?)$T{'/tag'}\]:do_tag($1,$2):geo;
    $html =~ s:\[\s*(\d?)\s*(\[[\000-\377]*?\])\s*\1\s*\]:scan_html($2):ge;

	$html =~ s:$T{'cart'}\s+(\w+)\]:tag_cart($1):ge;
	$html =~ s:$T{'search'}\s+($Coderex)\]:tag_search($1):geo;
    1 while $html =~ s% $T{'item-list'}(?:\s+)?($Codere)?\]		# tag
						(?![\000-\377]*$T{'item-list'}\])	# ensure innermost
						([\000-\377]*?)
						$T{'/item-list'}\]%
					 tag_item_list($1,$2)%xgeo;

    1 while $html =~ s:$T{'loop'}\s+
						([^\]]*)							# all args
							\]
						(?![\000-\377]*$T{'loop'}\s+)			# ensure innermost
						([\000-\377]*?)
						$T{'/loop'}\]:
              tag_loop_list($1,$2):xgeo;
    $html =~ s:$T{'default'}\s+([^\]]+)\]:tag_default($1):geo;
    $html =~ s!$T{'value'}\s+($Codere)(?:\s+)?($Codere)?\]!tag_value($1,$2)!geo;
    $html =~ s:$T{'scratch'}\s+([^\]]+)\]:tag_scratch($1):geo;


    1 while $html =~ s:$T{'calc'}\]
						(?![\000-\377]*$T{'calc'}\])			# ensure innermost
						([\000-\377]*?)
						$T{'/calc'}\]:
              	tag_calc($1):xgeo;

	1 while $html =~ s:$T{'if'}\s+
						([^\]]+[^\\])           # all args
						\]
						(?![\000-\377]*\[if\s+)				# ensure innermost
						([\000-\377]*?)
						$T{'/if'}\]:
				  tag_if($1,$2):xgeo;

	$html =~ s#$T{'lookup'}\s+([^\]]+)\]#tag_lookup(quoted_string($1))#geo;
	$html =~ s#$T{'set'}\s+([^\]]+)\]([\000-\377]*?)$T{'/set'}\]#
				  set_scratch($1,$2)#geo;
    $html =~ s:$T{'data'}\s+([^\]]+)\]:
					tag_data(quoted_string($1)):geo;
	$html =~ s#\[ m?sql \s+ ($Codere) ([^\]]*) \]
				([\000-\377]*?)
				\[/(m)?sql(?:\s+)?($Codere)?\]#
				  sql_query($1,$2,$3,$4,$5)#geixo;
	$html =~ s!$T{'file'}\s+($Codere)\]!readfile($1, $Global::NoAbsolute)!geo;

    $html =~ s!$T{'finish-order'}(?:\s+)?($Codere)?\]!tag_finish_order($1)!geo;

    $html =~ s:$T{'frames-on'}\]:tag_frames_on():geo;
    $html =~ s:$T{'frames-off'}\]:tag_frames_off():geo;

    $html =~ s:$T{'framebase'}\s+($Codere)\]:tag_frame_base($1):geo;
    $html =~ s:$T{'body'}\s+($Codere)\]:tag_body($1):geo;
    $html =~ s:$T{'help'}\s+($Codere)\]:tag_help($1):geo;
    $html =~ s:$T{'buttonbar'}\s+($Codere)\]:tag_buttonbar($1):geo;
    $html =~ s:$T{'random'}\]:tag_random():geo;
    $html =~ s!$T{'rotate'}(?:\s+)?($Codere)?\]!tag_rotate($1)!geo;

	$html =~ s!$T{'checked'}\s+($Codere)(?:\s+)?($Codere)?(?:\s+)?($Codere)?\]!
					tag_checked($1,$2 || 'on', $3)!geo;
	$html =~ s!$T{'selected'}\s+($Codere)\s+($Codere)(?:\s+)?($Codere)?\]!
				tag_selected($1,$2,$3)!geo;

    $html =~ s:$T{'accessories'}\s+($Codere)(\s+[^\]]+)?\]:
					tag_accessories($1,'',$2):geo;
    $html =~ s:$T{'field'}\s+($Codere)\s+($Codere)\]:product_field($1,$2):geo;

    $html =~ s!$T{'pagetarget'}\s+($Coderex)\s+($Coderex)(?:\s+)?($Coderex)?\]!
					tag_pagetarget($1,$2,$3)!geo;

    $html =~ s!$T{'area'}\s+($Coderex)(?:\s+)?($Coderex)?\]!tag_area($1,$2)!geo;

    $html =~ s!$T{'areatarget'}\s+($Coderex)\s+($Coderex)(?:\s+)?($Coderex)?\]!
						tag_areatarget($1,$2,$3)!geo;

    $html =~ s!$T{'page'}\s+($Coderex)(?:\s+)?($Coderex)?\]!tag_page($1,$2)!geo;

    $html =~ s!$T{'last-page'}(?:\s+)?($Coderex)?(?:\s+)?($Coderex)?\]!
				tag_last_page($1,$2)!geo;

    $html =~ s:$T{'/pagetarget'}\]:</a>:go;
    $html =~ s:$T{'/page'}\]:</a>:go;
    $html =~ s:$T{'/order'}\]:</a>:go;
    $html =~ s:$T{'/last-page'}\]:</a>:go;

	$html =~ s~  $T{'perl'}  (?:\s+)?  ([^\]]+[^\\])?\]
					(?:<!--+\s*)?
					([\000-\377]*?)
					(?:-->\s*)?$T{'/perl'}\]
					~ tag_perl($1,$2) ~xgeo;

    $html =~ s!$T{'order'}\s+($Codere)(?:\s+)?($Codere)?(?:\s+)?($Codere)?\]!
					tag_order($1,$2,$3)!geo;

    $html =~ s!$T{'nitems'}(?:\s+)?($Codere)?\]!tag_nitems($1)!geo;
	$html =~ s#$T{'discount'}\s+($Codere)\]([\000-\377]*?)$T{'/discount'}\]#
				  tag_discount($1,$2)#geo;
    $html =~ s#$T{'subtotal'}(?:\s+)?($Codere)?\]#currency(subtotal($1))#geo;
    $html =~ s#$T{'shipping-desc'}\w*(?:[\s]+)?($Codere)?\]#
					tag_shipping_desc($1)#geo;
    $html =~ s#$T{'shipping'}(?:\s+)?($Codere)?\]#currency(shipping($1))#geo;
    $html =~ s#$T{'salestax'}(?:\s+)?($Codere)?\]#currency(salestax('', $1))#geo;
    $html =~ s#$T{'total-cost'}(?:\s+)?($Codere)?\]#tag_total_cost($1)#geo;
    $html =~ s#$T{'price'}\s+($Codere)(?:\s+)?($Codere)?(?:\s+)?($Codere)?\]#
                currency(product_price($1,$2,$3))#geo;
	$html =~ s:$T{'currency'}\]([\000-\377]*?)$T{'/currency'}\]:currency($1):geo;
	$html =~ s:$T{'currency'}\]([\000-\377]*?)$T{'/currency'}\]:currency($1):geo;
    $html =~ s#$T{'description'}\s+($Codere)\]#product_description($1)#goe;
	$html =~ s:$T{'row'}\s+(\d+)\]([\000-\377]*?)$T{'/row'}\]:tag_row($1,$2):geo;

    $html =~ s#$T{'process-order'}(?:\s+)?($Codere)?\]#tag_process_order($1)#geo;
    $html =~ s#$T{'process-search'}(?:\s+)?($Codere)?\]#tag_process_search($1)#geo;
    $html =~ s#$T{'process-target'}(?:\s+)?($Codere)?(?:\s+)?($Codere)?\]#
				tag_process_target($1,$2)#goe;

    $html =~ s#(<i\w+\s+[^>]*?src=")(?!http:)([^/][^"]+)#
                $1 . $Vend::Cfg->{ImageDir} . $2#ige
                 if $Vend::Cfg->{ImageDir};

	#$html =~ s#(<i\w+\s+[^>]*?src=")([^/])#$1 . $Vend::Cfg->{ImageDir} . $2#ige
	#	if $Vend::Cfg->{ImageDir};

	$html;

}

# Returns the text of a configurable database field or a 
# variable
sub tag_data {
	my($selector,$field,$key,$value,$inc) = @_;
#print("Data args: @_\n") if $Global::DEBUG;

	if(defined $Vend::Database{$selector}) {
print("Database with: key=$key field=$field db=$selector val=$value inc=$inc\n") if $Global::DEBUG;
		my $db = $Vend::Database{$selector};
		unless(defined $value) {
			$CacheInvalid = 1
				if defined $Vend::Cfg->{DynamicData}->{$selector};
			my $data =  database_field($db,$key,$field);
			return $data;
		}
		$CacheInvalid = 1;
		if(defined $inc) {
			return increment_field($db,$key,$field,$value || 1);
		}
		#$value =~ s/^(["'])(.*)\1$/$2/;
		return set_field($db,$key,$field,$value);
	}
	elsif($selector eq 'arg') {
		$CacheInvalid = 1;
		return (! defined $Vend::Argument
			? '' :  $Vend::Argument );
	}
	elsif($selector eq 'session') {
		$CacheInvalid = 1;
		return (! defined $Vend::Session->{$field}
			? '' :  $Vend::Session->{$field} );
	}
	elsif($selector eq 'config') {
		no strict 'refs';
		return (! defined $Vend::Cfg->{$field}
			? 'BAD CONFIG TERM' : $Vend::Cfg->{$field}  );
	}
	elsif($selector eq 'cart') {
		$CacheInvalid = 1;
		return (! ref $Vend::Session->{'carts'}->{$field}
				? '' :  uneval $Vend::Session->{'carts'}->{$field} );
	}
	elsif($selector eq 'items') {
		$CacheInvalid = 1;
		return (! ref $Vend::Session->{'carts'}->{$field}
				? '' :  tag_item_list($field, "'[item-code]' ") );
	}
	elsif($selector eq 'discount') {
		$CacheInvalid = 1;
		no strict 'refs';
		return (! defined $Vend::Session->{'discount'}->{$field}
				? '' :  $Vend::Session->{'discount'}->{$field});
	}
	elsif($selector eq 'scratch') {
		$CacheInvalid = 1;
		return (! defined $Vend::Session->{'scratch'}->{$field}
				? '' :  $Vend::Session->{'scratch'}->{$field});
	}
	elsif($selector =~ /^value/) {
		$CacheInvalid = 1;
		return (! defined $Vend::Session->{'values'}->{$field}
				? '' :  $Vend::Session->{'values'}->{$field} );
	}
	elsif($selector eq 'salestax') {
		$field = uc $field;
		return (! defined $Vend::Cfg->{SalesTaxTable}->{$field}
				? '' : $Vend::Cfg->{SalesTaxTable}->{$field} );
	}
	else {
		logError("Bad data '$selector' '$field' '$key'");
		return '';
	}
}

		
sub conditional {
	my($base,$term,$operator,$comp) = @_;

	$base = lc $base;
	my ($op, $status);
	local($) = 0;
	undef $@;

print("cond: base=$base term=$term op=$operator comp=$comp\n") if $Global::DEBUG;
	my %stringop = ( qw! eq 1 ne 1 gt 1 lt 1! );

	if(defined $stringop{$operator}) {
		$comp =~ /^(["']).*\1$/ or
		$comp =~ /^qq?([{(]).*[})]$/ or
		$comp =~ /^qq?(\S).*\1$/ or
		(index ($comp, '}') == -1 and $comp = 'q{' . $comp . '}')
			or
		(index ($comp, '!') == -1 and $comp = 'q{' . $comp . '}')
	}

print("cond: base=$base term=$term op=$operator comp=$comp\n") if $Global::DEBUG;


	if($base eq 'session') {
		$CacheInvalid = 1;
		$op =	qq%"$Vend::Session->{$term}"%;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'scratch') {
		$CacheInvalid = 1;
		$op =	qq%"$Vend::Session->{'scratch'}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'explicit') {
		$status = tag_perl($term,$comp);
	}
    elsif($base eq 'items') {
        $CacheInvalid = 1;
        $term = 'main' unless $term;
        $op =   scalar @{$Vend::Session->{'carts'}->{$term}};
        $op .=  qq% $operator $comp%
                if defined $comp;
    }
	elsif($base =~ /^value/) {
		$CacheInvalid = 1;
		$op =	qq%"$Vend::Session->{'values'}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'data') {
		my($d,$f,$k) = split /::/, $term;
		$CacheInvalid = 1
			if defined $Vend::Cfg->{DynamicData}->{$d};
		my $data = database_field($d,$k,$f);
print("tag_if db=$d fld=$f key=$k data=$data\n") if $Global::DEBUG;
		$op = 'q{' . $data . '}';
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'discount') {
		$CacheInvalid = 1;
		$op =	qq%"$Vend::Session->{'discount'}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'file') {
		#$op =~ s/[^rwxezfdTsB]//g;
		#$op = substr($op,0,1) || 'f';
		$CacheInvalid = 1;
		$op = 'f';
		$op = qq|-$op "$term"|;
	}
	elsif($base eq 'validcc') {
		$CacheInvalid = 1;
		no strict 'refs';
		$status = ValidCreditCard($term, $operator, $comp);
	}
    elsif($base eq 'config') {
		$op = qq%"$Vend::Cfg->{$term}"%;
		$op .=	qq%	$operator $comp%
				if defined $comp;
    }
	elsif($base =~ /^pric/) {
		$op = qq%"$Vend::Cfg->{'Pricing'}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base =~ /^accessor/) {
        if ($comp) {
            $op = qq%"$Vend::Cfg->{Accessories}->{$term}"%;
            $op .=  qq% $operator $comp%;
        }
        else {
            for(@{$Vend::Cfg->{UseModifier}}) {
                next unless product_field($_,$term);
                $status = 1;
                last;
            }
        }
	}
	elsif($base =~ /^salestax/) {
		$term = uc $term;
		$op = qq%"$Vend::Cfg->{SalesTaxTable}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base =~ /^ship/) {
		$op = qq%"$Vend::Cfg->{'Shipping_desc'}->{$term}"%;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	else {
		$@ = "No such comparison available";
	}

	RUNSAFE: {
		$ready_safe->untrap(@{$Global::SafeUntrap});
		$status = $ready_safe->reval($op)
			unless ($@ or $status);
		if ($@) {
			logError qq%Bad if '@_': $@%;
			$status = 0;
		}
	}

	return $status;
}

sub split_if {
	my ($body) = @_;

	my ($then, $else, $elsif);
	$else = $elsif = '';

	$body =~ s#^\s*$T{'then'}\]([\000-\377]*?)$T{'/then'}\]##o
		and $then = $1;

	$body =~ s#$T{'else'}\]([\000-\377]*)$T{'/else'}\]\s*$##o
		and $else = $1;

	$body =~ s#$T{'elsif'}\s+([\000-\377]*)$T{'/elsif'}\]\s*$#$2#o
		and $elsif = $1;

	$body = $then if defined $then;

	return($body, $elsif, $else);
}

sub tag_if {
	my ($cond,$body) = @_;
print("Called tag_if: $cond\n$body\n") if $Global::DEBUG;
	my ($base, $term, $op, $operator, $comp);
	my ($else, $elsif, $else_present);

	unless ($cond =~ /^explicit\b/i) {
		($base, $term, $operator, $comp) = split /\s+/, $cond, 4;
	}
	elsif ($body =~ s#^\s*$T{'condition'}\]([\000-\377]*?)$T{'/condition'}\]##o) {
		$comp = $1;
		$term = $cond;
		$operator = '';
		$term =~ s/^explicit\s+//i;
		$base = 'explicit';
	}
	else {
		$cond =~ s/^explicit\s+//i;
		$comp = qq%$cond%;
		$base = 'explicit';
		$operator = '';
		$term = '';
	}

	$else_present = 1 if
		$body =~ /\[[EeTt][hHLl][SsEe]/;

	($body, $elsif, $else) = split_if($body)
		if $else_present;

	unless(defined $operator) {
		undef $operator;
		undef $comp;
	}

	my $status = conditional ($base, $term, $operator, $comp);

print("Result of if: $status\n") if $Global::DEBUG;

	if($status) {
		return interpolate_html($body);
	}
	elsif ($elsif) {
		$else = '[else]' . $else . '[/else]' if $else;
		$elsif =~ s#(.*?)$T{'/elsif'}\](.*)#$1${2}[/elsif]#s;
		return interpolate_html('[if ' . $elsif . $else . '[/if]');
	}
	elsif ($else) {
		return interpolate_html($else);
	}

}

sub tag_accessories {
	my($code,$item,$extra) = @_;

	if(! defined $extra) {
		if(defined $Vend::Cfg->{Accessories}->{$code}) {
			return $Vend::Cfg->{Accessories}->{$code};
		}
		else {
			return $Vend::Cfg->{Accessories}->{'default'} || '';
		}
	}
	# Had extra if got here
	$extra =~ s/^\s+//;
	my($attribute, $type, $field, $db, $name) = split /\s*,\s*/, $extra;
	$type = 'select' unless $type;
	$field = $attribute unless $field;
#local($) = 0 if $Global::DEBUG;
#print("accessory db=$db type=$type field=$field attr=$attribute name=$name\n") if $Global::DEBUG;
	my $data = $db ? tag_data($db, $field, $code) : product_field($field,$code);

	unless ($data) {
		return '' if $item;
		return '' if $name;
		return qq|<INPUT TYPE="hidden" NAME="mv_order_$attribute" VALUE="">|;
	}

	return $data if "\L$type" eq 'show';

	my $attrib_value = $item ? $item->{$attribute} : '';

	$name = $item ? "[modifier-name $attribute]" : "mv_order_$attribute";

	return qq|<INPUT TYPE="hidden" NAME="$name" VALUE="$attrib_value">|
		if "\L$type" eq 'hidden';
	return qq|<TEXTAREA NAME="$name" ROWS=$1 COLS=$2>$attrib_value</TEXTAREA>|
		if "\L$type" =~ /^textarea_(\d+)_(\d+)$/;
	return qq|<INPUT TYPE=text NAME="$name" SIZE=$1 VALUE="$attrib_value"|
		if "\L$type" =~ /^text_(\d+)$/;

	# Building select box if got here
	my ($default, $label, $select, $value, $run);
	if($item) {
		$default = $item->{$attribute};
	}

	$run = qq|<SELECT NAME="$name"|;

	$run .= ' MULTIPLE' if $type =~ /^multi/i;
	$run .= '>';
	my @opts = split /\s*,\s*/, $data;
	for(@opts) {
		$run .= '<OPTION';
		$select = 0;
		s/\*$// and $select = 1;
		if ($default) {
			$select = 0;
		}
		($value,$label) = split /=/, $_, 2;
		if($label) {
			$value =~ s/"/&quot;/;
			$run .= qq| VALUE="$value"|;
		}
		if ($default) {
			$default =~ /\b$value\b/ and $select = 1;
		}
		$run .= ' SELECTED' if $select;
		$run .= '>';
		if($label) {
			$run .= $label;
		}
		else {
			$run .= $value;
		}
	}
	$run .= '</SELECT>';

}

sub safe_tag {
	$Force_old = 1;
	return do_tag ('', @_);
}

sub tag_perl {
	my($args,$body,@args) = @_;
	my ($result,$file, $sub);
	my $code = '';
	my(@share);
#print("tag_perl: args=$args BODY:\n$body\nARGS: @args\n") if $Global::DEBUG;
	%Vend::Interpolate::Safe = ();
	@share = split /\s+/, $args if $args;
	my $safe = new Safe;
	for(@share) {
		if( /^value/) {
			$Vend::Interpolate::Safe{'values'} = $Vend::Session->{'values'};
		}
		elsif($_ eq 'sub') {
			$sub = 1;
		}
		elsif($_ eq 'import') {
			$Vend::Interpolate::Safe{'values'} = $Vend::Session->{'values'};
			for(keys %{$Vend::Session->{'values'}}) {
				$code .= '$' . $_;
				$code .= q! = $Safe{'values'}->{'! . $_ . "'};\n";
			}
		}
		elsif($_ eq 'cgi') {
			$Vend::Interpolate::Safe{'cgi'} = {%CGI::values};
		}
		elsif($_ eq 'discount') {
			$Vend::Interpolate::Safe{'discount'} = $Vend::Session->{'discount'};
		}
		elsif($_ eq 'config') {
			$Vend::Interpolate::Safe{'config'} = $Vend::Cfg;
		}
		elsif(/^carts?$/) {
			$Vend::Interpolate::Safe{'carts'} = $Vend::Session->{carts};
		}
		elsif($_ eq 'items') {
			$Vend::Interpolate::Safe{'items'} = [@{$Vend::Items}];
		}
		elsif($_ eq 'file') {
			$file = 1;
		}
		elsif($_ eq 'scratch') {
			$Vend::Interpolate::Safe{'scratch'} = $Vend::Session->{'scratch'};
		}
		elsif($_ eq 'frames') {
			$Vend::Interpolate::Safe{'frames'} = $Vend::Session->{'frames'};
		}
		elsif($_ eq 'browser') {
			$Vend::Interpolate::Safe{'browser'} = $Vend::Session->{'browser'};
		}
	}

	$safe->share('%Safe', '&safe_tag', '&tag_data', '&interpolate_html');
	$safe->untrap(@{$Global::SafeUntrap})
		if $Global::SafeUntrap;

	unless (defined $file or defined $sub) {
		$result = $safe->reval($code . $body);
	}
	elsif (defined $sub) {
		$body =~ s/\s*(\w+)\s*//;
		my $name = $1;


		if(@args) {
			$body .= ',' if $body =~ /\S/;
			$body = "($body";
			for(@args) {
				$body .= uneval($_);
				$body .= ',';
			}
			$body .= ')';
		}
#print("Body now: $body\n") if $Global::DEBUG;
		eval {@_ = eval $body};

		if($@) {
			logError("Bad args to perl sub $name for page $CGI::path_info: $@");
			return '';
		}

		if (defined $Vend::Session->{scratch}->{$name}) {
			$result = $safe->reval( '@_ = ' . $body . ';' . $code .
						$Vend::Session->{scratch}->{$name});
		}
		elsif (defined $Vend::Cfg->{Sub}->{$name}) {
			if($Global::AllowGlobal->{$Vend::Cfg->{CatalogName}}) {
				$result = &{$Vend::Cfg->{Sub}->{$name}};
			}
			else {
				$body = '()' unless $body =~ /\S/;
				$result = $safe->reval( '@_ = ' . $body . ';' . $code .
						$Vend::Cfg->{Sub}->{$name} );
			}
		}
		elsif (defined $Global::GlobalSub->{$name}) {
			$result = &{$Global::GlobalSub->{$name}};
		}
		else {
			logError("Undefined perl sub $name");
			return '';
		}
			
	}
	else {
		$result = $safe->rdo($body);
	}
		
	if ($@) {
		logGlobal("Safe: $@\n$body\n");
		return '';
	}
	undef %Vend::Interpolate::Safe;
	return $result;
}

sub do_tag {
	my($arg, $text) = @_;
#print("Do_tag: arg=$arg text=$text\n") if $Global::DEBUG;
	if($arg) {
		if($arg =~ s/^\s*flag\s+(.+)//si ) {
			do_flag($1, $text);
		}
		elsif($arg =~ s/^\s*header\s*$//si ) {
			$text =~ s/^\s+//;
			$Vend::StatusLine = $text;
		}
		elsif($arg =~ s/^\s*show_tags\s*$//si ) {
			$text =~ s/\[/&#91;/g;
			$text =~ s/\</&lt;/g;
			return $text;
		}
		elsif($arg =~ m!^\s*scan/(.*)!i ) {
			my $string = "[page scan/$1";
			my $se = $text;
			$se =~ s/(\W)/'.' . sprintf("%02x", ord($1))/ge;
			return $string . ']' unless $text;
			return $string . '/se=' . $se . "]$text";
		}
		elsif($arg =~ m!^\s*sql/(.*)!i ) {
			my $string = "[page scan/$1";
			$string .= '/st=sql' unless $string =~ m:/st=sql:;
			$text =~ s/(\W)/'%' . sprintf("%02x", ord($1))/ge;
			return $string . '/sq=' . $text . "]";
		}
		elsif($arg =~ /^\s*import\s+($Codere)(?:\s+)?(.*)/i ) {
			my $type = $2 || '';
			my $db = database_exists_ref($1) 
				or do {
					$arg =~ s/\s*\w+\s+//;
					logError("tag import: unknown database '$arg'");
					return '';
				};
			$db = $db->ref();
			return '' unless $text;
			$text = interpolate_html($text);
			my ($delimiter, $record_delim) =
				Vend::Data::find_delimiter($type || 1);
			my $count = $db->columns();
			$count++;
			my(@records) = split /$record_delim/, $text, -1;
			my @fields;
			my $fields;
			for(@records) {
				chomp;
				next unless /\S/;
				if($delimiter eq 'CSV') {
					$fields = @fields = quoted_comma_string($_);
				}
				else {
					$fields = @fields = split /$delimiter/, $_, $count;
				}
				push (@fields, '') until $fields++ >= $count;
				$db->set_row(@fields);
			}
			return scalar @records;
		}
		elsif($arg =~ /^\s*each\s+($Coderex)/i ) {
			my $base = $1;
			my $db = database_exists_ref($base) 
				or do {
					logError("tag each: unknown database '$base'");
					return '';
				};
			$db = $db->ref();
			my $key;
			my $out = '';
			my $i = 0;
			# See if we are to sort, and do so
			if($text =~ m#^\s*$T{'sort'}([^\]]*)\]#) {
				my @out;
				while(($key) = $db->each_record()) {
					push (@out, $key);
				}
				return tag_loop_list((join "\n", @out), $text);
			}
			else {
				while(($key) = $db->each_record()) {
					$out .= loop_substitute($key, $text, $i++);
				}
				return $out;
			}
		}
		elsif($arg =~ /^\s*touch\s+($Codere)/i ) {
			my $base = $1;
			my $db = database_exists_ref($base) 
				or do {
					logError("tag touch: unknown database '$base'");
					return '';
				};
			$db = $db->ref();
			$db->touch();
		}
		elsif($arg =~ /^\s*time\b/i ) {
			unless ($text =~ /\S/) {
				return scalar localtime();
			}
			return POSIX::strftime($text, localtime());
		}
		elsif($arg =~ /^\s*untaint\b/i ) {
			my(@vars) = split /\s+/, $text;
			for(@vars) {
				next unless defined 
					$Vend::Session->{'values'}->{$_};
				$Vend::Session->{'values'}->{$_} =~ /([\000-\377]*)/;
				$Vend::Session->{'values'}->{$_} = $1;
			}
			return '';
		}
		elsif($arg =~ /^\s*mime(?:\s+)?([\s\S]+)?/i ) {
			my $opt = $1 || '';
			my $id;
			$Vend::TIMESTAMP = POSIX::strftime("%y%m%d%H%M%S", localtime())
				unless defined $Vend::TIMESTAMP;

			$Vend::MIME_BOUNDARY =	$Vend::TIMESTAMP . '-' .
									$Vend::SessionID . '-' .
									$Vend::Session->{'pageCount'} . 
									':=' . $$
				unless defined $Vend::MIME_BOUNDARY;

			if("\L$opt" eq 'boundary') {
				return "--$Vend::MIME_BOUNDARY";
			}
			elsif($opt =~ /^\s*type\s+(.*)/i) {
				$Vend::MIME_TYPE = $1;
			}
			elsif("\L$opt" eq 'id') {
				$Vend::MIME = 1;
				return	mime_id();
			}
			elsif("\L$opt" eq 'header') {
				$id = mime_id();
				return <<EndOFmiMe;
MIME-Version: 1.0
Content-Type: MULTIPART/MIXED; BOUNDARY="$Vend::MIME_BOUNDARY"
Content-ID: $id
EndOFmiMe
			}
			else {
				$text = interpolate_html($text);
				return '' unless $text =~ /\S/;
				$id = mime_id();
				$Vend::MIME = 1;
				$Vend::MIME_TYPE = 'TEXT/PLAIN; CHARSET=US-ASCII'
					unless $Vend::MIME_TYPE;
				return <<EndOFmiMe;
--$Vend::MIME_BOUNDARY
Content-Type: $Vend::MIME_TYPE
Content-ID: $id
Content-Description: $opt

$text
EndOFmiMe

			}
		}
		elsif($arg =~ /^\s*log\s+([\s\S]+)/i ) {
			do_log($1,$text);
		}
		elsif($arg =~ /^\s*export
							\s+($Codere)
							(?:\s+)?($Coderex)?
							(?:\s+)?($Coderex)?
							/oxi ) {
			return export_database($1,$2,$3);
		}
		else {
			logError("Unknown tag argument '$arg'");
		}
		return '';
	}
	else {
		$text = $arg unless $text;
		# Need something not occurring in Perl
		# May as well use the standard
		$text =~ s/&#91;/[/g;
		$text =~ s/&#93;/]/g;
		return interpolate_html("[$text]");
	}
}

# AUTOLOAD
#1;
#__END__
# END AUTOLOAD

sub do_flag {
	my($flag, $arg) = @_;

	$flag =~ s/^\s+//;
	$flag =~ s/\s+$//;
	if($flag =~ /^write$/i) {
		my @args = quoted_string($arg);
		for(@args) {
			$Vend::WriteDatabase{$_} = 1;
			$Vend::Cfg->{DynamicData}->{$_} = 1;
#print("Flagged database '$_' for write\n") if $Global::DEBUG;
		}
	}
	elsif($flag =~ /^build$/i) {
		$Vend::ForceBuild = 1;
	}
	elsif($flag =~ /^cache$/i) {
		$Vend::ForceCache = 1;
	}
	elsif($flag =~ /^checkhtml$/i) {
		$Vend::CheckHTML = 1;
	}
	else {
		logError("Unknown flag operation '$flag', ignored.");
	}
	return '';
}

sub do_log {
	my($arg, $data) = @_;
	my(@lines);
	my(@fields);

	$arg =~ /($Coderex)(?:\s+)?(\w+)?/o;
	my $file = $1;
	my $op = $2 || 'tabbed';
	if($op =~ /^tab/) {
		$data = interpolate_html($data);
		$data =~ s/^\s+//;
		$data =~ s/\s+$//;
		@lines = split /\r?\n/, $data;
		for(@lines) {
			@fields = split /\t/, $_;
			logData($file, @fields)
				or return '';
		}
	}
	elsif($op =~ /^quot/) {
		$data =~ interpolate_html($data);
		$data =~ s/^\s+//;
		$data =~ s/\s+$//;
		@lines = split /\r?\n/, $data;
		for(@lines) {
			@fields = quoted_string $_;
			logData($file, @fields)
				or return '';
		}
	}
	elsif($op =~ /^text/) {
		$data =~ interpolate_html($data);
		writefile($file, $data)
				or return '';
	}
	else {
		logError("Unknown logging operation '$op'");
		return '';
	}

	1;
}

sub mime_id {
	'<MiniVend.' . $::VERSION . '.' .
	$Vend::TIMESTAMP . '.' .
	$Vend::SessionID . '.' .
	++$Vend::Session->{'pageCount'} . '@' .
	$Vend::Cfg->{VendURL} . '>';
}


sub do_parse_tag {
	my($op, $base, $file, $type, $text) = @_;
	if($op eq 'flag') {
		do_flag($type,$text);
	}
	elsif ($op eq 'log') {
		do_log($file, $text);
	}
	elsif ($op eq 'each') {
		do_tag("each $base", $text);
	}
	elsif ($op eq 'export') {
		do_export($base, $file, $type);
	}
	elsif (!$op) {
		do_tag('', $text);
	}
	else {
		do_tag(join(" ", $op, $base, $file, $type), $text);
	}
}

# Returns the text of a user entered field named VAR.
sub tag_value {
    my($var,$esc) = @_;
    my($value);

	local($) = 0;
    if (defined ($value = $Vend::Session->{'values'}->{$var})) {
		# Eliminate any MiniVend tags
		$value =~ s/\[/&#91;/g;
		$value =~ s/\]/&#93;/g;
		$value =~ s/(['"])/\\$1/g if $esc;
		return $value;
    }
	else {
		return "";
    }
}

# Returns the contents of a file.  Won't allow any arbitrary file unless
# NoAbsolute is not set.
sub tag_file {
    return readfile($_[0], $Global::NoAbsolute);
}

# Returns the text of a user entered field named VAR.
# Same as tag value except returns 'default' if not present
sub tag_default {
    my($var) = @_;
    my($value);
	my $default = 'default';
	if($var =~ /\s/) {
		($var, $default) = split /\s+/, $var, 2;
	}
    if (defined ($value = $Vend::Session->{'values'}->{$var}) and $value) {
	return $value;
    } else {
	return $default;
    }
}

# Returns an href which will call up the specified PAGE.

sub tag_page {
    my($page, $arg) = @_;
	if(defined $Vend::Cfg->{StaticPage}->{$page} and !$arg) {
	  $page .= $Vend::Cfg->{StaticSuffix};
	  return '<a href="' . vendUrl($page,$arg,$Vend::Cfg->{StaticPath}) . '">';
	}
    '<a href="' . vendUrl($page,$arg || undef) . '">';
}

# Returns an href which will call up the specified PAGE with TARGET reference.

sub tag_pagetarget {
    my($page,$target,$arg) = @_;
    my($r);

	if(defined $Vend::Cfg->{StaticPage}->{$page} and !$arg) {
		$page .= $Vend::Cfg->{StaticSuffix};
    	$r  = '<a href="' . vendUrl($page,'',$Vend::Cfg->{StaticPath});
	}
	else {
    	$r  = '<a href="' . vendUrl($page, $arg || undef);
	}

    $r .= '" TARGET="' . $target
        if defined $target and $Vend::Session->{'frames'};
    $r .= '">';
}

# Returns an href which will call up the specified PAGE.

sub tag_area {
    my($area, $arg) = @_;

	if(defined $Vend::Cfg->{StaticPage}->{$area} and ! $arg) {
		$area .= $Vend::Cfg->{StaticSuffix};
    	return vendUrl($area,'',$Vend::Cfg->{StaticPath});
	}
    vendUrl($area, $arg);
}

# Returns an href which will call up the specified PAGE with TARGET reference.

sub tag_areatarget {
    my($area, $target, $arg) = @_;
	my($r);

	if(defined $Vend::Cfg->{StaticPage}->{$area} and ! $arg) {
		$area .= $Vend::Cfg->{StaticSuffix};
    	$r = vendUrl($area,'',$Vend::Cfg->{StaticPath});
	}
    else {
        $r = vendUrl($area, $arg || undef);
    }

	$r .= '" TARGET="' . $target
		if $Vend::Session->{'frames'};
	$r;
}

# Sets the default shopping cart for display
sub tag_cart {
	my($cart) = @_;
	defined $cart
		and ref $Vend::Session->{'carts'}->{$cart}
	    and
		$Vend::Items = $Vend::Session->{'carts'}->{$cart};
	return '';
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
	my $ceiling = $_[0] || @{$Vend::Cfg->{'Rotate'}} || return '';

	$ceiling = $ceiling - 1;

    my $rotate;
	$rotate = $Vend::Session->{'rotate'} || 0;
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
	my($buttonbar) = @_;
    if (defined $Vend::Cfg->{'ButtonBars'}->[$buttonbar]) {
		return $Vend::Cfg->{'ButtonBars'}->[$buttonbar];
	}
	else {
		return '';
	}
}

# Returns an href to call up the last page visited.

sub tag_last_page {
	my ($target, $arg) = @_;
    my $page = $Vend::Session->{'page'};
    defined $target ?
		return tag_page($page, $arg || undef) :
		return tag_pagetarget($page, $target, $arg || undef) ;
}

# Returns the shipping description.

sub tag_shipping_desc {
	my $mode = 	shift ||
				do {
					$CacheInvalid = 1 if 
					$Vend::Session->{'values'}->{'mv_shipmode'};
					$Vend::Session->{'values'}->{'mv_shipmode'};
				}	||
				'default';
	return '' unless defined $Vend::Cfg->{'Shipping_desc'}->{$mode};
	$Vend::Cfg->{'Shipping_desc'}->{$mode};
}

# Returns the total cost of items ordered.

sub tag_total_cost {
	my($cart) = @_;
    my($total, $i, $save);

	if ($cart) {
		$save = $Vend::Items;
		tag_cart($cart);
	}

	$total = 0;

	my $shipping = shipping();
	if(defined $Vend::Session->{'values'}->{mv_handling}) {
		my @modes = split /[\s\0,]+/, $Vend::Session->{'values'}->{mv_handling};
		for(@modes) {
			$total += custom_shipping($_);
		}
	}

    $total += subtotal();

    $total += $shipping;
    $total += salestax();
	$Vend::Items = $save if defined $save;
    currency($total);
}

# Returns the href to process the completed order form or do the search.

sub tag_process_target {
	my($frame,$security) = @_;
	my $frametag = '';

	if($frame and $Vend::Session->{'frames'}) {
    	$frametag = '" TARGET="'. $frame
			unless ! defined $frame or $frame eq 'none'
					    or
					$Vend::Session->{scratch}->{mv_ignore_frame};
	}

	if ("\L$security" eq 'secure') {
    	secure_vendUrl('process') . $frametag;
	}
	else {
    	vendUrl('process') . $frametag;
	}
}

sub tag_process_search {
	my($arg) = @_;
	my $frametag = '';
	if($Vend::Session->{'frames'} and
		! $Vend::Session->{scratch}->{mv_ignore_frame} )
	{
    	$frametag = '" TARGET="' .  ($arg || $Vend::Cfg->{'SearchFrame'});
	}
    return vendUrl('search') . $frametag; 
}

sub tag_process_order {
	my($arg) = @_;
	my $frametag = '';

	if($Vend::Session->{'frames'}) {
    	$frametag = '" TARGET="' . ($arg || '_self')
			unless $Vend::Session->{scratch}->{mv_ignore_frame};
	}

	if ($Vend::Session->{'secure'}) {
    	secure_vendUrl('process') . $frametag;
	}
	else {
    	vendUrl('process') . $frametag;
	}
}

sub tag_calc {
	my($body) = @_;
	my $result = 0;

	$result = $ready_safe->reval($body);
	if ($@) {
		logGlobal("Safe: $@\n$body\n");
		return 0;
	}
	return $result;
}

sub tag_self_contained_if {
	my($base, $term, $operator, $comp, $body) = @_;

	my ($else,$elsif,$else_present);
	
	local($) = 0;
print("Calling self_if with base=$base term=$term op=$operator comp=$comp\n") if $Global::DEBUG;
	if ($body =~ s#^\s*$T{'condition'}\]([\000-\377]*?)$T{'/condition'}\]##o) {
		$comp = $1;
	}

	$else_present = 1 if
		$body =~ /\[[EeTt][hHLl][SsEe]/;

	($body, $elsif, $else) = split_if($body)
		if $else_present;

#print("self_if body=" . substr($body, 0, 20) . "... else=" .  substr($else, 0, 20) . "...\n") if $Global::DEBUG;

	unless(defined $operator || defined $comp) {
		$comp = '';
		undef $operator;
		undef $comp;
	}

	my $status = conditional ($base, $term, $operator, $comp);

	if($status) {
		return interpolate_html($body);
	}
	elsif ($elsif) {
		$else = '[else]' . $else . '[/else]' if $else;
		$elsif =~ s#(.*?)$T{'elsif'}\](.*)#$1${2}[/elsif]#s;
		return interpolate_html('[if ' . $elsif . $else . '[/if]');
	}
	elsif ($else) {
		return interpolate_html($else);
	}
	else {
		return '';
	}
	

}

	
sub pull_if {
	my($string) = @_;
	$string =~ s:$T{'else'}\]([\000-\377\s]*?)$T{'/else'}\]::o;
	return $string;
}

sub pull_else {
	my($string) = @_;
	my($r);
	if($string =~ s:$T{'else'}\]([\000-\377\s]*?)$T{'/else'}\]::o) {
		$r = $1;
	}
	else {
		$r = '';
	}
	$r;
}

## ORDER PAGE

# NOAUTO
my (@Opts);
my (@Flds);
my %Sort = (
# END NOAUTO

# AUTOLOAD
#%Sort = (
# END AUTOLOAD
	''	=> sub { $a cmp $b				},
	none	=> sub { $a cmp $b				},
	f	=> sub { (lc $a) cmp (lc $b)	},
	fr	=> sub { (lc $b) cmp (lc $a)	},
	n	=> sub { $a <=> $b				},
	nr	=> sub { $b <=> $a				},
	r	=> sub { $b cmp $a				},
	rf	=> sub { (lc $b) cmp (lc $a)	},
	rn	=> sub { $b <=> $a				},
);


# AUTOLOAD
#%Sort_field = (
# END AUTOLOAD

# NOAUTO
my %Sort_field = (
# END NOAUTO

	none	=> sub { $_[0] cmp $_[1]			},
	f	=> sub { (lc $_[0]) cmp (lc $_[1])	},
	fr	=> sub { (lc $_[1]) cmp (lc $_[0])	},
	n	=> sub { $_[0] <=> $_[1]			},
	nr	=> sub { $_[1] <=> $_[0]			},
	r	=> sub { $_[1] cmp $_[0]			},
	rf	=> sub { (lc $_[1]) cmp (lc $_[0])	},
	rn	=> sub { $_[1] <=> $_[0]			},
);

sub field_sort {
	my(@a) = split /\t/, $a;
	my(@b) = split /\t/, $b;
	my ($r, $i);
	for($i = 0; $i < @Flds; $i++) {
		$r = &{$Sort_field{$Opts[$i]}}($a[$Flds[$i]], $b[$Flds[$i]]);
		return $r if $r;
	}
}

sub tag_sort {
    my($opts, $list, $joiner) = (@_); 
    $list =~ s/^\s+//; $opts =~ s/^\s+//; 
    $list =~ s/\s+$//; $opts =~ s/\s+$//; 
	$joiner = " " unless defined $joiner;
	my @codes;
	unless (ref $list) {
		@codes = split /\s+/, $list;
	}
	else {
		undef $joiner;
	}

    my @opts =  split /\s+/, $opts;
    my @option; my @bases; my @fields;
 
    for(@opts) {
        my ($base, $fld, $opt) = split /:/, $_;
        push @bases, $base;
        push @fields, $fld;
        push @option, (defined $Sort_field{$opt} ? $opt : 'none');
    }
 
    my $i;
    my $routine = 'sub { ';
    for( $i = 0; $i < @bases; $i++) {
            $routine .= '&{$Sort_field{"' . $option[$i] . '"}}(' . "\n";
            $routine .= "tag_data('$bases[$i]','$fields[$i]'," . '$a),' . "\n";
            $routine .= "tag_data('$bases[$i]','$fields[$i]'," . '$b) ) or ';
    }
    $routine .= '0 or &{$Sort_field{"none"}}($a,$b); }';
print("Sort routine: $routine\n") if $Global::DEBUG;
    my $code = eval $routine;  
    die "Bad sort routine\n" if $@;

	#Prime the sort? Prevent variable suicide??
	&{$Sort_field{'n'}}('31', '30');

	if(defined $joiner) {
		return join $joiner, sort {&$code} @codes;
	}
	else {
		@codes =  sort {&$code} @$list;
		return \@codes;
	}
}

my %Prev;

sub check_change {
	my($name, $value) = @_;
	my $prev = $Prev{$name} || undef;
	$Prev{$name} = $value || '';
	return 1 unless defined $prev;
	return $value eq $prev ? 0 : 1;
}

sub tag_search {
	my($params) = @_;
	my $c = {mv_list_only => 1};
	Vend::Scan::find_search_params($c, $params);
	my $out = Vend::Scan::perform_search($c);
	return join "\n", @$out;
}

sub tag_search_list {
    my($text,$obj,$q) = @_;
    my($r, $i, $item, $code, $db, $link);
	my($linkvalue, $run, $count, %field_hash);
	my($fields, @fields);
	my $g = $q->{'global'};

	# get the number to start the increment from
	$count = $g->{first_match};

    $r = "";
	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};
	my $linkdir = $Vend::Cfg->{'ItemLinkDir'};
	my $delim =  $g->{return_delim} || "\t";

#	if($text =~ s/$T{'onchange'}(?:\s+)?($Codere)\]//i) {
#		my %seen;
#		local($ = 0);
#		@$obj = grep ((m:^([^\t]+): && ! $seen{$1}++), @$obj);
#	}

	if($text =~ s/$T{'uniq'}\]//i) {
		my %seen;
		local($ = 0);
		@$obj = grep ((m:^([^\t]+): && ! $seen{$1}++), @$obj);
	}

	if(ref ($fields = $g->{field_names} ) ) {
		my $ptr = 0;
		my(@fieldnames);
		@fieldnames = @{$fields}[@{$g->{return_fields}}]
			if ref $g->{return_fields};
		for(@fieldnames) {
			$field_hash{$_} = $ptr++;
#print("Sorting on field $_\n") if $Global::DEBUG;
		}
		
	}
			

	SORT: {
		last SORT unless $text =~ m!$T{'sort'}!i;
		my $options = '';

		if ($text =~ s!$T{'sort'}\]([\000-\377]*?)$T{'/sort'}\]!!o) {
			$options = $1;
			$options = scan_html($options);
		}
		elsif ($text =~ s!$T{'sort'}([^\]]*)\]!!o) {
			$options = $1;
			$options = scan_html($options);
		}
			
		$options =~ s/^\s+//;
		$options =~ s/\s+$//;

		if($options =~ m#^$Coderex:$Coderex(?::[NnRrRf]{0,2})?($|\s)#o) {
				$obj = tag_sort($options, $obj);
		}
		elsif($options =~ m:^[nrf]{0,2}$:i) {
			(
			logError("Bad sort options $options in search on page "
					  . $g->{search_page} ),
			$options = ""
			) unless defined $Sort{lc $options};

			@$obj = sort { &{$Sort{lc $options}} } @$obj;
		}
		else {
			@Flds = split /\s+/, $options;
			@Opts = ();
			my ($opt, $fld);
			for(@Flds) {
				$opt = 'none';
				s/:(.*)// and $opt = $1 || 'none';
				s/(.*\D.*)/$field_hash{$1}/;
				push @Opts, $opt;
				(
				  logError("Bad sort field $_ in search on page "
							  . $g->{search_page} ),
				  last SORT
				) unless /^\d+$/;
			}
#print("Flds: @Flds\nOpts: @Opts\n") if $Global::DEBUG;
			@$obj = sort { field_sort() } @$obj;

		}
		
	}

	# Zero the on-change hash
	undef %Prev;

    foreach $item (@$obj) {
		chomp($item);
		@fields = split /$delim/o, $item;
		
		#($code, $link) = split(/\s+/,$item, 2);
		#$link = $code if is_yes($Vend::Cfg->{'UseCode'});
		$link = $code = $fields[0];

		$count++;

	    $run = $text;
	    $run =~ s:$T{'item-param'}\s+(\d+)\]:$fields[$1]:go;
	    $run =~ s:$T{'item-param'}\s+($Codere)\]:$fields[$field_hash{$1}]:go;
		$run =~ s#$T{'if-field'}\s+($Codere)\]([\000-\377]*?)$T{'/if-field'}\]#
				  product_field($1, $code)	?	pull_if($2)
											:	pull_else($2)#geo;
		$run =~ s#$T{'if-data'}\s+($Codere)\s+($Codere)\]
					([\000-\377]*?)
					$T{'/if-data'}\]#
                  tag_data($1,$2,$code)    ?   pull_if($3)
                                           :   pull_else($3)#xgeo;
	    $run =~ s:$T{'item-increment'}\]:$count:go;
		$run =~ s:$T{'item-accessories'}(\s+[^\]]+)?\]:
						tag_accessories($code,'',$1):geo;
	    $run =~ s:$T{'item-code'}\]:$code:go;
		$run =~ s:$T{'item-data'}\s+($Codere)\s+($Codere)\]:
							tag_data($1,$2,$code):geo;
	    $run =~ s:$T{'item-description'}\]:trim_desc(product_description($code)):geo;
	    $run =~ s:$T{'item-field'}\s+($Codere)\]:product_field($1, $code):geo;
	    $run =~ s#$T{'item-link'}\]#"[page $linkdir$link]"
	  			. $linkvalue . '[/page]'#geo;
	    $run =~ s!$T{'item-price'}(?:\s+)?(\d+)?\]!
					currency(product_price($code,$1))!geo;

		1 while $run =~ s!	$T{'on-change'} \s+ ($Codere)\] \s*
						$T{'condition'}\]
						([\000-\377]*?)
						$T{'/condition'}\]
						([\000-\377]*?)
					$T{'/on-change'} \s+ \1 \]!
							check_change($1,$2)
											?	pull_if($3)
											:	pull_else($3)!xgeo;

		$r .= $run;
    }
    $r;
}

sub tag_more_list {
	my($r,$q,$next_anchor, $prev_anchor, $page_anchor, $border) = @_;
	my($arg,$inc,$last,$m);
	my($adder,$current,$pages);
	my $next_tag = '';
	my $list = '';
	my $session = $q->{global}->{session_key};
	my $first = $q->{global}->{first_match};
	my $mod   = $q->{global}->{search_mod};
	my $chunk = $q->{global}->{match_limit};
	my $total = $q->{global}->{matches};
	my $next = $q->{global}->{next_pointer};
	$border = qq{ BORDER="$border"} if defined $border;

	if($chunk >= $total) {
		return '';
	}

	$adder = ($total % $chunk) ? 1 : 0;
	$pages = int($total / $chunk) + $adder;
	$current = int($next / $chunk) || $pages;


	if($first) {
		unless (defined $prev_anchor) {
			$prev_anchor = 'Previous';
		}
		elsif ($prev_anchor ne 'none') {
			$prev_anchor = qq%<IMG SRC="$prev_anchor"$border>%;
		}
		unless ($prev_anchor eq 'none') {
			$arg = $session;
			$arg .= ':';
			$arg .= $first - $chunk;
			$arg .= ':';
			$arg .= $first - 1;
			$arg .= ":$chunk:$mod";
			$list .= '<A HREF="';
			$list .= vendUrl('search', $arg);
			$list .= '">';
			$list .= $prev_anchor;
			$list .= '</A>';
		}
	}
	
	if($next) {
		unless (defined $next_anchor) {
			$next_anchor = 'Next';
		}
		else {
			$next_anchor = qq%<IMG SRC="$next_anchor"$border>%;
		}
		$last = $next + $chunk - 1;
		$last = $last > ($total - 1) ? $total - 1 : $last;
		$arg = "$session:$next:$last:$chunk:$mod";
		$next_tag .= '<A HREF="';
		$next_tag .= vendUrl('search', $arg);
		$next_tag .= '">';
		$next_tag .= $next_anchor;
		$next_tag .= '</A>';
	}
	
	unless (defined $page_anchor) {
		$page_anchor = '__PAGE__';
	}
	elsif ($page_anchor ne 'none') {
		$page_anchor = qq%<IMG SRC="$page_anchor?__PAGE__"$border>%;
	}

	my $pa;
	foreach $inc (1..$pages) {
		last if $page_anchor eq 'none';
		$pa = $page_anchor;
		$pa =~ s/__PAGE__/$inc/g;
		$next = ($inc-1) * $chunk;
		$last = $next + $chunk - 1;
		$last = ($last+1) < $total ? $last : ($total - 1);
		if($inc == $current) {
			$list .= qq|<STRONG>$pa</STRONG> |;
		}
		else {
			$arg = "$session:$next:$last:$chunk:$mod";
			$list .= '<A HREF="';
			$list .= vendUrl('search', $arg);
			$list .= '">';
			$list .= $pa;
			$list .= '</A> ';
		}
	}

	$list .= $next_tag;

	$first = $first + 1;
	$last = $first + $chunk - 1;
	$last = $last > $total ? $total : $last;
	$m = $first . '-' . $last; 
	$r =~ s/$T{'more'}\]/$list/ge;
	$r =~ s/$T{'matches'}\]/$m/ge;

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

=head2 C<wrap($str, $width)>

Wraps the passed string to fit the specified maximum width.  An array
of lines, each $width or less, is returned.  The line is wrapped at a
space if one exists in the string.

(The function could also wrap on other characters, such as a dash, but
currently does not).

=cut

sub wrap {
    my ($str, $width) = @_;
    my @a = ();
    my ($l, $b);

    for (;;) {
        $str =~ s/^ +//;
        $l = length($str);
        last if $l == 0;
        if ($l <= $width) {
            push @a, $str;
            last;
        }
        $b = rindex($str, " ", $width - 1);
        if ($b == -1) {
            push @a, substr($str, 0, $width);
            $str = substr($str, $width);
        }
        else {
            push @a, substr($str, 0, $b);
            $str = substr($str, $b + 1);
        }
    }
    return @a;
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
	while( $text =~ s!	$T{'col'}(?:[uU][mM][Nn])?\s+
				 		([^\]]+)
				 		\]
				 		([\000-\377]*?)
				 		$T{'/col'}(?:[uU][mM][Nn])?\] !!xi    ) {
		$spec = $1;
		$col = $2;
		$lines[$i] = [];
		@{$lines[$i]} = tag_column($spec,$col);
		# Discover X dimension
		$len[$i] = length(${$lines[$i]}[0]);
		if(defined ${$lines[$i]}[1] and ${$lines[$i]}[1] =~ /^<\s*input\s+/i) {
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

sub sort_cart {
	my($options, $cart) = @_;
	my ($item,$code);
	my %order; my @codes; my @out;
	my $sort_order;
	foreach $item  (@$cart) {
		$code = $item->{'code'};
		$order{$code} = [] unless defined $order{$code};
		push @{$order{$code}}, $item;
		push @codes, $code;
	}

	$sort_order = tag_sort($options, \@codes);

	foreach $code (@$sort_order) {
		push @out, @{$order{$code}};
	}
	return \@out;
}

sub tag_item_list {
	my($cart,$text) = @_;
	my($r, $i, $item, $link, $code, $db, $linkvalue, $run);
	$r = "";

#print("Called tag_item_list with cart=$cart text=$text\n") if $Global::DEBUG;

	$cart = get_cart($cart);
	$CacheInvalid = 1;

	# See if we are to sort, and do so
	if($text =~ s#^\s*$T{'sort'}([^\]]*)\]##o) {
		$cart = sort_cart( $1, $cart);
	}

	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};
	my $linkdir = $Vend::Cfg->{'ItemLinkDir'};

	foreach $i (0 .. $#$cart) {
		$item = $cart->[$i];
		next if $code = $Vend::Cfg->{TransparentItem} and is_yes($item->{$code});
		$code = $item->{'code'};

		$run = $text;
		$run =~ s#$T{'if-field'}\s+($Codere)\]([\000-\377]*?)$T{'/if-field'}\]#
				  item_field($item,$1)	?	pull_if($2)
										:	pull_else($2)#geo;
		$run =~ s#$T{'if-data'}\s+($Codere)\s+($Codere)\]
					([\000-\377]*?)
					$T{'/if-data'}\]#
				  tag_data($1,$2,$code)	?	pull_if($3)
												:	pull_else($3)#xgeo;
		$run =~ s#$T{'if-modifier'}\s+($Codere)\]([\000-\377]*?)$T{'/if-modifier'}\]#
				  $item->{$1}	?	pull_if($2)
								:	pull_else($2)#geo;
		$run =~ s:$T{'item-increment'}\]:$i + 1:geo;
		$run =~ s:$T{'item-accessories'}(\s+[^\]]+)?\]:
						tag_accessories($code,$item,$1):geo;
		$run =~ s:$T{'item-data'}\s+($Codere)\s+($Codere)\]:
							tag_data($1,$2,$code):geo;
		$run =~ s:$T{'item-quantity'}\]:$item->{'quantity'}:go;
		$run =~ s:$T{'item-modifier'}\s+(\w+)\]:$item->{$1}:go;
		$run =~ s:$T{'quantity-name'}\]:quantity$i:go;
		$run =~ s:$T{'modifier-name'}\s+(\w+)\]:$1$i:go;
		$run =~ s:$T{'item-subtotal'}\]:currency(item_subtotal($item)):geo;
		$run =~ s:$T{'item-code'}\]:$code:go;
		$run =~ s:$T{'item-field'}\s+($Codere)\]:item_field($item, $1):geo;
		$run =~ s:$T{'item-description'}\]:trim_desc(item_description($item)):geo;
		$run =~ s#$T{'item-link'}\]#"[page $linkdir$code]"
				  . $linkvalue . '[/page]'#geo;
		$run =~ s!$T{'item-price'}(?:\s+)?(\d+)?\]!
					currency(item_price($item,$1))!geo;
		$run =~ s!$T{'discount-price'}(?:\s+)?(\d+)?\]!
					currency(discount_price($item->{code},
											item_price($item,$1),
											$item->{quantity}))!geo;
		$run =~ s!$T{'item-discount'}\]!
					currency(item_discount($item->{code},
											item_price($item),
											$item->{quantity}))!geo;
		$r .= $run;
	}
	$r;
}

sub tag_sql_list {
    my($text,$obj) = @_;
    my($r, $i, $item, $code, $db, $link);
	my($linkvalue, $run, $count);
    my($Codere) = '[\w-_#/.]+';

	# get the number to start the increment from
	$count = 0;

    $r = "";
	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};
	my $linkdir = $Vend::Cfg->{'ItemLinkDir'};

    foreach $item (@$obj) {
		$code = $item->[0];
		next unless $code;

		# Uncomment next line to ignore non-database items
		# next unless product_code_exists_ref($code);

		$count++;

	    $run = $text;
	    $run =~ s:$T{'msql-param'}\s+(\d+)\]:$item->[$1]:go;
		$run =~ s#$T{'if-msql-field'}\s+($Codere)\]
						([\000-\377]*?)
				  $T{'/if-msql-field'}\]#
				  product_field($1, $code)	?	pull_if($2)
											:	pull_else($2)#xgeo;
		$run =~ s#$T{'if-msql-data'}\s+($Codere)\s+($Codere)\]
					([\000-\377]*?)
					$T{'/if-msql-data'}\]#
				  tag_data($1,$2,$code)	?	pull_if($3)
												:	pull_else($3)#xgeo;
	    $run =~ s:$T{'msql-increment'}\]:$count:go;
	    $run =~ s:$T{'msql-code'}\]:$code:go;
		$run =~ s:$T{'msql-data'}\s+($Codere)\s+($Codere)\]:
							tag_data($1,$2,$code):geo;
	    $run =~ s:$T{'msql-description'}\]:trim_desc(product_description($code)):geo;
	    $run =~ s:$T{'msql-field'}\s+($Codere)\]:product_field($1, $code):geo;
	    $run =~ s#$T{'msql-link'}\]#"[page $linkdir$link]"
	  			. $linkvalue . '[/page]'#geo;
	    $run =~ s!$T{'msql-price'}(?:\s+)?(\d+)?\]!
					currency(product_price($code,$1))!geo;

	  $r .= $run;
    }
    $r;
}

sub loop_substitute {
	my ($code,$run,$i) = @_;

	$run =~ s#$T{'if-loop-field'}\s+($Codere)\]
					([\000-\377]*?)
				$T{'/if-loop-field'}\]#
			  product_field($1,$code)	?	pull_if($2)
										:	pull_else($2)#xgeo;
	$run =~ s#$T{'if-loop-data'}\s+($Codere)\s+($Codere)\]
				([\000-\377]*?)
				$T{'/if-loop-data'}\]#
			  tag_data($1,$2,$code)	?	pull_if($3)
									:	pull_else($3)#xgeo;
	$run =~ s:$T{'loop-increment'}\]:$i:xgo;
	$run =~ s:$T{'loop-accessories'}(\s+[^\]]+)?\]:tag_accessories($code,'',$1):geo;
	$run =~ s:$T{'loop-data'}\s+($Codere)\s+($Codere)\]:
						tag_data($1,$2,$code):geo;
	$run =~ s:$T{'loop-code'}\]:$code:go;
	$run =~ s:$T{'loop-field'}\s+($Codere)\]:product_field($1, $code):geo;
	$run =~ s:$T{'loop-description'}\]:trim_desc(product_description($code)):geo;
	$run =~ s#$T{'loop-link'}\]#"[page " . $Vend::Cfg->{'ItemLinkDir'} . "$code]"
			  . $Vend::Cfg->{'ItemLinkValue'} . '[/page]'#geo;
	$run =~ s!$T{'loop-price'}(?:\s+)?(\d+)?\]!
				currency(product_price($code,$1))!geo;

	1 while $run =~ s!	$T{'loop-change'} \s+ ($Codere)\] \s*
					$T{'condition'}\]
					([\000-\377]*?)
					$T{'/condition'}\]
					([\000-\377]*?)
				$T{'/loop-change'} \s+ \1 \]!
						check_change($1,$2)
										?	pull_if($3)
										:	pull_else($3)!xgeo;
					
	return $run;
}

sub tag_loop_list {
	my($list,$text) = @_;
	my($r, $i, $link, $code, $db, $linkvalue, $run);
	my(@list);
	my(@post);
	# Allow nesting.  Starts saved area at first loop substitution
	# AFTER the first right-bracket. 
	$i = 0;
	while( $text =~ s!($T{'loop'}\s+[\000-\377]+?$T{'/loop'}\])!'__POST' . $i . '__'!eix ) {
		$post[$i++] = $1;
	}

	$r = "";
	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};
	$list =~ s/[\0\s]+$//;

	# See if we are to sort, and do so
	if($text =~ s#^\s*$T{'sort'}([^\]]*)\]##) {
		$list = tag_sort( $1, $list, "\n");
	}

	# Allow newlines for search lists, as they are transparent
	# Will work fine for others as well
	# Too bad if you have leading/trailing spaces in list!
	if($list =~ /\n/) {
		@list = split /\n/, $list;
	}
	else {
		@list = quoted_comma_string($list);
	}

	$i = 1;
	undef %Prev;
	foreach $code (@list) {
		$r .= loop_substitute($code, $text, $i);
		$i++;
	}

	#undo nesting if appropriate
	$r =~ s!__POST(\d+)__!$post[$1]!g if @post;

	$r;
}

# Displays a search page with the special [search-list] tag evaluated.

sub search_page {

	my($q,$o) = @_;
    my($page);
	my $key = $q->{global}->{cache_key} || '';

	if (($page = $q->{global}->{search_page}) ) {
    	$page = readin($page);
	}
	elsif($Vend::Cfg->{'FrameSearchPage'} && $Vend::Session->{'frames'}) {
    	$page = readin($Vend::Cfg->{'FrameSearchPage'});
	}
    else {
    	$page = readin($Vend::Cfg->{'Special'}->{'search'});
	}

 	unless (defined $page) {
		logError("Missing special page: $page");
		logGlobal("Missing special page: $page");
		return main::response('plain', "No search page '$page' found!");
	}

	my $no_match_found = 0;

	# passing the list reference here
	if(@$o) {
		$page =~ s:$T{'search-list'}\]([\000-\377]*?)$T{'/search-list'}\]:
				  tag_search_list($1,$o,$q):geo;
		$page =~ s!
					$T{'more-list'}
						(?:\s+)?($Coderex)?
						(?:\s+)?($Coderex)?
						(?:\s+)?($Coderex)?
						(?:\s+)?($Coderex)?
						\]([\000-\377]*?)$T{'/more-list'}\]!
				  tag_more_list($5,$q,$1,$2,$3,$4)!xgeo;
		$page =~ s:$T{'no-match'}([\000-\377]*?)$T{'/no-match'}\]::geo;
	}
	else {
		$page =~ s:$T{'search-list'}\]([\000-\377]*?)$T{'/search-list'}\]::geo;
		$page =~ s!
					$T{'more-list'}
						(?:\s+)?($Coderex)?
						(?:\s+)?($Coderex)?
						(?:\s+)?($Coderex)?
						\]([\000-\377]*?)$T{'/more-list'}\]!
				  !xgeo;
		$page =~ s:$T{'no-match'}([\000-\377]*?)$T{'/no-match'}\]:$1:geo
					or do {
						my $subj = join "|", @{$q->{specs}};
						::display_special_page(
							$Vend::Cfg->{Special}->{nomatch}, $subj);
						return 0;
					};
	}

	# This is a fake search from the page builder
	# Doesn't return response, just returns page if not dynamic
	if (defined $Vend::BuildingPages) {
		$page = cache_html($page);
		return $page
			if defined $Vend::CachePage or defined $Vend::ForceBuild;
		return undef;
	}

	# add to cache if appropriate
	if($key) {

		my $ref;
		$page = interpolate_html($page);
		logData($Vend::Cfg->{'LogFile'}, format_log_msg('add to search cache'))
			if defined $Vend::Cfg->{CollectData}->{cache};
		open(SEARCHCACHE, ">$Vend::Cfg->{ScratchDir}/SearchCache/$key.html")
			or die "Cache failure: $!\n";
		print SEARCHCACHE $page;
		close SEARCHCACHE;
		return main::response('html', $page);
	}

    main::response('html',interpolate_html($page));

}


# Tries to display the on-the-fly page if page is missing
sub fly_page
{
	my($code, $argument) = @_;
	$code =~ s:.*/::;
    my($page,$selector,$db);
    my($Codere) = '[\w-_#/.]+';

	my $base = product_code_exists_ref($code, $argument || undef);
	return undef unless $base;

    if($selector = $Vend::Cfg->{'PageSelectField'}) {
		if(db_column_exists($base,$selector)) {
#print("fly_page\n") if $Global::DEBUG;
			$selector = database_field($base, $code, $selector);
		}
		else {
			logError("PageSelectField column '$selector' doesn't exist") ;
		}
	}
	else {
		$selector = $Vend::Cfg->{'FrameFlyPage'}
			if $Vend::Session->{frames};
	}

	$selector = $Vend::Cfg->{'Special'}->{'flypage'}
		unless $selector;

    $page = readin($selector);
    return undef unless defined $page;

	$page =~ s#$T{'if-field'}\s+($Codere)\]([\000-\377]*?)$T{'/if-field'}\]#
			     database_field($base,$code,$1)	?	pull_if($2)
												:	pull_else($2)#geo;
	$page =~ s#$T{'if-data'}\s+($Codere)\s+($Codere)\]
				([\000-\377]*?)
				$T{'/if-data'}\]#
				  tag_data($1,$2,$code) ?	pull_if($3)
										:	pull_else($3)#xgeo;
    $page =~ s!$T{'item-code'}\]!$code!go;
	$page =~ s:$T{'item-accessories'}(\s+[^\]]+)?\]:tag_accessories($code,'',$1):geo;
    $page =~ s!$T{'item-description'}\]!
					database_field($base,$code,$Vend::Cfg->{DescriptionField})!geo;
	$page =~ s!$T{'item-price'}(?:\s+)?(\d+)?\]!
					currency(product_price($code,$1 || 1,$base))!geo;
	$page =~ s:$T{'item-field'}\s+($Codere)\]:database_field($base,$code,$1):geo;
	$page =~ s:$T{'item-data'}\s+($Codere)\s+($Codere)\]:
							tag_data($1,$2,$code):geo;

    $page;
}

sub order_page {
    my($which) = @_;
	defined $which or $which = '';
    my $page;


	if( ! $which and $Vend::Cfg->{'FrameOrderPage'} and
	   $Vend::Session->{'frames'}) {
    	$which = $Vend::Cfg->{'FrameOrderPage'};
	}
    else {
		$which = $Vend::Cfg->{'Special'}->{'order'} unless $which;
	}

	$page = readin($which);

 	unless (defined $page) {
		logError("Missing special page: $which");
		logGlobal("Missing special page: $which");
		return main::response('plain', "No page defined!");
	}
    main::response('html',interpolate_html($page));
}

sub tag_shipping {
	currency(shipping(@_));
}

sub shipping {
	if($Vend::Cfg->{'CustomShipping'}) {
		return custom_shipping(@_);
	}
	else {
		return $Vend::Cfg->{'Shipping'};
	}
}

sub item_discount {
	my($code,$price,$q) = @_;
	return $price - discount_price($code,$price,$q);
}

sub discount_price {
	my ($code, $price, $quantity) = @_;
	$Vend::Interpolate::q = $quantity || 1;
	my ($discount, $return);
	return $price unless defined $Vend::Session->{discount};
	for($code, 'ALL_ITEMS') {
		next unless $discount = $Vend::Session->{discount}->{$_};
		$Vend::Interpolate::s = $return = $price;
		$ready_safe->share('$s', '$q');
        $return = $ready_safe->reval($discount);
		if($@) {
			$return = $price;
			next;
		}
        $price = $return;
    }
	return $price;
}

sub apply_discount {
	my($item) = @_;

	my($formula, $cost);
	my(@formulae);

	# Check for individual item discount
	push(@formulae, $Vend::Session->{'discount'}->{$item->{code}})
		if defined $Vend::Session->{'discount'}->{$item->{code}};
	# Check for all item discount
	push(@formulae, $Vend::Session->{'discount'}->{ALL_ITEMS})
		if defined $Vend::Session->{'discount'}->{ALL_ITEMS};

	my $subtotal = item_subtotal($item);

	# Calculate any formalas found
	foreach $formula (@formulae) {
		next unless $formula;
		$formula =~ s/\$q/$item->{quantity}/g; 
		$formula =~ s/\$s/$subtotal/g; 
		$cost = $ready_safe->reval($formula);
		if($@) {
			logError
				"Discount for $item->{code} has bad formula. Not applied.\n$@";
			next;
		}
		$subtotal = $cost;
	}
	$subtotal;
}

sub custom_shipping {
	my($mode, $cart) = @_;
	$mode = 	$mode ||
				$Vend::Session->{'values'}->{'mv_shipmode'} ||
				'default';
    my($save, $qual);

	if ($cart) {
		$save = $Vend::Items;
		tag_cart($cart);
	}
	
	$Vend::Session->{ship_message} = ''
		unless defined $Vend::Shipping_in_progress;
	$Vend::Shipping_in_progress = 1;
	my($field) = $Vend::Cfg->{'CustomShipping'};
	my($code, $i, $total, $cost, $multiplier, $formula);

	if(defined $Vend::Cfg->{'Shipping_criterion'}->{$mode}) {
		$field = $Vend::Cfg->{'Shipping_criterion'}->{$mode};
	}

	$@ = 1;

	# Security hole if we don't limit characters
	$mode !~ /[\s,;{}]/ and 
		eval {'what' =~ /$mode/};

	if ($@) {
		logError("Bad shipping mode '$mode', returning 0");
		$Vend::Items = $save if defined $save;
		return 0;
	}

	# See if the field needs to be returned by a MiniVend function.
	# If a space is encountered, a qualification code
	# will be set up, with any characters after the first space
	# used to determine geography or other qualifier for the mode.
	if($field =~ /[[\s]|__/) {
		($field, $qual) = split /\s+/, interpolate_html($field), 2;
		if($qual =~ /{}/) {
			logError("Bad qualification code '$qual', returning 0");
		}
	}

	# Uses the quantity on the order form if the field is 'quantity',
	# otherwise goes to the database.
    $total = 0;

	if($field =~ /^[\d.]+$/) {
		$total = $field;
	}
	elsif($field eq 'quantity') {
    	foreach $i (0 .. $#$Vend::Items) {
			$total = $total + $Vend::Items->[$i]->{$field};
    	}
	}
	else {
		eval { column_exists $field };
		if($@) {
			logError("Custom shipping field '$field' doesn't exist. Returning 0");
			$Vend::Items = $save if defined $save;
			return 0;
		}
    	foreach $i (0 .. $#$Vend::Items) {
			my $item = $Vend::Items->[$i];
			my $base = product_code_exists_ref($item->{code}, $item->{mv_ib});
			$total += database_field($base, $item->{code}, $field) *
						$item->{'quantity'};
		}
	}
	$Vend::Items = $save if defined $save;

	# We will return from this loop if a match is found
	foreach $code (sort keys %{$Vend::Cfg->{'Shipping_cost'}}) {
		next unless $code =~ /^$mode\d*$/i;
		if($qual) {
			next unless
				$Vend::Cfg->{Shipping_criterion}->{$code} =~ m{\b$qual\b} or
				$Vend::Cfg->{Shipping_criterion}->{$code} =~ /^\s*$/;
		}
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
				if($Vend::Cfg->{OldShipping}) {
					$formula = interpolate_html($formula)
								if $formula =~ /\[\w/;
					$formula =~ s/\bx\b/$total/g;
				}
				else {
					$formula =~ s/\@\@TOTAL\@\@/$total/g;
					$formula = interpolate_html($formula)
								if $formula =~ /\[\w/;
				}
				$cost = $ready_safe->reval($formula);
				if($@) {
					my $msg = "Shipping mode '$mode': bad formula. Returning 0.";
					logError($msg);
					$Vend::Session->{ship_message} .= $msg;
					return 0;
				}
				return $cost;
			}
			elsif ($Vend::Cfg->{'Shipping_cost'}->{$code} =~ /^\s*u/i) {
				my $what = $Vend::Cfg->{'Shipping_cost'}->{$code};
				$what =~ s:\s*u\s*::;
				my ($type, $geo, $adder, $mod, $sub);
				if($Vend::Cfg->{OldShipping}) {
					$what =~ m:u\s*([-\w]+)\s+([-\d]+):i;
					$what = interpolate_html($what);
					$type = $1;
					$geo = $2;
					unless ($geo =~ /^\d\d\d/) {
						$Vend::Session->{ship_message} .= "No zip code\n";
						return undef;
					}
					$cost = tag_ups($type,$geo,$total) and return $cost;
				}
				else {
					$what = interpolate_html($what);
					($type, $geo, $adder, $mod, $sub) = split /\s+/, $what, 5;
					$cost = tag_ups($type,$geo,$total);
					FIGURE: {
						last FIGURE unless $cost;
						$cost = $cost + $adder if defined $adder;
						if(defined $mod) {
							$cost = ceil($cost) if $mod =~ /round/;
							if($mod =~ /min([\d.]+)/) {
								my $min = $1;
								$cost = $cost > $min ? $cost : $min;
							}
						}
					}
					if(defined $sub) {
						$sub =~ s/\@\@COST\@\@/$cost/g;
						$sub =~ s/\@\@TYPE\@\@/$type/g;
						$sub =~ s/\@\@ADDER\@\@/$adder/g;
						$sub =~ s/\@\@GEO\@\@/$geo/g;
						$sub =~ s/\@\@TOTAL\@\@/$total/g;
						$cost = tag_perl("sub", $sub);
					}
					return $cost if $cost;
				}
			}
			elsif ($Vend::Cfg->{'Shipping_cost'}->{$code} =~
                      m/^\s*s\s+   # Beginning s call with mandatory whitespace
                        (\w+)      # subroutine name
                        [\s(]*     # whitespace or open parens
                        (.*)       # Parameter mess
                        [\s)]*     # Possible closing paren or whitespace
                        /xi)
			{
				my $what = $1;
				my $params = $2 || '';
				my @fixed;
				if($params =~ /\S/) {
					my $item;
					my @calls;
					my (@params) = split /\s*,\s*/, interpolate_html($params);
					my($call, $routine, $database, $field, $code);
					my(@args);
					foreach $item (@params) {
						if($item =~ /^;(.*)/) {  # Fixed value
							push @fixed, $1;
							next;
						}
						# Just a field and optional fixed key
						elsif( $item =~ /^($Codere)\s*(;\s*(.*))?$/o) {
							$field = $1;
							$database = '';
							$code = $3 || '';
						}
						# database, field and optional fixed key
						elsif( $item =~ /^($Codere)\s*:\s*($Codere)(;\s*(.*))?/o) {
							$database = $1;
							$field = $2;
							$code = $4 || '';
						}
						else {
							next;  # Can non-conforming params
						}

						if($database) {
							push @calls, [\&tag_data, $database, $field, $code ];
						}
						else {
							push @calls, [\&product_field, $field, $code ];
						}
					}
					unless(@calls) {
						$cost = tag_perl('sub', $what, @fixed);
					}
					else {
						my %items;
						foreach $item (@$Vend::Items) {
							$items{$item->{'code'}} = {};
							foreach $call (@calls) {
								@args = @$call;
								$routine = shift @args;
								$code = pop(@args) || $item->{code};
#print("routine=$routine args='@args' code=$code\n") if $Global::DEBUG;
								$items{$item->{code}}->{$args[$#args]} =
									&$routine(@args,$code);
							}
						}
						$cost = tag_perl('sub', $what, \%items, @fixed);
					}
#print("sub cost: '$cost'\n") if $Global::DEBUG;
					next unless defined $cost;
					return $cost if $cost =~ /^[\d.]+$/;
					$Vend::Session->{ship_message} = $cost;
					return 0;
				}
			}
			elsif ($Vend::Cfg->{'Shipping_cost'}->{$code} =~ /^e\s*/i) {
				my $msg = $Vend::Cfg->{'Shipping_cost'}->{$code};
				$msg =~ s/^e\s*//i;
				$msg =~ s/\@\@TOTAL\@\@/$total/g;
#print("error message: '$msg'\n") if $Global::DEBUG;
				$Vend::Session->{ship_message} = $msg;
				return 0;
			}
			else {
				return $Vend::Cfg->{'Shipping_cost'}->{$code};
			}
		}
	}

	# If we got here, the mode and quantity fit was not found
	$Vend::Session->{ship_message} .=
		"No match found for mode '$mode', quantity '$total', "	.
		($qual ? "qualifier '$qual', " : '')					.
		"returning 0. ";
	return 0;
}

sub taxable_amount {
	my($cart) = @_;
    my($taxable, $i, $code, $item, $tmp, $quantity);

	return subtotal($cart || undef) unless $Vend::Cfg->{'NonTaxableField'};

	my($save);

    if ($cart) {
        $save = $Vend::Items;
        tag_cart($cart);
    }

    $taxable = 0;

    foreach $i (0 .. $#$Vend::Items) {
		$item =	$Vend::Items->[$i];
		next if is_yes( item_field($item, $Vend::Cfg->{'NonTaxableField'}) );
		$tmp = item_subtotal($item);
		unless (defined $Vend::Session->{'discount'}) {
			$taxable += $tmp;
		}
		else {
			$taxable += apply_discount($item);
		}
    }

	$Vend::Items = $save if defined $save;

	$taxable;
}

# Calculate the sales tax
sub salestax {
	my($amount, $cart) = @_;

	my($save);

    if ($cart) {
        $save = $Vend::Items;
        tag_cart($cart);
    }

	$amount = $amount || taxable_amount($cart || undef);
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
		next unless defined $code && $code;
		# Trim the zip+4
		$code =~ s/(\d{5})-\d+/$1/;
		# Make it upper case for state and overseas postal
		# codes, zips don't matter
		$code = uc $code;
		if(defined $Vend::Cfg->{SalesTaxTable}->{$code}) {
			$r = $amount * $Vend::Cfg->{SalesTaxTable}->{$code};
			last;
		}
	}

	if( $r <= 0 ) {
		$r = $amount * ($Vend::Cfg->{SalesTaxTable}->{'default'} || 0);
	}

	$Vend::Items = $save if defined $save;

	$r;
}

sub tag_salestax {
	currency(salestax(@_));
}

sub tag_subtotal {
	currency(subtotal(@_));
}

# Returns just subtotal of items ordered, with discounts
# applied
sub subtotal {
	my($cart) = @_;

    my($save,$subtotal, $i, $item, $tmp, $cost, $formula);
	if ($cart) {
		$save = $Vend::Items;
		tag_cart($cart);
	}
	my $discount = defined $Vend::Session->{'discount'};

    $subtotal = 0;
	$tmp = 0;

    foreach $i (0 .. $#$Vend::Items) {
        $item = $Vend::Items->[$i];
        $tmp = item_subtotal($item);
        if($discount) {
            $subtotal +=
                apply_discount($item, $tmp);
        }
        else { $subtotal += $tmp }
	}



	if (defined $Vend::Session->{'discount'}->{ENTIRE_ORDER}) {
		$formula = $Vend::Session->{'discount'}->{ENTIRE_ORDER};
		$formula =~ s/\$q\b/tag_nitems()/eg; 
		$formula =~ s/\$s\b/$subtotal/g; 
		$cost = $ready_safe->reval($formula);
		if($@) {
			logError
				"Discount ENTIRE_ORDER has bad formula. Returning normal subtotal.\n$@";
			$cost = $subtotal;
		}
		$subtotal = $cost;
	}
	$Vend::Items = $save if defined $save;
    $subtotal;
}

sub tag_ups {
	my($type,$zip,$weight) = @_;
	my(@data);
	my(@fieldnames);
	my($i,$point,$zone);

#print("Called UPS lookup with type='$type' zip='$zip' weight='$weight'\n") if $Global::DEBUG;
	unless (defined $Vend::Database{$type}) {
		logError("UPS lookup called, no type file loaded for '$type'");
		return undef;
	}
	unless ($Vend::Cfg->{'UpsZoneFile'}) {
		logError("UPS lookup called, no zone file defined");
		return undef;
	}
	unless (defined $Vend::Cfg->{UPSzone}) {
		logError("UPS lookup called, zone file not found");
		return undef;
	}

	# UPS doesn't like fractional pounds, rounds up
	$weight = ceil($weight);

	$zip = substr($zip, 0, 3);
	$zip =~ s/^0+//;
	@fieldnames = split /\t/, ${$Vend::Cfg->{UPSzone}}[0];
#print("Fields: @fieldnames Num" . scalar @{$Vend::Cfg->{UPSzone}} . "\n") if $Global::DEBUG;
	for($i = 2; $i < @fieldnames; $i++) {
		next unless $fieldnames[$i] eq $type;
		$point = $i;
		last;
	}

	unless (defined $point) {
		logError("UPS lookup failed, type '$type' not found");
		return undef;
	}

#print("Point ") if $Global::DEBUG;
	for(@{$Vend::Cfg->{UPSzone}}[1..$#{$Vend::Cfg->{UPSzone}}]) {
		@data = split /\t/, $_;
#print("$data[$point] ") if $Global::DEBUG;
		next unless ($zip >= $data[0] and $zip <= $data[1]);
		$zone = $data[$point];
#print("Found match with $zip, $zone\n") if $Global::DEBUG;
		return 0 unless $zone ||= 0;
		last;
	}

	if (! defined $zone) {
		$Vend::Session->{ship_message} .=
			"No zone found for geo code $zip, type $type. ";
		return undef;
	}
	elsif (!$zone or $zone eq '-') {
		$Vend::Session->{ship_message} .=
			"No $type shipping allowed for geo code $zip. ";
		return undef;
	}

	my $cost = tag_data($type,$zone,$weight);
	$Vend::Session->{ship_message} .=
		"Zero cost returned for mode $type, geo code $zip. " unless $cost;
	$cost;

}

# Returns 'SELECTED' when a value is present on the form
# Must match exactly, but NOT case-sensitive

sub tag_selected {
	my ($field,$value,$multiple) = @_;
	$value = $value || '';
	my $ref = $Vend::Session->{'values'}->{$field};
	$ref = lc $ref;
	my $r;

	if( $ref eq "\L$value" ) {
		$r = 'SELECTED';
	}
	elsif ($multiple) {
		$r = 'SELECTED' if $ref =~ /\b$value\b/i;
	}
	else {$r = ''}
	$r;
}

sub tag_checked {
	my ($field,$value,$multiple) = @_;
	$value = $value || 'on';
	my $ref = $Vend::Session->{'values'}->{$field};
	$ref = lc $ref;
	my $r;

	if( $ref eq "\L$value" ) {
		$r = 'CHECKED';
	}
	elsif ($multiple) {
		$r = 'CHECKED' if $ref =~ /\b$value\b/i;
	}
	else {$r = ''}
	$r;
}

sub tag_finish_order {
	my($page) = @_;
    my($finish_order);

	return '' unless @$Vend::Items;

	unless (defined $page) {
		if ( $Vend::Session->{'scratch'}->{'mv_checkout'} ||= 0) {
			$page = $Vend::Session->{'scratch'}->{'mv_checkout'};
		}
		else { $page = $Vend::Cfg->{'CheckoutPage'}; }
	}

	$finish_order = '<a href="' . vendUrl($page);
	
	$finish_order .= '" TARGET="' . $Vend::Cfg->{'CheckoutFrame'}
			if $Vend::Session->{'frames'};

	$finish_order .= '">' . $Vend::Cfg->{'FinishOrder'} . "</a><p>";

}

# Returns an href to place an order for the product PRODUCT_CODE.
# If AlwaysSecure is set, goes by the page accessed, otherwise 
# if a secure order has been started (with a call to at least
# one secure_vendUrl), then it will be given the secure URL
 
sub tag_order {
    my($product_code,$page,$base) = @_;
    my($r);
    my $action = 'order';

	if($base || '') {
		$action = 'obtain';
		$page = defined $page ? "/$page" : '';
		$page = $base . $page;
	}

    unless(defined $page) {
        $page = $action;
    }   
	else {
		$page = "$action/$page";
	}

    if ($Vend::Cfg->{'AlwaysSecure'}) {
        if (defined $Vend::Cfg->{'AlwaysSecure'}->{$page}) {
            $r  = '<a href="' . secure_vendUrl($page, $product_code);
        }       
        else {
            $r  = '<a href="' . vendUrl($page, $product_code);
        }   
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

# Sets the value of a discount field
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
	#my($selector,$field,$key,$rest) = quoted_string($_[0]);
	my($selector,$field,$key,$rest) = @_;
	return $rest if (defined $rest and $rest);
	return tag_data($selector,$field,$key);
}

1;
__END__
