# Parse.pm - Parse MiniVend tags
# 
# $Id: Parse.pm,v 1.8 1997/06/17 04:22:52 mike Exp $
#
# Copyright 1997 by Michael J. Heins <mikeh@iac.net>
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

# $Id: Parse.pm,v 1.8 1997/06/17 04:22:52 mike Exp $

require Vend::Parser;


$VERSION = sprintf("%d.%02d", q$Revision: 1.8 $ =~ /(\d+)\.(\d+)/);

use Safe;
use Vend::Util;
use Vend::Interpolate;
# STATICPAGE
use Vend::PageBuild;
# END STATICPAGE

require Exporter;

# AUTOLOAD
#use AutoLoader;
#@ISA = qw(Exporter AutoLoader Vend::Parser);
#*AUTOLOAD = \&AutoLoader::AUTOLOAD;
# END AUTOLOAD

# NOAUTO
@ISA = qw(Exporter Vend::Parser);
# END NOAUTO

$VERSION = substr(q$Revision: 1.8 $, 10);
@EXPORT = ();
@EXPORT_OK = qw(find_matching_end find_end);

use strict;

# NOAUTO
use vars qw($VERSION);
# END NOAUTO

# AUTOLOAD
#use vars qw(
#
#$VERSION
#%Implicit
#%InvalidateCache
#%Order
#%PosNumber
#%PosRoutine
#%Required
#%Routine
#%canNest
#%Default
#%hasEndTag
#%isEndAnchor
#%isOperator
#
#);
#
# END AUTOLOAD


# AUTOLOAD
#%PosNumber =	(
# END AUTOLOAD

# NOAUTO
my %PosNumber =	(
# END NOAUTO

				accessories		=> 2,
				area			=> 3,
				areatarget		=> 3,
				body			=> 1,
				buttonbar		=> 1,
				cart			=> 1,
				checked			=> 3,
				data			=> 4,
				default			=> 1,
				discount		=> 1,
				description		=> 2,
				field			=> 2,
				file			=> 2,
				finish_order	=> 1,
				framebase		=> 1,
				help			=> 1,
				'if'			=> 1,
				last_page		=> 2,
				lookup			=> 1,
				loop			=> 1,
				msql			=> 2,
				nitems			=> 1,
				order			=> 3,
				page			=> 3,
				pagetarget		=> 3,
				perl			=> 1,
				price			=> 3,
				process_order	=> 2,
				process_search	=> 1,
				process_target	=> 2,
				rotate			=> 1,
				row				=> 1,
				salestax		=> 1,
				scratch			=> 1,
				selected		=> 3,
				set				=> 1,
				shipping		=> 1,
				shipping_desc	=> 1,
				shipping_description	=> 1,
				sql				=> 2,
				subtotal		=> 1,
				tag				=> 1,
				total_cost		=> 1,
				value			=> 2,

			);

# AUTOLOAD
#%Order =	(
# END AUTOLOAD

# NOAUTO
my %Order =	(
# END NOAUTO

				accessories		=> [qw( code false arg )],
				area			=> [qw( href target base )],
				areatarget		=> [qw( href target base )],
				body			=> [qw( type  )],
				buttonbar		=> [qw( type  )],
				calc			=> [],
				cart			=> [qw( name  )],
				'currency'		=> [],
				checked			=> [qw( name value multiple)],
				data			=> [qw( base name code value increment)],
				default			=> [qw( name )],
				description		=> [qw( code base )],
				discount		=> [qw( code  )],
				field			=> [qw( name code )],
				file			=> [qw( name )],
				finish_order	=> [qw( href )],
				framebase		=> [qw( target  )],
				frames_off		=> [],
				frames_on		=> [],
				help			=> [qw( name  )],
				'if'			=> [qw( type term op compare )],
				item_list		=> [qw( name )],
				last_page		=> [qw( target arg )],
				lookup			=> [qw( base name code value )],
				loop			=> [qw( arg )],
				msql			=> [qw( base type arg )],
				nitems			=> [qw( name  )],
				order			=> [qw( code href base )],
				page			=> [qw( href target base )],
				pagetarget		=> [qw( href target base )],
				perl			=> [qw( arg )],
				price			=> [qw( code quantity base )],
				process_order	=> [qw( target secure )],
				process_search	=> [qw( target )],
				process_target	=> [qw( target secure )],
				random			=> [],
				rotate			=> [qw( ceiling )],
				row				=> [qw( width )],
				salestax		=> [qw( name  )],
				scratch			=> [qw( name  )],
				selected		=> [qw( name value multiple )],
				set				=> [qw( name  )],
				shipping		=> [qw( name  )],
				shipping_desc	=> [qw( name  )],
				shipping_description	=> [qw( name  )],
				sql				=> [qw( base type arg )],
				subtotal		=> [qw( name  )],
				tag				=> [qw( op base file type )],
				total_cost		=> [qw( name )],
				value			=> [qw( name escaped )],

			);

