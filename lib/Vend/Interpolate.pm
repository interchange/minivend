#!/usr/bin/perl
# Interpolate.pm - Interpret MiniVend tags
# 
# $Id: Interpolate.pm,v 1.80 1999/02/28 18:30:31 mike Exp $
#
# Copyright 1996-1999 by Michael J. Heins <mikeh@iac.net>
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

$VERSION = substr(q$Revision: 1.80 $, 10);

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
tag_value

);

# SQL
push @EXPORT, 'tag_sql_list';
# END SQL

@EXPORT_OK = qw( sort_cart );

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
use Vend::Parse;
use POSIX qw(ceil);

use vars qw($New $Safe_tag);

my $wantref = 1;
my $CacheInvalid = 1;
my $ready_safe = new Safe;
$ready_safe->untrap(qw/sort ftfile/);
$ready_safe->share( qw/
						$mv_filter_value $mv_filter_name $s $q $item &tag_data
						/);

sub reset_calc {
	undef $ready_safe;
	$ready_safe = new Safe;
	$ready_safe->share( qw/
						$mv_filter_value $mv_filter_name $s $q $item &tag_data
						/);
	$ready_safe->share('$s', '$q', '$item', '&tag_data');
}

my %T;

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
		compat
		/compat
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
		discount-subtotal
		/discount
		else
		/else
		elsif
		/elsif
		field
		file
		finish-order
		fly-list
		/fly-list
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
		if-sql-data
		/if-sql-data
		if-sql-field
		/if-sql-field
		include
		item-accessories
		item-code
		item-data
		item-description
		item-discount
		item-field
		item-alternate
		/item-alternate
		item-increment
		item-last
		/item-last
		item-link
		item-next
		/item-next
		item-list
		/item-list
		item-modifier
		item-param
		if-sql-param
		/if-sql-param
		if-param
		/if-param
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
		loop-alternate
		/loop-alternate
		loop-increment
		loop-last
		/loop-last
		loop-link
		loop-next
		/loop-next
		loop-price
		m
		matches
		modifier-name
		more
		more-list
		/more-list
		sql
		sql-code
		sql-data
		sql-description
		sql-field
		sql-alternate
		/sql-alternate
		sql-increment
		sql-link
		sql-param
		sql-price
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
		then
		/then
		tag
		/tag
		total-cost
		uniq
		value

	! );


	my $tag;
	for (@th) {
		$tag = $_;
		s/(\w)/[\u$1\l$1]/g;
		s/[-_]/[-_]/g;
		$T{$tag} = "\\[$_";
		$T{'shipping-desc'} .= '(?:[Rr][Ii][Pp][Tt][Ii][Oo][Nn])?';
	}
}

my $All = '[\000-\377]*';
my $Some = '[\000-\377]*?';
my $Codere = '[\w-_#/.]+';
my $Coderex = '[\w-_:#=/.%]+';
my $Mandx = '\s+([\w-_:#=/.%]+)';
my $Mandf = '(?:%20|\s)+([\w-_#/.]+)';
my $Spacef = '(?:%20|\s)+';
my $Spaceo = '(?:%20|\s)*';

my $Optx = '(?:\s+)?([\w-_:#=/.%]+)?';
my $Mand = '\s+([\w-_#/.]+)';
my $Opt = '(?:\s+)?([\w-_#/.]+)?';
my $T    = '\]';
my %Comment_out = ( '<' => '&lt;', '[' => '&#91;', '_' => '&#95;', );

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

	my $dir = $CGI::secure											?
		($Vend::Cfg->{ImageDirSecure} || $Vend::Cfg->{ImageDir})	:
		$Vend::Cfg->{ImageDir};

    if ($dir) {
        $$text =~ s#(<i\w+\s+[^>]*?src=")(?!https?:)([^/][^"]+)#
                         $1 . $dir . $2#ige;
    }
    if($Vend::Cfg->{ImageAlias}) {
		for (keys %{$Vend::Cfg->{ImageAlias}} ) {
        	$$text =~ s#(<i\w+\s+[^>]*?src=")($_)#
                         $1 . ($Vend::Cfg->{ImageAlias}->{$2} || $2)#ige;
		}
    }
}

#use vars '$Ready_parse';

sub cache_html {
	my ($html,$wantref) = @_;
	my ($name, @post);
	my ($bit, %post);
	my $it = 'POST1000';

	# Comment facility

	unless ($Global::DisplayComments) {
		1 while $html =~ s% $T{'comment'}\]				# tag
							(?!$All$T{'comment'}\])   # ensure innermost
							$Some
							$T{'/comment'}\]%%xgo;
	}
	else {
		1 while $html =~ s% $T{'comment'}\]				# tag
							(?!$All$T{'comment'}\])   # ensure innermost
							$Some
							$T{'/comment'}\]%comment_out($1)%xego;
	}

	$CacheInvalid = 0;

# NOOLDTAGS
#	$New = 1;
#
#	$html =~ s/\[(old|new)\]//ig;
# END NOOLDTAGS

# OLDTAGS
	local ($New) = $New || $Vend::Cfg->{NewTags};

	if($New) { $New = 0 if $html =~ s/\[(old|new)\]//i and lc $1 eq 'old' }
	else 	 { $New = 1 if $html =~ s/\[(old|new)\]//i and lc $1 eq 'new' }
# END OLDTAGS

# DEBUG
#Vend::Util::logDebug
#("New tags=$New\n")
#	if ::debug(0x1);
# END DEBUG

	# Substitute defines from configuration file
	$html =~ s#\@\@([A-Za-z0-9]\w+[A-Za-z0-9])\@\@#$Global::Variable->{$1}#ge;
	$html =~ s#__([A-Za-z0-9]\w*?[A-Za-z0-9])__#
			$Vend::Cfg->{Member}->{$1} || $Vend::Cfg->{Variable}->{$1}#ge
		if $Vend::Session->{logged_in};
	$html =~ s#__([A-Za-z0-9]\w*?[A-Za-z0-9])__#$Vend::Cfg->{Variable}->{$1}#g;

	# Uncomment to use parallel MV and HTML tags
	#$html =~ s#<!--\s*$T{'alt'}\]\s*-->$Some<!--\s*$T{'/alt'}\]\s*-->##o;
	#$html =~ s#<!--\s*\[mv\]\s*##;
	#$html =~ s#\[/mv\]\s*-->##;

# OLDTAGS
    # Returns, could be recursive
    if($New and ! $Safe_tag) {
# END OLDTAGS
		my $complete;
		my $full = '';
        my $parse = new Vend::Parse;
		$parse->parse($html);
		while($parse->{_buf}) {
			substitute_image(\$parse->{OUT});
			::response('html', \$parse->{OUT});
			$full .= $parse->{OUT};
			$parse->{OUT} = '';
			$parse->parse('');
		}
		substitute_image(\$parse->{OUT})
			unless $parse->{ABORT};
		$full .= $parse->{OUT} if $full;
		$CacheInvalid++ if $parse->{INVALID};
		$Vend::CachePage = $CacheInvalid ? undef : 1;
		$complete = \$full if $full;
		if (defined $Vend::BuildingPages) {
			return $full if $full;
			return $parse->{OUT};
		}
        return (\$parse->{OUT}, $complete || undef) if defined $wantref;
        return ($parse->{OUT});
# OLDTAGS
    }
# END OLDTAGS

# OLDTAGS
    $html =~ s#$T{'compat'}\]($Some)$T{'/compat'}\]#$1#og;
    $html =~ s#$T{'post'}(\d*)]($Some)$T{'/post'}\1\]#
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

	return cache_scan_html($html, $wantref);
# END OLDTAGS

}

sub ref_or_positional {
	my($stuff, $patt, @names) = @_;
	my ($ref, @out);

	if(ref $stuff) {
		$ref = $stuff;
	}
	elsif($stuff =~ /^\s*{/) {
		$ref = $ready_safe->reval($stuff);
	}

	if(ref $ref) {
		for(@names) {
			push @out, ($ref->{$_} || undef);	
		}
		return @out;
	}
	else {
		$stuff =~ s/^\s+//;
		$stuff =~ s/\s+$//;
		return split m{$patt}, $stuff, scalar @names;
	}
}

#
# This is one entry point for page display.
# Evaluates all of the MiniVend tags.
#

sub interpolate_html {
	my ($html, $wantref) = @_;
	my ($name, @post);
	my ($bit, %post);
	my $it = 'POST1000';

	# Comment facility
	1 while $html =~ s% $T{'comment'}\]				# tag
						(?!$All$T{'comment'}\])   # ensure innermost
						$Some
						$T{'/comment'}\]%%xgo;
	$html =~ s/<!--+\[/[/g
		and $html =~ s/\]--+>/]/g;

# NOOLDTAGS
#	$New = 1;
#
#	$html =~ s/\[(old|new)\]//ig;
# END NOOLDTAGS

# OLDTAGS
	local ($New) = $New || $Vend::Cfg->{NewTags};

	if($New) { $New = 0 if $html =~ s/\[(old|new)\]//i and lc $1 eq 'old' }
	else 	 { $New = 1 if $html =~ s/\[(old|new)\]//i and lc $1 eq 'new' }
# END OLDTAGS

# DEBUG
#Vend::Util::logDebug
#("New tags=$New\n")
#	if ::debug(0x1);
# END DEBUG

	# Substitute defines from configuration file
	$html =~ s#\@\@([A-Za-z0-9]\w+[A-Za-z0-9])\@\@#$Global::Variable->{$1}#ge;
	$html =~ s#__([A-Za-z0-9]\w*?[A-Za-z0-9])__#$Vend::Cfg->{Variable}->{$1}#ge;

	defined $Vend::Cfg->{Variable}{MV_AUTOLOAD}
		and $html =~ s/^/$Vend::Cfg->{Variable}{MV_AUTOLOAD}/;

    # Returns, could be recursive
# OLDTAGS
	if($New and ! $Safe_tag) {
# END OLDTAGS
		my $parse = new Vend::Parse;
		$parse->parse($html);
		while($parse->{_buf}) {
			$parse->parse('');
		}
		substitute_image(\$parse->{OUT});
		return \$parse->{OUT} if defined $wantref;
		return $parse->{OUT};
# OLDTAGS
	}
# END OLDTAGS

# OLDTAGS
    $html =~ s#$T{'post'}(\d*)]($Some)$T{'/post'}\1\]# 
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
# END OLDTAGS

}

# OLDTAGS
sub cache_scan_html {
    my($html,$wantref) = @_;

	# [tag ..] can't nest
	$html =~ s:$T{'tag'}([^\]]*)\]($Some)$T{'/tag'}\]:do_tag($1,$2):geo;
    $html =~ s:\[\s*(\d?)\s*(\[[\000-\377]*?\])\s*\1\s*\]:cache_scan_html($2):ge;

	$html =~ s:$T{'cart'}\s+(\w+)\]:tag_cart($1):geo
			and $CacheInvalid = 1;
	$html =~ s:$T{'search'}\s+($Some)\]:tag_search($1):geo;
    1 while $html =~ s% $T{'item-list'}$Opt\]		# tag
						(?!$All$T{'item-list'}\])	# ensure innermost
						($Some)
						$T{'/item-list'}\]%
					 tag_item_list($1,$2)%xgeo;

    1 while $html =~ s:$T{'loop'}([-_]\w|\b)?\s+
						([^\]]*)							# all args
							\]
						(?!$All$T{'loop'}\s+)			# ensure innermost
						($Some)
						$T{'/loop'}\1\]:
              tag_loop_list($1,$2,undef,$3):xgeo;
    $html =~ s:$T{'default'}\s+([^\]]+)\]:tag_default($1):geo
				and $CacheInvalid = 1;
    $html =~ s!$T{'value'}$Mand$Opt\]!tag_value($1,$2)!geo
				and $CacheInvalid = 1;
    $html =~ s:$T{'scratch'}\s+([^\]]+)\]:tag_scratch($1):geo
				and $CacheInvalid = 1;

    1 while $html =~ s:$T{'calc'}\]
						(?!$All$T{'calc'}\])			# ensure innermost
						($Some)
						$T{'/calc'}\]:
              	tag_calc($1):xgeo;

	1 while $html =~ s:$T{'if'}\s+
						([^\]]+[^\\])           # all args
						\]
						(?!$All\[if\s+)				# ensure innermost
						($Some)
						$T{'/if'}\]:
				  tag_if($1,$2):xgeo;


	$html =~ s#$T{'lookup'}\s+$Mand$Mand$Mandx$Some\]#tag_lookup($1,$2,$3,$4)#geo
				and $CacheInvalid = 1;
	$html =~ s#$T{'set'}\s+([^\]]+)\]($Some)$T{'/set'}\]#
				  set_scratch($1,$2)#geo and $CacheInvalid = 1;
    $html =~ s#$T{'data'}\s+([^\]]+)\]#
					tag_data(Text::ParseWords::shellwords($1))#geo;
	$html =~ s#
				\[m?sql \s+ ($Codere) ([^\]]*) \]
				($Some)
				\[/(m)?sql$Opt\]#
				  $CacheInvalid = 1 if "\L$1" eq 'set';
				  sql_query($1,$2,$3,$4,$5)#geixo;

	$html =~ s!$T{'file'}$Mand\]!readfile($1, $Global::NoAbsolute)!geo;

    $html =~ s!$T{'finish-order'}$Opt\]!tag_finish_order($1)!geo;

    $html =~ s:$T{'frames-on'}\]:tag_frames_on():geo
			and $CacheInvalid = 1;
    $html =~ s:$T{'frames-off'}\]:tag_frames_off():geo
			and $CacheInvalid = 1;

    $html =~ s:$T{'framebase'}$Mand\]:tag_frame_base($1):geo;
    $html =~ s:$T{'body'}$Mand(\s+[^\]]*)?\]:tag_body($1,$2):geo;
    $html =~ s:$T{'help'}$Mand\]:tag_help($1):geo;
    $html =~ s:$T{'buttonbar'}$Mand\]:tag_buttonbar($1):geo;
    $html =~ s:$T{'random'}\]:tag_random():geo;
    $html =~ s!$T{'rotate'}$Opt$Opt\]!
					tag_rotate($1,$2)!geo;

	$html =~ s!$T{'checked'}$Mand$Opt$Opt\]!
					tag_checked($1,$2 || 'on', $3)!geo
			and $CacheInvalid = 1;
	$html =~ s!$T{'selected'}$Mand$Mand$Opt\]!
				tag_selected($1,$2,$3)!geo
			and $CacheInvalid = 1;

    $html =~ s:$T{'accessories'}$Mand(\s+[^\]]+)?\]:
					tag_accessories($1,'',$2):geo;
    $html =~ s:$T{'field'}$Mand$Mand\]:product_field($1,$2):geo;

    $html =~ s!$T{'pagetarget'}$Mandx$Mandx(?:\s+)?($Some)\]!
					tag_pagetarget($1,$2,$3)!geo;

    $html =~ s!$T{'area'}$Mandx(?:\s+)?($Some)\]!tag_area($1,$2)!geo;

    $html =~ s!$T{'areatarget'}$Mandx$Mandx(?:\s+)?($Some)\]!
						tag_areatarget($1,$2,$3)!geo;

    $html =~ s!$T{'page'}$Mandx(?:\s+)?($Some)?\]!tag_page($1,$2)!geo;

    $html =~ s!$T{'last-page'}$Optx(?:\s+)?($Some)?\]!
				tag_last_page($1,$2)!geo and $CacheInvalid = 1;

    $html =~ s:$T{'/pagetarget'}\]:</a>:go;
    $html =~ s:$T{'/page'}\]:</a>:go;
    $html =~ s:$T{'/order'}\]:</a>:go;
    $html =~ s:$T{'/last-page'}\]:</a>:go;

	$html =~ s~  $T{'perl'}  (?:\s+)?  ([^\]]+[^\\])?\]
					(?:<!--+\s*)?
					($Some)
					(?:-->\s*)?$T{'/perl'}\]
					~ tag_perl($1,$2) ~xgeo and $CacheInvalid = 1;

    $html =~ s!$T{'order'}$Mand$Opt$Opt$Opt$T!
					tag_order($1,$2,$3,$4)!geo;


    $html =~ s!$T{'nitems'}$Opt$T!tag_nitems($1)!geo
			and $CacheInvalid = 1;
	$html =~ s#$T{'discount'}$Mand$T($Some)$T{'/discount'}$T#
				  tag_discount($1,$2)#geo
				  		and $CacheInvalid = 1;
    $html =~ s#$T{'subtotal'}$Opt$Opt$T#tag_subtotal($1,$2)#geo
			and $CacheInvalid = 1;
    $html =~ s#$T{'shipping-desc'}$Opt$T#
					tag_shipping_desc($1)#geo;
    $html =~ s#$T{'shipping'}$Opt$Opt$Opt$T#tag_shipping($1,$2,$3)#geo
				and $CacheInvalid = 1;
    $html =~ s#$T{'salestax'}$Opt$Opt$T#tag_salestax($1,$2)#geo
				and $CacheInvalid = 1;
    $html =~ s#$T{'total-cost'}$Opt$Opt$T#tag_total_cost($1, $2)#geo
				and $CacheInvalid = 1;
    $html =~ s#$T{'price'}$Mand$Opt$Opt$Opt$T#tag_price($1,$2,$3,$4)#geo;
	$html =~ s:$T{'currency'}$Opt$T($Some)$T{'/currency'}$T:
					currency($2, undef, $1):geo;
    $html =~ s#$T{'description'}$Mand$T# product_description($1)#goe;
	$html =~ s:$T{'row'}\s+(\d+)$T($Some)$T{'/row'}$T:tag_row($1,$2):geo;

    $html =~ s#$T{'process-order'}$Opt$T#tag_process_order($1)#geo;
    $html =~ s#$T{'process-search'}$Opt$T#tag_process_search($1)#geo;
    $html =~ s#$T{'process-target'}$Opt$Opt$T#tag_process_target($1,$2)#goe;

    substitute_image(\$html);

	$Vend::CachePage = $CacheInvalid ? undef : 1;

	return \$html if defined $wantref;
	return $html;

}

