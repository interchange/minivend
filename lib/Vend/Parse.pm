# Parse.pm - Parse MiniVend tags
# 
# $Id: Parse.pm,v 1.21 1998/01/16 07:30:42 mike Exp mike $
#
# Copyright 1997-1998 by Michael J. Heins <mikeh@iac.net>
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

package Vend::Parse;

# $Id: Parse.pm,v 1.21 1998/01/16 07:30:42 mike Exp mike $

require Vend::Parser;


$VERSION = sprintf("%d.%02d", q$Revision: 1.21 $ =~ /(\d+)\.(\d+)/);

use Safe;
use Vend::Util;
use Vend::Interpolate;
use Text::ParseWords;
# STATICPAGE
use Vend::PageBuild;
# END STATICPAGE
use Vend::Data qw/product_field/;

require Exporter;

@ISA = qw(Exporter Vend::Parser);

$VERSION = substr(q$Revision: 1.21 $, 10);
@EXPORT = ();
@EXPORT_OK = qw(find_matching_end);

use strict;

use vars qw($VERSION);

my($CurrentSearch, $CurrentCode, $CurrentDB, $CurrentWith, $CurrentItem);
my(@SavedSearch, @SavedCode, @SavedDB, @SavedWith, @SavedItem);

my %PosNumber =	( qw!
					
				accessories		 2
				area			 2
				areatarget		 3
				body			 2
				buttonbar		 1
				cart			 1
				checked			 3
				currency		 1
				data			 5
				default			 2
				discount		 1
				description		 2
				field			 2
				file			 2
				finish_order	 1
				fly_list		 2
				framebase		 1
				help			 1
				if				 1
				include			 1
				last_page		 2
				lookup			 1
				loop			 1
				msql			 2
				nitems			 1
				order			 4
				page			 2
				pagetarget		 3
				perl			 1
				price			 4
				process_order	 2
				process_search	 1
				process_target	 2
				rotate			 2
				row				 1
				salestax		 2
				scratch			 1
				search			 1
				search_region	 1
				selected		 3
				set				 1
				setlocale		 3
				shipping		 3
				shipping_desc	 1
				shipping_description	 1
				sql				 2
				subtotal		 2
				tag				 1
				total_cost		 2
				value			 4

			! );

my %Order =	(

				accessories		=> [qw( code arg )],
				area			=> [qw( href arg secure)],
				areatarget		=> [qw( href target arg secure)],
				body			=> [qw( type extra )],
				buttonbar		=> [qw( type  )],
				calc			=> [],
				cart			=> [qw( name  )],
				compat			=> [],
				'currency'		=> [qw( convert )],
				checked			=> [qw( name value multiple)],
				data			=> [qw( table field key value increment)],
				default			=> [qw( name default set)],
				description		=> [qw( code base )],
				discount		=> [qw( code  )],
				field			=> [qw( name code )],
				file			=> [qw( name )],
				finish_order	=> [qw( href )],
				fly_list		=> [qw( code base )],
				framebase		=> [qw( target  )],
				frames_off		=> [],
				frames_on		=> [],
				help			=> [qw( name  )],
				'if'			=> [qw( type term op compare )],
				'or'			=> [qw( type term op compare )],
				'and'			=> [qw( type term op compare )],
				include			=> [qw( file )],
				item_list		=> [qw( name )],
				last_page		=> [qw( target arg )],
				lookup			=> [qw( table field key value )],
				loop			=> [qw( with arg search option)],
				loop_change		=> [qw( with arg )],
				msql			=> [qw( type query list true base)],
				nitems			=> [qw( name  )],
				order			=> [qw( code href base quantity )],
				page			=> [qw( href arg secure)],
				pagetarget		=> [qw( href target arg secure)],
				perl			=> [qw( arg )],
				post			=> [],
				price			=> [qw( code quantity base noformat)],
				process_order	=> [qw( target secure )],
				process_search	=> [qw( target )],
				process_target	=> [qw( target secure )],
				random			=> [],
				rotate			=> [qw( ceiling floor )],
				row				=> [qw( width )],
				'salestax'		=> [qw( name noformat)],
				scratch			=> [qw( name  )],
				search			=> [qw( arg   )],
				search_region	=> [qw( arg   )],
				selected		=> [qw( name value multiple )],
				setlocale		=> [qw( locale persist currency )],
				set				=> [qw( name  )],
				'shipping'		=> [qw( name cart noformat )],
				shipping_desc	=> [qw( name  )],
				shipping_description	=> [qw( name  )],
				sql				=> [qw( type query list false base)],
				'subtotal'		=> [qw( name noformat )],
				tag				=> [qw( op base file type )],
				total_cost		=> [qw( name noformat )],
				value			=> [qw( name escaped set hide)],

			);