# AUTOLOAD
#%Required = (
# END AUTOLOAD

# NOAUTO
my %Required = (
# END NOAUTO

				accessories	=> [ qw( code )],
				area		=> [ qw( href )],
				areatarget	=> [ qw( href )],
				body		=> [ qw( type )],
				buttonbar	=> [ qw( type )],
				cart		=> [ qw( name )],
				checked		=> [ qw( name value )],
				data		=> [ qw( base )],
				default		=> [ qw( name )],
				discount	=> [ qw( code )],
				field		=> [ qw( name code )],
				file		=> [ qw( name )],
				framebase	=> [ qw( target )],
				help		=> [ qw( name )],
				'if'		=> [ qw( base )],
				lookup		=> [ qw( base name code )],
				order		=> [ qw( code )],
				page		=> [ qw( href )],
				pagetarget	=> [ qw( href )],
				scratch		=> [ qw( name )],
				selected	=> [ qw( name value )],
				set			=> [ qw( name )],
				value		=> [ qw( name )],

			);

# AUTOLOAD
#%InvalidateCache = (
# END AUTOLOAD

# NOAUTO
my %InvalidateCache = (
# END NOAUTO

			qw(
				cart		1
				checked		1
				default		1
				discount	1
				frames_off	1
				frames_on	1
				item_list	1
				last_page	1
				lookup		1
				msql		1
				nitems		1
				perl		1
				salestax	1
				scratch		1
				selected	1
				set			1
				shipping	1
				sql			1
				subtotal	1
				total_cost	1
				value		1

			   )
			);

# AUTOLOAD
#%isOperator = (
# END AUTOLOAD

# NOAUTO
my %isOperator = (
# END NOAUTO

			qw(
				!=		1
				!~		1
				<=		1
				==		1
				=~		1
				>=		1
				eq		1
				gt		1
				lt		1
				ne		1
			   )
			);

# AUTOLOAD
#%Implicit = (
# END AUTOLOAD

# NOAUTO
my %Implicit = (
# END NOAUTO

			   qw(
				escaped	escaped
			    increment  increment
				secure	secure
				multiple	multiple
			   )
			);

# AUTOLOAD
#%PosRoutine = (
# END AUTOLOAD

# NOAUTO
my %PosRoutine = (
# END NOAUTO

				'if'			=> \&Vend::Interpolate::tag_if,
				tag				=> \&Vend::Interpolate::do_tag,
			);


# AUTOLOAD
#%Routine = (
# END AUTOLOAD