sub scan_html {
    my($html, $wantref) = @_;

	$html =~ s:$T{'tag'}([^\]]*)$T($Some)$T{'/tag'}$T:do_tag($1,$2):geo;
    $html =~ s:\[\s*(\d?)\s*(\[[\000-\377]*?\])\s*\1\s*\]:scan_html($2):ge;

	$html =~ s:$T{'cart'}\s+(\w+)$T:tag_cart($1):ge;
	$html =~ s:$T{'search'}\s+($Some)$T:tag_search($1):geo;
    1 while $html =~ s% $T{'item-list'}$Opt$T		# tag
						(?!$All$T{'item-list'}$T)	# ensure innermost
						($Some)
						$T{'/item-list'}$T%
					 tag_item_list($1,$2)%xgeo;

    1 while $html =~ s:$T{'loop'}([-_]\w|\b)?\s+
						([^\]]*)							# all args
							$T
						(?!$All$T{'loop'}\s+)			# ensure innermost
						($Some)
						$T{'/loop'}\1$T:
              tag_loop_list($1,$2,undef,$3):xge;
    $html =~ s:$T{'default'}\s+([^\]]+)$T:tag_default($1):geo;
    $html =~ s!$T{'value'}$Mand$Opt\]!tag_value($1,$2)!geo;
    $html =~ s:$T{'scratch'}\s+([^\]]+)$T:tag_scratch($1):geo;


    1 while $html =~ s:$T{'calc'}$T
						(?!$All$T{'calc'}$T)			# ensure innermost
						($Some)
						$T{'/calc'}$T:
              	tag_calc($1):xgeo;

	1 while $html =~ s:$T{'if'}\s+
						([^\]]+[^\\])           # all args
						\]
						(?!$All\[if\s+)				# ensure innermost
						($Some)
						$T{'/if'}\]:
				  tag_if($1,$2):xgeo;

	$html =~ s#$T{'lookup'}\s+$Mand$Mand$Mandx$Some\]#tag_lookup($1,$2,$3,$4)#geo;
	$html =~ s#$T{'set'}\s+([^\]]+)$T($Some)$T{'/set'}$T#
				  set_scratch($1,$2)#geo;
    $html =~ s#$T{'data'}\s+([^\]]+)$T#
					tag_data(Text::ParseWords::shellwords($1))#geo;
	$html =~ s#\[ m?sql $Mand ([^\]]*) $T
				($Some)
				\[/(m)?sql$Opt$T#
				  sql_query($1,$2,$3,$4,$5)#geixo;
	$html =~ s!$T{'file'}$Mand$T!readfile($1, $Global::NoAbsolute)!geo;

    $html =~ s!$T{'finish-order'}$Opt$T!tag_finish_order($1)!geo;

    $html =~ s:$T{'frames-on'}$T:tag_frames_on():geo;
    $html =~ s:$T{'frames-off'}$T:tag_frames_off():geo;

    $html =~ s:$T{'framebase'}$Mand$T:tag_frame_base($1):geo;
    $html =~ s:$T{'body'}$Mand(\s+[^\]]*)?$T:tag_body($1,$2):geo;
    $html =~ s:$T{'help'}$Mand$T:tag_help($1):geo;
    $html =~ s:$T{'buttonbar'}$Mand$T:tag_buttonbar($1):geo;
    $html =~ s:$T{'random'}$T:tag_random():geo;
    $html =~ s!$T{'rotate'}$Opt$Opt$T!
					tag_rotate($1,$2)!geo;

	$html =~ s!$T{'checked'}$Mand$Opt$Opt$T!
					tag_checked($1,$2 || 'on', $3)!geo;
	$html =~ s!$T{'selected'}$Mand$Mand$Opt$T!
				tag_selected($1,$2,$3)!geo;

    $html =~ s!$T{'accessories'}$Mand(\s+[^\]]+)?$T!
					tag_accessories($1,'',$2)!geo;
    $html =~ s:$T{'field'}$Mand$Mand$T:product_field($1,$2):geo;

    $html =~ s!$T{'pagetarget'}$Mandx$Optx(?:\s+)?($Some)?$T!
					tag_pagetarget($1,$2,$3)!geo;

    $html =~ s!$T{'area'}$Mand(?:\s+)?($Some)?$T!tag_area($1,$2)!geo;

    $html =~ s!$T{'areatarget'}$Mand$Mand(?:\s+)?($Some)?$T!
						tag_areatarget($1,$2,$3)!geo;

    $html =~ s!$T{'page'}$Mand(?:\s+)?($Some)?$T!tag_page($1,$2)!geo;

    $html =~ s!$T{'last-page'}$Optx(?:\s+)?($Some)?$T!
				tag_last_page($1,$2)!geo;

    $html =~ s:$T{'/pagetarget'}$T:</a>:go;
    $html =~ s:$T{'/page'}$T:</a>:go;
    $html =~ s:$T{'/order'}$T:</a>:go;
    $html =~ s:$T{'/last-page'}$T:</a>:go;

	$html =~ s~  $T{'perl'}  (?:\s+)?  ([^\]]+[^\\])?$T
					(?:<!--+\s*)?
					($Some)
					(?:-->\s*)?$T{'/perl'}$T
					~ tag_perl($1,$2) ~xgeo;

    $html =~ s!$T{'order'}$Mand$Opt$Opt$Opt$T!
					tag_order($1,$2,$3,$4)!geo;

    $html =~ s!$T{'nitems'}$Opt$T!tag_nitems($1)!geo;
	$html =~ s#$T{'discount'}$Mand$T($Some)$T{'/discount'}$T#
				  tag_discount($1,$2)#geo;
    $html =~ s#$T{'subtotal'}$Opt$Opt$T#tag_subtotal($1,$2)#geo;
    $html =~ s#$T{'shipping-desc'}$Opt$T#
					tag_shipping_desc($1)#geo;
    $html =~ s#$T{'shipping'}$Opt$Opt$Opt$T#tag_shipping($1,$2,$3)#geo;
    $html =~ s#$T{'salestax'}$Opt$Opt$T#tag_salestax($1,$2)#geo;
    $html =~ s#$T{'total-cost'}$Opt$Opt$T#tag_total_cost($1,$2)#geo;
    $html =~ s#$T{'price'}$Mand$Opt$Opt$Opt$T#tag_price($1,$2,$3,$4)#geo;
	$html =~ s:$T{'currency'}$Opt$T($Some)$T{'/currency'}$T:
					currency($2, undef, $1):geo;
    $html =~ s#$T{'description'}$Mand$T#product_description($1)#goe;
	$html =~ s:$T{'row'}\s+(\d+)$T($Some)$T{'/row'}$T:tag_row($1,$2):geo;

    $html =~ s#$T{'process-order'}$Opt$T#tag_process_order($1)#geo;
    $html =~ s#$T{'process-search'}$Opt$T#tag_process_search($1)#geo;
    $html =~ s#$T{'process-target'}$Opt$Opt$T#
				tag_process_target($1,$2)#goe;

    $html =~ s#(<i\w+\s+[^>]*?src=")(?!http:)([^/][^"]+)#
                $1 . $Vend::Cfg->{ImageDir} . $2#ige
                 if $Vend::Cfg->{ImageDir};

	return \$html if defined $wantref;
	return $html;

}
# END OLDTAGS

# Returns the text of a configurable database field or a 
# variable
sub tag_data {
	my($selector,$field,$key,$value,$inc,$append) = @_;
# DEBUG
#Vend::Util::logDebug
#("Data args: @_\n")
#	if ::debug(0x1);
# END DEBUG
	$CacheInvalid = 1
				if defined $Vend::Cfg->{DynamicData}->{$selector};
	return database_field($selector,$key,$field)
			if ! defined $value and $Vend::Database{$selector};

	if(defined $Vend::Database{$selector}) {
# DEBUG
#Vend::Util::logDebug
#("Database with: key=$key field=$field db=$selector val=$value inc=$inc\n")
#	if ::debug(0x1);
# END DEBUG
		my $db = $Vend::Database{$selector};
		$CacheInvalid = 1;
		if(defined $inc) {
			return increment_field($db,$key,$field,$value || 1);
		}
		#$value =~ s/^(["'])(.*)\1$/$2/;
		return set_field($db,$key,$field,$value,$append);
	}
	elsif($selector eq 'arg') {
		$CacheInvalid = 1;
		return (! defined $Vend::Argument
			? '' :  $Vend::Argument );
	}
	elsif($selector eq 'session') {
# DEBUG
#Vend::Util::logDebug
#("Data session with: key=$key field=$field db=$selector val=$value inc=$inc\n")
#	if ::debug(0x1);
# END DEBUG
		$CacheInvalid = 1;
		if($value) {
			if ($inc) {
				$Vend::Session->{$field} += ($value || 1);
			}
			elsif ($append) {
				$Vend::Session->{$field} .= $value;
			}
			else  {
				$Vend::Session->{$field} = $value;
			}
			return '';
		}
		else {
			return ($Vend::Session->{$field} || '');
		}
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
		return (! defined $::Scratch->{$field}
				? '' :  $::Scratch->{$field});
	}
	elsif($selector =~ /^value/) {
		$CacheInvalid = 1;
		return (! defined $::Values->{$field}
				? '' :  $::Values->{$field} );
	}
	elsif($selector eq 'salestax') {
		$field = uc $field;
		return (! defined $Vend::Cfg->{SalesTaxTable}->{$field}
				? '' : $Vend::Cfg->{SalesTaxTable}->{$field} );
	}
	else {
		logError( errmsg('Interpolate.pm:1',
					"Bad data '%s' '%s' '%s'" , $selector, $field, $key
					)
				);
		return '';
	}
}

use vars qw/%Filters/;

%Filters = (
	
	'uc' =>		sub {
					return uc(shift);
				},
	'lc' =>		sub {
					return lc(shift);
				},
	'digits_dot' => sub {
					my $val = shift;
					$val =~ s/[^\d.]+//g;
					return $val;
				},
	'digits' => sub {
					my $val = shift;
					$val =~ s/\D+//g;
					return $val;
				},
	'length' =>	sub {
					my ($val, $len) = (@_);
					$val = substr($val, 0, $len);
					return $val;
				},
	'word' =>	sub {
					my $val = shift;
					$val =~ s/\W+//g;
					return $val;
				},
	'unix' =>	sub {
					my $val = shift;
					$val =~ s/\r?\n/\n/g;
					return $val;
				},
	'dos' =>	sub {
					my $val = shift;
					$val =~ s/\r?\n/\r\n/g;
					return $val;
				},
	'mac' =>	sub {
					my $val = shift;
					$val =~ s/\r?\n|\r\n?/\r/g;
					return $val;
				},
	'gate' =>	sub {
					my ($val, $var) = @_;
					return '' unless $::Scratch->{$var};
					return $val;
				},
	'no_white' =>	sub {
					my $val = shift;
					$val =~ s/\s+//g;
					return $val;
				},
	'strip' =>	sub {
					my $val = shift;
					$val =~ s/^\s+//;
					$val =~ s/\s+$//;
					return $val;
				},
	'urlencode' => sub {
					my $val = shift;
					$val =~ s|[^\w:/.@]|sprintf "%02x", ord $1|eg;
					return $val;
				},
	'entities' => sub {
					return HTML::Entities::encode(shift);
				},
	);

sub input_filter_do {
	my($varname, $opt, $routine) = @_;
#::logGlobal("filter var=$varname opt=" . Vend::Util::uneval($opt));
	return undef unless defined $CGI::values{$varname};
#::logGlobal("before filter=$CGI::values{$varname}");
	$routine = $opt->{routine} || ''
		if ! $routine;
	if($routine =~ /\S/) {
		$Vend::Interpolate::mv_filter_value = $CGI::values{$varname};
		$Vend::Interpolate::mv_filter_name = $varname;
		$routine = interpolate_html($routine);
		$CGI::values{$varname} = tag_calc($routine);
	}
	if ($opt->{op}) {
		my @ops = grep /\S/, split /\s+/, $opt->{op};
		for(@ops) {
#::logGlobal("filter op=$_ found");
			if(/^\d+$/) {
				$CGI::values{$varname} = substr($CGI::values{$varname} , 0, $_);
				next;
			}
			next unless defined $Filters{$_};
#::logGlobal("filter op=$_ exists");
			$CGI::values{$varname} = &{$Filters{$_}}(
										$CGI::values{$varname},
										$varname,
										);
		}
	}
#::logGlobal("after filter=$CGI::values{$varname}");
	return;
}

sub input_filter {
	my ($varname, $opt, $routine) = @_;
	if($opt->{remove}) {
		return if ! ref $Vend::Session->{Filter};
		delete $Vend::Session->{Filter}{$_};
		return;
	}
	$opt->{routine} = $routine if $routine =~ /\S/;
	$Vend::Session->{Filter} = {} if ! $Vend::Session->{Filter};
	$Vend::Session->{Filter}{$varname} = $opt;
	return;
}