my %Required = (

				accessories	=> [ qw( code )],
				area		=> [ qw( href )],
				areatarget	=> [ qw( href )],
				body		=> [ qw( type )],
				buttonbar	=> [ qw( type )],
				cart		=> [ qw( name )],
				checked		=> [ qw( name value )],
				data		=> [ qw( table )],
				default		=> [ qw( name )],
				discount	=> [ qw( code )],
				field		=> [ qw( name code )],
				file		=> [ qw( name )],
				fly_list	=> [ qw( code )],
				framebase	=> [ qw( target )],
				help		=> [ qw( name )],
				'if'		=> [ qw( base )],
				'or'		=> [ qw( base )],
				'and'		=> [ qw( base )],
				include		=> [ qw( file )],
				lookup		=> [ qw( table field key )],
				order		=> [ qw( code )],
				page		=> [ qw( href )],
				pagetarget	=> [ qw( href )],
				scratch		=> [ qw( name )],
				search		=> [ qw( arg  )],
				selected	=> [ qw( name value )],
				set			=> [ qw( name )],
				value		=> [ qw( name )],

			);

my %InvalidateCache = (

			qw(
				cart		1
				checked		1
				default		1
				discount	1
				frames_off	1
				frames_on	1
				item_list	1
				if          1
				last_page	1
				lookup		1
				msql		1
				nitems		1
				perl		1
				'salestax'	1
				scratch		1
				selected	1
				set			1
				'shipping'	1
				sql			1
				subtotal	1
				total_cost	1
				value		1

			   )
			);

my %Implicit = (

			'data' =>		{ qw( increment increment ) },
			'value' =>		{ qw( escaped	escaped hide hide ) },
			'checked' =>	{ qw( multiple	multiple ) },
			'area'    =>	{ qw( secure	secure ) },
			'page'    =>	{ qw( secure	secure ) },
			'areatarget'    =>	{ qw( secure	secure ) },
			'process_order' =>	{ qw( secure	secure ) },
			'process_target' =>	{ qw( secure	secure ) },
			'pagetarget'    =>	{ qw( secure	secure ) },

			'if' =>		{ qw(
								!=		op
								!~		op
								<=		op
								==		op
								=~		op
								>=		op
								eq		op
								gt		op
								lt		op
								ne		op
					   )},

			'and' =>		{ qw(
								!=		op
								!~		op
								<=		op
								==		op
								=~		op
								>=		op
								eq		op
								gt		op
								lt		op
								ne		op
					   )},

			'or' =>		{ qw(
								!=		op
								!~		op
								<=		op
								==		op
								=~		op
								>=		op
								eq		op
								gt		op
								lt		op
								ne		op
					   )},

			);

my %PosRoutine = (

				'or'			=> sub { return &Vend::Interpolate::tag_if(@_, 1) },
				'and'			=> sub { return &Vend::Interpolate::tag_if(@_, 1) },
				'if'			=> \&Vend::Interpolate::tag_if,
				'tag'				=> \&Vend::Interpolate::do_tag,
				'sql'			=> \&Vend::Data::sql_query,
			);


