# Parse.pm - Parse MiniVend tags
# 
# $Id: Parse.pm,v 1.14 1997/11/08 16:45:21 mike Exp mike $
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

# $Id: Parse.pm,v 1.14 1997/11/08 16:45:21 mike Exp mike $

require Vend::Parser;


$VERSION = sprintf("%d.%02d", q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/);

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

$VERSION = substr(q$Revision: 1.14 $, 10);
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
#%Interpolate
#%Alias
#%hasEndTag
#%isEndAnchor
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
				area			=> 2,
				areatarget		=> 3,
				body			=> 1,
				buttonbar		=> 1,
				cart			=> 1,
				checked			=> 3,
				data			=> 5,
				default			=> 1,
				discount		=> 1,
				description		=> 2,
				field			=> 2,
				file			=> 2,
				finish_order	=> 1,
				framebase		=> 1,
				help			=> 1,
				'if'			=> 1,
				include			=> 1,
				last_page		=> 2,
				lookup			=> 1,
				loop			=> 1,
				msql			=> 2,
				nitems			=> 1,
				order			=> 3,
				page			=> 2,
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
				search			=> 1,
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

				accessories		=> [qw( code arg )],
				area			=> [qw( href arg )],
				areatarget		=> [qw( href target arg )],
				body			=> [qw( type  )],
				buttonbar		=> [qw( type  )],
				calc			=> [],
				cart			=> [qw( name  )],
				compat			=> [],
				'currency'		=> [],
				checked			=> [qw( name value multiple)],
				data			=> [qw( table field key value increment)],
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
				include			=> [qw( file )],
				item_list		=> [qw( name )],
				last_page		=> [qw( target arg )],
				lookup			=> [qw( table field key value )],
				loop			=> [qw( arg )],
				msql			=> [qw( base type arg )],
				nitems			=> [qw( name  )],
				order			=> [qw( code href base )],
				page			=> [qw( href arg )],
				pagetarget		=> [qw( href target arg )],
				perl			=> [qw( arg )],
				post			=> [],
				price			=> [qw( code quantity base )],
				process_order	=> [qw( target secure )],
				process_search	=> [qw( target )],
				process_target	=> [qw( target secure )],
				random			=> [],
				rotate			=> [qw( ceiling )],
				row				=> [qw( width )],
				salestax		=> [qw( name  )],
				scratch			=> [qw( name  )],
				search			=> [qw( arg   )],
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
				data		=> [ qw( table )],
				default		=> [ qw( name )],
				discount	=> [ qw( code )],
				field		=> [ qw( name code )],
				file		=> [ qw( name )],
				framebase	=> [ qw( target )],
				help		=> [ qw( name )],
				'if'		=> [ qw( base )],
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
#%Implicit = (
# END AUTOLOAD

# NOAUTO
my %Implicit = (
# END NOAUTO

			'data' =>		{ qw( increment increment ) },
			'value' =>		{ qw( escaped	escpaped ) },
			'checked' =>	{ qw( multiple	multiple ) },

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
				'currency'		=> \&Vend::Interpolate::currency,
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
				'if'			=> \&Vend::Interpolate::tag_self_contained_if,
				last_page		=> \&Vend::Interpolate::tag_last_page,
				lookup			=> \&Vend::Interpolate::tag_lookup,
				loop			=> \&Vend::Interpolate::tag_loop_list,
				msql			=> \&Vend::Data::msql_query,
				nitems			=> \&Vend::Util::tag_nitems,
				order			=> \&Vend::Interpolate::tag_order,
				page			=> \&Vend::Interpolate::tag_page,
				pagetarget		=> \&Vend::Interpolate::tag_pagetarget,
				perl			=> \&Vend::Interpolate::tag_perl,
				post			=> sub { return $_[0] },
				price        	=> \&Vend::Data::product_price,
				process_order	=> \&Vend::Interpolate::tag_process_order,
				process_search	=> \&Vend::Interpolate::tag_process_search,
				process_target	=> \&Vend::Interpolate::tag_process_target,
				random			=> \&Vend::Interpolate::tag_random,
				rotate			=> \&Vend::Interpolate::tag_rotate,
				row				=> \&Vend::Interpolate::tag_row,
				salestax		=> \&Vend::Interpolate::tag_salestax,
				scratch			=> \&Vend::Interpolate::tag_scratch,
				search			=> \&Vend::Interpolate::tag_search,
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
#%Alias = (
# END AUTOLOAD

# NOAUTO
my %Alias = (
# END NOAUTO

				qw(
						href		area
						a			pagetarget
				)
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
				)
			);


# AUTOLOAD
#%hasEndTag = (
# END AUTOLOAD

# NOAUTO
my %hasEndTag = (
# END NOAUTO

				qw(
						calc		1
						compat		1
						currency	1
						discount	1
						if			1
						item_list	1
						loop		1
						msql		1
						perl		1
						post		1
						row			1
						set			1
						tag			1

				)
			);

# AUTOLOAD
#%Interpolate = (
# END AUTOLOAD