sub conditional {
	my($base,$term,$operator,$comp, @addl) = @_;
	my $reverse;
	$base = lc $base;
	$base =~ s/^!// and $reverse = 1;
	my ($op, $status);
	my $noop;
	$noop = 1 unless defined $operator;
	local($) = 0;
	undef $@;

# DEBUG
#Vend::Util::logDebug
#("cond: base=$base term=$term op=$operator comp=$comp\n")
#	if ::debug(0x1);
# END DEBUG
#::logGlobal (($reverse ? '!' : '') . "cond: base=$base term=$term op=$operator comp=$comp");
	my %stringop = ( qw! eq 1 ne 1 gt 1 lt 1! );

	if(defined $stringop{$operator}) {
		$comp =~ /^(["']).*\1$/ or
		$comp =~ /^qq?([{(]).*[})]$/ or
		$comp =~ /^qq?(\S).*\1$/ or
		(index ($comp, '}') == -1 and $comp = 'q{' . $comp . '}')
			or
		(index ($comp, '!') == -1 and $comp = 'q{' . $comp . '}')
	}

# DEBUG
#Vend::Util::logDebug
#("cond: base=$base term=$term op=$operator comp=$comp\n")
#	if ::debug(0x1);
# END DEBUG


	if($base eq 'session') {
		$CacheInvalid = 1;
		$op =	qq%$Vend::Session->{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'scratch') {
		$CacheInvalid = 1;
		$op =	qq%$::Scratch->{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'explicit') {
		undef $noop;
		$status = tag_perl($term,$comp);
	}
    elsif($base eq 'items') {
        $CacheInvalid = 1;
		my $cart;
        if($term) {
        	$cart = $Vend::Session->{'carts'}->{$term} || undef;
		}
		else {
			$cart = $Vend::Items;
		}
		$op =   defined $cart ? scalar @{$cart} : 0;

        $op .=  qq% $operator $comp%
                if defined $comp;
    }
	elsif($base =~ /^value/) {
		$CacheInvalid = 1;
		$op =	qq%$::Values->{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'cgi') {
		$CacheInvalid = 1;
		$op =	qq%$CGI::values{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'data') {
		my($d,$f,$k) = split /::/, $term;
		$CacheInvalid = 1
			if defined $Vend::Cfg->{DynamicData}->{$d};
		$op = database_field($d,$k,$f);
# DEBUG
#Vend::Util::logDebug
#("tag_if db=$d fld=$f key=$k\n")
#	if ::debug(0x1);
# END DEBUG
		$op = 'q{' . $op . '}' unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'field') {
		my($f,$k) = split /::/, $term;
		$op = product_field($f,$k);
# DEBUG
#Vend::Util::logDebug
#("tag_if field fld=$f key=$k\n")
#	if ::debug(0x1);
# END DEBUG
		$op = 'q{' . $op . '}' unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'discount') {
		$CacheInvalid = 1;
		$op =	qq%$Vend::Session->{'discount'}->{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'ordered') {
		$CacheInvalid = 1;
		$operator = 'main' unless $operator;
		my ($attrib, $i);
		$op = '';
		unless ($comp) {
			$attrib = 'quantity';
		}
		else {
			($attrib,$comp) = split /\s+/, $comp;
		}
		foreach $i (@{$Vend::Session->{'carts'}->{$operator}}) {
			next unless $i->{code} eq $term;
			($op++, next) if $attrib eq 'lines';
			$op = $i->{$attrib};
			last;
		}
		$op = "q{$op}" unless defined $noop;
		$op .=  qq% $comp% if $comp;
	}
	elsif($base eq 'file') {
		#$op =~ s/[^rwxezfdTsB]//g;
		#$op = substr($op,0,1) || 'f';
		undef $noop;
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
		$op = qq%$Vend::Cfg->{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
    }
	elsif($base =~ /^pric/) {
		$op = qq%$Vend::Cfg->{'Pricing'}->{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base =~ /^accessor/) {
        if ($comp) {
            $op = qq%$Vend::Cfg->{Accessories}->{$term}%;
			$op = "q{$op}" unless defined $noop;
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
		$op = qq%$Vend::Cfg->{SalesTaxTable}->{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base =~ /^ship/) {
		$op = qq%$Vend::Cfg->{'Shipping_desc'}->{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	else {
		$@ = "No such comparison available";
	}

#::logGlobal("noop='$noop' op='$op'");

	RUNSAFE: {
		last RUNSAFE if defined $status;
		last RUNSAFE if $status = ($noop && $op);
		$ready_safe->untrap(@{$Global::SafeUntrap});
		$status = $ready_safe->reval($op)
			unless ($@ or $status);
		if ($@) {
			logError qq%Bad if '@_': $@%;
			$status = 0;
		}
	}

	$status = $reverse ? ! $status : $status;

	for(@addl) {
		my $chain = /^\[[Aa]/;
		last if ($chain ^ $status);
		$status = (new Vend::Parse)->parse($_)->{OUT};
	}

	return $status;
}

sub find_andor {
	my($text) = @_;
	return undef
		unless $$text =~ s# \s* \[
								( (?:[Aa][Nn][Dd]|[Oo][Rr]) \s+
									$All)
									#$1#x;
	my $expr = find_close_square($$text);
	return undef unless defined $expr;
	$$text = substr( $$text,length($expr) + 1 );
	return "[$expr]";
}

sub split_if {
	my ($body) = @_;

	my ($then, $else, $elsif, $andor, @addl);
	$else = $elsif = '';

	push (@addl, $andor) while $andor = find_andor(\$body);

	$body =~ s#^\s*$T{'then'}$T($Some)$T{'/then'}$T##o
		and $then = $1;

	$body =~ s#$T{'else'}$T($All)$T{'/else'}$T\s*$##o
		and $else = $1;

	$body =~ s#$T{'elsif'}\s+($All)$T{'/elsif'}$T\s*$##o
		and $elsif = $1;

	$body = $then if defined $then;

	return($body, $elsif, $else, @addl);
}

sub tag_if {
	my ($cond,$body) = @_;
# DEBUG
#Vend::Util::logDebug
#("Called tag_if: $cond\n$body\n")
#	if ::debug(0x2);
# END DEBUG
	my ($base, $term, $op, $operator, $comp);
	my ($else, $elsif, $else_present, @addl);

	unless ($cond =~ /^explicit\b/i) {
		($base, $term, $operator, $comp) = split /\s+/, $cond, 4;
	}
	elsif ($body =~ s#^\s*$T{'condition'}$T($Some)$T{'/condition'}$T##o) {
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
		$body =~ /\[[EeTtAaOo][hHLlNnRr][SsEeDd\s]/;

	($body, $elsif, $else, @addl) = split_if($body)
		if $else_present;

#::logGlobal("Additional ops found:\n" . join("\n", @addl) ) if @addl;

	unless(defined $operator) {
		undef $operator;
		undef $comp;
	}

	my $status = conditional ($base, $term, $operator, $comp, @addl);

# DEBUG
#Vend::Util::logDebug
#("Result of if: $status\n")
#	if ::debug(0x1);
# END DEBUG

	my $out;
	if($status) {
		$out = $body;
	}
	elsif ($elsif) {
		$else = '[else]' . $else . '[/else]' if $else;
		$elsif =~ s#(.*?)$T{'/elsif'}\](.*)#$1${2}[/elsif]#s;
		$out = '[if ' . $elsif . $else . '[/if]';
	}
	elsif ($else) {
		$out = $else;
	}
	return $New ? $out : interpolate_html($out);
}

sub show_current_accessory_label {
	my($val, $choices) = @_;
	my @choices;
	@choices = split /\s*,\s*/, $choices;
	for(@choices) {
		my ($setting, $label) = split /=/, $_, 2;
		return ($label || $setting) if $val eq $setting;
	}
	return '';
}

sub build_accessory_textarea {
	my($name, $type, $default, @opts) = @_;

	my $select;
	my $run = qq|<TEXTAREA NAME="$name"|;

	while($type =~ m/\b(row|col)(?:umn)s?[=\s'"]*(\d+)/gi) {
		$run .= " \U$1\ES=$2";
	}
	if ($type =~ m/\bwrap[=\s'"]*(hard|soft|none)/i) {
		$run .= qq{WRAP="$1"};
	}
	$run .= '>';
	$run .= $default;
	$run .= '</TEXTAREA>';
}


sub build_accessory_select {
	my($name, $type, $default, @opts) = @_;

	my $select;
	my $run = qq|<SELECT NAME="$name"|;

	if($type =~ /multiple/i) {
		$run .= " $type ";
	}
	elsif ($type  =~ /^multi/i ) {
		$run .= ' MULTIPLE';
	}
	$run .= '>';
	
	for(@opts) {
		$run .= '<OPTION';
		$select = '';
		s/\*$// and $select = 1;
		if ($default) {
			$select = '';
		}
		my ($value,$label) = split /=/, $_, 2;
		if($label) {
			$value =~ s/"/&quot;/;
			$run .= qq| VALUE="$value"|;
		}
		if ($default) {
			my $regex = quotemeta $value;
			$default =~ /(?:\0|^)$regex(?:\0|$)/ and $select = 1;
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

sub build_accessory_box {
	my($name, $type, $default, @opts) = @_;

	my ($inc, $select, $xlt, $template, $header, $footer, $row_hdr, $row_ftr);

	$header = $template = $footer = $row_hdr = $row_ftr = '';

	my $variant = ($type =~ /check/i) ? 'checkbox' : 'radio';
	if($type =~ /nbsp/i) {
		$xlt = 1;
		$template = qq{<INPUT TYPE="$variant" NAME="$name" VALUE="__VALUE__"__SEL__>&nbsp;__LABEL__&nbsp;&nbsp;};
	}
	elsif ($type  =~ /left[\s_]*(\d?)/i ) {
		$inc = $1 || undef;
		$header = '<TABLE>';
		$footer = '</TABLE>';
		$template = '<TR>' unless $inc;
		$template .= <<EOF;
<TD><INPUT TYPE="$variant" NAME="$name" VALUE="__VALUE__"__SEL__></TD><TD>__LABEL__</TD>
EOF
		$template .= '</TR>' unless $inc;
	}
	elsif ($type  =~ /right[\s_]*(\d?)/i ) {
		$inc = $1 || undef;
		$header = '<TABLE>';
		$footer = '</TABLE>';
		$template = '<TR>' unless $inc;
		$template .= <<EOF;
<TD>__LABEL__</TD><TD><INPUT TYPE="$variant" NAME="$name" VALUE="__VALUE__"__SEL__></TD>
EOF
		$template .= '</TR>' unless $inc;
	}
	else {
		$template = <<EOF;
<INPUT TYPE="$variant" NAME="$name" VALUE="__VALUE__"__SEL__> __LABEL__
EOF
		$template =~ s/\s+$/<BR>/ if $type =~ /break/i;
	}
	
	my $run = $header;

	$default = '' unless defined $default;

	my $i = 0;
	for(@opts) {
		$run .= '<TR>' if $inc && ! ($i % $inc);
		$i++;
		$run .= $template;
		$select = '';
		s/\*$// and $select = "CHECKED";

		$select = '' if $default;

		my ($value,$label) = split /=/, $_, 2;
		$label = $value unless $label;

		$value =~ s/"/&quot;/g;

		$value eq '' and $default eq '' and $select = "CHECKED";
		$default =~ /\b$value\b/ and $select = "CHECKED" if length($value);

		$label =~ s/ /&nbsp;/g if $xlt;

		$run =~ s/__SEL__/ $select/;
		$run =~ s/__VALUE__/$value/;
		$run =~ s/__LABEL__/$label/;
		$run .= '</TR>' if $inc && ! ($i % $inc);
		
	}
	$run .= $footer;
}

sub tag_price {
	my($code,$quantity,$base,$noformat,$ref) = @_;
	$ref = { code => $code, quantity => $quantity, base => $base }
		if ! defined $ref->{code};
	$quantity = $ref->{quantity} = 1 if ! defined $ref->{quantity};
	return currency(
					 discount_price($ref,Vend::Data::item_price($ref,$quantity),
					 					$quantity),
					 $noformat
					) if $ref->{discount};
	return currency(
					 Vend::Data::item_price($ref,$quantity),
					 $noformat,
					 );
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
	my($attribute, $type, $field, $db, $name, $outboard, $passed) = 
		ref_or_positional($extra, '\s*,\s*',
							qw/attribute type field db name outboard passed/);
	$type = 'select' unless $type;
	$field = $attribute unless $field;
	$code = $outboard if $outboard;
# DEBUG
#local($) = 0 
#	if ::debug(0x1);
#Vend::Util::logDebug
#("accessory db=$db type=$type field=$field attr=$attribute name=$name\n")
#	if ::debug(0x1);
# END DEBUG

	my $data;
	if($passed) {
		$data = $passed;
	}
	else {
		$data = $db ? tag_data($db, $field, $code) : product_field($field,$code);
	}

	unless ($data || $type =~ /^text/i) {
		return '' if $item;
		return '' if $name;
		return qq|<INPUT TYPE="hidden" NAME="mv_order_$attribute" VALUE="">|;
	}

	return show_current_accessory_label($item->{$attribute},$data)
			if "\L$type" eq 'display' and $item;
	return $data if "\L$type" eq 'show';

	my $attrib_value = $item ? $item->{$attribute} : '';

	$name = $item ? "[modifier-name $attribute]" : "mv_order_$attribute"
		unless $name;

	return qq|<INPUT TYPE="hidden" NAME="$name" VALUE="$attrib_value">|
		if "\L$type" eq 'hidden';
	return qq|<TEXTAREA NAME="$name" ROWS=$1 COLS=$2>$attrib_value</TEXTAREA>|
		if "\L$type" =~ /^textarea_(\d+)_(\d+)$/;
	return qq|<INPUT TYPE=text NAME="$name" SIZE=$1 VALUE="$attrib_value"|
		if "\L$type" =~ /^text_(\d+)$/;

	my ($default, $label, $select, $value, $run);
	my @opts = split /\s*,\s*/, $data;

	if($item) {
		$default = $item->{$attribute};
	}

	# returns just list of options, no labels
	if($type eq 'options') {
		return join "\n", (map { s/\s*=.*//; $_ } @opts);
	}
	# returns just list of labels, no options
	elsif ($type eq 'labels') {
		return join "\n", (map { s/.*?=//; $_ } @opts);
	}

	# Ranging type, for price breaks based on quantity
	if ($type =~ s/^range:?(.*)//) {
		$select = $1 || 'quantity';
		$default = ($item && defined $item->{$select}) ? $item->{$select} : undef;
		my $min;
		my $max;
		for(@opts) {
			/^ (-?[\d.]+) - (-?[\d.]*)  \s*=\s*  (.+) /x
				or next;
			$min = $1;
			$max = $2;
			$label = $3;
			if($label =~ s/\*$// and ! $default) {
				$default = $min;
			}
			next unless $default >= $min;
			next unless $default <= $max;
			last;
		}
		($item->{$attribute} = $label, return '') if $item;
		return qq|<INPUT TYPE="hidden" NAME="$name" VALUE="$label">|;
	}

	# Building select, textarea, or radio/check box if got here

	if ($type =~ /^(radio|check)/i) {
		return build_accessory_box($name, $type, $default, @opts);
	}
	elsif($type =~ /^textarea/i) {
		return build_accessory_textarea($name, $type, $default, @opts);
	}
	else {
		return build_accessory_select($name, $type, $default, @opts);
	}

}

# OLDTAGS
sub safe_tag {
	local($Safe_tag);
	$Safe_tag = 1;
	return do_tag ('', @_);
}
# END OLDTAGS

# MVASP
use vars qw/
		$CGI
		$CGI_array
		$Carts
		$Config
		%Db
		$DbSearch
		$Document
		$Items
		$Scratch
		$Session
		%Sql
		$Tag
		$TextSearch
		$Values
		/;

my $new_safe = new Safe 'MVASP';
$new_safe->share( qw/
							$CGI_array
							$CGI
							$Document
							%Db
							$DbSearch
							$Search
							$Carts
							$Config
							%Sql
							$Items
							$Scratch
							$Session
							$Tag
							$TextSearch
							$Values
							&tag_data
							&spec_check
							&Log
							&HTML
							&interpolate_html
					/
);

sub mvasp {
	my ($tables, $text) = @_;
	my @code;
	if($tables) {
		my (@tab) = grep /\S/, split /\s+/, $tables;
		for(@tab) {
			my $db = Vend::Data::database_exists_ref($_);
			next unless $db;
			$db = $db->ref();
			$db->touch();
			$Db{$_} = $db;
			$Sql{$_} = $db->[$Vend::Table::DBI::DBI]
				if $db =~ /::DBI/;
		}
	}
	while ( $text =~ s/(.*?)<%//s || $text =~ s/(.+)//s ) {
		push @code, <<EOF;
; my \$html = <<'_MV_ASP_EOF$^T';
$1
_MV_ASP_EOF$^T
chop(\$html);
		HTML( \$html );
EOF
		$text =~ s/(.*?)%>//s
			or last;;
		my $bit = $1;
		if ($bit =~ s/^\s*=\s*//) {
			$bit =~ s/;\s*$//;
			push @code, "; HTML( $bit );"
		}
		else {
			push @code, $bit, ";\n";
		}
	}
	my $asp = join "", @code;
#::logError("ASP CALL:\n$asp\n");
	return tag_perl ('new', $asp);
}

# END MVASP

sub tag_perl {
	my($args,$body,@args) = @_;
	my ($result,$file, $sub);
	my $code = '';
	my(@share);

	my $new;

	%Vend::Interpolate::Safe = ();
	@share = split /\s+/, $args if $args;
	my $safe;
	my @other;
	for(@share) {
		if( /^value/) {
			$Vend::Interpolate::Safe{'values'} = $::Values;
		}
		elsif($_ eq 'scratch') {
			$Vend::Interpolate::Safe{'scratch'} = $::Scratch;
		}
# MVASP
		elsif($_ eq 'new') {
			$new = 1;
			$safe = $new_safe, $MVASP::Safe = 1
				unless $Global::AllowGlobal->{$Vend::Cfg->{CatalogName}};
			$CGI     = \%CGI::values;
			$CGI_array     = \%CGI::values_array;
			$Carts   = $Vend::Session->{carts};
			$Config  = $Vend::Cfg;
			$Document = new Vend::Tags::Document;
			$DbSearch   = new Vend::DbSearch;
			$TextSearch = new Vend::TextSearch;
			$Scratch = $::Scratch;
			$Session = $Vend::Session;
			*Log = \&Vend::Util::logError;
			*HTML = \&Vend::Tags::Document::HTML;
			$Tag = new Vend::Tags;
		}
# END MVASP
		elsif($_ eq 'sub') {
			$sub = 1;
		}
# SQL
		elsif($_ eq 'sql') {
			@Vend::Interpolate::mv_sql_param = @Vend::Table::DBI::mv_sql_param;
			$Vend::Interpolate::mv_sql_array = $Vend::Table::DBI::mv_sql_array || [];
			$Vend::Interpolate::mv_sql_hash = $Vend::Table::DBI::mv_sql_hash || {};
			$Vend::Interpolate::mv_sql_hash_order
				= $Vend::Table::DBI::mv_sql_hash_order || [];
			push(@other, '@mv_sql_param', '$mv_sql_hash', '$mv_sql_array');
		}
# END SQL
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
		elsif($_ eq 'frames') {
			$Vend::Interpolate::Safe{'frames'} = $Vend::Session->{'frames'};
		}
		elsif($_ eq 'browser') {
			$Vend::Interpolate::Safe{'browser'} = $Vend::Session->{'browser'};
		}
		elsif($_ eq 'import') {
			$Vend::Interpolate::Safe{'values'} = $::Values;
			for(keys %{$::Values}) {
				$code .= '$' . $_;
				$code .= q! = $Safe{'values'}->{'! . $_ . "'};\n";
			}
		}
	}


	$body =~ tr/\r//d if $Global::Windows;

# MVASP
	if($new and $safe) {
		$safe->reval($body);
		$result = join "", @Vend::Tags::Out;
		undef $MVASP::Safe;
	}
	elsif($new) {
		eval($body);
		$result = join "", @Vend::Tags::Out;
	}
	else {
# END MVASP
		$safe = new Safe
			unless defined $safe;
		$safe->untrap(@{$Global::SafeUntrap})
			if $Global::SafeUntrap;
		$safe->share(qw/
					%Safe &do_tag	&tag_data	&interpolate_html
				/);
# OLDTAGS
		$safe->share('&safe_tag');
# END OLDTAGS
		$safe->share(@other);

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

			eval {@_ = eval $body};

			if($@) {
				logError("Bad args to perl sub $name for page $CGI::path_info: $@");
				return '';
			}

			if (defined $::Scratch->{$name}) {
				$result = $safe->reval( '@_ = ' . $body . ';' . $code .
							$::Scratch->{$name});
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
# MVASP
	}
# END MVASP

	if ($@) {
		my $msg = $@;
		logError( errmsg('Interpolate.pm:2', "Safe: %s\n%s\n" , $msg, $body) );
		logGlobal( errmsg('Interpolate.pm:2', "Safe: %s\n%s\n" , $msg, $body) );
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
			my $esc = $Vend::Cfg->{NewEscape} ? '%' : '.';
			my $se = $text;
			$se =~ s/(\W)/$esc . sprintf("%02x", ord($1))/ge;
			return $string . ']' unless $text;
			return $string . '/se=' . $se . "]$text";
		}
# SQL
		elsif($arg =~ m!^\s*sql
					(/?$Codere)?
					(?:\s+)?
					($Codere)?
					(?:\s+)?
					($Codere)?
					!iox ) {
			my $string = "scan$1";
			my $arg = $2;
			$string .= '/st=sql' unless $string =~ m:/st=sql:;
			$text =~ s/(\W)/'%' . sprintf("%02x", ord($1))/ge;
			return tag_area(($string . '/sq=' . $text), $arg);
		}
# END SQL
		elsif($arg =~ /^\s*import$Mand(?:\s+)?(.*)/i ) {
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
		elsif($arg =~ /^\s*each([-_]\w)?$Mandx/i ) {
			my $with = $1;
			my $base = $2;
			my $db = database_exists_ref($base) 
				or do {
					logError("tag each: unknown database '$base'");
					return '';
				};
			$db = $db->ref();
			my $key;
			my $out = '';
			my $i = 1;
			# See if we are to sort, and do so
			if($text =~ m#^\s*$T{'sort'}([^\]]*)$T#) {
				my @out;
				while(($key) = $db->each_record()) {
					push (@out, $key);
				}
				return tag_loop_list($with, (join "\n", @out), undef, $text);
			}
			else {
				my $sub = $with ? \&loop_with : \&loop_substitute;
				while(($key) = $db->each_record()) {
					$out .= &$sub($key, $text, $i++, $with);
				}
				return $out;
			}
		}
		elsif($arg =~ /^\s*touch$Mand/i ) {
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
			return strftime($text, localtime());
		}
		elsif($arg =~ /^\s*untaint\b/i ) {
			my(@vars) = split /\s+/, $text;
			for(@vars) {
				next unless defined 
					$::Values->{$_};
				$::Values->{$_} =~ /($All)/o;
				$::Values->{$_} = $1;
			}
			return '';
		}
		elsif($arg =~ /^\s*mime(?:\s+)?([\s\S]+)?/i ) {
			my $opt = $1 || '';
			my $id;
			$Vend::TIMESTAMP = strftime("%y%m%d%H%M%S", localtime())
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
							$Mand
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

sub do_flag {
	my($flag, $arg) = @_;

	$flag =~ s/^\s+//;
	$flag =~ s/\s+$//;
	if($flag =~ /^write$/i) {
		my @args = Text::ParseWords::shellwords($arg);
		for(@args) {
			$Vend::WriteDatabase{$_} = 1;
			$Vend::Cfg->{DynamicData}->{$_} = 1;
#print("Flagged database '$_' for write\n") if $Global::DEBUG;
		}
	}
	elsif($flag =~ /^debug$/i) {
# DEBUG
#		my ($add, $reverse, $debug, @args);
#		@args = split /[\s,]+/, $arg;
#
#		foreach $add (@args) {
#			$reverse = ($add =~ s/^!//) ? 1 : 0;
#			$add = $Global::DHASH{uc $add} if $add =~ /[^\d]/;
#			# !OFF will turn off anyway
#			($debug = 0, last) if $add eq '0';
#
#			unless($reverse) {
#				$debug |= $add;
#			}
#			else {
#				$add ^= 0xFFFF;
#				$debug &= $add;
#			}
#		}
#	
#		unless ($Global::AllowGlobal{$Vend::Cfg->{CatalogName}}) {
#			$debug &= 0x7FF;
#			$Global::DEBUG &= (4096 | 2048) if ! $debug;
#		}
#		else {
#			$Global::DEBUG = 0 if $debug == 0;
#		}
#
#		$Global::DEBUG |= $debug;
#
#		if($Global::DEBUG | $Global::DHASH{COMMENT} ) {
#			$Vend::DebugComment = 1;
#		}
#		else {
#			undef $Vend::DebugComment;
#		}
#		logGlobal("Called debug change: arg=$arg called=$debug final=$Global::DEBUG");
#
# END DEBUG
	}
	elsif($flag =~ /^build$/i) {
		$Vend::ForceBuild = 1;
		if($arg) {
			$Vend::ScanName = Vend::Util::escape_chars(interpolate_html($arg));
		}
	}
	elsif($flag =~ /^cache$/i) {
		$Vend::ForceCache = 1;
	}
	elsif($flag =~ /^checkhtml$/i) {
		$Vend::CheckHTML = 1;
	}
    elsif($flag =~ /^cleanhtml$/i and defined $HTML::Clean::VERSION) {
        $Vend::CleanHTML = 1;
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

	$arg =~ /(>?$Coderex)(?:\s+)?(\w+)?/o;
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
			@fields = Text::ParseWords::shellwords $_;
			logData($file, @fields)
				or return '';
		}
	}
	elsif($op =~ /^text/) {
		Vend::Util::writefile($file, $data)
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
		if($type) {
			$file = "$file $type";
		}
		do_log($file, $text);
	}
	elsif ($op eq 'each') {
		do_tag("each $base", $text);
	}
	elsif ($op eq 'header') {
		$Vend::ContentType = $type if $type;
		return '' unless $text;
		do_tag(join(" ", $op, $base, $file), $text);
	}
	elsif ($op eq 'export') {
		Vend::Data::export_database($base, $file, $type);
	}
	elsif (!$op) {
		do_tag('', $text);
	}
	else {
		do_tag(join(" ", $op, $base, $file, $type), $text);
	}
}

# Returns the text of a user entered field named VAR.
sub tag_cgi {
    my($var) = @_;
    my($value);

	$value = $CGI::values{$var} || '';
    if ($value) {
		# Eliminate any MiniVend tags
		$value =~ s~<([A-Za-z]*[^>]*\s+[Mm][Vv]\s*=\s*)~&lt;$1~g;
		$value =~ s/\[/&#91;/g;
    }
    return $value;
}

# Returns the text of a user entered field named VAR.
sub tag_value_extended {
    my($var, $opt) = @_;

	my $yes = $opt->{'yes'} || 1;
	my $no = $opt->{'no'} || '';

	if($opt->{'test'}) {
		$opt->{'test'} =~ /(?:is)?file/i
			and
			return defined $CGI::file{$var} ? $yes : $no;
		$opt->{'test'} =~ /defined/i
			and
			return defined $CGI::file{$var} ? $yes : $no;
		return length $CGI::value{$var}
			if $opt->{'test'} =~ /length|size/i;
		return '';
	}

	return '' unless defined $CGI::values{$var};
	
	if($opt->{file_contents}) {
		return '' if ! defined $CGI::file{$var};
		return $CGI::file{$var};
	}

	if($opt->{outfile}) {
		my $file = $opt->{outfile};
		$file =~ s/^\s+//;
		$file =~ s/\s+$//;
		if($file =~ m{^([A-Za-z]:)?[\\/.]}) {
			logError("attempt to write absolute file $file");
			return '';
		}
		if($opt->{ascii}) {
			my $replace = $^O =~ /win32/i ? "\r\n" : "\n";
			if($CGI::file{$var} !~ /\n/) {
				# Must be a mac file.
				$CGI::file{$var} =~ s/\r/$replace/g;
			}
			elsif ( $CGI::file{$var} =~ /\r\n/) {
				# Probably a PC file
				$CGI::file{$var} =~ s/\r\n/$replace/g;
			}
			else {
				$CGI::file{$var} =~ s/\n/$replace/g;
			}
		}
		Vend::Util::writefile(">$file", \$CGI::file{$var})
			and return $opt->{'yes'} || '';
		return $opt->{'no'} || '';
	}

	my $joiner;
	if (defined $opt->{'joiner'}) {
		$joiner = $opt->{'joiner'};
		if($joiner eq '\n') {
			$joiner = "\n";
		}
		elsif($joiner =~ m{\\}) {
			$joiner = $ready_safe->reval("qq{$joiner}");
		}
	}
	else {
		$joiner = ' ';
	}

	my $index = defined $opt->{'index'} ? $opt->{'index'} : '*';

	$index = '*' if $index =~ /^\s*\*?\s*$/;

	my @ary;
	@ary = split /\0/, $CGI::values{$var};

	return join " ", 0 .. $#ary if $opt->{elements};

	eval {
		@ary = @ary[$ready_safe->reval( $index eq '*' ? "0 .. $#ary" : $index )];
	};
	logError("value-extend $var: bad index") if $@;

	return join $joiner, @ary;
}


# Returns the text of a user entered field named VAR.
sub tag_value {
    my($var,$esc,$set,$hide) = @_;
    my($value);

	local($) = 0;
	$::Values->{$var} = $set if defined $set;
	$value = $::Values->{$var} || '';
    if ($value) {
		# Eliminate any MiniVend tags
		$value =~ s~<([A-Za-z]*[^>]*\s+[Mm][Vv]\s*=\s*)~&lt;$1~g;
		$value =~ s/\[/&#91;/g;
		$value =~ s/\]/&#93;/g;
		$value =~ s/(['"])/\\$1/g if $esc;
    }
	return '' if $set and $hide;
    return $value;
}

# Returns the contents of a file.  Won't allow any arbitrary file unless
# NoAbsolute is not set.
sub tag_file {
	my ($file, $type) = @_;
    return readfile($file, $Global::NoAbsolute)
		unless $type;
	my $text = readfile($file, $Global::NoAbsolute);
	if($type =~ /mac/i) {
		$text =~ tr/\n/\r/;
	}
	elsif($type =~ /dos|window/i) {
		$text =~ s/\n/\r\n/g;
	}
	elsif($type =~ /unix/i) {
		if($text=~ /\n/) {
			$text =~ tr/\r/\n/;
		}
		else {
			$text =~ s/\r\n/\n/g;
		}
	}
	return $text;
}

# Returns the text of a user entered field named VAR.
# Same as tag value except returns 'default' if not present
sub tag_default {
    my($var, $default, $set) = @_;
    my($value);
	$default = 'default' if ! length $default;
	if(! $default and $var =~ s/\s+(.*)//s) {
		$default = $1;
	}
    if (defined ($value = $::Values->{$var}) and $value) {
		# do nothing
    } elsif ($set) {
		$value = $::Values->{$var} = $default;
    } else {
		$value = $default;
    }
	return $set ?  '' : $value;
}

sub esc {
	my $string = shift;
	$string =~ s!(\W)!'%' . sprintf '%02x', ord($1)!eg;
	return $string;
}

# Escapes a scan reliably in three different possible ways
sub escape_scan {
	my ($scan, $ref) = @_;

	if($scan =~ /^\s*(?:sq\s*=\s*)?select\s+/im) {
		$scan = Vend::Scan::sql_statement($scan, $ref || $::Scratch);
	}

	return join '/', 'scan', escape_mv('/', $scan);
}

sub escape_mv {
	my ($joiner, $scan, $not_scan) = @_;

	my @args;

	if(index($scan, "\n") != -1) {
		$scan =~ s/^\s+//mg;
		$scan =~ s/\s+$//mg;
		@args = split /\n+/, $scan;
	}
	elsif($scan =~ /&\w\w=/) {
		@args = split /&/, $scan;
	}
	else {
		$scan =~ s!::!__ESLASH__!g;
		@args  = split m:/:, $scan;
	}
	@args = grep $_, @args;
	for(@args) {
		s!/!__SLASH__!g unless defined $not_scan;
		s!\0!__NULL__!g;
		s!(\w\w=)(.*)!$1 . esc($2)!eg
			or (undef $_, next);
		s!__SLASH__!::!g unless defined $not_scan;
	}
	return join $joiner, grep(defined $_, @args);
}

sub form_link {
	my ($href, $arg, $secure, $opt) = @_;

	if( $href and $opt->{'alias'}) {
		my $aloc = $opt->{once} ? 'one_time_path_alias' : 'path_alias';
		$Vend::Session->{$aloc}{$href} = {}
			if not defined $Vend::Session->{path_alias}{$href};
		$Vend::Session->{$aloc}{$href} = $opt->{'alias'};
	}

	my $base = ! $secure ? ($Vend::Cfg->{VendURL}) : $Vend::Cfg->{SecureURL};

	$href = 'process' unless $href;
	$href =~ s:^/+::;
	$href = "$base/$href"     unless $href =~ /^\w+:/;

	my $extra = <<EOF;
mv_session_id=$Vend::Session->{'id'}
EOF
	$arg = '' if ! $arg;
	$arg = "mv_arg=$arg\n" if $arg && $arg !~ /\n/; 
	$extra .= $arg . $opt->{'form'};
	$extra = escape_mv('&', $extra, 1);
	return $href . '?' . $extra;
}

sub tag_page {
    my($page, $arg, $secure, $opt) = @_;

	return '<A HREF="' . form_link(@_) . '">' if defined $opt and $opt->{form};

	if ($page eq 'scan') {
		$page = escape_scan($arg);
		undef $arg;
	}

	my $urlroutine = $secure ? \&secure_vendUrl : \&vendUrl;

	while($Vend::Cookie and ! $arg) {
		if(defined $Vend::StaticDBM{$page}) {
		  $page = $Vend::StaticDBM{$page} || $page;
		}
		elsif (defined $Vend::Cfg->{StaticPage}{$page}) {
		  $page = $Vend::Cfg->{StaticPage}{$page}
					if $Vend::Cfg->{StaticPage}{$page};
		}
		else {
			last;
		}
		$page .= $Vend::Cfg->{StaticSuffix};
		return '<a href="' . $urlroutine->($page,undef,$Vend::Cfg->{StaticPath}) . '">';
	}
	
    return '<a href="' . $urlroutine->($page,$arg || undef) . '">';
}

# Returns an href which will call up the specified PAGE with TARGET reference.
# This is deprecated.
sub tag_pagetarget {
    my($page, $target, $arg, $secure) = @_;

    my($r, $anchor, $tmp);
	$tmp = $page;
	$tmp =~ s/(#.*)// and $anchor = $1;

	if ($page eq 'scan') {
		$page = escape_scan($arg);
		undef $arg;
	}

	my $urlroutine = $secure ? \&secure_vendUrl : \&vendUrl;

	if($Vend::Cookie and defined $Vend::Cfg->{StaticPage}{$tmp} and !$arg) {
		$tmp .= $Vend::Cfg->{StaticSuffix};
		$tmp .= $anchor if defined $anchor;
    	$r  = '<a href="' . $urlroutine->($tmp,'',$Vend::Cfg->{StaticPath});
	}
	else {
    	$r  = '<a href="' . $urlroutine->($page, $arg || undef);
	}

    $r .= '" TARGET="' . $target
        if defined $target and $Vend::Session->{'frames'};
    $r .= '">';
}

# Returns an href which will call up the specified PAGE.

sub tag_area {
    my($page, $arg, $secure, $opt) = @_;

	return form_link(@_) if defined $opt and $opt->{form};

	if ($page eq 'scan') {
		$page = escape_scan($arg);
		undef $arg;
	}

	my $urlroutine = $secure ? \&secure_vendUrl : \&vendUrl;

	while($Vend::Cookie and ! $arg) {
		if(defined $Vend::StaticDBM{$page}) {
		  $page = $Vend::StaticDBM{$page} || $page;
		}
		elsif (defined $Vend::Cfg->{StaticPage}{$page}) {
		  $page = $Vend::Cfg->{StaticPage}{$page}
					if $Vend::Cfg->{StaticPage}{$page};
		}
		else {
			last;
		}
		$page .= $Vend::Cfg->{StaticSuffix};
		return $urlroutine->($page,undef,$Vend::Cfg->{StaticPath});
	}
    return $urlroutine->($page, $arg);
}

# Returns an href which will call up the specified PAGE with TARGET reference.

sub tag_areatarget {
    my($page, $target, $arg, $secure) = @_;

	my($r,$anchor,$tmp);
	$tmp = $page;
	$tmp =~ s/(#.*)// and $anchor = $1;

	if ($page eq 'scan') {
		$page = escape_scan($arg);
		undef $arg;
	}

	my $urlroutine = $secure ? \&secure_vendUrl : \&vendUrl;

	if($Vend::Cookie and defined $Vend::Cfg->{StaticPage}{$tmp} and ! $arg) {
		$tmp .= $Vend::Cfg->{StaticSuffix};
		$tmp .= $anchor if defined $anchor;
    	$r = $urlroutine->($tmp,'',$Vend::Cfg->{StaticPath});
	}
    else {
        $r = $urlroutine->($page, $arg || undef);
    }

	$r .= '" TARGET="' . $target
		if defined $target and $Vend::Session->{'frames'};
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
	return '' unless $Vend::Cfg->{Rotate};
	my $ceiling = $_[0] || @{$Vend::Cfg->{'Rotate'}} || return '';
	my $floor   = $_[1] || 1;

	$ceiling--;
	$floor--;

	my $marker = "rotate$floor$ceiling";

	if($ceiling < 0 or $floor < 0) {
		$floor = 0;
		$ceiling = scalar  @{$Vend::Cfg->{'Rotate'}} - 1;
		logError "Bad ceiling or floor for rotate";
	}

    my $rotate;
	$rotate = $Vend::Session->{$marker} || $floor;

	if($rotate > $ceiling or $rotate < $floor ) {
		$rotate = $floor;
	}

	$Vend::Session->{$marker} = $rotate + 1;
	return $Vend::Cfg->{'Rotate'}->[$rotate];
}

# Returns a help item by name, if it exists
sub tag_help {
	my($help) = shift;
	# Move this to control section?
	if ($::Values->{mv_helpon}) {
		delete $::Values->{mv_helpoff};
		undef $::Values->{mv_helpon};
	}
	return '' if defined $::Values->{'mv_helpoff'};
    if (defined $Vend::Cfg->{'Help'}{$help}) {
		return $Vend::Cfg->{'Help'}{$help};
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

sub shipmode_select {
	return undef unless $Vend::Cfg->{CustomShipping};
	my($sel,$loc,$val,$modes,$currency,$ship);
	$ship = $Vend::Cfg->{Shipping_repository};
	return undef unless $ship;
	my (@select) = grep $::Values->{$_},
						split /[\s,]+/, $Vend::Cfg->{CustomShipping};
	my (@locales) = sort keys %$ship;
	foreach $sel (@select) {
		$val = $::Values->{$sel};
		next unless $val;
		$val =~ tr/-a-z0-9_ //cd;
		foreach $loc (map {$_ = $ship->{$_}} @locales) {
			next unless defined $loc->{$sel};
			logError("checking ship locale '$loc->{$sel}' val=$val");
			if($loc->{$sel} =~ /\b$val\b/i) {
				$modes = $loc->{'modes'} || '';
				$currency = $loc->{currency_symbol} || '';
				last;
			}
		}
	}
	my $out =  q{<SELECT NAME="mv_shipmode">};
	LOOK: {
		last LOOK unless $modes;
		@select = split /[\s,]+/, $modes;
		$modes = '';
		my $mode;
		my $cost;
		foreach $mode (@select) {
			$cost = shipping($mode);
			next unless $cost > 0;
			$modes .= qq{<OPTION VALUE="$mode"};
			$modes .= " SELECTED"
				if $mode eq $::Values->{mv_shipmode};
			$modes .= '>';
			$modes .= tag_shipping_desc($mode);
			$modes .= $currency || ' - ';
			$modes .= currency($cost);
		}
	}
	if(! $modes ) {
		my $def_message = $Vend::Cfg->{Variable}->{MV_SHIPPING_DEFAULT}
						|| 'Contact us for shipping cost';
		$modes = qq{<OPTION VALUE="default"> $def_message };
	}
	$out .= $modes;
	$out .= '</SELECT>';
}

# Returns the shipping description.

sub tag_shipping_desc {
	my $mode = 	shift;
	$CacheInvalid = 1 unless $mode;
	$mode = $mode || $::Values->{'mv_shipmode'} || 'default';
	if($mode eq 'mv_shipmode') {
		return shipmode_select();
	}
	return '' unless defined $Vend::Cfg->{'Shipping_desc'}->{$mode};
	$Vend::Cfg->{'Shipping_desc'}->{$mode};
}

# Returns the total cost of items ordered.

sub total_cost {
	my($cart) = @_;
    my($total, $i, $save);

	if ($cart) {
		$save = $Vend::Items;
		tag_cart($cart);
	}

	$total = 0;

	my $shipping = shipping();
	if(defined $::Values->{mv_handling}) {
		my @modes = split /[\s\0,]+/, $::Values->{mv_handling};
		for(@modes) {
			$total += shipping($_);
		}
	}

    $total += subtotal();

    $total += $shipping;
    $total += salestax();
	$Vend::Items = $save if defined $save;
	$Vend::Session->{latest_total} = $total;
    return $total;
}

# Returns the href to process the completed order form or do the search.

sub tag_process_target {
	my($frame,$security) = @_;
	my $frametag = '';

	if($frame and $Vend::Session->{'frames'}) {
    	$frametag = '" TARGET="'. $frame
			unless ! defined $frame or $frame eq 'none'
					    or
					$::Scratch->{mv_ignore_frame};
	}

	if ($security) {
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
		! $::Scratch->{mv_ignore_frame} )
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
			unless $::Scratch->{mv_ignore_frame};
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
		my $msg;
		$msg = $Vend::Session->{active_routine} || '';
		$msg .= $@;
		logGlobal( errmsg('Interpolate.pm:3', "Safe: %s\n%s\n" , $msg, $body) );
		logError( errmsg('Interpolate.pm:3', "Safe: %s\n%s\n" , $msg, $body) );
		return 0;
	}
	return $result;
}

sub tag_self_contained_if {
	my($base, $term, $operator, $comp, $body) = @_;

	my ($else,$elsif,@addl);
	
	local($) = 0;
#print("Calling self_if with base=$base term=$term op=$operator comp=$comp\n") if $Global::DEBUG;
	if ($body =~ s#^\s*$T{'condition'}$T($Some)$T{'/condition'}$T##o) {
		$comp = $1;
	}

	if ( $body =~ /\[[EeTtAaOo][hHLlNnRr][SsEeDd\s]/ ) {
		($body, $elsif, $else, @addl) = split_if($body);
	}

#::logGlobal("Additional ops found:\n" . join("\n", @addl) ) if @addl;

#print("self_if body=" . substr($body, 0, 20) . "... else=" .  substr($else, 0, 20) . "...\n") if $Global::DEBUG;

	unless(defined $operator || defined $comp) {
		$comp = '';
		undef $operator;
		undef $comp;
	}

	my $status = conditional ($base, $term, $operator, $comp, @addl);

	my $out;
	if($status) {
		$out = $body;
	}
	elsif ($elsif) {
		$else = '[else]' . $else . '[/else]' if $else;
		$elsif =~ s#(.*?)$T{'elsif'}\](.*)#$1${2}[/elsif]#s;
		$out = '[if ' . $elsif . $else . '[/if]';
	}
	elsif ($else) {
		$out = $else;
	}
	else {
		return '';
	}

	return $New ? $out : interpolate_html($out);
}


sub pull_if {
	my($string, $reverse) = @_;
	return pull_else($string) if $reverse;
	$string =~ s:$T{'else'}\]($All)$T{'/else'}\]\s*$::o;
	return $string;
}

sub pull_else {
	my($string, $reverse) = @_;
	return pull_if($string) if $reverse;
	my($r);
	if($string =~ s:$T{'else'}\]($All)$T{'/else'}\]\s*$::o) {
		$r = $1;
	}
	else {
		$r = '';
	}
	$r;
}

## ORDER PAGE

my (@Opts);
my (@Flds);
my %Sort = (

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


%Vend::Interpolate::Sort_field = (

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
		$r = &{$Vend::Interpolate::Sort_field{$Opts[$i]}}($a[$Flds[$i]], $b[$Flds[$i]]);
		return $r if $r;
	}
}

sub tag_sort {
    my($opts, $list, $joiner) = (@_); 
    $opts =~ s/^\s+//; 
    $opts =~ s/\s+$//; 
	if(index($opts,'[') > -1 or $opts =~ /__/) {
		$opts = interpolate_html($opts);
	}
	my @codes;
	if (ref $list) {
		undef $joiner;
	}
	else {
		$list =~ s/^\s+//;
		$list =~ s/\s+$//;
		if(defined $joiner) {
			@codes = split $joiner, $list;
		}
		else {
			@codes = split /\s+/, $list;
		}
		$joiner = " " unless defined $joiner;
	}

	my ($start, $end, $num);

    my @opts =  split /\s+/, $opts;
    my @option; my @bases; my @fields;
 
    for(@opts) {
        my ($base, $fld, $opt) = split /:/, $_;

		if($base =~ /^([-=+])(\d+)-?(\d*)/) {
			my $op = $1;
			if    ($op eq '-') { $start = $2 }
			elsif ($op eq '+') { $num   = $2 }
			elsif ($op eq '=') {
				$start = $2;
				$end = ($3 || undef);
			}
			next;
		}
		
        push @bases, $base;
        push @fields, $fld;
        push @option, (defined $Vend::Interpolate::Sort_field{$opt} ? $opt : 'none');
    }

	if(defined $end) {
		$num = 1 + $end - $start;
		$num = undef if $num < 1;
 	}

    my $i;
    my $routine = 'sub { ';
    for( $i = 0; $i < @bases; $i++) {
            $routine .= '&{$Vend::Interpolate::Sort_field{"' . $option[$i] . '"}}(' . "\n";
            $routine .= "tag_data('$bases[$i]','$fields[$i]'," . '$a),' . "\n";
            $routine .= "tag_data('$bases[$i]','$fields[$i]'," . '$b) ) or ';
    }
    $routine .= '0 or &{$Vend::Interpolate::Sort_field{"none"}}($a,$b); }';
#print("Sort routine: $routine\n") if $Global::DEBUG;
    my $code = eval $routine;  
    die "Bad sort routine\n" if $@;

	#Prime the sort? Prevent variable suicide??
	&{$Vend::Interpolate::Sort_field{'n'}}('31', '30');

eval {

	use locale;
	if($::Scratch->{mv_locale}) {
		POSIX::setlocale(POSIX::LC_COLLATE(),
			$::Scratch->{mv_locale});
	}

	if(defined $joiner) {
		@codes = sort {&$code} @codes;
	}
	else {
		@codes = sort {&$code} @$list;
	}
};

	if(defined $start and $start > 1) {
		splice(@codes, 0, $start - 1);
	}

	if(defined $num) {
		splice(@codes, $num);
	}

	if(defined $joiner) {
		return join $joiner, @codes;
	}
	else {
		return \@codes;
	}
}

my %Prev;

sub check_change {
	my($name, $value, $text) = @_;
	# $value is case-sensitive flag if passed text;
	if(defined $text) {
		$text =~ s:$T{'condition'}\]($All)$T{'/condition'}\]::o;
		$value = $value ? lc $1 : $1;
	}
	my $prev = $Prev{$name} || undef;
	$Prev{$name} = $value || '';
	if(defined $text) {
		return pull_if($text) if ! defined $prev or $value ne $prev;
		return pull_else($text);
	}
	return 1 unless defined $prev;
	return $value eq $prev ? 0 : 1;
}

sub tag_search_region {
	my($params, $page) = @_;
	my ($c, $more);
	unless($params) {
		$c = '';
	}
	else {
		$c = {mv_search_immediate => 1};
		$params = "mp=$params"
			unless $params =~ /[=\s]/;
		$params = escape_scan($params);
		Vend::Scan::find_search_params($c, $params);
	}
	my ($q, $o) = Vend::Scan::perform_search($c);
#::logGlobal("search_region: q=$q o=$o");
	search_page($q, $o, $page);
}

sub tag_search {
	my($params) = @_;
	my $c = {mv_list_only => 1};
	unless($params) {
		$params = $::Scratch->{mv_search_arg};
	}
	$params = "mp=$params"
		unless $params =~ /[=\s]/;
	$params = escape_scan($params);
	Vend::Scan::find_search_params($c, $params);
	my $out = Vend::Scan::perform_search($c);
	return $out if defined $c->{mv_return_format};
	push @$out, "" if $c->{mv_search_line_return};
	return "" unless ref $out;
	return join "\n", @$out;
}

sub find_sort {
	my($text) = @_;
	return undef unless defined $$text and $$text =~ s#$T{'sort'}(([\s\]])$All)#$1#;
	my $options = find_close_square($$text);
	$$text = substr( $$text,length($options) + 1 )
				if defined $options;
	$options = interpolate_html($options) if index($options, '[') != -1;
	return $options || '';
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

#	if($text =~ s/$T{'onchange'}$Mand\]//i) {
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
		if (ref $g->{return_fields}) {
			@fieldnames = @{$fields}[@{$g->{return_fields}}]
				if ref $g->{return_fields};
		}
		else {
			@fieldnames = @$fields;
		}
		for(@fieldnames) {
			$field_hash{$_} = $ptr++;
		}
		
	}
			

	SORT: {
		last SORT unless $text =~ m!^\s*$T{'sort'}!i;
		my $options = '';
		if ($text =~ s!$T{'sort'}\]($Some)$T{'/sort'}\]!!o) {
			$options = $1;
			$options = interpolate_html($options);
		}
		else {
			$options = find_sort(\$text);
		}
			
		$options =~ s/^\s+//;
		$options =~ s/\s+$//;

		if( $options =~ m#^$Coderex:$Coderex(?::[NnRrRf]{0,2})?($|\s)#o or
			$options =~ m#^[-=+]#o
			) {
				$obj = tag_sort($options, $obj);
# DEBUG
#Vend::Util::logDebug
#("Sorting, options $options\n")
#	if ::debug(0x1);
# END DEBUG
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

	my $return;
	if($Vend::OnlyProducts) {
		$text =~ s#$T{'item-field'}$Spacef#[item-data $Vend::OnlyProducts #g;
		$text =~ s#$T{'if-field'}\s+(!\s*)?#[if-data $1$Vend::OnlyProducts #g;
		$text =~ s#$T{'/if-field'}\]#[/if-data]#g;
	}
    foreach $item (@$obj) {
		chomp($item);
		@fields = split /$delim/o, $item;
		
		#($code, $link) = split(/\s+/,$item, 2);
		#$link = $code if is_yes($Vend::Cfg->{'UseCode'});
		$link = $code = $fields[0];

		$count++;

	    $run = $text;
		$run =~ s#$T{'item-alternate'}$Opt\]($Some)$T{'/item-alternate'}\]#
				  $count % ($1 || $::Values->{mv_item_alternate} || 2)
				  							?	pull_else($2)
											:	pull_if($2)#geo;
	    $run =~ s:$T{'item-param'}$Spacef(\d+)\]:$fields[$1]:go;
		$run =~ s#$T{'if-param'}$Spacef(!?)\s*($Codere)\]($Some)$T{'/if-param'}\]#
				  $fields[$field_hash{$2}]	?	pull_if($3,$1)
											:	pull_else($3,$1)#geo;
	    $run =~ s:$T{'item-param'}$Mandf\]:$fields[$field_hash{$1}]:go;
		$run =~ s#$T{'if-field'}$Spacef(!?)\s*($Codere)\]($Some)$T{'/if-field'}\]#
				  product_field($2, $code)	?	pull_if($3,$1)
											:	pull_else($3,$1)#geo;
        tag_item_data_row($code,\$run);
	    $run =~ s:$T{'item-increment'}\]:$count:go;
		$run =~ s:$T{'item-accessories'}($Spacef[^\]]+)?\]:
						tag_accessories($code,'',$1):geo;
		$run =~ s:$T{'item-code'}\]:$code:go;
		$run =~ s:$T{'item-description'}\]:product_description($code):geo;
		$run =~ s:$T{'item-field'}$Mandf\]:product_field($1, $code):geo;
		$run =~ s#$T{'item-link'}\]#"[page $linkdir$link]"
						. $linkvalue . '[/page]'#geo;
		$run =~ s!$T{'item-price'}(?:\s+)?(\d+)?$Optx\]!
					currency(product_price($code,$1), $2)!geo;

		1 while $run =~ s!	$T{'on-change'} $Spacef ($Codere)\] \s*
						$T{'condition'}\]
						($Some)
						$T{'/condition'}\]
						($Some)
					$T{'/on-change'} \s+ \1 \]!
							check_change($1,$2)
											?	pull_if($3)
											:	pull_else($3)!xgeo;
		$run =~ s#$T{'item-last'}\]
                    \s* ($Some) \s*
                $T{'/item-last'}\]#
                    my $tmp = interpolate_html($1);
                    if($tmp && $tmp < 0) {
                        last;
                    }
                    elsif($tmp) {
                        $return = 1;
                    }
                    '' #xoge;
		$run =~ s#$T{'item-next'}\]
                    \s* ($Some) \s*
                $T{'/item-next'}\]#
                    interpolate_html($1) != 0 ? next : '' #xoge;

		$r .= $run;
		last if $return;
    }
    $r;
}

sub tag_more_list {
	my($r,$q,$next_anchor, $prev_anchor,
		$page_anchor, $border, $border_selected) = @_;
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

	if($r =~ s:\[border\]($All)\[/border\]::i) {
		$border = $1;
		$border =~ s/\D//g;
	}
	if($r =~ s:\[border[-_]selected\]($All)\[/border[-_]selected\]::i) {
		$border = $1;
		$border =~ s/\D//g;
	}

	if(! $chunk or $chunk >= $total) {
		return '';
	}

	$border = qq{ BORDER="$border"} if defined $border;
	$border_selected = qq{ BORDER="$border_selected"}
		if defined $border_selected;

	$adder = ($total % $chunk) ? 1 : 0;
	$pages = int($total / $chunk) + $adder;
	$current = int($next / $chunk) || $pages;


	if($first) {
		$first = 0 if $first < 0;
		unless ($prev_anchor) {
			if($r =~ s:\[prev[-_]anchor\]($All)\[/prev-anchor\]::i) {
				$prev_anchor = $1;
			}
			else {
				$prev_anchor = 'Previous';
			}
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
			$list .= vendUrl("scan/MM=$arg");
			$list .= '">';
			$list .= $prev_anchor;
			$list .= '</A>';
		}
	}
	else {
		$r =~ s:\[prev[-_]anchor\]($All)\[/prev[-_]anchor\]::i;
	}
	
	if($next) {
		unless ($next_anchor) {
			if($r =~ s:\[next[-_]anchor\]($All)\[/next[-_]anchor\]::i) {
				$next_anchor = $1;
			}
			else {
				$next_anchor = 'Next';
			}
		}
		else {
			$next_anchor = qq%<IMG SRC="$next_anchor"$border>%;
		}
		$last = $next + $chunk - 1;
		$last = $last > ($total - 1) ? $total - 1 : $last;
		$arg = "$session:$next:$last:$chunk:$mod";
		$next_tag .= '<A HREF="';
		$next_tag .= vendUrl("scan/MM=$arg");
		$next_tag .= '">';
		$next_tag .= $next_anchor;
		$next_tag .= '</A>';
	}
	else {
		$r =~ s:\[next[-_]anchor\]($All)\[/next[-_]anchor\]::i;
	}
	
	unless ($page_anchor) {
		if($r =~ s:\[page[-_]anchor\]($All)\[/page[-_]anchor\]::i) {
			$page_anchor = $1;
			$page_anchor =~ s/\$PAGE\$/__PAGE__/i;
		}
		else {
			$page_anchor = '__PAGE__';
		}
	}
	elsif ($page_anchor ne 'none') {
		$page_anchor = qq%<IMG SRC="$page_anchor?__PAGE__"__BORDER__>%;
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
			$pa =~ s/__BORDER__/$border_selected || $border || ''/e;
			$list .= qq|<STRONG>$pa</STRONG> | ;
		}
		else {
			$pa =~ s/__BORDER__/$border || ''/e;
			$arg = "$session:$next:$last:$chunk:$mod";
			$list .= '<A HREF="';
			$list .= vendUrl("scan/MM=$arg");
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
					html 0
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

	if($spec{'html'} && $spec{'wrap'}) {
		logDebug("tag_column: can't have 'wrap' and 'html' specified at same time.");
		$spec{wrap} = 0;
	}

	# What was I doing here?
	#$text =~ s/^\s+\n?//;
	#$text =~ s/\s+\n?$//;
	#$text =~ s/\s*\n\s*/ /;
	$text =~ s/\s+/ /g;

	my $len = sub {
		my($txt) = @_;
		if (1 or $spec{html}) {
			$txt =~
			s{ <
				   (
					 [^>'"] +
						|
					 ".*?"
						|
					 '.*?'
					) +
				>
			}{}gsx;
		}
		return length($txt);
	};

	$usable = $spec{'width'} - $spec{'gutter'};
	return "BAD_WIDTH" if  $usable < 1;
	
	if($spec{'align'} =~ /^l/) {
		$f = sub {
					$_[0] .
					' ' x ($usable - $len->($_[0])) .
					' ' x $spec{'gutter'};
					};
	}
	elsif($spec{'align'} =~ /^r/) {
		$f = sub {
					' ' x ($usable - $len->($_[0])) .
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
	elsif (! $spec{'html'}) {
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
				 		($Some)
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

my %Data_cache;

sub tag_item_data_row {
	my ($key, $text) = @_;
	my ($row, $table);
	my $done;
    while($$text =~ /
                (?:$T{'item-data'}|$T{'if-data'})  # Want the last one
                \s+ !?\s* ($Codere)\s
                (?!$All(?:$T{'item-data'}|$T{'if-data'}))
                /xo) {
		$table = $1;
		if($Vend::UPPERCASE{$table}) {
			$$text =~ s#($T{'if-data'}$Spacef!?$Spaceo$table)$Mandf\]#$1 \U$2]#g;
			$$text =~ s#($T{'item-data'}$Spacef$table)$Mandf\]#$1 \U$2]#g;
		}
		$row = $Data_cache{"$table.$key"}
				|| ( $Data_cache{"$table.$key"}
						= Vend::Data::database_row($table, $key)
					)
				|| {};
		$done = 1;
		$$text =~ s#$T{'if-data'}$Spacef(!?)$Spaceo$table$Mandf\]
				($Some)
				$T{'/if-data'}\]#
				$row->{$2}	? pull_if($3,$1)
							: pull_else($3,$1)#xge
			and undef $done;
		$$text =~ s/$T{'item-data'}$Spacef$table$Mandf\]/$row->{$1}/g
			and undef $done;
		last if $done;
	}
	return $_;
}

sub tag_loop_data_row {
	my ($key, $text, $with) = @_;
	$with = '' unless defined $with;
	my ($row, $table);
	my $done;
    while($$text =~ /
                (?:$T{'loop-data'}|$T{'if-loop-data'})  # Want the last one
                $with $Spacef !?\s* ($Codere) \s
                (?!$All(?:$T{'loop-data'}|$T{'if-loop-data'})$with$Spacef)
                /x) {
		$table = $1;
		$row = $Data_cache{"$table.$key"}
				|| ( $Data_cache{"$table.$key"}
						= Vend::Data::database_row($table, $key)
					)
				|| {};
		if($Vend::UPPERCASE{$table}) {
			$$text =~ s#($T{'if-loop-data'}$Spacef!?$Spaceo$table)$Mandf\]#$1 \U$2]#g;
			$$text =~ s#($T{'loop-data'}$Spacef$table)$Mandf\]#$1 \U$2]#g;
		}
		$done = 1;
		$$text =~ s#$T{'if-loop-data'}$with$Spacef(!?)\s*$table$Mand\]
				($Some)
				$T{'/if-loop-data'}$with\]#
				$row->{$2}	? pull_if($3,$1)
							: pull_else($3,$1)#xge
			and undef $done;
		$$text =~ s/$T{'loop-data'}$with$Spacef$table$Mand\]/$row->{$1}/g
			and undef $done;
		last if $done;
	}
	return $_;
}

sub query {
	my ($query, $opt, $text) = @_;
	$opt->{table} = $Vend::Cfg->{ProductFiles}[0]
		unless $opt->{table};
	my $db = $Vend::Database{$opt->{table}} ;
	return $opt->{failure} if ! $db;

	if($db =~ /Vend::Table::DummyDB/) {
		$db = $db->ref();
		$db->touch();
	}
	return $db->do_query($opt, $text);
}

# SQL
sub tag_sql_data_row {
	my $key = shift;
	my $text = shift;
	my ($row, $table);
	my $done;
    while($$text =~ /
                (?:$T{'sql-data'}|$T{'if-sql-data'})  # Want the last one
                $Spacef !?$Spaceo ($Codere)\s
                (?!$All(?:$T{'sql-data'}|$T{'if-sql-data'}))
                /xo) {
		$table = $1;
		$row = $Data_cache{"$table.$key"}
				|| ( $Data_cache{"$table.$key"}
						= Vend::Data::database_row($table, $key)
					)
				|| {};
		$done = 1;
		if($Vend::UPPERCASE{$table}) {
			$$text =~ s#($T{'if-sql-data'}$Spacef!?$Spaceo$table)$Mandf\]#$1 \U$2]#g;
			$$text =~ s#($T{'sql-data'}$Spacef$table)$Mandf\]#$1 \U$2]#g;
		}
		$$text =~ s#$T{'if-sql-data'}$Spacef(!?)$Spaceo$table$Mand\]
				($Some)
				$T{'/if-sql-data'}\]#
				$row->{$2}	? pull_if($3,$1)
							: pull_else($3,$1)#xge
			and undef $done;
		$$text =~ s/$T{'sql-data'}$Spacef$table$Mand\]/$row->{$1}/g
			and undef $done;
		last if $done;
	}
	return $_;
}
# END SQL

sub tag_item_list {
	my($cart,$text) = @_;
	my($r, $i, $item, $link, $code, $db, $linkvalue, $run);
	$r = "";

	$cart = get_cart($cart);
	$CacheInvalid = 1;

	# See if we are to sort, and do so
	my $opts = find_sort(\$text);
	$cart = sort_cart( $opts, $cart) if defined $opts;

	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};
	my $linkdir = $Vend::Cfg->{'ItemLinkDir'};

	my $return;
	if($Vend::OnlyProducts) {
		$text =~ s/$T{'item-field'}$Spacef/[item-data $Vend::OnlyProducts /g;
		$text =~ s/$T{'if-field'}$Spacef(!$Spaceo)?/[if-data $1$Vend::OnlyProducts /g;
		$text =~ s!$T{'/if-field'}\]![/if-data]!g;
	}
	foreach $i (0 .. $#$cart) {
		$item = $cart->[$i];
		next if $code = $Vend::Cfg->{TransparentItem} and is_yes($item->{$code});
		$item->{mv_cache_price} = undef;
		$code = $item->{'code'};

		$run = $text;
		$run =~ s#$T{'item-alternate'}$Opt\]($Some)$T{'/item-alternate'}\]#
				  ($i + 1) % ($1 || $::Values->{mv_item_alternate} || 2)
				  							?	pull_else($2)
											:	pull_if($2)#geo;
		tag_item_data_row($code,\$run);
		$run =~ s#$T{'if-field'}$Spacef(!?)$Spaceo($Codere)\]($Some)$T{'/if-field'}\]#
				  product_field($2, $code)	?	pull_if($3,$1)
											:	pull_else($3,$1)#geo;
		$run =~ s#$T{'if-modifier'}$Spacef(!?)$Spaceo($Codere)\]($Some)$T{'/if-modifier'}\]#
				  $item->{$2}	?	pull_if($3,$1)
								:	pull_else($3,$1)#geo;
		$run =~ s:$T{'item-increment'}\]:$i + 1:geo;
		$run =~ s:$T{'item-accessories'}($Spacef[^\]]+)?\]:
						tag_accessories($code,$item,$1):geo;
		$run =~ s:$T{'item-quantity'}\]:$item->{'quantity'}:go;
		$run =~ s:$T{'item-modifier'}$Spacef(\w+)\]:$item->{$1}:go;
		$run =~ s:$T{'quantity-name'}\]:quantity$i:go;
		$run =~ s:$T{'modifier-name'}$Spacef(\w+)\]:$1$i:go;
		$run =~ s!$T{'item-subtotal'}$Opt$T!currency(item_subtotal($item),$1)!geo;
		$run =~ s!$T{'discount-subtotal'}$Opt$T!
						currency( discount_price(
										$item,item_subtotal($item)
									),
								$1
								)!geo;
		$run =~ s:$T{'item-code'}\]:$code:go;
		$run =~ s:$T{'item-field'}$Mandf\]:item_field($item, $1):geo;
		$run =~ s:$T{'item-description'}\]:
							item_description($item) || $item->{description}
							:geo;
		$run =~ s#$T{'item-link'}\]#"[page $linkdir$code]"
				  . $linkvalue . '[/page]'#geo;
		$run =~ s!$T{'item-price'}(?:\s+)?(\d+)?$Optx$T!
					currency(item_price($item,$1), $2)!geo;
		$run =~ s!$T{'discount-price'}(?:\s+(\d+))?$Opt$T!
					currency(
						discount_price($item, item_price($item,$1), $1)
						, $2
						)!geo;
		$run =~ s!$T{'item-discount'}(?:\s+(?:quantity=)?"?(\d+)"?)?$Optx$T!
					currency(item_discount($item->{code},
											item_price($item, $1),
											$item->{quantity}), $2)!geo;
		$run =~ s#$T{'item-last'}\]
                    \s* ($Some) \s*
                $T{'/item-last'}\]#
                    my $tmp = interpolate_html($1);
                    if($tmp && $tmp < 0) {
                        last;
                    }
                    elsif($tmp) {
                        $return = 1;
                    }
                    '' #xoge;
		$run =~ s#$T{'item-next'}\]
                    \s* ($Some) \s*
                $T{'/item-next'}\]#
                    interpolate_html($1) != 0 ? next : '' #xoge;

		$r .= $run;
		delete $item->{mv_cache_price};
		last if $return;
	}
	$r;
}

# SQL
sub tag_sql_list {
    my($text,$obj) = @_;
    my($r, $i, $item, $code, $db, $link);
	my($linkvalue, $run, $count);

	# get the number to start the increment from
	$count = 0;

    $r = "";
	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};
	my $linkdir = $Vend::Cfg->{'ItemLinkDir'};

	if($Vend::OnlyProducts) {
		$text =~ s/$T{'sql-field'}$Spacef/[sql-data $Vend::OnlyProducts /g;
		$text =~ s/$T{'if-sql-field'}$Spacef(!$Spaceo)?/[if-sql-data $1$Vend::OnlyProducts /g;
		$text =~ s!$T{'/if-sql-field'}($Spacef$Codere)?\]![/if-sql-data$1]!g;
	}
    foreach $item (@$obj) {
		$code = $item->[0];
		next unless $code;

		# Uncomment next line to ignore non-database items
		# next unless product_code_exists_ref($code);

		$count++;

	    $run = $text;
		$run =~ s#$T{'sql-alternate'}$Opt\]($Some)$T{'/sql-alternate'}\]#
				  $count % ($1 || $::Values->{mv_sql_alternate} || 2)
				  							?	pull_else($2)
											:	pull_if($2)#geo;
	    $run =~ s:$T{'sql-param'}\s+(\d+)\]:$item->[$1]:go;
		$run =~ s#$T{'if-sql-param'}$Spacef(!?)\s*($Codere)\]($Some)$T{'/if-sql-param'}\]#
			  $item->[$Vend::Table::DBI::mv_sql_names{lc $2}]
			  			?	pull_if($3,$1)
						:	pull_else($3,$1)#geo;
		$run =~ s!$T{'sql-param'}$Mand\]!$item->[$Vend::Table::DBI::mv_sql_names{lc $1}]!go;
		$run =~ s#$T{'if-sql-field'}$Spacef(!?)$Spaceo($Codere)\]
						($Some)
				  $T{'/if-sql-field'}\]#
				  product_field($2, $code)	?	pull_if($3, $1)
											:	pull_else($3, $1)#xgeo;
		tag_sql_data_row($code, \$run);
	    $run =~ s:$T{'sql-increment'}\]:$count:go;
	    $run =~ s:$T{'sql-code'}\]:$code:go;
	    $run =~ s:$T{'sql-description'}\]:product_description($code):geo;
	    $run =~ s:$T{'sql-field'}$Mand\]:product_field($1, $code):geo;
	    $run =~ s#$T{'sql-link'}\]#"[page $linkdir$link]"
	  			. $linkvalue . '[/page]'#geo;
	    $run =~ s!$T{'sql-price'}(?:\s+)?(\d+)?$Optx$T!
					currency(product_price($code,$1), $2)!geo;

	  $r .= $run;
    }
    $r;
}
# END SQL

