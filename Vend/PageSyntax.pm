# PageSyntax.pm - check MiniVend pages for fatal errors
# 
# $Id: PageSyntax.pm,v 1.3 1996/05/25 07:06:03 mike Exp mike $
#
# Copyright 1996 by Michael J. Heins <mikeh@iac.net>
#
# $Log: PageSyntax.pm,v $
# Revision 1.3  1996/05/25 07:06:03  mike
# mv103i
#
# Revision 1.2  1996/05/18 20:02:39  mike
# Minivend 1.03 Beta 1
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

package Vend::PageSyntax;

$VERSION = substr(q$Revision: 1.3 $, 10);

eval { require HTML::Parse; import HTML::Parse; };

@EXPORT = 'check_pages';
@EXPORT_OK = 'check_pages check_form';
use Carp;
use strict;
use Vend::Data;

my(@Errors);
my(@Warnings);
my($Fatal,$Page,$Name);
my(%minElement);
my(%maxElement);
my(%columnElement);
my(%blockElement);
my(%Balancers);
my(%noEndTag);
my(%Size);

$Fatal = 0;

# Elements that have multiple end balance tags
%Balancers = (
					'pagetarget' => 'page|pagetarget',
					'page' => 'page|pagetarget',
       			);

# Elements that do not have corresponding end tags
for (qw(

accessories
area
areatarget
body
buttonbar
checked
data
field
file
finish-order
finish_order
framebase
frames-off
frames-on
frames_off
frames_on
help
item-accessories
item-code
item-description
item-data
item-field
item-increment
item-link
item-price
item-quantity
item-subtotal
item_accessories
item_code
item_description
item_data
item_field
item_increment
item_link
item_price
item_quantity
item_subtotal
matches
more
message
nitems
price
process-order
process-search
process-target
process_order
process_search
process_target
quantity-name
quantity_name
random
salestax
scratch
secure-order
secure_order
selected
shipping
shipping-desc
shipping-description
shipping_desc
shipping_description
subject
subtotal
total-cost
total_cost
value
       )
    ) {
    $noEndTag{$_} = 1;
}

# Elements that act as paragraph 
for (qw(

col
column
else
if-field
if_field
if
order-list
order_list
item-list
item_list
last-page
last_page
more-list
more_list
order
p
page
pagetarget
row
search-list
search_list
set

       )
	){
    $blockElement{$_} = 1;
	$Balancers{$_} = $_
		unless defined $Balancers{$_};
}

# Elements that have attached values, and their minimum number
%minElement = (
					'accessories' => 1,
					'area' => 1,
					'areatarget' => 2,
					'body' => 1,
					'buttonbar' => 1,
					'checked' => 1,
					'col' => 1,
					'column' => 1,
					'data' => 3,
					'file' => 1,
					'field' => 2,
					'framebase' => 1,
					'help' => 1,
					'if-field' => 1,
					'if_field' => 1,
					'if' => 2,
					'item-data' => 2,
					'item-field' => 1,
					'item-price' => 0,
					'item_data' => 2,
					'item_field' => 1,
					'item_price' => 0,
					'order' => 1,
					'page' => 1,
					'pagetarget' => 2,
					'price' => 1,
					'process-target' => 1,
					'process_target' => 1,
					'row' => 1,
					'selected' => 2,
					'value' => 1,

       			);

# Elements that have attached values, and their maximum number
%maxElement = (
					'accessories' => 1,
					'area' => 1,
					'areatarget' => 2,
					'body' => 1,
					'buttonbar' => 1,
					'checked' => 2,
					'col' => 6,
					'column' => 6,
					'data' => 3,
					'field' => 2,
					'file' => 1,
					'framebase' => 1,
					'help' => 1,
					'if-field' => 1,
					'if_field' => 1,
					'if' => 9,
					'item-data' => 2,
					'item-field' => 1,
					'item-price' => 1,
					'item_data' => 2,
					'item_field' => 1,
					'item_price' => 1,
					'order' => 2,
					'page' => 1,
					'pagetarget' => 2,
					'price' => 2,
					'process-target' => 2,
					'process_target' => 2,
					'row' => 1,
					'selected' => 2,
					'value' => 1,
       			);

# Elements that have column tags, and its position(s)
%columnElement = (
					'field' => 1,
					'if-field' => 1,
					'if_field' => 1,
					'item-field' => 1,
					'item_field' => 1,
       			);