my %Routine = (

				accessories		=> sub {
									&Vend::Interpolate::tag_accessories
										($_[0], '', $_[1])
									},
				area			=> \&Vend::Interpolate::tag_area,
				areatarget		=> \&Vend::Interpolate::tag_areatarget,
				body			=> \&Vend::Interpolate::tag_body,
				buttonbar		=> \&Vend::Interpolate::tag_buttonbar,
				calc			=> \&Vend::Interpolate::tag_calc,
				cart			=> \&Vend::Interpolate::tag_cart,
				checked			=> \&Vend::Interpolate::tag_checked,
				'currency'		=> sub {
										my($convert,$amount) = @_;
										return &Vend::Util::currency(
														$amount,
														undef,
														$convert);
									},
				compat			=> sub {
										&Vend::Interpolate::interpolate_html('[old]' . $_[0]);
									},
				data			=> \&Vend::Interpolate::tag_data,
				default			=> \&Vend::Interpolate::tag_default,
				description		=> \&Vend::Data::product_description,
				discount		=> \&Vend::Interpolate::tag_discount,
				field			=> \&Vend::Data::product_field,
				file			=> \&Vend::Interpolate::tag_file,
				finish_order	=> \&Vend::Interpolate::tag_finish_order,
				fly_list		=> \&Vend::Interpolate::fly_page,
				framebase		=> \&Vend::Interpolate::tag_frame_base,
				frames_off		=> \&Vend::Interpolate::tag_frames_off,
				frames_on		=> \&Vend::Interpolate::tag_frames_on,
				help			=> \&Vend::Interpolate::tag_help,
				include			=> sub {
									&Vend::Interpolate::interpolate_html(
										&Vend::Util::readfile
											($_[0], $Global::NoAbsolute)
										  );
									},
				item_list		=> \&Vend::Interpolate::tag_item_list,
				value		=> \&Vend::Interpolate::tag_value,
				'if'			=> \&Vend::Interpolate::tag_self_contained_if,
				'or'			=> sub { return &Vend::Interpolate::tag_self_contained_if(@_, 1) },
				'and'			=> sub { return &Vend::Interpolate::tag_self_contained_if(@_, 1) },
				last_page		=> \&Vend::Interpolate::tag_last_page,
				lookup			=> \&Vend::Interpolate::tag_lookup,
				loop			=> sub {
									# Munge the args, UGHH. Fix this.
									my $option = splice(@_,3,1);
									return &Vend::Interpolate::tag_loop_list
										(@_, $option);
									},
				msql			=> \&Vend::Data::sql_query,
				nitems			=> \&Vend::Util::tag_nitems,
				order			=> \&Vend::Interpolate::tag_order,
				page			=> \&Vend::Interpolate::tag_page,
				pagetarget		=> \&Vend::Interpolate::tag_pagetarget,
				perl			=> \&Vend::Interpolate::tag_perl,
				post			=> sub { return $_[0] },
				price        	=> \&Vend::Interpolate::tag_price,
				process_order	=> \&Vend::Interpolate::tag_process_order,
				process_search	=> \&Vend::Interpolate::tag_process_search,
				process_target	=> \&Vend::Interpolate::tag_process_target,
				random			=> \&Vend::Interpolate::tag_random,
				rotate			=> \&Vend::Interpolate::tag_rotate,
				row				=> \&Vend::Interpolate::tag_row,
				'salestax'		=> \&Vend::Interpolate::tag_salestax,
				scratch			=> \&Vend::Interpolate::tag_scratch,
				search			=> \&Vend::Interpolate::tag_search,
				search_region	=> \&Vend::Interpolate::tag_search_region,
				selected		=> \&Vend::Interpolate::tag_selected,
				setlocale		=> \&Vend::Util::setlocale,
				set				=> \&Vend::Interpolate::set_scratch,
				'shipping'		=> \&Vend::Interpolate::tag_shipping,
				shipping_desc	=> \&Vend::Interpolate::tag_shipping_desc,
				shipping_description => \&Vend::Interpolate::tag_shipping_desc,
				sql				=> \&Vend::Data::sql_query,
				'subtotal'	=> \&Vend::Interpolate::tag_subtotal,
				tag			=> \&Vend::Interpolate::do_parse_tag,
				total_cost	=> \&Vend::Interpolate::tag_total_cost,

			);

my %attrAlias = (
	 page          	=> { 'base' => 'arg' },
	 field          	=> { 
	 						'field' => 'name',
	 						'column' => 'name',
	 						'col' => 'name',
	 						'key' => 'code',
	 						'row' => 'code',
						},
	 data          	=> { 
	 						'database' => 'table',
	 						'base' => 'table',
	 						'name' => 'field',
	 						'column' => 'field',
	 						'col' => 'field',
	 						'code' => 'key',
	 						'row' => 'key',
						},
	 'or'			=> { 
	 						'comp' => 'compare',
	 						'operator' => 'op',
	 						'base' => 'type',
						},
	 'and'			=> { 
	 						'comp' => 'compare',
	 						'operator' => 'op',
	 						'base' => 'type',
						},
	 'shipping'			=> { 'cart' => 'name', },
	 'salestax'			=> { 'cart' => 'name', },
	 'subtotal'			=> { 'cart' => 'name', },
	 'total_cost'		=> { 'cart' => 'name', },
	 'if'			=> { 
	 						'comp' => 'compare',
	 						'operator' => 'op',
	 						'base' => 'type',
						},
	 search_region	   	=> { params => 'arg',
	 						 args => 'arg', },
	 loop	          	=> { args => 'arg',
	 						 list => 'arg', },
	 item_list	       	=> { cart => 'name', },
	 lookup          	=> { 
	 						'database' => 'table',
	 						'base' => 'table',
	 						'name' => 'field',
	 						'code' => 'key',
						},
);

my %Alias = (

				qw(
						url			urldecode
						urld		urldecode
						href		area
						a			pagetarget
				)
			);

my %canNest = (

				qw(
						if			1
						loop		1
				)
			);


my %replaceHTML = (
				qw(
					del .*
					pre .*
					xmp .*
				)
			);

my %replaceAttr = (
					area			=> { qw/ a 	href			/},
					areatarget		=> { qw/ a 	href			/},
					process_target	=> { qw/ form action		/},
					process_order 	=> { qw/ form action		/},
					process_search	=> { qw/ form action		/},
					checked			=> { qw/ input checked		/},
					selected		=> { qw/ option selected	/},
			);