sub loop_with {
	my ($code,$run,$count,$with) = @_;
	return '' unless $code && defined $run;
	$with = '' unless defined $with;
	if($Vend::OnlyProducts) {
		$run =~ s/$T{'loop-field'}$with$Spacef/[loop-data$with $Vend::OnlyProducts /g;
		$run =~ s/$T{'if-loop-field'}$with$Spacef(!\s*)?/[if-loop-data$with $1$Vend::OnlyProducts /g;
		$run =~ s!$T{'/if-loop-field'}$with\]![/if-loop-data$with]!g;
	}
	$run =~ s#$T{'loop-last'}$with\]
					\s* ($Some) \s*
				$T{'/loop-last'}$with\]#
					interpolate_html($1) ? '' : return undef#xge;
	$run =~ s#$T{'loop-next'}$with\]
					\s* ($Some) \s*
				$T{'/loop-next'}$with\]#
					interpolate_html($1) ? '' : return ''#xge;

	$run =~ s#$T{'if-loop-field'}$with$Spacef(!?)\s*($Codere)\]
					($Some)
				$T{'/if-loop-field'}$with\]#
			  product_field($2, $code)	?	pull_if($3,$1)
										:	pull_else($3,$1)#xge;
	tag_loop_data_row($code,\$run,$with);
	$run =~ s:$T{'loop-increment'}$with\]:$count:xg;
	$run =~ s:$T{'loop-accessories'}$with($Spacef[^\]]+)?\]:tag_accessories($code,'',$1):ge;
	$run =~ s:$T{'loop-code'}$with\]:$code:g;
	$run =~ s:$T{'loop-field'}$with$Mandf\]:product_field($1, $code):ge;
	$run =~ s:$T{'loop-description'}$with\]:product_description($code):ge;
	$run =~ s#$T{'loop-link'}$with\]#"[page " . $Vend::Cfg->{'ItemLinkDir'} . "$code]"
			  . $Vend::Cfg->{'ItemLinkValue'} . '[/page]'#ge;
	$run =~ s!$T{'loop-price'}$with(?:\s+)?(\d+)?$Optx$T!
				currency(product_price($code,$1), $2)!ge;

	1 while $run =~ s!	$T{'loop-change'}$with $Spacef ($Codere)\] \s*
					$T{'condition'}\]
					($Some)
					$T{'/condition'}\]
					([\000-\377]*?)
				$T{'/loop-change'}$with $Spacef \1 \]!
						check_change($1,$2)
										?	pull_if($3)
										:	pull_else($3)!xge;
					
	return $run;
}