# NOAUTO
my %Routine = (
# END NOAUTO

				accessories		=> \&Vend::Interpolate::tag_accessories,
				area			=> \&Vend::Interpolate::tag_areatarget,
				areatarget		=> \&Vend::Interpolate::tag_areatarget,
				body			=> \&Vend::Interpolate::tag_body,
				buttonbar		=> \&Vend::Interpolate::tag_buttonbar,
				calc			=> \&Vend::Interpolate::tag_calc,
				cart			=> \&Vend::Interpolate::tag_cart,
				checked			=> \&Vend::Interpolate::tag_selected,
				'currency'		=> \&Vend::Interpolate::currency,
				data			=> \&Vend::Interpolate::tag_data,
				default			=> \&Vend::Interpolate::tag_default,
				description		=> \&Vend::Data::product_description,
				discount		=> \&Vend::Interpolate::tag_discount,
				field			=> \&Vend::Data::product_field,
				file			=> \&Vend::Interpolate::tag_file,
				finish_order	=> \&Vend::Interpolate::tag_finish_order,
				framebase		=> \&Vend::Interpolate::tag_frame_base,
				frames_off		=> \&Vend::Interpolate::tag_frames_off,
				frames_on		=> \&Vend::Interpolate::tag_frames_on,
				help			=> \&Vend::Interpolate::tag_help,
				item_list		=> \&Vend::Interpolate::tag_item_list,
				'if'			=> \&Vend::Interpolate::tag_self_contained_if,
				last_page		=> \&Vend::Interpolate::tag_last_page,
				lookup			=> \&Vend::Interpolate::tag_lookup,
				loop			=> \&Vend::Interpolate::tag_loop_list,
				msql			=> \&Vend::Data::msql_query,
				nitems			=> \&Vend::Util::tag_nitems,
				order			=> \&Vend::Interpolate::tag_order,
				page			=> \&Vend::Interpolate::tag_pagetarget,
				pagetarget		=> \&Vend::Interpolate::tag_pagetarget,
				perl			=> \&Vend::Interpolate::tag_perl,
				price        	=> \&Vend::Data::product_price,
				process_order	=> \&Vend::Interpolate::tag_process_order,
				process_search	=> \&Vend::Interpolate::tag_process_search,
				process_target	=> \&Vend::Interpolate::tag_process_target,
				random			=> \&Vend::Interpolate::tag_random,
				rotate			=> \&Vend::Interpolate::tag_rotate,
				row				=> \&Vend::Interpolate::tag_row,
				row				=> \&Vend::Interpolate::tag_row,
				salestax		=> \&Vend::Interpolate::salestax,
				scratch			=> \&Vend::Interpolate::tag_scratch,
				selected		=> \&Vend::Interpolate::tag_selected,
				set				=> \&Vend::Interpolate::set_scratch,
				shipping		=> \&Vend::Interpolate::tag_shipping,
				shipping_desc	=> \&Vend::Interpolate::tag_shipping_desc,
				shipping_description => \&Vend::Interpolate::tag_shipping_desc,
				sql				=> \&Vend::Data::dbi_query,
				subtotal	=> \&Vend::Interpolate::tag_subtotal,
				tag			=> \&Vend::Interpolate::do_parse_tag,
				total_cost	=> \&Vend::Interpolate::tag_total_cost,
				value		=> \&Vend::Interpolate::tag_value,

			);

# AUTOLOAD
#%canNest = (
# END AUTOLOAD

# NOAUTO
my %canNest = (
# END NOAUTO

				qw(
						if			1
						loop		1
						then		1
						else		1

				)
			);


# AUTOLOAD
#%Default = (
# END AUTOLOAD

# NOAUTO
my %Default = (
# END NOAUTO
						checked	 =>	{ value => 'on' }
			);

# AUTOLOAD
#%hasEndTag = (
# END AUTOLOAD

# NOAUTO
my %hasEndTag = (
# END NOAUTO

				qw(
						calc		1
						currency	1
						discount	1
						if			1
						item_list	1
						loop		1
						msql		1
						perl		1
						row			1
						set			1
						tag			1

				)
			);

# AUTOLOAD
#%isEndAnchor = (
# END AUTOLOAD

# NOAUTO
my %isEndAnchor = (
# END NOAUTO

				qw(
						areatarget	1
						area		1
						pagetarget	1
						page		1
						order		1
						last_page	1
				)
			);