# NOAUTO
my %Interpolate = (
# END NOAUTO

				qw(
						buttonbar	1
						row			1
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

my $Initialized = 0;

sub new
{
    my $class = shift;
    my $self = new Vend::Parser;
	$self->{INVALID} = 0;
	$self->{INTERPOLATE} = shift || 0;
	$self->{WAIT_BRACKET} = 0;

	if(!$Initialized) {
print("Adding tags\n") if $Global::DEBUG;
		add_tags($Vend::Cfg->{UserTag});
#		tie $self->{OUT}, 'Vend::Response';
#	}
#	else {
#		$self->{OUT} = '';
	}

	$self->{OUT} = '';
	$Initialized = 1;
    bless $self, $class;
}

my %myRefs = (
	 Alias          => \%Alias,
	 Implicit       => \%Implicit,
	 Order          => \%Order,
	 PosNumber      => \%PosNumber,
	 PosRoutine     => \%PosRoutine,
	 Required       => \%Required,
	 Routine        => \%Routine,
	 canNest        => \%canNest,
	 hasEndTag      => \%hasEndTag,
	 isEndAnchor    => \%isEndAnchor,
	 InvalidateCache => \%InvalidateCache,
);

my %attrAlias = (
	 page          	=> { 'base' => 'arg' },
	 data          	=> { 
	 						'database' => 'table',
	 						'base' => 'table',
	 						'name' => 'field',
	 						'code' => 'key',
						},
	 'if'			=> { 
	 						'comp' => 'compare',
	 						'operator' => 'op',
	 						'base' => 'type',
						},
	 loop	          	=> { args => 'arg', },
	 lookup          	=> { 
	 						'database' => 'table',
	 						'base' => 'table',
	 						'name' => 'field',
	 						'code' => 'key',
						},
);

sub add_tags {
	return unless @_;
	my $ref = shift;
	my $area;
	no strict 'refs';
	foreach $area (keys %myRefs) {
		next unless $ref->{$area};
		if($area eq 'Routine') {
			for (keys %{$ref->{$area}}) {
				$myRefs{$area}->{$_} = $ref->{$area}->{$_};
			}
			next;
		}
		Vend::Util::copyref $ref->{$area}, $myRefs{$area};
	}
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

my %Monitor = ( qw(
					if 1
					data 1
					compat 1
					) );

sub start
{
    my($self, $tag, $attr, $attrseq, $origtext) = @_;
	$tag =~ tr/-/_/;   # canonical
	local($Global::DEBUG) = defined $Monitor{$tag} ? 1 : 0;
print("called start $tag with attributes" . @$attrseq . "\n") if $Global::DEBUG;
	my($tmpbuf);
    # $attr is reference to a HASH, $attrseq is reference to an ARRAY
	unless (defined $Routine{$tag}) {
		if(defined $Alias{$tag}) {
			my ($rest, $text);
			($tag, $rest) = split /\s+/, $Alias{$tag}, 2;
print("Calling alias, tag $tag rest $rest, orig=$origtext\n") if $Global::DEBUG;
			$text = _find_tag (\$rest, $attr, $attrseq);
			$text = " $text" if $text;
			$origtext =~ s:^(\[\S+):[$tag$text:;
		}
		else {
print("Returning text, tag $tag not found\n$origtext\n") if $Global::DEBUG;
			$self->{OUT} .= $origtext;
			return 1;
		}
	}

	if(defined $InvalidateCache{$tag}) {
		$self->{INVALID} = 1;
	}

	$attr->{interpolate} = $self->{INTERPOLATE}
		unless defined $attr->{interpolate};
#print("Start $tag: wait for $self->{WAIT_BRACKET}...") if $Global::DEBUG;

	for(@$attrseq) {
		# Attribute aliases
		if(defined $attrAlias{$tag} and $attrAlias{$tag}{$_}) {
			my $new = $attrAlias{$tag}{$_} ;
			$attr->{$new} = delete $attr->{$_};
			$_ = $new;
		}
		# Parse tags within tags, only works if the [ is the
		# first character.
print("Parsing attribute $_ $attr->{$_}\n") if $Global::DEBUG;
		next unless $attr->{$_} =~ /\[\w+[-\w]*\s+[\000-\377]+\]/;
		my $t = $_;
print("Re-parsing attribute $t $attr->{$t}\n") if $Global::DEBUG;

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
			$attr->{interpolate} = 0 if $hasEndTag{$tag} and $canNest{$tag};
			$attr->{interpolate} = 1 if defined $Interpolate{$tag};
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
print("...interpolating with end tag...") if $Global::DEBUG;
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
print("...interpolating...") if $Global::DEBUG;
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
print("...removed bracket (4)...") if $Global::DEBUG;
					$self->{WAIT_BRACKET}--;
			}
			$found++;
			push(@out, $tmpbuf);
			$more++ while ($tmpbuf =~ m!\[$tag[\]\s]!g);
print("---found=$found more=$more") if $Global::DEBUG;
			push(@out, $eaten);
			last if $found > $more;
		}
		else {
print("---eof found.") if $Global::DEBUG;
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
print("Found no match for $tag.\n") if $Global::DEBUG;
		return undef;
	}
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
			# eaten value is grown
			$old = 1;
		}
		next if $old;
		$attrhash->{$attr} = $val;
		push(@attrseq, $attr);
	}
	unshift(@$attrseq, @attrseq);
	return ($eaten);
}

sub implicit {
	my($self, $tag, $attr) = @_;
print("check tag='$tag' attr='$attr'...") if $Global::DEBUG;
	return ($attr, undef) unless defined $Implicit{$tag} and $Implicit{$tag}{$attr};
	return ( $Implicit{$tag}{$attr}, $attr );
}

1;
__END__