sub loop_substitute {
	my ($code,$run,$count) = @_;
	my $return;
	if($Vend::OnlyProducts) {
		$run =~ s/$T{'loop-field'}$Spacef/[loop-data $Vend::OnlyProducts /g;
		$run =~ s/$T{'if-loop-field'}$Spacef(!\s*)?/[if-loop-data $1$Vend::OnlyProducts /g;
		$run =~ s!$T{'/if-loop-field'}\]![/if-loop-data]!g;
	}
	$run =~ s#$T{'if-loop-field'}$Spacef(!?)\s*($Codere)\]
					($Some)
				$T{'/if-loop-field'}\]#
			  product_field($2, $code)	?	pull_if($3,$1)
										:	pull_else($3,$1)#xgeo;
	tag_loop_data_row($code,\$run);
	$run =~ s#$T{'loop-alternate'}$Opt\]($Some)$T{'/loop-alternate'}\]#
				  $count % ($1 || $::Values->{mv_loop_alternate} || 2)
				  							?	pull_else($2)
											:	pull_if($2)#geo;
	$run =~ s:$T{'loop-increment'}\]:$count:xgo;
	$run =~ s:$T{'loop-accessories'}($Spacef[^\]]+)?\]:tag_accessories($code,'',$1):geo;
	$run =~ s:$T{'loop-code'}\]:$code:go;
	$run =~ s:$T{'loop-field'}$Mandf\]:product_field($1, $code):geo;
	$run =~ s:$T{'loop-description'}\]:product_description($code):geo;
	$run =~ s#$T{'loop-link'}\]#"[page " . $Vend::Cfg->{'ItemLinkDir'} . "$code]"
			  . $Vend::Cfg->{'ItemLinkValue'} . '[/page]'#geo;
	$run =~ s!$T{'loop-price'}(?:\s+)?(\d+)?$Optx$T!
				currency(product_price($code,$1), $2)!geo;

	1 while $run =~ s!	$T{'loop-change'} $Spacef ($Codere)\] \s*
					$T{'condition'}\]
					($Some)
					$T{'/condition'}\]
					($Some)
				$T{'/loop-change'} $Spacef \1 \]!
						check_change($1,$2)
										?	pull_if($3)
										:	pull_else($3)!xgeo;
	$run =~ s#$T{'loop-last'}\]
					\s* ($Some) \s*
				$T{'/loop-last'}\]#
					my $tmp = interpolate_html($1);
					if($tmp && $tmp < 0) {
						return('',1);
					}
					elsif($tmp) {
						$return = 1;
					}
					'' #xoge;
	return($run, $return) if $return;
	$run =~ s#$T{'loop-next'}\]
					\s* ($Some) \s*
				$T{'/loop-next'}\]#
					my $tmp = interpolate_html($1); $tmp =~ s/^\s+//;
					is_yes($tmp) ? return '' : '' #xoge;
	return $run;
}