my %insertHTML = (
				qw(

				form	process_target|process_order|process_search|area
				a 		area|areatarget
				input	checked
				option  selected
				)
			);

my %lookaheadHTML = (
				qw(

				if 		then|elsif|else
				)
			);

my %rowfixHTML = (	qw/
						td	item_list|loop|sql_list
					/	 );
# Only for containers
my %insideHTML = (
				qw(
					select	loop|item_list|tag
				)

				);

# Only for containers
my %endHTML = (
				qw(

				tr 		.*
				td 		.*
				th 		.*
				del 	.*
				script 	.*
				table 	if
				object 	perl
				param 	perl
				font 	if
				a 		if
				)
			);

my %hasEndTag = (

				qw(
						calc		1
						compat		1
						currency	1
						discount	1
						fly_list	1
						if			1
						item_list	1
						loop		1
						msql		1
						sql			1
						perl		1
						post		1
						row			1
						set			1
						search_region			1
						tag			1

				)
			);

my %Interpolate = (

				qw(
						buttonbar	1
						calc		1
						currency	1
						random		1
						rotate		1
						row			1
				)
			);

my %isEndAnchor = (

				qw(
						areatarget	1
						area		1
						pagetarget	1
						page		1
						order		1
						last_page	1
				)
			);

my $Tags_added = 0;

my $Initialized = 0;


sub global_init {
		add_tags($Global::UserTag);
}

sub new_noinit {
    my $class = shift;
    my $self = new Vend::Parser;
	$self->{INVALID} = 0;
	$self->{INTERPOLATE} = 0;

	add_tags($Vend::Cfg->{UserTag});
	$Tags_added = 1;

	$self->{OUT} = '';
    bless $self, $class;
}

sub new
{
    my $class = shift;
    my $self = new Vend::Parser;
	$self->{INVALID} = 0;
	$self->{INTERPOLATE} = shift || 0;

	add_tags($Vend::Cfg->{UserTag})
		unless $Tags_added;

	$self->{TOPLEVEL} = 1 if ! $Initialized;

	$self->{OUT} = '';
	$Initialized = 1;
    bless $self, $class;
}

my %myRefs = (
	 insideHTML		=> \%insideHTML,
	 Alias          => \%Alias,
	 attrAlias      => \%attrAlias,
	 canNest        => \%canNest,
	 endHTML    	=> \%endHTML,
	 hasEndTag      => \%hasEndTag,
	 Implicit       => \%Implicit,
	 insertHTML		=> \%insertHTML,
	 InvalidateCache => \%InvalidateCache,
	 isEndAnchor    => \%isEndAnchor,
	 lookaheadHTML	=> \%lookaheadHTML,
	 Order          => \%Order,
	 PosNumber      => \%PosNumber,
	 PosRoutine     => \%PosRoutine,
	 replaceAttr    => \%replaceAttr,
	 replaceHTML    => \%replaceHTML,
	 Required       => \%Required,
	 Routine        => \%Routine,
);

sub add_tags {
	return unless @_;
	my $ref = shift;
	my $area;
	no strict 'refs';
	foreach $area (keys %myRefs) {
		next unless $ref->{$area};
# DEBUG
# Vend::Util::logDebug
# ("Adding $area = " . Vend::Util::uneval($ref->{$area}) . "\n")
#	if ::debug(0x2);
# END DEBUG
		if($area eq 'Routine') {
			for (keys %{$ref->{$area}}) {
				$myRefs{$area}->{$_} = $ref->{$area}->{$_};
			}
			next;
		}
		elsif ($area =~ /HTML$/) {
			for (keys %{$ref->{$area}}) {
				$myRefs{$area}->{$_} =
					defined $myRefs{$area}->{$_}
					? $ref->{$area}->{$_} .'|'. $myRefs{$area}->{$_}
					: $ref->{$area}->{$_};
			}
		}
		else {
			Vend::Util::copyref $ref->{$area}, $myRefs{$area};
		}
	}
}

sub eof
{
    shift->parse(undef);
}

sub text
{
    my($self, $text) = @_;
	$Vend::PageCacheCopy .= $text
		if defined $Vend::PageCacheCopy and $self->{TOPLEVEL};
	$self->{OUT} .= $text;
}

sub comment
{
    # my($self, $comment) = @_;
}

my %Monitor = ( qw(    calc  1 currency  1 ) );