# AUTOLOAD
#1;
#__END__
# END AUTOLOAD

sub new
{
    my $class = shift;
    my $self = new Vend::Parser;
	$self->{OUT} = '';
	$self->{INVALID} = 0;
	$self->{INTERPOLATE} = shift || 0;
	$self->{WAIT_BRACKET} = 0;
    bless $self, $class;
}

sub eof
{
    shift->parse(undef);
}

sub text
{
    my($self, $text) = @_;
	$self->{OUT} .= $text;
}

sub comment
{
    # my($self, $comment) = @_;
}

sub start
{
    my($self, $tag, $attr, $attrseq, $origtext) = @_;
	$tag =~ tr/-/_/;   # canonical
#print("called start @_\n") if $Global::DEBUG;
	my($tmpbuf);
    # $attr is reference to a HASH, $attrseq is reference to an ARRAY
	unless (defined $Routine{$tag}) {
#print("Returning text, tag $tag not found\n$origtext\n") if $Global::DEBUG;
		$self->{OUT} .= $origtext;
		return 1;
	}
	if($InvalidateCache{$tag}) {
		$self->{INVALID} = 1;
	}


	if(0) {
	#unless (!$Vend::Cfg->{AllowMixed}) {
		for(@{$Required{$tag}}) {
			next if defined $attr->{$_};
			if (defined $Default{$tag}->{$_}) {
				$attr->{$_} = $Default{$tag}->{$_};
				next;
			}
#print("Returning blank, required attribute $_ not found\n$origtext\n") if $Global::DEBUG;
			return undef;
		}
	}

	$attr->{interpolate} = $self->{INTERPOLATE}
		unless defined $attr->{interpolate};
#print("Start $tag: wait for $self->{WAIT_BRACKET}...") if $Global::DEBUG;

	for(@$attrseq) {
		# Handle implicit tags
		#$attr->{$_} = $Implicit{$_} if defined $Implicit{$_};
		
		# Parse tags within tags, only works if the [ is the
		# first character.
		next unless $attr->{$_} =~ /\[[\000-\377]+\]/;
		my $t = $_;
#print("Parsing attribute $t\n$attr->{$t}") if $Global::DEBUG;

		my $p = new Vend::Parse $self->{WAIT_BRACKET};
		$p->parse($attr->{$t});
		$attr->{$t} = $p->{OUT};
		$self->{INVALID} += $p->{INVALID};
	}

	$attr->{'true'} = 1;
	$attr->{'false'} = 0;
	$attr->{'undef'} = undef;

	my ($routine,@args);
	if($self->{OUT} =~ s/\[\s*\d?\s*$//) {
		$self->{WAIT_BRACKET}++;
		$attr->{interpolate}++;
#print("...waiting for $self->{WAIT_BRACKET} bracket(s)...") if $Global::DEBUG;
	}

	# Check for old-style positional tag
	if($origtext =~ s/\[[-\w]+\s+//i and !@$attrseq)
	{
#print("called old $tag with args $origtext\n") if $Global::DEBUG;
			$origtext =~ s/\]$//;
			$attr->{interpolate} = 1 if $hasEndTag{$tag};
			@args = ($origtext);
			if(defined $PosNumber{$tag} and $PosNumber{$tag} > 1) {
				@args = split /\s+/, $origtext, $PosNumber{$tag};
			}
			$routine =  $PosRoutine{$tag} || $Routine{$tag};
	}
	else {
		$routine = $Routine{$tag};
		@args = @{$attr}{ @{ $Order{$tag} } };
	}

	if($hasEndTag{$tag}) {
#print("...has end tag...") if $Global::DEBUG;
		if($canNest{$tag}) {
#print("...find_matching_end...") if $Global::DEBUG;
			$tmpbuf = $self->find_matching_end($tag);
		}
		else {
#print("...find_end...") if $Global::DEBUG;
			$tmpbuf = $self->find_end($tag);
		}

		# Handle embedded tags, but only if interpolate is 
		# defined (always if using old tags)
		if($attr->{interpolate}) {
#print("...interpolating...") if $Global::DEBUG;
			my $p = new Vend::Parse $self->{WAIT_BRACKET};
			$p->parse($tmpbuf);
			$tmpbuf = $p->{OUT};
			$self->{INVALID} += $p->{INVALID};
		}
		elsif(	$self->{WAIT_BRACKET} and
				$self->{'_buf'} =~ s/\s*\d?\s*\]// ) {
			$self->{WAIT_BRACKET}--;
#print("...removed bracket (1)...") if $Global::DEBUG;
		}

		# recursive
		$self->{'_buf'} = 
			&$routine( @args, $tmpbuf )
				. $self->{'_buf'};
	}
	elsif($attr->{interpolate}) {
#print("...interpolating...") if $Global::DEBUG;
			my $p = new Vend::Parse $self->{WAIT_BRACKET};
			$p->parse(&$routine( @args ));
			$self->{INVALID} += $p->{INVALID};
			$self->{OUT} .= $p->{OUT};
	}
	else {
		$self->{OUT} .= &$routine( @args );
	}

	if($self->{WAIT_BRACKET} and $self->{'_buf'} =~ s/\s*\d?\s*\]// ) {
#print("...removed bracket (2)...") if $Global::DEBUG;
			$self->{WAIT_BRACKET}--;
	}
#print("waiting for $self->{WAIT_BRACKET} brackets.\n") if $Global::DEBUG;

	return 1;
}