# $extra only present on new syntax lists
# will be used as text
sub tag_loop_list {
	my($with,$list,$search,$text,$option) = @_;
	my($r, $i, $link, $code, $db, $linkvalue, $run);
	my(@list);
	my(@post);
	# Allow nesting.  Starts saved area at first loop substitution
	# AFTER the first right-bracket. 
	$i = 0;

	$list =~ s/[\0\s]+$// if defined $list;
	
	$list = tag_search($search) if defined $search;

	if($option) {
		$option = $::Values->{$option} || '';
	}
	unless($with) {
		$with = '';
		# Pull out old-syntax embedded loops.
		# This is a bad thing, but I don't see any real good
		# way to substitute otherwise. If embedding a loop within
		# a non-with loop and using with=, you must put it right after [loop .
		# Solution is to loop with an extra identifier on all embedded
		# loops.
		while( $text =~ s#
			($T{'loop'}  \s+  (?!with\s*=)
			[\000-\377]+?  $T{'/loop'}\])
			#'__POST' . $i . '__'#eix ) {
			$post[$i++] = $1;
		}
	}

	$r = "";
	$linkvalue = $Vend::Cfg->{'ItemLinkValue'};

	if($list =~ /^search\s*=\s*(["']?)(.*)\1/is ) {
		$list = tag_search($2);
	}

	# See if we are to sort, and do so
	my $opts = find_sort(\$text);
	$list = tag_sort($opts, $list, "\n") if defined $opts;

	# Allow newlines for search lists, as they are transparent
	# Will work fine for others as well
	# Too bad if you have leading spaces in list!
	if($list =~ /\n/) {
		$list =~ s/[\0\s]+$//;
		@list = split /\r?\n/, $list;
	}
	else {
		@list = quoted_comma_string($list);
	}

	$i = 1;
	undef %Prev;

	my $sub = $with ? \&loop_with : \&loop_substitute;

	my $orig;
	if($option) {
		$orig = $text;
	}

	foreach $code (@list) {
		if($option) {
			$text = $orig;
			$text =~ s/<option\s*/<OPTION SELECTED /i
				if "\L$code" eq "\L$option";
		}
		my ($tmp,$return) = &$sub($code, $text, $i, $with);
		$r .= $tmp;
		last if $return;
		$i++;
	}

	#undo nesting if appropriate
	$r =~ s!__POST(\d+)__!$post[$1]!g if @post;

	$r;
}

# Displays a search page with the special [search-list] tag evaluated.

sub search_page {

	my($q,$o,$page) = @_;
	my $delay_or_immediate;

	# If page is not defined, then $q and $o must be
	if(defined $page) {
		$delay_or_immediate = 1;
		($q,$o) = Vend::Scan::perform_search()
			unless $q;
	}
	elsif (($page = $q->{global}->{search_page}) ) {
    	$page = readin($page);
	}
	elsif($Vend::Cfg->{'FrameSearchPage'} && $Vend::Session->{'frames'}) {
    	$page = readin($Vend::Cfg->{'FrameSearchPage'});
	}
    else {
    	$page = readin(find_special_page('search'));
	}
	my $key;
	$key = $q->{global}{cache_key} if $Vend::Cfg->{SearchCache};

 	unless (defined $page) {
#		logError("Missing special page: $page");
		logError( errmsg('Interpolate.pm:4', "Missing special page: %s" , $page) );
#		logGlobal("Missing special page: $page");
		logGlobal( errmsg('Interpolate.pm:5', "Missing special page: %s" , $page) );
		return main::response('plain', errmsg('Interpolate.pm:6', "No search page '%s' found!", $page) );
	}

	my $no_match_found = 0;

	# Substitute defines from configuration file
	$page =~ s#\@\@([A-Za-z0-9]\w+[A-Za-z0-9])\@\@#$Global::Variable->{$1}#ge;
	$page =~ s#__([A-Za-z0-9]\w*?[A-Za-z0-9])__#$Vend::Cfg->{Variable}->{$1}#ge;

	$page =~ s:\[/?search[-_]region\b$Some]::goi;

	# passing the list reference here
	if(ref $o and @$o) {
		$page =~ s:$T{'search-list'}\]($Some)$T{'/search-list'}\]:
				  tag_search_list($1,$o,$q):geo;
		$page =~ s!
					$T{'more-list'}
						$Optx
						$Optx
						$Optx
						$Optx
						$Optx
						$T ($Some) $T{'/more-list'} $T!
				  tag_more_list($6,$q,$1,$2,$3,$4,$5)!xgeo;
		$page =~ s:$T{'no-match'}\]($Some)$T{'/no-match'}\]::geo;
	}
	else {
		$page =~ s:$T{'search-list'}\]($Some)$T{'/search-list'}\]::geo;
		$page =~ s!
					$T{'more-list'}
						$Optx
						$Optx
						$Optx
						$Optx
						$Optx
						$T($Some)$T{'/more-list'}$T!
				  !xgeo;
		$page =~ s:$T{'no-match'}\]($Some)$T{'/no-match'}\]:$1:geo
					or ! $q or do {
                        if(! ref $q->{specs}) {
                            $q->{specs} = [ $q->{specs} ];
                        }
						my $subj = join "|", @{$q->{specs}};
						::display_special_page(
							find_special_page('nomatch'), $subj);
						return 0;
					};
	}

	return $page if $delay_or_immediate;

	# This is a fake search from the page builder
	# Doesn't return response, just returns page if not dynamic
	if (defined $Vend::BuildingPages) {
		$page = cache_html($page);
		return $page
			if defined $Vend::CachePage or defined $Vend::ForceBuild;
		return undef;
	}

	# add to cache if appropriate