sub check_form {
	my($max, $allow, $form) = @_;
    my $codere = '[\w-_.]+';
	my(%found);
	my ($ref);
	my (@errors);

	$Config::PageCheck = 1;

	my $f;
	$f = parse_html($form);
	$f->traverse(
	 sub {
		my($s,$start,$depth) = @_;
		my($name,$type);
		return 1 unless $start;
		my $tag = $s->{'_tag'};

		# Zero the instances error if new form
		if ($tag eq 'form') {
			for(keys %found) {
				push(@errors, "Variable $_ defined too many times")
					if $found{$_} > $$max{$_};
			}
			%found = ();
			return 1;
		}

		if($tag eq 'input') {
			$name = $s->attr('name');
			$type = $s->attr('type');
			unless (defined $name) {
				push(@errors, "Input field has no name.")
					unless $type =~ /^reset$/i;
				return 1;
			}
			return 1 unless defined $$max{$name};
			unless (defined $type or 
					(defined $$allow{$name} and
					$$allow{$name} =~ /\btext\b/i and
					$type = 'text') ) {
				push(@errors, "Input field $name has no type.");
				return 1;
			}
			$found{$name}++;
			push(@errors, "Variable $name is wrong type $type")
				unless $$allow{$name} =~ /\b$type\b/i;
			if($$allow{$name} =~ /\bfile\b/i) {
				my $value = $s->attr('value');
				push(@errors, "Input field $name must be valid page, was $value")
					unless -s "$Config::PageDir/$value.html";
			}
		}
		elsif($tag eq 'select') {
			$name = $s->attr('name');
			unless (defined $name) {
				push(@errors, "Select field has no name.");
				return 1;
			}
			push(@errors, "Variable $name defined too many times")
				if defined $found{$name};
			return 1 unless defined $$max{$name};
			$found{$name} = $$max{$name};
			if(defined $s->attr('multiple') and $s->attr('multiple')) {
				push(@errors, "Variable $name can't be MULTIPLE select field")
					unless $$allow{$name} =~ /\b(checkbox|multiselect)\b/i;
			}
			else {
				push(@errors, "Variable $name can't be select field")
					unless $$allow{$name} =~ /\b(radio|select)\b/i;
			}
			if($$allow{$name} =~ /\bfile\b/i) {
				push(@errors, "Input field $name must be valid page.")
					unless parse_valid_page($name);
			}
		}
		1;
	 }, 1);
	croak (join "\n", @errors) if scalar @errors;
	0;
}

sub check_pages {
	my($varfile,@files) = @_;
    my($codere) = '[\w-_#/.]+';
	my($page);
	my($name,$max,$type);
	my($file,$form,$junk);
	my(%max);
	my(%type);

	$Config::PageCheck = 1;

	my $checkforms = defined $INC{'HTML/Parse.pm'};
	if($checkforms) {
		$HTML::Parse::IGNORE_TEXT = 1;
		$HTML::Parse::IMPLICIT_TAGS = 0;
	}

	open (Vend::CHECKFORM, $varfile)
		or die "Couldn't open variable definitions: $!";
	while(<Vend::CHECKFORM>) {
		next if /^\s*#/;
		next unless /\S/;
		chomp;
		($name, $max, $type) = split /\s+/, $_, 3;
		$max{$name} = $max;
		$type{$name} = $type;
	}
	close Vend::CHECKFORM;

	unless(@files) {
		chdir $Config::PageDir or die "Couldn't change to PageDir: $!\n";
		@files = `find . -name '*.html' -print`;	#PORTABILITY?
		chop(@files);
		chdir $Config::VendRoot or die "Couldn't change to VendRoot: $!\n";
	}

	foreach $file (@files) {
		$file =~ s:^\./::;
		$Name = $file;
		$file =~ s/\.html$//;
		$Page = ::readin($file);
		$page = $Page;
		$page =~ s:(\[[A-Za-z][^\]]*?)\[([A-Za-z][^\]]*?)\]:
				check_inner_tag($1,$2,$'):ige;
		$page =~ s:\[([A-Za-z][^\]]*?)\]+:check_tag($1,$'):ige;
		$junk = eval { check_form(\%max,\%type,$Page); }
				if $checkforms;
		if($@) {
			push @Errors, "$Name:  $@\n";
			$Fatal++;
		}
	}

	if(@Errors) {
		unshift @Errors,   "****** Serious errors ******:\n\n";
	}

	if(@Warnings) {
		unshift @Warnings, "******     Warnings   ******:\n\n";
	}

	# One of those nice reverse status fields
	return ($Fatal, join "\n", @Errors, @Warnings );

}

sub check_column {
	my($col) = @_;
	eval {column_exists($col) };
	if($@) {
		return($@);
	}
	return '';
}

sub check_balance {
	return $_[1] =~ m:\[/$Balancers{$_[0]}\]:i ;
}

sub check_inner_tag {
	my ($enclose,$tag,$rest) = @_;
	check_tag($tag,$rest);
	return $enclose . 'c' x (length($tag) + 2);
}

sub check_tag {
	my ($tag,$rest) = @_;
	my ($error,$name,$pos);
	my (@param);

	($name,@param) = split /\s+/, $tag;

	$name = lc $name;

	if(defined $blockElement{$name}) {
		unless(check_balance($name,$rest)) {
			$pos = (length $rest) + length $tag;
			$pos = (length $Page) - $pos;
			push @Errors, "$Name:  $tag' -- no end tag, character $pos";
		}
	}
	elsif( ! defined $noEndTag{$name} ) {
		push @Warnings, "$Name:  $name'";
		return '';
	}

	if(defined $maxElement{$name}) {
		if(scalar @param > $maxElement{$name}) {
			$pos = (length $rest) + length $tag;
			$pos = (length $Page) - $pos;
			push @Errors, "$Name:  $tag' -- too many params, character $pos";
		}
		if(scalar @param < $minElement{$name}) {
			$pos = (length $rest) + length $tag;
			$pos = (length $Page) - $pos;
			push @Errors, "$Name:  $tag' -- too few params, character $pos";
		}
	}

	if(defined $columnElement{$name}) { 
		if($error = check_column(@param[$columnElement{$name} - 1])) {
			$pos = (length $rest) + length $tag;
			$pos = (length $Page) - $pos;
			push @Errors, "$Name:  $tag' at character $pos: $error";
			$Fatal++;
		}
	}
	return '';
}

sub version { $Vend::PageSyntax::VERSION }

1;