sub end
{
    my($self, $tag) = @_;
	my $save = $tag;
	$tag =~ tr/-/_/;   # canonical
#print("called Vend::Parse::end with $tag\n") if $Global::DEBUG;

	if ($isEndAnchor{$tag}) {
		$self->{OUT} .= '</a>';
	}
	elsif (! $hasEndTag{$tag}) {
#print("Returning text, end tag $tag not found\n") if $Global::DEBUG;
		$self->{OUT} .= "[/$save]";
		return '';
	}

	if($self->{WAIT_BRACKET} and $self->{'_buf'} =~ s/\s*\d?\s*\]// ) {
#print("...removed bracket (3)...") if $Global::DEBUG;
			$self->{WAIT_BRACKET}--;
	}
	return '';
}

sub find_matching_end {
	my($self, $tag) = @_;
	my $buf = \$self->{'_buf'};
	my ($tmpbuf, $eaten, $outbuf, $more, $found);
	$tmpbuf = '';
	$found = $more = 0;
	my @out;
	for(;;) {
		if ( $$buf =~ s#^([\000-\377]*?)(\[/$tag\])##i) {
			$tmpbuf = $1;
			$eaten = $2;
			if($self->{WAIT_BRACKET} and $$buf =~ s/\s*\d?\s*\]// ) {
#print("...removed bracket (4)...") if $Global::DEBUG;
					$self->{WAIT_BRACKET}--;
			}
			$found++;
			push(@out, $tmpbuf);
			$more++ while ($tmpbuf =~ m!\[$tag[\]\s]!g);
#print("---found=$found more=$more") if $Global::DEBUG;
			push(@out, $eaten);
			last if $found > $more;
		}
		else {
#print("---eof found.") if $Global::DEBUG;
			last;
		}
	}
	pop @out;

	$outbuf = join '', @out;
#print("---BUFFER LOOP ----\n$outbuf\n------\n") if $Global::DEBUG;
	$outbuf;
}


sub find_end {
	my($self, $tag) = @_;
	my $buf = \$self->{'_buf'};
	$tag =~ s'_'[-_]'g;
#print("Finding match for $tag...\n") if $Global::DEBUG;
	if($$buf =~ s!([\000-\377]*?)(\[/${tag}\])!!) {
		return $1;
	}
	else {
#print("Found no match for $tag.\n") if $Global::DEBUG;
		return undef;
	}
}

1;
__END__