#::logGlobal("cache_key=$key");
	if($key) {
		my $complete;
		($page, $complete) = cache_html($page, $wantref);
		return main::response('html', $page)
			unless ($Vend::CachePage || $Vend::ForceBuild);

		if($q->{'global'}->{more_in_progress}) {
			$key = generate_key($Vend::Session->{last_search});
		}

		my $out = $complete || $page;

		logData($Vend::Cfg->{'LogFile'}, format_log_msg('add to search cache'))
			if defined $Vend::Cfg->{CollectData}->{cache};
		open(SEARCHCACHE, ">$Vend::Cfg->{ScratchDir}/SearchCache/$key.html")
			or die "Cache failure: $!\n";
		print SEARCHCACHE $$out;
		close SEARCHCACHE;
		return main::response('html', $page);
	}


    main::response('html',interpolate_html($page, $wantref));

}


# Tries to display the on-the-fly page if page is missing
sub fly_page {
	my($code, $argument, $selector) = @_;
	$code =~ s:.*/::;
    my($page,$db);

	my $base = product_code_exists_ref($code, $argument || undef);
	return undef unless $base || defined $selector;

	$base = $Vend::Cfg->{ProductFiles}[0] unless $base;

	$Vend::Flypart = $code;

	if(defined $selector) {
		$page = $selector if index($selector, '[') > -1;
	}
    elsif($selector = $Vend::Cfg->{'PageSelectField'}) {
		if(db_column_exists($base,$selector)) {
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

	$selector = find_special_page('flypage')
		unless $selector;

    $page = readin($selector) unless defined $page;

    if(! defined $page) {
		logError("attempt to display code=$code with bad flypage '$selector'");
		return undef;
	}

	# Substitute defines from configuration file
	$page =~ s#\@\@([A-Za-z0-9]\w+[A-Za-z0-9])\@\@#$Global::Variable->{$1}#ge;
	$page =~ s#__([A-Za-z0-9]\w*?[A-Za-z0-9])__#$Vend::Cfg->{Variable}->{$1}#ge;

	if($Vend::OnlyProducts) {
		$page =~ s/$T{'item-field'}$Spacef/[item-data $Vend::OnlyProducts /g;
		$page =~ s/$T{'if-field'}$Spacef(!$Spaceo)?/[if-data $1$Vend::OnlyProducts /g;
		$page =~ s!$T{'/if-field'}\]![/if-data]!g;
	}

	my $it = 0; my @it;
	$page =~ s#($T{'fly-list'}\s+[\s\S]+?$T{'/fly-list'}\])#
					$it[$it] = $1; '_@_POSTFLY' . $it++ . '_@_';#xgeo;

	$page =~ s#$T{'if-field'}$Spacef(!?)$Spaceo($Codere)\]($Some)$T{'/if-field'}\]#
			  database_field($base, $code, $2)	?	pull_if($3,$1)
										:	pull_else($3,$1)#geo;
	tag_item_data_row($code,\$page);
    $page =~ s!$T{'item-code'}\]!$code!go;
	$page =~ s:$T{'item-accessories'}(\s+[^\]]+)?\]:tag_accessories($code,'',$1):geo;
    $page =~ s!$T{'item-description'}\]!
					database_field($base,$code,$Vend::Cfg->{DescriptionField})!geo;
	$page =~ s!$T{'item-price'}(?:\s+)?(\d+)?$Optx$T!
					currency(product_price($code,$1 || 1,$base), $2)!geo;
	$page =~ s:$T{'item-field'}$Mandf\]:database_field($base,$code,$1):geo;
	$page =~ s:_\@_POSTFLY(\d+)_\@_:$it[$1]:g;

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
		$which = find_special_page('order') unless $which;
	}

	$page = readin($which);

 	unless (defined $page) {
		logError( errmsg('Interpolate.pm:7', "Missing special page: %s" , $which) );
		logGlobal( errmsg('Interpolate.pm:8', "Missing special page: %s" , $which) );
		return main::response('plain', "No page defined!");
	}
    main::response('html',interpolate_html($page, $wantref));
}

sub item_discount {
	my($code,$price,$q) = @_;
	return ($price * $q) - discount_price($code,$price,$q);
}