sub build_html_tag {
	my ($orig, $attr, $attrseq) = @_;
	$orig =~ s/\s+.*//s;
	for (@$attrseq) {
		$orig .= qq{ \U$_="} ;
		$attr->{$_} =~ s/"/\\"/g;
		$orig .= $attr->{$_};
		$orig .= '"';
	}
	$orig .= ">";
}

my %implicitHTML = (qw/checked CHECKED selected SELECTED/);

sub format_html_attribute {
	my($attr, $val) = @_;
	if(defined $implicitHTML{$attr}) {
		return $implicitHTML{$attr};
	}
	$val =~ s/"/&quot;/g;
	return qq{$attr="$val"};
}

sub html_start {
    my($self, $tag, $attr, $attrseq, $origtext, $end_tag) = @_;
	$tag =~ tr/-/_/;   # canonical
	$end_tag = lc $end_tag;
	my $buf = \$self->{_buf};
#::logGlobal("tag=$tag end_tag=$end_tag buf length " . length($$buf)) if $Monitor{$tag};
#::logGlobal("attributes: ", %{$attr}) if $Monitor{$tag};
	my($tmpbuf);
    # $attr is reference to a HASH, $attrseq is reference to an ARRAY
	my($return_html);

	unless (defined $Routine{$tag}) {
		if(defined $Alias{$tag}) {
			my ($rest, $text);
			($tag, $rest) = split /\s+/, $Alias{$tag}, 2;
			_find_tag (\$rest, $attr, $attrseq);
		}
		elsif ($tag eq 'urldecode') {
			$attr->{urldecode} = 1;
			$return_html = $origtext;
			$return_html =~ s/\s+.*//s;
		}
		else {
			$self->{OUT} .= $origtext;
			return 1;
		}
	}

	if(defined $InvalidateCache{$tag} and !$attr->{cache}) {
		$self->{INVALID} = 1;
	}

	$attr->{interpolate} = $self->{INTERPOLATE}
		unless defined $attr->{interpolate};

	my $trib;
	foreach $trib (@$attrseq) {
		# Attribute aliases
		if(defined $attrAlias{$tag} and $attrAlias{$tag}{$trib}) {
			my $new = $attrAlias{$tag}{$trib} ;
			$attr->{$new} = delete $attr->{$trib};
			$trib = $new;
		}
		elsif (0 and defined $Alias{$trib}) {
			my $new = $Alias{$trib} ;
			$attr->{$new} = delete $attr->{$trib};
			$trib = $new;
		}
		# Parse tags within tags, only works if the [ is the
		# first character.
		$attr->{$trib} =~ s/%([A-Fa-f0-9]{2})/chr(hex($1))/eg if $attr->{urldecode};
		next unless $attr->{$trib} =~ /\[\w+[-\w]*\s*[\000-\377]*\]/;

		my $p = new Vend::Parse;
		$p->parse($attr->{$trib});
		$attr->{$trib} = $p->{OUT};
		$self->{INVALID} += $p->{INVALID};
	}

	if($tag eq 'urldecode') {
		$self->{OUT} .= build_html_tag($return_html, $attr, $attrseq);
		return 1;
	}

	$attr->{'decode'} = 1 unless defined $attr->{'decode'};
	$attr->{'reparse'} = 1 unless defined $attr->{'reparse'};
	$attr->{'true'} = 1;
	$attr->{'false'} = 0;
	$attr->{'undef'} = undef;

	my ($routine,@args);

	if ($attr->{OLD}) {
	# HTML old-style tag
		$attr->{interpolate} = 0 if $hasEndTag{$tag} and $canNest{$tag};
		$attr->{interpolate} = 1 if defined $Interpolate{$tag};
		@args = $attr->{OLD};
		if(defined $PosNumber{$tag} and $PosNumber{$tag} > 1) {
			@args = split /\s+/, $attr->{OLD}, $PosNumber{$tag};
			push(@args, undef) while @args < $PosNumber{$tag};
		}
		$routine =  $PosRoutine{$tag} || $Routine{$tag};
	}
	else {
	# New style tag, HTML or otherwise
		$routine = $Routine{$tag};
		$attr->{interpolate} = 1
			if defined $Interpolate{$tag} and ! defined $attr->{interpolate};
		@args = @{$attr}{ @{ $Order{$tag} } };
	}

#::logGlobal("tag=$tag end_tag=$end_tag attributes:\n" . Vend::Util::uneval($attr)) if$Monitor{$tag};

	my $prefix = '';
	my $midfix = '';
	my $postfix = '';
	my @out;

	if($insertHTML{$end_tag}
		and ! $attr->{noinsert}
		and $tag =~ /^($insertHTML{$end_tag})$/) {
		$origtext =~ s/>\s*$//;
		@out = Text::ParseWords::shellwords($origtext);
		shift @out;
		@out = grep $_ !~ /^[Mm][Vv][=.]/, @out
			unless $attr->{showmv};
		if (defined $replaceAttr{$tag}
			and $replaceAttr{$tag}->{$end_tag}
			and	! $attr->{noreplace})
		{
			my $t = $replaceAttr{$tag}->{$end_tag};
			@out = grep $_ !~ /^($t)\b/i, @out;
			unless(defined $implicitHTML{$t}) {
				$out[0] .= qq{ \U$t="};
				$out[1] = defined $out[1] ? qq{" } . $out[1] : '"';
			}
			else { $midfix = ' ' }
		}
		else {
			$out[0] = " " . $out[0] . " "
				if $out[0];
		}
		if (@out) {
			$out[$#out] .= '>';
		}
		else {
			@out = '>';
		}
#::logGlobal("inserted " . join "|", @out);
	}

	if($hasEndTag{$tag}) {
		my $rowfix;
		# Handle embedded tags, but only if interpolate is 
		# defined (always if using old tags)
		if (defined $replaceHTML{$end_tag}
			and $tag =~ /^($replaceHTML{$end_tag})$/
			and ! $attr->{noreplace} )
		{
			$origtext = '';
			$tmpbuf = find_html_end($end_tag, $buf);
			$tmpbuf =~ s:</$end_tag\s*>::;
			HTML::Entities::decode($tmpbuf) if $attr->{decode};
			$tmpbuf =~ tr/\240/ /;
		}
		else {
			@out = Text::ParseWords::shellwords($origtext);
			($attr->{showmv} and
					@out = map {s/^[Mm][Vv]\./mv-/} @out)
				or @out = grep ! /^[Mm][Vv][=.]/, @out;
			$out[$#out] =~ s/([^>\s])\s*$/$1>/;
			$origtext = join " ", @out;

			if (defined $lookaheadHTML{$tag} and ! $attr->{nolook}) {
				$tmpbuf = $origtext . find_html_end($end_tag, $buf);
				while($$buf =~ s~^\s*(<([A-Za-z][-A-Z.a-z0-9]*)[^>]*)\s+
								[Mm][Vv]\s*=\s*
								(['"]) \[?
									($lookaheadHTML{$tag})\b(.*?)
								\]?\3~~ix ) 
				{
					my $orig = $1;
					my $enclose = $4;
					my $adder = $5;
					my $end = lc $2;
					$tmpbuf .= "[$enclose$adder]"	.  $orig	.
								find_html_end($end, $buf)	.
								"[/$enclose]";
				}
			}
			# GACK!!! No table row attributes in some editors????
			elsif (defined $rowfixHTML{$end_tag}
				and $tag =~ /^($rowfixHTML{$end_tag})$/
				and $attr->{rowfix} )
			{
				$rowfix = 1;
				$tmpbuf = '<tr>' . $origtext . find_html_end('tr', $buf);
#::logGlobal("Tmpbuf: $tmpbuf");
			}
			elsif (defined $insideHTML{$end_tag}
					and ! $attr->{noinside}
					and $tag =~ /^($insideHTML{$end_tag})$/i) {
				$prefix = $origtext;
				$tmpbuf = find_html_end($end_tag, $buf);
				$tmpbuf =~ s:</$end_tag\s*>::;
				$postfix = "</$end_tag>";
				HTML::Entities::decode($tmpbuf) if $attr->{'decode'};
				$tmpbuf =~ tr/\240/ / if $attr->{'decode'};
			}
			else {
				$tmpbuf = $origtext . find_html_end($end_tag, $buf);
			}
		}

		$tmpbuf =~ s/%([A-Fa-f0-9]{2})/chr(hex($1))/eg if $attr->{urldecode};

		if ($attr->{interpolate}) {
			my $p = new Vend::Parse;
			$p->parse($tmpbuf);
			$tmpbuf = $p->{OUT};
		}

		$tmpbuf =  $attr->{prepend} . $tmpbuf if defined $attr->{prepend};
		$tmpbuf .= $attr->{append}            if defined $attr->{append};

		if (! $attr->{reparse}) {
			$self->{OUT} .= $prefix . &{$routine}(@args,$tmpbuf) . $postfix;
		}
		elsif (! defined $rowfix) {
			$$buf = $prefix . &{$routine}(@args,$tmpbuf) . $postfix . $$buf
		}
		else {
			$tmpbuf = &{$routine}(@args,$tmpbuf);
			$tmpbuf =~ s|<tr>||i;
			$$buf = $prefix . $tmpbuf . $postfix . $$buf;
		}


	}
	else {
		if(! @out and $attr->{prepend} or $attr->{append}) {
			my @tmp;
			@tmp = Text::ParseWords::shellwords($origtext);
			shift @tmp;
			@tmp = grep $_ !~ /^[Mm][Vv][=.]/, @tmp
				unless $attr->{showmv};
			$postfix = $attr->{prepend} ? "<\U$end_tag " . join(" ", @tmp) : '';
			$prefix = $attr->{append} ? "<\U$end_tag " . join(" ", @tmp) : '';
		}
		if(! $attr->{interpolate}) {
			if(@out) {
				$self->{OUT} .= "<\U$end_tag ";
				if 		($out[0] =~ / > \s*$ /x ) { }   # End of tag, do nothing
				elsif	($out[0] =~ / ^[^"]*"$/x ) {     # End of tag
					$self->{OUT} .= shift(@out);
				}
				else {
					unshift(@out, '');
				}
			}
			$self->{OUT} .= $prefix . &$routine( @args ) . $midfix;
			$self->{OUT} .= join(" ", @out) . $postfix;
		}
		else {
			if(@out) {
				$$buf = "<\U$end_tag " . &$routine( @args ) . $midfix . join(" ", @out) . $$buf;
			}
			else {
				$$buf = $prefix . &$routine( @args ) . $postfix . $$buf;
			}
		}
	}

	$self->{SEND} = $attr->{'send'} || undef;
#::logGlobal("Returning from $tag");
	return 1;

}

sub start {
	return html_start(@_) if $_[0]->{HTML};
    my($self, $tag, $attr, $attrseq, $origtext) = @_;
	$tag =~ tr/-/_/;   # canonical
	my $buf = \$self->{_buf};
#::logGlobal("tag=$tag buf length " . length($$buf));
#::logGlobal("tag=$tag Interp='$Interpolate{$tag}' attributes:\n" . Vend::Util::uneval($attr)) if$Monitor{$tag};
	my($tmpbuf);
    # $attr is reference to a HASH, $attrseq is reference to an ARRAY
	unless (defined $Routine{$tag}) {
		if(defined $Alias{$tag}) {
			my ($rest, $text);
			($tag, $rest) = split /\s+/, $Alias{$tag}, 2;
			$text = _find_tag (\$rest, $attr, $attrseq);
			$text = " $text" if $text;
			$origtext =~ s:^(\[\S+):[$tag$text:;
		}
		else {
			$self->{OUT} .= $origtext;
			return 1;
		}
	}

	if(defined $InvalidateCache{$tag} and !$attr->{cache}) {
		$self->{INVALID} = 1;
	}

	$attr->{interpolate} = $self->{INTERPOLATE}
		unless $Interpolate{$tag} or defined $attr->{interpolate};

	my $trib;
	foreach $trib (@$attrseq) {
		# Attribute aliases
		if(defined $attrAlias{$tag} and $attrAlias{$tag}{$trib}) {
			my $new = $attrAlias{$tag}{$trib} ;
			$attr->{$new} = delete $attr->{$trib};
			$trib = $new;
		}
		# Parse tags within tags, only works if the [ is the
		# first character.
		next unless $attr->{$trib} =~ /\[\w+[-\w]*\s*[\000-\377]*\]/;

		my $p = new Vend::Parse;
		$p->parse($attr->{$trib});
		$attr->{$trib} = $p->{OUT};
		$self->{INVALID} += $p->{INVALID};
	}

	$attr->{'true'} = 1;
	$attr->{'false'} = 0;
	$attr->{'undef'} = undef;

	my ($routine,@args);

	# Check for old-style positional tag
	if(!@$attrseq and $origtext =~ s/\[[-\w]+\s+//i) {
			$origtext =~ s/\]$//;
			$attr->{interpolate} = 0 if $hasEndTag{$tag} and $canNest{$tag};
			$attr->{interpolate} = 1 if defined $Interpolate{$tag};
			@args = ($origtext);
			if(defined $PosNumber{$tag} and $PosNumber{$tag} > 1) {
				@args = split /\s+/, $origtext, $PosNumber{$tag};
				push(@args, undef) while @args < $PosNumber{$tag};
			}
			$routine =  $PosRoutine{$tag} || $Routine{$tag};
	}
	else {
		$routine = $Routine{$tag};
		$attr->{interpolate} = 1
			if  defined $Interpolate{$tag} and ! defined $attr->{interpolate};
		@args = @{$attr}{ @{ $Order{$tag} } };
	}

#::logGlobal("Interpolate value now='$attr->{interpolate}'") if$Monitor{$tag};

#::logGlobal("$tag, routine=$routine interpolate=" . $attr->{interpolate}) if $Monitor{$tag};
	if($hasEndTag{$tag}) {
		# Handle embedded tags, but only if interpolate is 
		# defined (always if using old tags)
#::logGlobal("look end for $tag, buf=" . length($$buf) );
		$tmpbuf = find_matching_end($tag, $buf);
#::logGlobal("FOUND end for $tag\nBuf " . length($$buf) . ":\n" . $$buf . "\nTmpbuf:\n$tmpbuf\n");
		if ($attr->{interpolate}) {
			my $p = new Vend::Parse;
			$p->parse($tmpbuf);
			$tmpbuf = $p->{OUT};
		}
		$$buf = &$routine(@args,$tmpbuf) . $$buf;
	}
	elsif(! $attr->{interpolate}) {
		$self->{OUT} .= &$routine( @args );
	}
	else {
		$$buf = &$routine( @args ) . $$buf;
	}

	$self->{SEND} = $attr->{'send'} || undef;
#::logGlobal("Returning from $tag");
	return 1;
}

sub end
{
    my($self, $tag) = @_;
	my $save = $tag;
	$tag =~ tr/-/_/;   # canonical
	
# DEBUG
#Vend::Util::logDebug
#("called Vend::Parse::end with $tag\n")
#	if ::debug(0x2);
# END DEBUG

	$self->{OUT} .= $isEndAnchor{$tag} ? '</a>' : "[/$save]";

}

sub find_html_end {
    my($tag, $buf) = @_;
    my $out;
	my $canon;

    my $open  = "<$tag ";
    my $close = "</$tag>";
	($canon = $tag) =~ s/_/[-_]/g;

    $$buf =~ s!<$canon\s!<$tag !ig;
    $$buf =~ s!</$canon\s*>!</$tag>!ig;
    my $first = index($$buf, $close);
    return undef if $first < 0;
    my $int = index($$buf, $open);
    my $pos = 0;
#::logGlobal("find_html_end: tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
    while( $int > -1 and $int < $first) {
        $pos   = $int + 1;
        $first = index($$buf, $close, $first + 1);
        $int   = index($$buf, $open, $pos);
#::logGlobal("find_html_end: tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
    }
#::logGlobal("find_html_end: tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
	return undef if $first < 0;
    $first += length($close);
#::logGlobal("find_html_end (add close): tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
    $out = substr($$buf, 0, $first);
    substr($$buf, 0, $first) = '';
    return $out;
}

sub find_matching_end {
    my($tag, $buf) = @_;
    my $out;
	my $canon;

    my $open  = "[$tag ";
    my $close = "[/$tag]";
	($canon = $tag) =~ s/_/[-_]/g;

    $$buf =~ s!\[$canon\s![$tag !ig;
    $$buf =~ s!\[/$canon\]![/$tag]!ig;
    my $first = index($$buf, $close);
    return undef if $first < 0;
    my $int = index($$buf, $open);
    my $pos = 0;
#::logGlobal("find_matching_end: tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
    while( $int > -1 and $int < $first) {
        $pos   = $int + 1;
        $first = index($$buf, $close, $first + 1);
        $int   = index($$buf, $open, $pos);
#::logGlobal("find_matching_end: tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
    }
    $out = substr($$buf, 0, $first);
    $first = $first < 0 ? $first : $first + length($close);
#::logGlobal("find_matching_end (add close): tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
    substr($$buf, 0, $first) = '';
    return $out;
}

# Passed some string that might be HTML-style attributes
# or might be positional parameters, does the right thing
sub _find_tag {
	my ($buf, $attrhash, $attrseq) = (@_);
	my $old = 0;
	my $eaten = '';
	my %attr;
	my @attrseq;
	while ($$buf =~ s|^(([a-zA-Z][-a-zA-Z0-9._]*)\s*)||) {
		$eaten .= $1;
		my $attr = lc $2;
		my $val;
		$old = 0;
		# The attribute might take an optional value (first we
		# check for an unquoted value)
		if ($$buf =~ s|(^=\s*([^\"\'\]\s][^\]\s]*)\s*)||) {
			$eaten .= $1;
			$val = $2;
			HTML::Entities::decode($val);
		# or quoted by " or '
		} elsif ($$buf =~ s|(^=\s*([\"\'])(.*?)\2\s*)||s) {
			$eaten .= $1;
			$val = $3;
			HTML::Entities::decode($val);
		# truncated just after the '=' or inside the attribute
		} elsif ($$buf =~ m|^(=\s*)$| or
				 $$buf =~ m|^(=\s*[\"\'].*)|s) {
			$eaten = "$eaten$1";
			last;
		} else {
			# assume attribute with implicit value, which 
			# means in MiniVend no value is set and the
			# eaten value is grown. Note that you should
			# never use an implicit tag when setting up an Alias.
			$old = 1;
		}
		next if $old;
		$attrhash->{$attr} = $val;
		push(@attrseq, $attr);
	}
	unshift(@$attrseq, @attrseq);
	return ($eaten);
}

# checks for implicit tags
# INT is special in that it doesn't get pushed on @attrseq
sub implicit {
	my($self, $tag, $attr) = @_;
# DEBUG
Vend::Util::logDebug
("check tag='$tag' attr='$attr'...")
	if ::debug(0x2);
# END DEBUG
	return ('interpolate', 1, 1) if $attr eq 'int';
	return ($attr, undef) unless defined $Implicit{$tag} and $Implicit{$tag}{$attr};
	my $imp = $Implicit{$tag}{$attr};
	return ($attr, $imp) if $imp =~ s/^$attr=//i;
	return ( $Implicit{$tag}{$attr}, $attr );
}

1;
__END__