sub discount_price {
	my ($item, $price, $quantity) = @_;
	my $extra;
	my $code;

	$code = $item  unless ref $item;

	if(! $code) {
		($code, $extra) = ($item->{'code'}, $item->{mv_discount});
		$quantity = $item->{quantity} unless $quantity;
		$Vend::Session->{discount} = {}
			if $extra and !$Vend::Session->{discount};
	}

	return $price unless defined $Vend::Session->{discount};

	$Vend::Interpolate::q = $quantity || 1;
	my ($discount, $return);
	for($code, 'ALL_ITEMS') {
		next unless $discount = $Vend::Session->{discount}->{$_};
		$Vend::Interpolate::s = $return = $price;
        $return = $ready_safe->reval($discount);
		if($@) {
			$return = $price;
			next;
		}
        $price = $return;
    }
	$Vend::Interpolate::s = $price;
	if($extra) {
		$Vend::Interpolate::item = $item;
        $return = $ready_safe->reval($extra);
		if($@) {
			$return = $price;
			next;
		}
		$price = $return;
		undef $Vend::Interpolate::item;
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
	push(@formulae, $item->{'mv_discount'})
		if defined $item->{'mv_discount'};

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

sub ship_opt {
	return undef unless defined $Vend::Cfg->{Shipping_options};
	my($mode,$option) = @_;
	for($mode, 'mv_global') {
		return $Vend::Cfg->{Shipping_options}{$_}{$option}
			if defined $Vend::Cfg->{Shipping_options}{$_}{$option};
	}
	return undef;
}

sub tag_shipping {
	my($mode, $cart, $noformat) = @_;
	my $cost = shipping($mode, $cart);
	return currency($cost, $noformat);
}

sub shipping {
	my($mode, $cart) = @_;
	return $Vend::Cfg->{'Shipping'}
		unless $Vend::Cfg->{'CustomShipping'};
	$mode = 	$mode ||
				$::Values->{'mv_shipmode'} ||
				'default';
    my($save, $qual);

	if ($cart) {
		$save = $Vend::Items;
		tag_cart($cart);
	}
	
	$Vend::Session->{ship_message} = ''
		unless defined $Vend::Shipping_in_progress;
	$Vend::Shipping_in_progress = 1;
	my($field, $code, $i, $total, $cost, $multiplier, $formula);

	if(defined $Vend::Cfg->{'Shipping_criterion'}->{$mode}) {
		$field = $Vend::Cfg->{'Shipping_criterion'}->{$mode};
	}

	return 0 unless $field;

	$@ = 1;

	# Security hole if we don't limit characters
	$mode !~ /[\s,;{}]/ and 
		eval {'what' =~ /$mode/};

	if ($@) {
		logError("Bad character(s) in shipping mode '$mode', returning 0");
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
	elsif ( index($field, ':') != -1) {
		my ($base, $field) = split /:+/, $field;
		my $db = database_exists_ref($base);
		unless ($db and db_column_exists($db,$field) ) {
			logError("Bad shipping field '$field' or table '$base'. Returning 0");
			$Vend::Items = $save if defined $save;
			return 0;
		}
    	foreach $i (0 .. $#$Vend::Items) {
			my $item = $Vend::Items->[$i];
			$total += (database_field($base, $item->{code}, $field) || 0) *
						$item->{'quantity'};
		}
	}
	else {
		unless (column_exists $field) {
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

	my $final;

	# We will LAST this loop and return $final if a match is found
	SHIPIT: 
	foreach $code (sort keys %{$Vend::Cfg->{'Shipping_cost'}}) {
		next unless $code =~ /^$mode\d*$/;
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
			my $what = $Vend::Cfg->{'Shipping_cost'}->{$code};
			$what =~ s/^\s+//;
			if ($what =~ /^x\s*/i) {
				$multiplier = $Vend::Cfg->{'Shipping_cost'}->{$code};
				$multiplier =~ s/^x\s*//i;
				$final = $multiplier * $total;
				last SHIPIT;
			}
			elsif ($what =~ /^f\s*(.*)/i) {
				$formula = $1;
				if($Vend::Cfg->{OldShipping}) {
					$formula = interpolate_html($formula)
								if $formula =~ /__|\[\w/;
					$formula =~ s/\bx\b/$total/g;
				}
				else {
					$formula =~ s/\@\@TOTAL\@\@/$total/g;
					$formula = interpolate_html($formula)
								if $formula =~ /__\w+__|\[\w/;
				}
				$cost = $ready_safe->reval($formula);
				if($@) {
					my $msg = "Shipping mode '$mode': bad formula. Returning 0.";
					logError($msg);
					$Vend::Session->{ship_message} .= $msg;
					last SHIPIT;
				}
				$final = $cost;
				last SHIPIT;
			}
			elsif ($what =~ s/^([uA-Z])\s*//) {
				my $zselect = $1;
				my ($type, $geo, $adder, $mod, $sub);
				if($Vend::Cfg->{OldShipping}) {
					$what = interpolate_html($what);
					$what =~ m:([-\w]+)\s+([-\w]+):i;
					$type = $1;
					$geo = $2;
					unless ($geo =~ /^\d\d\d/) {
						$Vend::Session->{ship_message} .= "No zip code\n";
						return undef;
					}
					$cost = tag_ups($type,$geo,$total) and
						($final = $cost, last SHIPIT);
				}
				else {
					$what = interpolate_html($what);
					($type, $geo, $adder, $mod, $sub) = split /\s+/, $what, 5;
					$cost = tag_ups($type,$geo,$total,$zselect);
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
					($final = $cost, last SHIPIT) if $cost;
				}
			}
			elsif ($what =~ s/^([im])\s*//) {
				my $select = $1;
				$what =~ s/\@\@TOTAL\@\@/$total/g;
				my ($item, $field, $sum);
				my (@items) = @{$Vend::Items};
				my @fields = split /\s+/, $qual;
				if ($select eq 'm') {
					$sum = { code => $mode, quantity => $total };
				}
				foreach $item (@items) {
					for(@fields) {
						if(s/(.*):+//) {
							$item->{$_} = tag_data($1, $_, $item->{'code'});
						}
						else {
							$item->{$_} = product_field($_, $item->{'code'});
						}
						$sum->{$_} += $item->{$_} if defined $sum;
					}
				}
				@items = ($sum) if defined $sum;
				for(@items) {
					$cost = Vend::Data::chain_cost($_, $what);
					if($cost =~ /[A-Za-z]/) {
						return shipping($cost);
					}
					$final += $cost;
				}
				last SHIPIT if $final;
			}
			elsif ($what =~
                      m/^s\s+   # Beginning s call with mandatory whitespace
                        (\w+)      # subroutine name
                        [\s(]*     # whitespace or open parens
                        (.*)       # Parameter mess
                        [\s)]*     # Possible closing paren or whitespace
                        /xi)
			{
				$what = $1;
				my $params = $2 || '';
				my @fixed;
				if($params =~ /\S/) {
					my $item;
					my @calls;
					$params =~ s/\@\@TOTAL\@\@/$total/g;
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
					$final = $cost if $cost =~ /^[\d.]+$/;
					$Vend::Session->{ship_message} = $cost;
					last SHIPIT;
				}
			}
			elsif ($what =~ /^e\s*/i) {
				my $msg = $Vend::Cfg->{'Shipping_cost'}->{$code};
				$msg =~ s/^e\s*//i;
				$msg =~ s/\@\@TOTAL\@\@/$total/g;
#print("error message: '$msg'\n") if $Global::DEBUG;
				$Vend::Session->{ship_message} = $msg;
				$final = 0;
				last SHIPIT;
			}
			else {
				$final = $what;
				last SHIPIT;
			}
		}
	}

	if(defined $final) {
		return Vend::Util::currency($final, 1, ship_opt($mode,'PriceDivide') );
	}
	# If we got here, the mode and quantity fit was not found
	$Vend::Session->{ship_message} .=
		"No match found for mode '$mode', quantity '$total', "	.
		($qual ? "qualifier '$qual', " : '')					.
		"returning 0. ";
	return 0;
}

*custom_shipping = \&shipping;

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
	my($cart) = @_;

	my($save);

    if ($cart) {
        $save = $Vend::Items;
        tag_cart($cart);
    }

	
	my $amount = taxable_amount($cart || undef);
	my($r, $code);
	# Make it upper case for state and overseas postal
	# codes, zips don't matter
	my(@code) = map { (uc $::Values->{$_}) || '' }
					split /\s*,\s*/,$Vend::Cfg->{'SalesTax'};
	push(@code, 'DEFAULT');

	if(! defined $Vend::Cfg->{SalesTaxTable}->{'default'}) {
		logError("Sales tax failed, no tax file, returning 0");
		return 0;
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
		next unless $code;
		# Trim the zip+4
		$code =~ s/(\d{5})-\d{4}/$1/;
		next unless defined $Vend::Cfg->{SalesTaxTable}->{$code};
		my $tax = $Vend::Cfg->{SalesTaxTable}->{$code};
		if($tax =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/) {
			$r = $amount * $tax;
		}
		else {
			$r = Vend::Data::chain_cost(
					{	mv_price	=> $amount, 
						code		=> $code,
						quantity	=> $amount, }, $tax);
		}
		last;
	}

	$Vend::Items = $save if defined $save;

	my $prec = 2;
	$prec = $Vend::Cfg->{Locale}{frac_digits}
		if ref $Vend::Cfg->{Locale}
		and defined $Vend::Cfg->{Locale}{frac_digits};
	$r = sprintf("%.${prec}f", $r);
	return $r;
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
	$Vend::Session->{latest_subtotal} = $subtotal;
    return $subtotal;
}

sub tag_subtotal {
	my($cart, $noformat) = @_;
	return currency( subtotal($cart), $noformat);
}

sub tag_salestax {
	my($cart, $noformat) = @_;
	return currency( salestax($cart), $noformat);
}

sub tag_total_cost {
	my($cart, $noformat) = @_;
	return currency( total_cost($cart), $noformat);
}

sub tag_ups {
	my($type,$zip,$weight,$code) = @_;
	my(@data);
	my(@fieldnames);
	my($i,$point,$zone);

	$code = 'u' unless $code;

	unless (defined $Vend::Database{$type}) {
		logError("UPS lookup called, no type file loaded for '$type'");
		return undef;
	}
	unless (ref $Vend::Cfg->{Shipping_zone}{$code}) {
		logError("type '$code' lookup called, no zone defined");
		return undef;
	}
	my $zref = $Vend::Cfg->{Shipping_zone}{$code};
	
	unless (defined $zref->{zone_data}) {
		logError("$zref->{zone_name} lookup called, zone data not found");
		return undef;
	}

	my $zdata = $zref->{zone_data};
	# UPS doesn't like fractional pounds, rounds up

	# here we can adapt for pounds/kg
	if ($zref->{mult_factor}) {
		$weight = $weight * $zref->{mult_factor};
	}
	$weight = ceil($weight);

	$zip = substr($zip, 0, ($zref->{str_length} || 3));
	
	@fieldnames = split /\t/, $zdata->[0];
	for($i = 2; $i < @fieldnames; $i++) {
		next unless $fieldnames[$i] eq $type;
		$point = $i;
		last;
	}

	unless (defined $point) {
		logError("Zone '$code' lookup failed, type '$type' not found");
		return undef;
	}

	for(@{$zdata}[1..$#{$zdata}]) {
		@data = split /\t/, $_;
		next unless ($zip ge $data[0] and $zip le $data[1]);
		$zone = $data[$point];
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
		($zref->{zero_cost_message} || 
		"Zero cost returned for mode $type, geo code $zip. ") unless $cost;
	$cost;

}

# Returns 'SELECTED' when a value is present on the form
# Must match exactly, but NOT case-sensitive

sub tag_selected {
	my ($field,$value,$multiple) = @_;
	$value = '' unless defined $value;
	my $ref = lc $::Values->{$field};
	$ref = lc $ref;
	my $r;

	if( $ref eq "\L$value" ) {
		$r = ' SELECTED';
	}
	elsif ($multiple) {
		$r = ' SELECTED' if $ref =~ /\b$value\b/i;
	}
	else {$r = ''}
	return $r;
}

sub tag_checked {
	my ($field,$value,$multiple,$default) = @_;

	$value = 'on' unless defined $value;
	my $ref = lc $::Values->{$field};
	my $r;

	if( $ref eq "\L$value" or ! $ref && $default) {
		$r = 'CHECKED';
	}
	elsif ($multiple) {
		my $regex = quotemeta $value;
		$r = 'CHECKED' if $ref =~ /(?:^|\0)$regex(?:$|\0)/i;
	}
	else {$r = ''}
	return $r;
}

sub tag_finish_order {
	my($page) = @_;
    my($finish_order);

	return '' unless @$Vend::Items;

	unless (defined $page) {
		if ( $::Scratch->{'mv_checkout'} ||= 0) {
			$page = $::Scratch->{'mv_checkout'};
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
    my($product_code,$page,$base,$quantity) = @_;
    my($r);
    my $action = 'order';

	if($base) {
		$action = 'obtain';
		$page = defined $page ? "/$page" : '';
		$page = $base . $page;
	}
	$quantity =~ s/^(\d+)/_$1/ if defined $quantity;
    unless(defined $page) {
        $page = $action;
    }   
	else {
		$page = "$action/$page";
	}

    if ($Vend::Cfg->{'AlwaysSecure'} and defined
		$Vend::Cfg->{'AlwaysSecure'}->{$page}) {
		$r  = '<a href="' . secure_vendUrl($page, $product_code);
    }
    else {  
        $r  = '<a href="' . vendUrl($page, $product_code);
    }

	$r =~ s/[^;]+$/$quantity/ if defined $quantity;
    
    $r .= '" TARGET="' . $Vend::Cfg->{'OrderFrame'}
        if $Vend::Session->{'frames'};
    $r .= '">';
}

# Returns a body tag with a user-entered, a set color scheme, or the default
sub tag_body {
    my($scheme, $extra) = @_;
	my $r = '<BODY';
	my ($var,$tag);
	#return '<BODY>' unless (int($scheme) < 16 and int($scheme) > 1);

	my %color = qw( mv_bgcolor BGCOLOR mv_textcolor TEXT
					mv_linkcolor LINK mv_vlinkcolor VLINK
					 mv_alinkcolor ALINK mv_background BACKGROUND );
	if (defined $::Values->{mv_resetcolors}
			and $::Values->{mv_resetcolors}) {
		delete $::Values->{mv_customcolors};
		undef $::Values->{mv_resetcolors};
	}
	if (defined $::Values->{mv_customcolors}) {
		foreach $var (keys %color) {
			$r .= qq| $color{$var}="| . $::Values->{$var} . '"'
				if $::Values->{$var};
		}
	}
	else {
		foreach $var (keys %color) {
			$r .= qq| $color{$var}="| . ${$Vend::Cfg->{Color}->{$var}}[$scheme] . '"'
				if defined ${$Vend::Cfg->{Color}->{$var}}[$scheme]
					&&  ${$Vend::Cfg->{Color}->{$var}}[$scheme] !~ /\bnone\b/;
		}
	}
	$r =~ s#(BACKGROUND="(?!http:))([^/])#$1$Vend::Cfg->{ImageDir}$2#;
	$r .= " $extra" if defined $extra;
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
    $::Scratch->{$var} = $val;
	return '';
}

# Returns the value of a scratchpad field named VAR.
sub tag_scratch {
    my($var) = @_;
    my($value);

    if (defined ($value = $::Scratch->{$var})) {
		return $value;
    }
	else {
		return '';
    }
}

sub tag_lookup {
	my($selector,$field,$key,$rest) = @_;
	return $rest if (defined $rest and $rest);
	return tag_data($selector,$field,$key);
}

sub timed_build {
    my $file = shift;
    my $opt = shift;
	my $abort;

	my $saved_file;
	if($opt->{scan}) {
		$saved_file = $Vend::Session->{last_search};
		$abort = 1 if $file =~ m:MM=:;
	}

	return Vend::Interpolate::interpolate_html(shift)
		if $abort
		or !  $CGI::cookie
		or $Vend::BuildingPages
		or ! $opt->{login} && $Vend::Session->{logged_in};

    if($opt->{noframes} and $::Session->{frames}) {
        return '';
    }

	my $secs;
	my $static;
	CHECKDIR: {
		last CHECKDIR if $file;
		my $dir = $Vend::Cfg->{StaticDir};
		$dir = ! -d $dir || ! -w _ ? 'timed' : do { $static = 1; $dir };
		$file = $saved_file || $Vend::Flypart || $Global::Variable->{MV_PAGE};
		if($saved_file) {
			$file = $saved_file;
			$file =~ s/(\W)/sprintf("%02x", ord($1))/eg;
		}
		else {
		 	$saved_file = $file = ($Vend::Flypart || $Global::Variable->{MV_PAGE});
		}
		$file .= $Vend::Cfg->{StaticSuffix};
		$dir .= "/$1" 
			if $file =~ s:(.*)/::;
		if(! -d $dir) {
			require File::Path;
			File::Path::mkpath($dir);
		}
		$file = Vend::Util::catfile($dir, $file);
	}

	if($opt->{minutes}) {
        $secs = int($opt->{minutes} * 60);
    }
	elsif ($opt->{period}) {
		$secs = Vend::Config::time_to_seconds($opt->{period});
	}

    if( ! -f $file or $secs && (stat(_))[9] < (time() - $secs) ) {
        my $out = Vend::Interpolate::interpolate_html(shift);
        Vend::Util::writefile(">$file", $out);
# STATICPAGE
		if ($Vend::Cfg->{StaticDBM} and ::tie_static_dbm(1) ) {
			chmod($Vend::Cfg->{FileCreationMask} | 0444, $file);
			if ($opt->{scan}) {
				$file =~ s:.*/::;
				$Vend::StaticDBM{$saved_file} = $file;
			}
			else {
				$Vend::StaticDBM{$saved_file} = '';
			}
		}
# END STATICPAGE
        return $out;
    }
    else {        return Vend::Util::readfile($file);    }
}

sub update {
	my ($func, $opt) = @_;
	if($func eq 'quantity') {
		::update_quantity();
	}
	elsif($func eq 'cart') {
		my $cart;
		if($opt->{name}) {
			$cart = $Vend::Session->{carts}{$opt->{name}};
		}
		else {
			$cart = $Vend::Items;
		}
		return if ! ref $cart;
		Vend::Cart::toss_cart($cart);
	}
	elsif ($func eq 'values') {
		::update_user();
	}
	elsif ($func eq 'data') {
		::update_data();
	}
	return;
}

# MVASP

package Vend::Tags;

require Exporter;
require AutoLoader;

use vars qw($AUTOLOAD @ISA);
@ISA = qw(Exporter);

sub new {
	return bless {}, shift;
}

sub AUTOLOAD {
	shift;
	my $routine = $AUTOLOAD;
	$routine =~ s/.*:://;
	if(ref $_[0]) {
		@_ = Vend::Parse::resolve_args($routine, @_);
	}
	return Vend::Parse::do_tag($routine, @_);
}

1;

package Vend::Tags::Db;

require Exporter;
require AutoLoader;

use vars qw($AUTOLOAD @ISA);
@ISA = qw(Exporter);

sub new {
	return bless {}, shift;
}

sub dbi {
	shift;
	return ${Vend::Database{shift}}{$Vend::Table::DBI::DBI};
}

sub ref {
	my ($s, $name) = @_;
	return $Vend::Database{$name};
}

sub AUTOLOAD {
	shift;
	my $select = $AUTOLOAD;
	$select =~ s/.*:://;
	my $db = $Vend::Database{$_};
	return $db;
}

1;



package Vend::Tags::Document;

my $Hot;

sub new { return bless {}, shift }

sub hot {
	shift;
	$Hot = shift;
}

sub send {
	shift;
	::response(undef, join "", @_);
}

sub header {
	return undef if $Vend::ResponseMade;
	shift;
	my ($text, $opt) = @_;
	$Vend::StatusLine = '' if ref $opt and $opt->{replace};
	$Vend::StatusLine = '' if !defined $Vend::StatusLine;
	$Vend::StatusLine .= shift;
}

sub insert {
	shift;
	unshift(@Vend::Tags::Out, @_);
	return;
}

sub ref {
	return \@Vend::Tags::Out;
}

sub review {
	shift;
	my $idx;
	if( defined ($idx = shift) ) {
		return $Vend::Tags::Out[$idx];
	}
	else {
		return @Vend::Tags::Out;
	}
}

sub replace {
	shift;
	@Vend::Tags::Out = @_;
	return;
}

sub HTML (@) {
	push @Vend::Tags::Out, @_;
	return if ! $Hot;
	Vend::Tags::Document::send( undef, join("", splice(@Vend::Tags::Out, 0)) );
}

sub write {
	shift;
	HTML(@_);
}

1;

package Vend::Interpolate;

# END MVASP

1;
__END__
