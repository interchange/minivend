# Vend::Table::Editor - Swiss-army-knife table editor for Interchange
#
# $Id$
#
# Copyright (C) 2002 ICDEVGROUP <interchange@icdevgroup.org>
# Copyright (C) 2002 Mike Heins <mike@perusion.net>
#
# This program was originally based on Vend 0.2 and 0.3
# Copyright 1995 by Andrew M. Wilcox <amw@wilcoxsolutions.com>
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
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA.

package Vend::Table::Editor;

use vars qw($VERSION);
$VERSION = substr(q$Revision$, 10);

use Vend::Util;
use Vend::Interpolate;
use Vend::Data;

=head1 NAME

Vend::Table::Editor -- Interchange do-all HTML table editor

=head1 SYNOPSIS

[table-editor OPTIONS] 

[table-editor OPTIONS] TEMPLATE [/table-editor]

=head1 DESCRIPTION

The [table-editor] tag produces an HTML form that edits a database
table or collects values for a "wizard". It is extremely configurable
as to display and characteristics of the widgets used to collect the
input.

The widget types are based on the Interchange C<[display ...]> UserTag,
which in turn is heavily based on the ITL core C<[accessories ...]> tag.

The C<simplest> form of C<[table-editor]> is:

	[table-editor table=foo]

A page which contains only that tag will edit the table C<foo>, where
C<foo> is the name of an Interchange table to edit. If no C<foo> table
is C<defined>, then nothing will be displayed.

If the C<mv_metadata> entry "foo" is present, it is used as the
definition for table display, including the fields to edit and labels
for sections of the form. If C<ui_data_fields> is defined, this
cancels fetch of the view and any breaks and labels must be
defined with C<ui_break_before> and C<ui_break_before_label>. More
on the view concept later.

A simple "wizard" can be made with:

	[table-editor
			wizard=1
			ui_wizard_fields="foo bar"
			mv_nextpage=wizard2
			mv_prevpage=wizard_intro
			]

The purpose of a "wizard" is to collect values from the user and
place them in the $Values array. A next page value (option mv_nextpage)
must be defined to give a destination; if mv_prevpage is defined then
a "Back" button is presented to allow paging backward in the wizard.

=cut

my $Tag = new Vend::Tags;

%Vend::Interpolate::Filter_desc = (
	filesafe        => 'Safe for filename',
	currency        => 'Currency',
	mailto          => 'mailto: link',
	commify         => 'Commify',
	lookup          => 'DB lookup',
	uc              => 'Upper case',
	date_change     => 'Date widget',
	null_to_space   => 'NULL to SPACE',
	null_to_comma   => 'NULL to COMMA',
	null_to_colons  => 'NULL to ::',
	space_to_null   => 'SPACE to NULL',
	colons_to_null  => ':: to NULL',
	last_non_null   => 'Reverse combo',
	nullselect      => 'Combo box',
	tabbed          => 'Newline to TAB',
	lc              => 'Lower case',
	digits_dot      => 'Digits-dots',
	backslash       => 'Strip backslash',
	option_format   => 'Option format',
	crypt           => 'Crypt',
	namecase        => 'Name case',
	name            => 'Last&#44;First to First Last',
	digits          => 'Digits only',
	word            => 'A-Za-z_0-9',
	unix            => 'DOS to UNIX newlines',
	dos             => 'UNIX to DOS newlines',
	mac             => 'UNIX/DOS to Mac OS newlines',
	no_white        => 'No whitespace',
	strip           => 'Trim whitespace',
	sql             => 'SQL quoting',
	textarea_put    => 'Textarea PUT',
	textarea_get    => 'Textarea GET',
	text2html       => 'Simple text2html',
	urlencode       => 'URL encode',
	entities        => 'HTML entities',
);

my $F_desc = \%Vend::Interpolate::Filter_desc;

my $fdesc_sort = sub {
	return 1 if $a and ! $b;
	return -1 if ! $a and $b;
	return lc($F_desc->{$a}) cmp lc($F_desc->{$b});
};

sub expand_values {
	my $val = shift;
	return $val unless $val =~ /\[/;
	$val =~ s/\[cgi\s+([^\[]+)\]/$CGI::values{$1}/ig;
	$val =~ s/\[var\s+([^\[]+)\]/$::Variable->{$1}/ig;
	$val =~ s/\[value\s+([^\[]+)\]/$::Values->{$1}/ig;
	return $val;
}

sub filters {
	my ($exclude, $opt) = @_;
	$opt ||= {};
	my @out = map { $_ . ($F_desc->{$_} ? "=$F_desc->{$_}" : '') } 
				sort $fdesc_sort keys %Vend::Interpolate::Filter;
	if($exclude) {
		@out = grep /=/, @out;
	}
	unshift @out, "=--add--" unless $opt->{no_add};
	$opt->{joiner} = Vend::Interpolate::get_joiner($opt->{joiner}, ",\n");
	return join $opt->{joiner}, @out;
}

sub meta_record {
	my ($item, $view, $mdb) = @_;

#::logDebug("meta_record: item=$item view=$view mdb=$mdb");
	return undef unless $item;

	if(! ref ($mdb)) {
		my $mtable = $mdb || $::Variable->{UI_META_TABLE} || 'mv_metadata';
#::logDebug("meta_record mtable=$mtable");
		$mdb = database_exists_ref($mtable)
			or return undef;
	}
#::logDebug("meta_record has an item=$item and mdb=$mdb");

	my $record;

	my $mkey = $view ? "${view}::$item" : $item;

	if(ref $mdb eq 'HASH') {
		$record = $mdb;
	}
	else {
		$record = $mdb->row_hash($mkey);
	}

	$record ||= $mdb->row_hash($item) if $view;
#::logDebug("meta_record  record=$record");

	return undef if ! $record;

	# Get additional settings from extended field, which is a serialized
	# hash
	my $hash;
	if($record->{extended}) {
		## From Vend::Util
		$hash = get_option_hash($record->{extended});
		if(ref $hash eq 'HASH') {
			@$record{keys %$hash} = values %$hash;
		}
		else {
			undef $hash;
		}
	}

	# Allow view settings to be placed in the extended area
	if($view and $hash and $hash->{view}) {
		my $view_hash = $record->{view}{$view};
		ref $view_hash
			and @$record{keys %$view_hash} = values %$view_hash;
	}
#::logDebug("return meta_record=" . ::uneval($record) );
	return $record;
}

my $base_entry_value;

sub display {
	my ($table,$column,$key,$opt) = @_;

	if( ref($opt) ne 'HASH' ) {
		$opt = get_option_hash($opt);
	}

	my $template = $opt->{type} eq 'hidden' ? '' : $opt->{template};

	if($opt->{override}) {
		$opt->{value} = defined $opt->{default} ? $opt->{default} : '';
	}

	if(! defined $opt->{value} and $table and $column and length($key)) {
		$opt->{value} = tag_data($table, $column, $key);
	}

	my $mtab;
	my $record;

	my $no_meta = $CGI::values{ui_no_meta_display};

	METALOOK: {
		## No meta display wanted
		last METALOOK if $no_meta;
		## No meta display possible
		$table and $column or $opt->{meta}
			or last METALOOK;

		## We get a metarecord directly, though why it would be here
		## and not in options I don't know
		if($opt->{meta} and ref($opt->{meta}) eq 'HASH') {
			$record = $opt->{meta};
			last METALOOK;
		}

		$mtab = $opt->{meta_table} || $::Variable->{UI_META_TABLE} || 'mv_metadata'
			or last METALOOK;
		my $meta = Vend::Data::database_exists_ref($mtab)
			or do {
				::logError("non-existent meta table: %s", $mtab);
				undef $mtab;
				last METALOOK;
			};

		my $view = $opt->{view} || $opt->{arbitrary};

		## This is intended to trigger on the first access
		if($column eq $meta->config('KEY')) {
			if($view and $opt->{value} !~ /::.+::/) {
				$base_entry_value = ($opt->{value} =~ /^([^:]+)::(\w+)$/)
									? $1
									: $opt->{value};
			}
			else {
				$base_entry_value = $opt->{value} =~ /::/
									? $table
									: $opt->{value};
			}
		}

		my (@tries) = "${table}::$column";
		unshift @tries, "${table}::${column}::$key"
			if length($key)
				and $CGI::values{ui_meta_specific} || $opt->{specific};

		my $sess = $Vend::Session->{mv_metadata} || {};

		push @tries, { type => $opt->{type} }
			if $opt->{type} || $opt->{label};

		for my $metakey (@tries) {
			## In case we were passed a meta record
			last if $record = $sess->{$metakey} and ref $record;
			$record = UI::Primitive::meta_record($metakey, $view, $meta)
				and last;
		}
	}

	my $w;

	METAMAKE: {
		last METAMAKE if $no_meta;
		if( ! $record ) {
			$record = { %$opt };
		}
		else {
			## Here we allow override with the display tag, even with views and
			## extended
			my @override = qw/
								append
								attribute
								db
								extra
								field
								filter
								height
								help
								help_url
								label
								lookup
								lookup_exclude
								lookup_query
								name
								options
								outboard
								passed
								pre_filter
								prepend
								type
								width
								/;
			for(@override) {
				delete $record->{$_} if ! length($record->{$_});
				next unless defined $opt->{$_};
				$record->{$_} = $opt->{$_};
			}
		}

		$record->{name} ||= $column;
#::logDebug("record now=" . ::uneval($record));

		if($record->{options} and $record->{options} =~ /^[\w:]+$/) {
#::logDebug("checking options");
			PASS: {
				my $passed = $record->{options};

				if($passed eq 'tables') {
					my @tables = $Tag->list_databases();
					$record->{passed} = join (',', "=--none--", @tables);
				}
				elsif($passed eq 'filters') {
					$record->{passed} = filters(1);
				}
				elsif($passed =~ /^columns(::(\w*))?\s*$/) {
					my $total = $1;
					my $tname = $2 || $record->{db} || $table;
					if ($total eq '::' and $base_entry_value) {
						$tname = $base_entry_value;
					}
					$record->{passed} = join ",",
											"=--none--",
											$Tag->db_columns($tname),
										;
				}
				elsif($passed =~ /^keys(::(\w+))?\s*$/) {
					my $tname = $2 || $record->{db} || $table;
					$record->{passed} = join ",",
											"=--none--",
											$Tag->list_keys($tname),
										;
				}
			}
		}

#::logDebug("checking for custom widget");
		if ($record->{type} =~ s/^custom\s+//s) {
			my $wid = lc $record->{type};
			$wid =~ tr/-/_/;
			my $w;
			$record->{attribute} ||= $column;
			$record->{table}     ||= $mtab;
			$record->{rows}      ||= $record->{height};
			$record->{cols}      ||= $record->{width};
			$record->{field}     ||= 'options';
			$record->{name}      ||= $column;
			eval {
				$w = $Tag->$wid($record->{name}, $opt->{value}, $record, $opt);
			};
			if($@) {
				::logError("error using custom widget %s: %s", $wid, $@);
			}
			last METAMAKE;
		}

#::logDebug("formatting prepend/append");
		for(qw/append prepend/) {
			next unless $record->{$_};
			$record->{$_} = expand_values($record->{$_});
			$record->{$_} = Vend::Util::resolve_links($record->{$_});
			$record->{$_} =~ s/_UI_VALUE_/$opt->{value}/g;
			$record->{$_} =~ /_UI_URL_VALUE_/
				and do {
					my $tmp = $opt->{value};
					$tmp =~ s/(\W)/sprintf '%%%02x', ord($1)/eg;
					$record->{$_} =~ s/_UI_URL_VALUE_/$tmp/g;
				};
			$record->{$_} =~ s/_UI_TABLE_/$table/g;
			$record->{$_} =~ s/_UI_COLUMN_/$column/g;
			$record->{$_} =~ s/_UI_KEY_/$key/g;
		}

#::logDebug("overriding defaults");
#::logDebug("passed=$record->{passed}") if $record->{debug};
		my %things = (
			attribute	=> $column,
			cols	 	=> $opt->{cols}   || $record->{width},
			column	 	=> $column,
			passed	 	=> $record->{options},
			rows 		=> $opt->{rows}	|| $record->{height},
			table		=> $table,
			value		=> $opt->{value},
		);

		while( my ($k, $v) = each %things) {
			next if length $record->{$k};
			next unless defined $v;
			$record->{$k} = $v;
		}

#::logDebug("calling Vend::Form");
		$w = Vend::Form::display($record);
		if($record->{filter}) {
			$w .= qq{<INPUT TYPE=hidden NAME="ui_filter:$record->{name}" VALUE="};
			$w .= $record->{filter};
			$w .= '">';
		}
	}

#::logDebug("widget=$w");
	# don't output label if widget is hidden form variable only
	return $w if $w =~ /^\s*<input\s[^>]*type\s*=\W*hidden\b[^>]*>\s*$/i;

	if(! defined $w) {
		my $text = $opt->{value};
		my $iname = $opt->{name} || $column;

		# Count lines for textarea
		my $count;
		$count = $text =~ s/(\r\n|\r|\n)/$1/g;

		HTML::Entities::encode($text, $ESCAPE_CHARS::std);
		my $size;
		if ($count) {
			$count++;
			$count = 20 if $count > 20;
			$w = <<EOF;
	<TEXTAREA NAME="$iname" COLS=60 ROWS=$count>$text</TEXTAREA>
EOF
		}
		elsif ($text =~ /^\d+$/) {
			my $cur = length($text);
			$size = $cur > 8 ? $cur + 1 : 8;
		}
		else {
			$size = 60;
		}
			$w = <<EOF;
	<INPUT NAME="$iname" SIZE=$size VALUE="$text">
EOF
	}

	my $array_return = wantarray;

	return $w unless $template || $array_return;

	if($template and $template !~ /\s/) {
		$template = <<'EOF';
<TR>
<TD>
	<B>$LABEL$</B>
</TD>
<TD VALIGN=TOP>
	<TABLE CELLSPACING=0 CELLMARGIN=0><TR><TD>$WIDGET$</TD><TD><I>$HELP$</I>{HELP_URL}<BR><A HREF="$HELP_URL$">help</A>{/HELP_URL}</TD></TR></TABLE>
</TD>
</TR>
EOF
	}

	$record->{label} ||= $column;

	my %sub = (
		WIDGET		=> $w,
		HELP		=> $opt->{applylocale}
						? errmsg($record->{help})
						: $record->{help},
        META_URL    => $opt->{meta_url},
		HELP_URL	=> $record->{help_url},
		LABEL		=> $opt->{applylocale}
						? errmsg($record->{label})
						: $record->{label},
	);
#::logDebug("passed meta_url=$opt->{meta_url}");
      $sub{HELP_EITHER} = $sub{HELP} || $sub{HELP_URL};

	if($array_return) {
		return ($w, $sub{LABEL}, $sub{HELP}, $record->{help_url});
	}
	else {
		# Strip the {TAG} {/TAG} pairs if nothing there
		$template =~ s#{([A-Z_]+)}(.*?){/\1}#$sub{$1} ? $2: '' #ges;
		# Insert the TAG
              $sub{HELP_URL} ||= 'javascript:void(0)';
		$template =~ s/\$([A-Z_]+)\$/$sub{$1}/g;
#::logDebug("substituted template is: $template");
		return $template;
	}
}

sub tabbed_display {
	my ($tit, $cont, $opt) = @_;
	
	$opt ||= {};

	my @chars = reverse(0 .. 9, 'a' .. 'e');
	my @colors;
	$opt->{tab_bgcolor_template} ||= '#xxxxxx';
	$opt->{tab_height} ||= '30';
	$opt->{tab_width} ||= '120';
	$opt->{panel_height} ||= '600';
	$opt->{panel_width} ||= '800';
	$opt->{panel_id} ||= 'mvpan';
	$opt->{tab_horiz_offset} ||= '10';
	$opt->{tab_vert_offset} ||= '8';
	$opt->{tab_style} ||= q{
								text-align:center;
								font-family: sans-serif;
								line-height:150%;
								border:2px;
								border-color:#999999;
								border-style:outset;
								border-bottom-style:none;
							};
	$opt->{panel_style} ||= q{ 
									font-family: sans-serif;
									font-size: smaller;
									border: 2px;
									border-color:#999999;
									border-style:outset;
								};
	$opt->{layer_tab_style} ||= q{
									font-weight:bold;
									text-align:center;
									font-family:sans-serif;
									};
	$opt->{layer_panel_style} ||= q{
									font-family:sans-serif;
									padding:6px;
									};

	my $id = $opt->{panel_id};
	my $num_panels = scalar(@$cont);
	my $tabs_per_row = int( $opt->{panel_width} / $opt->{tab_width}) || 1;
	my $num_rows = POSIX::ceil( $num_panels / $opt->{tab_width});
	my $width = $opt->{panel_width};
	my $height = $opt->{tab_height} * $num_rows + $opt->{panel_height};
	my $panel_y =
		$num_rows
		* ($opt->{tab_height} - $opt->{tab_vert_offset})
		+ $opt->{tab_vert_offset};
	my $int1 = $panel_y - 2;
	my $int2 = $opt->{tab_height} * $num_rows;
	for(my $i = 0; $i < $num_panels; $i++) {
		my $c = $opt->{tab_bgcolor_template} || '#xxxxxx';
		$c =~ s/x/$chars[$i] || 'e'/eg;
		$colors[$i] = $c;
	}
	my $cArray = qq{var colors = ['} . join("','", @colors) . qq{'];};
#::logDebug("num rows=$num_rows");
	my $out = <<EOF;
<SCRIPT language="JavaScript">
<!--
var panelID = "$id"
var numDiv = $num_panels;
var numRows = $num_rows;
var tabsPerRow = $tabs_per_row;
var numLocations = numRows * tabsPerRow
var tabWidth = $opt->{tab_width}
var tabHeight = $opt->{tab_height}
var vOffset = $opt->{tab_vert_offset};
var hOffset = $opt->{tab_horiz_offset};
$cArray

var divLocation = new Array(numLocations)
var newLocation = new Array(numLocations)
for(var i=0; i<numLocations; ++i) {
	divLocation[i] = i
	newLocation[i] = i
}

function getDiv(s,i) {
	var div
	if (document.layers) {
		div = document.layers[panelID].layers[panelID+s+i]
	} else if (document.all && !document.getElementById) {
		div = document.all[panelID+s+i]
	} else {
		div = document.getElementById(panelID+s+i)
	}
	return div
}

function setZIndex(div, zIndex) {
	if (document.layers) div.style = div;
	div.style.zIndex = zIndex
}

function updatePosition(div, newPos) {
	newClip=tabHeight*(Math.floor(newPos/tabsPerRow)+1)
	if (document.layers) {
		div.style=div;
		div.clip.bottom=newClip; // clip off bottom
	} else {
		div.style.clip="rect(0 auto "+newClip+" 0)"
	}
	div.style.top = (numRows-(Math.floor(newPos/tabsPerRow) + 1)) * (tabHeight-vOffset)
	div.style.left = (newPos % tabsPerRow) * tabWidth +	(hOffset * (Math.floor(newPos / tabsPerRow)))
}

function selectTab(n) {
	// n is the ID of the division that was clicked
	// firstTab is the location of the first tab in the selected row
	var firstTab = Math.floor(divLocation[n] / tabsPerRow) * tabsPerRow
	// newLoc is its new location
	for(var i=0; i<numDiv; ++i) {
		// loc is the current location of the tab
		var loc = divLocation[i]
		// If in the selected row
		if(loc >= firstTab && loc < (firstTab + tabsPerRow)) newLocation[i] = (loc - firstTab)
		else if(loc < tabsPerRow) newLocation[i] = firstTab+(loc % tabsPerRow)
		else newLocation[i] = loc
	}
	// Set tab positions & zIndex
	// Update location
	var j = 1;
	for(var i=0; i<numDiv; ++i) {
		var loc = newLocation[i]
		var div = getDiv("panel",i)
		var tdiv = getDiv("tab",i)
		if(i == n) {
			setZIndex(div, numLocations +1);
			div.style.display = 'block';
			tdiv.style.backgroundColor = colors[0];
			div.style.backgroundColor = colors[0];
		}
		else {
			setZIndex(div, numLocations - loc)
			div.style.display = 'none';
			tdiv.style.backgroundColor = colors[j];
			div.style.backgroundColor = colors[j++];
		}
		divLocation[i] = loc
		updatePosition(tdiv, loc)
		if(i == n) setZIndex(tdiv, numLocations +1)
		else setZIndex(tdiv,numLocations - loc)
	}
}

// Nav4: position component into a table
function positionPanel() {
	document.$id.top=document.panelLocator.pageY;
	document.$id.left=document.panelLocator.pageX;
}
if (document.layers) window.onload=positionPanel;

//-->
</SCRIPT>
<STYLE type="text/css">
<!--
.${id}tab {
	font-weight: bold;
	width:$opt->{tab_width}px;
	margin:0px;
	height: ${int2}px;
	position:absolute;
	$opt->{tab_style}
	}

.${id}panel {
	position:absolute;
	width: $opt->{panel_width}px;
	height: $opt->{panel_height}px;
	left:0px;
	top:${int1}px;
	margin:0px;
	padding:6px;
	$opt->{panel_style}
	}
-->
</STYLE>
EOF
	my $s1 = '';
	my $s2 = '';
	for(my $i = 0; $i < $num_panels; $i++) {
		my $zi = $num_panels - $i;
		my $pnum = $i + 1;
		my $left = (($i % $tabs_per_row)
					* $opt->{tab_width}
					+ ($opt->{tab_horiz_offset}
					* (int($i / $tabs_per_row))));
		my $top = ( $num_rows - (int($i / $tabs_per_row) + 1))
					- ($opt->{tab_height} - $opt->{tab_vert_offset});
		my $cliprect = $opt->{tab_height} * (int($i / $tabs_per_row) + 1);
		$s1 .= <<EOF;
<DIV id="${id}panel$i"
		class="${id}panel"
		style="
			background-color: $c; 
			z-index:$zi
		">
$opt->{panel_prepend}
$cont->[$i]
$opt->{panel_append}
</DIV>
<DIV
	onclick="selectTab($i)"
	id="${id}tab$i"
	class="${id}tab"
	style="
		background-color: $c; 
		cursor: pointer;
		left: ${left}px;
		top: ${top}px;
		z-index:$zi;
		clip:rect(0 auto $cliprect 0);
		">
$tit->[$i]
</DIV>
EOF
		my $lheight = $opt->{tab_height} * $num_rows;
		my $ltop = $num_rows * ($opt->{tab_height} - $opt->{tab_vert_offset})
					+ $opt->{tab_vert_offset} - 2;
		$s2 .= <<EOF;
<LAYER
	bgcolor="$c"
	style="$opt->{layer_tab_style}"
	width="$opt->{tab_width}"
	height="$lheight"
	left="$left"
	top="$top"
	z-index="$zi"
	id="${id}tab$i"
	onfocus="selectTab($i)"
	>
<table width="100%" cellpadding=2 cellspacing=0>
$tit->[$i]
</LAYER>
<LAYER
	bgcolor="$c"
	style="$opt->{layer_panel_style}"
	width="$opt->{panel_width}"
	height="$opt->{panel_height}"
	left="0"
	top="$ltop"
	z-index="$zi"
	id="${id}panel$i"
	>$cont->[$i]
</LAYER>
EOF
	}
	return <<EOF;
$out
<div style="
		position: relative;
		left: 0; top: 0; width=100%; height=100%;
		z-index: 0;
	">
$s1
<script>
	selectTab(0);
</script>
</div>
EOF
}

my $tcount_all;
my %alias;
my %exclude;
my %outhash;
my @titles;
my @controls;
my $ctl_index = 0;
my @out;

sub ttag {
	return 'TABLE_STD' . ++$tcount_all;
}

sub add_exclude {
	my ($tag, $string) = @_;
	$exclude{$tag} ||= ' ';
	$exclude{$tag} .= "$string ";
}

sub col_chunk {
	my $value = pop @_;
	my $tag = shift @_;
	my $exclude = shift @_;
	my @others = @_;

	$tag = "COLUMN_$tag";

#::logDebug("$tag content length=" . length($value));

	die "duplicate tag settor $tag" if exists $outhash{$tag};
	$outhash{$tag} = $value;

	if(@others) {
		$alias{$tag} ||= [];
		push @{$alias{$tag}}, @others;
	}

	my $ctl = $controls[$ctl_index] ||= [];
	add_exclude($tag, $exclude) if $exclude;

	return unless length($value);

	push @$ctl, $tag;
	return;
}

sub chunk_alias {
	my $tag = shift;
	$alias{$tag} ||= [];
	push @{$alias{$tag}}, @_;
	return;
}

sub chunk {
	my $value = pop @_;
	my $tag = shift @_;
	my $exclude = shift @_;
	my @others = @_;

	die "duplicate tag settor $tag" if exists $outhash{$tag};
	$outhash{$tag} = $value;

#::logDebug("$tag content length=" . length($value));

	if(@others) {
		$alias{$tag} ||= [];
		push @{$alias{$tag}}, @others;
	}

	add_exclude($tag, $exclude) if $exclude;

	return unless length($value);
	push @out, $tag;
}

sub resolve_exclude {
	my $exc = shift;
	while(my ($k, $v) = each %exclude) {
#::logDebug("examining $k for $v");
		while ($v =~ m{(\S+)}g) {
			my $thing = $1;
			if($thing =~ s/^[^A-Z]//) {
				$outhash{$k} = '' unless $exc->{$thing};
			}
			else {
				$outhash{$k} = '' if $exc->{$thing};
			}
		}
	}
}

sub editor_init {
	undef $base_entry_value;

	## Why?
	Vend::Interpolate::init_calc() if ! $Vend::Calc_initialized;
	@out = ();
	@controls = ();
	@titles = ();
	%outhash = ();
	%alias = ();
	$tab_number = $tcount_all = 0;
}

sub editor {

	my ($table, $key, $opt, $template) = @_;
show_times("begin table editor call item_id=$key") if $Global::ShowTimes;

	use vars qw/$Tag/;

	if(ref($opt->{all_opts}) eq 'HASH') {
		my $o = $opt->{all_opts};
		for (keys %$o ) {
			$opt->{$_} = $o->{$_};
		}
	}
	elsif ($opt->{all_opts}) {
		logError("%s: improper option %s, must be %s, was %s.",
					'table_editor',
					'all_opts',
					'hash',
					ref $opt->{all_opts},
					);
	}
#Debug("options now=" . ::uneval($opt));

	my @messages;
	my @errors;

	$table = $CGI->{mv_data_table}
		if ! $table and $opt->{cgi} and $CGI->{mv_data_table};

	### Need cleanup. Probably should bring in, along with
	### display tag.
	my $tmeta = meta_record($table, $opt->{ui_meta_view}) || {};

	FORMATS: {
		no strict 'refs';
		my $ref;
		for(qw/
					default     
					error       
					extra       
					filter      
					height      
					help        
					label       
					override    
					passed      
					options      
					outboard
					append
					prepend
					lookup
					lookup_query
					field
					pre_filter  
					left_width
					widget      
					width       
					meta       
				/ )
		{
			next if ref $opt->{$_};
			($opt->{$_} = {}, next) if ! $opt->{$_};
			my $ref = {};
			my $string = $opt->{$_};
			$string =~ s/^\s+//gm;
			$string =~ s/\s+$//gm;
			while($string =~ m/^(.+?)=\s*(.+)/mg) {
				$ref->{$1} = $2;
			}
			$opt->{$_} = $ref;
		}
	}

	my $rowcount = 0;
	my $action = $opt->{action} || 'set';
	my $wizard_next   = $opt->{wizard_next}   || 'return';
	my $wizard_cancel = $opt->{wizard_cancel} || 'back';
	my $rowdiv = $opt->{across} || 1;
	my $span = $rowdiv * 2;
	my $oddspan = $span - 1;
	my $def = $opt->{default_ref} || $::Values;

	my $check       = $opt->{check};
	my $default     = $opt->{default};
	my $error       = $opt->{error};
	my $extra       = $opt->{extra};
	my $filter      = $opt->{filter};
	my $height      = $opt->{height};
	my $help        = $opt->{help};
	my $help_url    = $opt->{help_url};
	my $label       = $opt->{label};
	my $override    = $opt->{override};
	my $pre_filter  = $opt->{pre_filter};
	my $passed      = $opt->{passed};
	my $options     = $opt->{options};
	my $outboard    = $opt->{outboard};
	my $prepend     = $opt->{prepend};
	my $append      = $opt->{append};
	my $lookup      = $opt->{lookup};
	my $lookup_query = $opt->{lookup_query};
	my $database    = $opt->{database};
	my $field       = $opt->{field};
	my $widget      = $opt->{widget};
	my $width       = $opt->{width};
	my $pmeta       = $opt->{meta};


	#my $blabel      = $opt->{begin_label} || '<b>';
	#my $elabel      = $opt->{end_label} || '</b>';
	my $blabel      ;
	my $elabel      ;
	my $mlabel = '';

	if($opt->{wizard}) {
		$opt->{noexport} = 1;
		$opt->{next_text} = 'Next -->' unless $opt->{next_text};
		$opt->{cancel_text} = 'Cancel' unless $opt->{cancel_text};
		$opt->{back_text} = '<-- Back' unless $opt->{back_text};
	}
	else {
		$opt->{cancel_text} = 'Cancel' unless $opt->{cancel_text};
		$opt->{next_text} = "Ok" unless $opt->{next_text};
	}

	for(qw/ next_text cancel_text back_text/ ) {
		$opt->{$_} = errmsg($opt->{$_});
	}

	my $ntext;
	my $btext;
	my $ctext;
	unless ($opt->{wizard} || $opt->{nosave}) {
		$::Scratch->{$opt->{next_text}} = $Tag->return_to('click', 1);
	}
	else {
		if($opt->{action_click}) {
			$ntext = <<EOF;
mv_todo=$wizard_next
ui_wizard_action=Next
mv_click=$opt->{action_click}
EOF
		}
		else {
			$ntext = <<EOF;
mv_todo=$wizard_next
ui_wizard_action=Next
mv_click=ui_override_next
EOF
		}
		$::Scratch->{$opt->{next_text}} = $ntext;

		my $hidgo = $opt->{mv_cancelpage} || $opt->{hidden}{ui_return_to} || $CGI->{return_to};
		$hidgo =~ s/\0.*//s;
		$ctext = $::Scratch->{$opt->{cancel_text}} = <<EOF;
mv_form_profile=
ui_wizard_action=Cancel
mv_nextpage=$hidgo
mv_todo=$wizard_cancel
EOF
		if($opt->{mv_prevpage}) {
			$btext = $::Scratch->{$opt->{back_text}} = <<EOF;
mv_form_profile=
ui_wizard_action=Back
mv_nextpage=$opt->{mv_prevpage}
mv_todo=$wizard_next
EOF
		}
		else {
			delete $opt->{back_text};
		}
	}

	for(qw/next_text back_text cancel_text/) {
		$opt->{"orig_$_"} = $opt->{$_};
	}

	$::Scratch->{$opt->{next_text}}   = $ntext if $ntext;
	$::Scratch->{$opt->{cancel_text}} = $ctext if $ctext;
	$::Scratch->{$opt->{back_text}}   = $btext if $btext;

	$opt->{next_text} = HTML::Entities::encode($opt->{next_text}, $ESCAPE_CHARS::std);
	$opt->{back_text} = HTML::Entities::encode($opt->{back_text}, $ESCAPE_CHARS::std);
	$opt->{cancel_text} = HTML::Entities::encode($opt->{cancel_text});

	$::Scratch->{$opt->{next_text}}   = $ntext if $ntext;
	$::Scratch->{$opt->{cancel_text}} = $ctext if $ctext;
	$::Scratch->{$opt->{back_text}}   = $btext if $btext;

	if($opt->{wizard} || $opt->{notable} and ! $table) {
		$table = 'mv_null';
		$Vend::Database{mv_null} = 
			bless [
					{},
					undef,
					[ 'code', 'value' ],
					[ 'code' => 0, 'value' => 1 ],
					0,
					{ },
					], 'Vend::Table::InMemory';
	}

	my @mapdirect = qw/
		mv_data_decode
		mv_data_table
		mv_blob_field
		mv_blob_nick
		mv_blob_pointer
		mv_blob_label
		mv_blob_title
		left_width
		table_width
		tabbed
		tab_bgcolor_template
		tab_height
		tab_width
		tab_cellspacing
		tab_cellpadding
		panel_height
		panel_width
		panel_id
		tab_horiz_offset
		tab_vert_offset
		ui_break_before
		ui_break_before_label
		ui_data_fields
		ui_data_fields_all
		ui_data_key_name
		ui_display_only
		ui_hide_key
		ui_meta_specific
		ui_meta_view
		ui_nextpage
		ui_new_item
		ui_delete_box
		mv_update_empty
	/;

	for(grep defined $tmeta->{$_}, @mapdirect) {
		$opt->{$_} ||= $tmeta->{$_};
	}

	if($opt->{cgi}) {
		unshift @mapdirect, qw/
				item_id
				item_id_left
				ui_clone_id
				ui_clone_tables
				ui_sequence_edit
		/;
		for(@mapdirect) {
			next if ! defined $CGI->{$_};
			$opt->{$_} = $CGI->{$_};
		}
		my @hmap = (
			[ qr/^ui_te_check:/, $check ],
			[ qr/^ui_te_default:/, $default ],
			[ qr/^ui_te_extra:/, $extra ],
			[ qr/^ui_te_widget:/, $widget ],
			[ qr/^ui_te_passed:/, $passed ],
			[ qr/^ui_te_options:/, $options ],
			[ qr/^ui_te_outboard:/, $outboard ],
			[ qr/^ui_te_prepend:/, $prepend ],
			[ qr/^ui_te_append:/, $append ],
			[ qr/^ui_te_lookup:/, $lookup ],
			[ qr/^ui_te_database:/, $database ],
			[ qr/^ui_te_field:/, $field ],
			[ qr/^ui_te_override:/, $override ],
			[ qr/^ui_te_filter:/, $filter ],
			[ qr/^ui_te_pre_filter:/, $pre_filter ],
			[ qr/^ui_te_height:/, $height ],
			[ qr/^ui_te_width:/, $width ],
			[ qr/^ui_te_help:/, $help ],
			[ qr/^ui_te_help_url:/, $help_url ],
		);
		my @cgi = keys %{$CGI};
		foreach my $row (@hmap) {
			my @keys = grep $_ =~ $row->[0], @cgi;
			for(@keys) {
				/^ui_\w+:(\S+)/
					and $row->[1]->{$1} = $CGI->{$_};
			}
		}
		$table = $opt->{mv_data_table};
		$key = $opt->{item_id};
	}

	$opt->{table_width} = '60%' if ! $opt->{table_width};
	$opt->{left_width}  = '30%' if ! $opt->{left_width};
	if (! $opt->{inner_table_width}) {
		if($opt->{table_width} =~ /%/) {
			$opt->{inner_table_width} = '100%';
		}
		elsif ($opt->{table_width} =~ /^\d+$/) {
			$opt->{inner_table_width} = $opt->{table_width} - 2;
		}
		else {
			$opt->{inner_table_width} = $opt->{table_width};
		}
	}

	$opt->{color_success} = $::Variable->{UI_C_SUCCESS} || '#00FF00'
		if ! $opt->{color_success};
	$opt->{color_fail} = $::Variable->{UI_CONTRAST} || '#FF0000'
		if ! $opt->{color_fail};
	### Build the error checking
	my $error_show_var = 1;
	my $have_errors;
	if($opt->{ui_profile} or $check) {
		$Tag->error( { all => 1 } )
			unless $CGI->{mv_form_profile} or $opt->{keep_errors};
		my $prof = $opt->{ui_profile} || '';
		if ($prof =~ s/^\*//) {
			# special notation ui_profile="*whatever" means
			# use automatic checklist-related profile
			my $name = $prof;
			$prof = $::Scratch->{"profile_$name"} || '';
			if ($prof) {
				$prof =~ s/^\s*(\w+)[\s=]+required\b/$1=mandatory/mg;
				for (grep /\S/, split /\n/, $prof) {
					if (/^\s*(\w+)\s*=(.+)$/) {
						my $k = $1; my $v = $2;
						$v =~ s/\s+$//;
						$v =~ s/^\s+//;
						$error->{$k} = 1;
						$error_show_var = 0 if $v =~ /\S /;
					}
				}
				$prof = '&calc delete $Values->{step_'
					  . $name
					  . "}; return 1\n"
					  . $prof;
				$opt->{ui_profile_success} = "&set=step_$name 1";
			}
		}
		my $success = $opt->{ui_profile_success};
		# make sure profile so far ends with a newline so we can add more
		$prof .= "\n" unless $prof =~ /\n\s*\z/;
		if(ref $check) {
			while ( my($k, $v) = each %$check ) {
				$error->{$k} = 1;
				$v =~ s/\s+$//;
				$v =~ s/^\s+//;
				$v =~ s/\s+$//mg;
				$v =~ s/^\s+//mg;
				$v =~ s/^required\b/mandatory/mg;
				unless ($v =~ /^\&/m) {
					$error_show_var = 0 if $v =~ /\S /;
					$v =~ s/^/$k=/mg;
					$v =~ s/\n/\n&and\n/g;
				}
				$prof .= "$v\n";
			}
		}
		elsif ($check) {
			for (@_ = grep /\S/, split /[\s,]+/, $check) {
				$error->{$_} = 1;
				$prof .= "$_=mandatory\n";
			}
		}
		$opt->{hidden} = {} if ! $opt->{hidden};
		$opt->{hidden}{mv_form_profile} = 'ui_profile';
		my $fail = $opt->{mv_failpage} || $Global::Variable->{MV_PAGE};

		# watch out for early interpolation here!
		$::Scratch->{ui_profile} = <<EOF;
[perl]
#Debug("cancel='$opt->{orig_cancel_text}' back='$opt->{orig_back_text}' click=\$CGI->{mv_click}");
	my \@clicks = split /\\0/, \$CGI->{mv_click};
	
	for( qq{$opt->{orig_cancel_text}}, qq{$opt->{orig_back_text}}) {
#Debug("compare is '\$_'");
		next unless \$_;
		my \$cancel = \$_;
		for(\@clicks) {
#Debug("click is '\$_'");
			return if \$_ eq \$cancel; 
		}
	}
	# the following should already be interpolated by the table-editor tag
	# before going into scratch ui_profile
	return <<'EOP';
$prof
&fail=$fail
&fatal=1
$success
mv_form_profile=mandatory
&set=mv_todo $action
EOP
[/perl]
EOF
		$blabel = '<span style="font-weight: normal">';
		$elabel = '</span>';
		$mlabel = ($opt->{message_label} || '&nbsp;&nbsp;&nbsp;<B>Bold</B> fields are required');
		$have_errors = $Tag->error( {
									all => 1,
									show_var => $error_show_var,
									show_error => 1,
									joiner => '<BR>',
									keep => 1}
									);
		if($opt->{all_errors}) {
			if($have_errors) {
				$mlabel .= '<P>Errors:';
				$mlabel .= qq{<FONT COLOR="$opt->{color_fail}">};
				$mlabel .= "<BLOCKQUOTE>$have_errors</BLOCKQUOTE></FONT>";
			}
		}
	}
	### end build of error checking

	$opt->{clear_image} = "bg.gif" if ! $opt->{clear_image};

	my $die = sub {
		::logError(@_);
		$::Scratch->{ui_error} .= "<BR>\n" if $::Scratch->{ui_error};
		$::Scratch->{ui_error} .= ::errmsg(@_);
		return undef;
	};

	my $db;
	unless($opt->{notable}) {
		$db = Vend::Data::database_exists_ref($table)
		or return $die->('table-editor: bad table %s', $table);
	}

	if($opt->{ui_wizard_fields}) {
		$opt->{ui_data_fields} = $opt->{ui_display_only} = $opt->{ui_wizard_fields};
	}

	my $keycol;
	if($opt->{notable}) {
		$keycol = $opt->{ui_data_key_name};
	}
	else {
		$keycol = $opt->{ui_data_key_name} || $db->config('KEY');
	}

	$opt->{form_extra} =~ s/^\s*/ /
		if $opt->{form_extra};

	$opt->{form_name} = qq{ NAME="$opt->{form_name}"}
		if $opt->{form_name};

	###############################################################
	# Get the field display information including breaks and labels
	###############################################################
	if( ! $opt->{ui_data_fields} and ! $opt->{ui_data_fields_all}) {
		$opt->{ui_data_fields} = $tmeta->{ui_data_fields} || $tmeta->{options};
	}

	$opt->{ui_data_fields} =~ s/\r\n/\n/g;
	$opt->{ui_data_fields} =~ s/\r/\n/g;

	if($opt->{ui_data_fields} =~ /\n\n/) {
		my @breaks;
		my @break_labels;
		my $fstring = "\n\n$opt->{ui_data_fields}";
		while ($fstring =~ s/\n+(?:\n[ \t]*=(.*))?\n+[ \t]*(\w[:.\w]+)/\n$2/) {
			push @breaks, $2;
			push @break_labels, "$2=$1" if $1;
		}
		$opt->{ui_break_before} = join(" ", @breaks)
			if ! $opt->{ui_break_before};
		$opt->{ui_break_before_label} = join(",", @break_labels)
			if ! $opt->{ui_break_before_label};
	}

	$opt->{ui_data_fields} ||= $opt->{mv_data_fields};

	if(! $opt->{ui_data_fields}) {
		if( $opt->{notable}) {
			::logError("table_editor: no place to get fields!");
			return '';
		}
		else {
			$opt->{ui_data_fields} = join " ", $db->columns();
		}
	}

	$opt->{ui_data_fields} =~ s/[,\0\s]+/ /g;
	###############################################################

	my $linecount;

	CANONCOLS: {
		my @cols = split /[,\0\s]/, $opt->{ui_data_fields};
		#@cols = grep /:/ || $db->column_exists($_), @cols;

		$opt->{ui_data_fields} = join " ", @cols;

		$linecount = scalar @cols;
	}

	my $url = $Tag->area('ui');

	my $key_message;
	if($opt->{ui_new_item} and ! $opt->{notable}) {
		if( ! $db->config('_Auto_number') ) {
			$db->config('AUTO_NUMBER', '000001');
			$key = $db->autonumber($key);
		}
		else {
			$key = '';
			$opt->{mv_data_auto_number} = 1;
			$key_message = errmsg('(new key will be assigned if left blank)');
		}
	}

	my $data;
	my $exists;

	if($opt->{notable}) {
		$data = {};
	}
	elsif($opt->{ui_clone_id} and $db->record_exists($opt->{ui_clone_id})) {
		$data = $db->row_hash($opt->{ui_clone_id})
			or
			return $die->('table-editor: row_hash function failed for %s.', $key);
		$data->{$keycol} = $key;
	}
	elsif ($db->record_exists($key)) {
		$data = $db->row_hash($key);
		$exists = 1;
	}

	if ($opt->{reload} and $have_errors) {
		if($data) {
			for(keys %$data) {
				$data->{$_} = $CGI->{$_}
					if defined $CGI->{$_};
			}
		}
		else {
			$data = { %$CGI };
		}
	}


	my $blob_data;
	my $blob_widget;
	if($opt->{mailto} and $opt->{mv_blob_field}) {
		$opt->{hidden}{mv_blob_only} = 1;
		$opt->{hidden}{mv_blob_nick}
			= $opt->{mv_blob_nick}
			|| POSIX::strftime("%Y%m%d%H%M%S", localtime());
	}
	elsif($opt->{mv_blob_field}) {
#::logDebug("checking blob");

		my $blob_pointer;
		$blob_pointer = $data->{$opt->{mv_blob_pointer}}
			if $opt->{mv_blob_pointer};
		$blob_pointer ||= $opt->{mv_blob_nick};
			

		DOBLOB: {

			unless ( $db->column_exists($opt->{mv_blob_field}) ) {
				push @errors, ::errmsg(
									"blob field %s not in database.",
									$opt->{mv_blob_field},
								);
				last DOBLOB;
			}

			my $bstring = $data->{$opt->{mv_blob_field}};

#::logDebug("blob: bstring=$bstring");

			my $blob;

			if(length $bstring) {
				$blob = $Vend::Interpolate::safe_safe->reval($bstring);
				if($@) {
					push @errors, ::errmsg("error reading blob data: %s", $@);
					last DOBLOB;
				}
#::logDebug("blob evals to " . ::uneval_it($blob));

				if(ref($blob) !~ /HASH/) {
					push @errors, ::errmsg("blob data not a storage book.");
					undef $blob;
				}
			}
			else {
				$blob = {};
			}
			my %wid_data;
			my %url_data;
			my @labels = keys %$blob;
			for my $key (@labels) {
				my $ref = $blob->{$_};
				my $lab = $ref->{$opt->{mv_blob_label} || 'name'};
				if($lab) {
					$lab =~ s/,/&#44/g;
					$wid_data{$lab} = "$key=$key - $lab";
					$url_data{$lab} = $Tag->page( {
											href => $Global::Variable->{MV_PAGE},
											form => "
												item_id=$opt->{item_id}
												mv_blob_nick=$key
											",
										});
					$url_data{$lab} .= "$key - $lab</A>";
				}
				else {
					$wid_data{$key} = $key;
					$url_data{$key} = $Tag->page( {
											href => $Global::Variable->{MV_PAGE},
											form => "
												item_id=$opt->{item_id}
												mv_blob_nick=$key
											",
										});
					$url_data{$key} .= "$key</A>";
				}
			}
#::logDebug("wid_data is " . ::uneval_it(\%wid_data));
			$opt->{mv_blob_title} = "Stored settings"
				if ! $opt->{mv_blob_title};
			$opt->{mv_blob_title} = errmsg($opt->{mv_blob_title});

			$::Scratch->{Load} = <<EOF;
[return-to type=click stack=1 page="$Global::Variable->{MV_PAGE}"]
ui_nextpage=
[perl]Log("tried to go to $Global::Variable->{MV_PAGE}"); return[/perl]
mv_todo=back
EOF
#::logDebug("blob_pointer=$blob_pointer blob_nick=$opt->{mv_blob_nick}");

			my $loaded_from;
			my $lfrom_msg;
			if( $opt->{mv_blob_nick} ) {
				$lfrom_msg = $opt->{mv_blob_nick};
			}
			else {
				$lfrom_msg = errmsg("current values");
			}
			$lfrom_msg = errmsg("loaded from %s", $lfrom_msg);
			$loaded_from = <<EOF;
<I>($lfrom_msg)</I><BR>
EOF
			if(@labels) {
				$loaded_from .= errmsg("Load from") . ":<BLOCKQUOTE>";
				$loaded_from .=  join (" ", @url_data{ sort keys %url_data });
				$loaded_from .= "</BLOCKQUOTE>";
			}

			my $checked;
			my $set;
			if( $opt->{mv_blob_only} and $opt->{mv_blob_nick}) {
				$checked = ' CHECKED';
				$set 	 = $opt->{mv_blob_nick};
			}

			unless ($opt->{nosave}) {
				$blob_widget = $Tag->widget({
									name => 'mv_blob_nick',
									type => $opt->{ui_blob_widget} || 'combo',
									filter => 'nullselect',
									override => 1,
									set => "$set",
									passed => join (",", @wid_data{ sort keys %wid_data }) || 'default',
									});
				my $msg1 = errmsg('Save to');
				my $msg2 = errmsg('Save here only');
				for (\$msg1, \$msg2) {
					$$_ =~ s/ /&nbsp;/g;
				}
				$blob_widget = <<EOF unless $opt->{ui_blob_hidden};
<B>$msg1:</B> $blob_widget&nbsp;
<INPUT TYPE=checkbox NAME=mv_blob_only VALUE=1$checked>&nbsp;$msg2</SMALL>
EOF
			}

			$blob_widget = <<EOF unless $opt->{ui_blob_hidden};
<TR class=rnorm>
	 <td class=clabel width="$opt->{left_width}">
	   <SMALL>$opt->{mv_blob_title}<BR>
		$loaded_from
	 </td>
	 <td class=cwidget>
	 	$blob_widget&nbsp;
	 </td>
</TR>

<tr class=rtitle>
<td colspan=$span><img src="$opt->{clear_image}" width=1 height=3 alt=x></td>
</tr>
EOF

		if($opt->{mv_blob_nick}) {
			my @keys = split /::/, $opt->{mv_blob_nick};
			my $ref = $blob->{shift @keys};
			for(@keys) {
				my $prior = $ref;
				undef $ref;
				eval {
					$ref = $prior->{$_};
				};
				last DOBLOB unless ref $ref;
			}
			for(keys %$ref) {
				$data->{$_} = $ref->{$_};
			}
		}

		}
	}

#::logDebug("data is: " . ::uneval($data));
	$data = { $keycol => $key }
		if ! $data;

	if(! $opt->{mv_data_function}) {
		$opt->{mv_data_function} = $exists ? 'update' : 'insert';
	}

	$opt->{mv_nextpage} = $Global::Variable->{MV_PAGE} if ! $opt->{mv_nextpage};
	$opt->{mv_update_empty} = 1 unless defined $opt->{mv_update_empty};

	my $url_base = $opt->{secure} ? $Vend::Cfg->{SecureURL} : $Vend::Cfg->{VendURL};

	$opt->{href} = "$url_base/ui" if ! $opt->{href};
	$opt->{href} = "$url_base/$opt->{href}"
		if $opt->{href} !~ m{^(https?:|)/};

	my $sidstr;
	if ($opt->{get}) {
		$opt->{method} = 'GET';
		$sidstr = '';
	} else {
		$opt->{method} = 'POST';
		$sidstr = qq{<INPUT TYPE=hidden NAME=mv_session_id VALUE="$Vend::Session->{id}">
};
	}
	$opt->{enctype} = $opt->{file_upload} ? ' ENCTYPE="multipart/form-data"' : '';

	my $wo = $opt->{widgets_only};

	my $restrict_begin;
	my $restrict_end;
	if($opt->{reparse} and ! $opt->{promiscuous}) {
		$restrict_begin = qq{[restrict allow="$opt->{restrict_allow}"]};
		$restrict_end = '[/restrict]';
	}

	no strict 'subs';

	chunk 'FORM_BEGIN', 'WO', 'TOP_PORTION', <<EOF; # unless $wo;
$restrict_begin<FORM METHOD=$opt->{method} ACTION="$opt->{href}"$opt->{form_name}$opt->{enctype}$opt->{form_extra}>
$sidstr<INPUT TYPE=hidden NAME=mv_todo VALUE="$action">
<INPUT TYPE=hidden NAME=mv_click VALUE="process_filter">
<INPUT TYPE=hidden NAME=mv_nextpage VALUE="$opt->{mv_nextpage}">
<INPUT TYPE=hidden NAME=mv_data_table VALUE="$table">
<INPUT TYPE=hidden NAME=mv_data_key VALUE="$keycol">
EOF

	my @opt_set = (qw/
						ui_meta_specific
						ui_hide_key
						ui_meta_view
						ui_data_decode
						mv_blob_field
						mv_blob_label
						mv_blob_title
						mv_blob_pointer
						mv_update_empty
						mv_data_auto_number
						mv_data_function
				/ );

	my @cgi_set = ( qw/
						item_id_left
						ui_sequence_edit
					/ );

	push(@opt_set, splice(@cgi_set, 0)) if $opt->{cgi};

  OPTSET: {
  	my @o;
	for(@opt_set) {
		next unless length $opt->{$_};
		my $val = $opt->{$_};
		$val =~ s/"/&quot;/g;
		push @o, qq{<INPUT TYPE=hidden NAME=$_ VALUE="$val">\n}; # unless $wo;
	}
	chunk 'HIDDEN_OPT', '', 'TOP_PORTION', join("", @o);
  }

  CGISET: {
	my @o;
	for (@cgi_set) {
		next unless length $CGI->{$_};
		my $val = $CGI->{$_};
		$val =~ s/"/&quot;/g;
		push @o, qq{<INPUT TYPE=hidden NAME=$_ VALUE="$val">\n}; # unless $wo;
	}
	chunk 'HIDDEN_CGI', join("", @o);
  }

	if($opt->{mailto}) {
		$opt->{mailto} =~ s/\s+/ /g;
		$::Scratch->{mv_email_enable} = $opt->{mailto};
		$opt->{hidden}{mv_data_email} = 1;
	}

	$Vend::Session->{ui_return_stack} ||= [];

	if($opt->{cgi}) {
		my $r_ary = $Vend::Session->{ui_return_stack};

#::logDebug("ready to maybe push/pop return-to from stack, stack = " . ::uneval($r_ary));
		if($CGI::values{ui_return_stack}++) {
			push @$r_ary, $CGI::values{ui_return_to};
			$CGI::values{ui_return_to} = $r_ary->[0];
		}
		elsif ($CGI::values{ui_return_to}) {
			@$r_ary = ( $CGI::values{ui_return_to} ); 
		}
		chunk 'RETURN_TO', 'WO', $Tag->return_to(); # unless $wo;
#::logDebug("return-to stack = " . ::uneval($r_ary));
	}

	if(ref $opt->{hidden}) {
		my ($hk, $hv);
		my @o;
		while ( ($hk, $hv) = each %{$opt->{hidden}} ) {
			push @o, qq{<INPUT TYPE=hidden NAME="$hk" VALUE="$hv">\n};
		}
		chunk 'HIDDEN', 'WO', join("", @o); # unless $wo;
	}

	my $tcount_all = 0;
	
	my $tcount_top = 0;
	my $tcount_bot = 0;
	chunk ttag(), 'WO', <<EOF; # unless $wo;
<table class=touter border="0" cellspacing="0" cellpadding="0" width="$opt->{table_width}">
<tr>
  <td>

<table class=tinner  width="$opt->{inner_table_width}" cellspacing=0 cellmargin=0 width="100%" cellpadding="2" align="center" border="0">
EOF
	chunk ttag(), 'NO_TOP', <<EOF; # unless $opt->{no_top} or $wo;
<tr class=rtitle> 
<td align=right colspan=$span><img src="$opt->{clear_image}" width=1 height=3 alt=x></td>
</tr>
EOF

	  #### Extra buttons
      my $extra_ok =	$blob_widget
	  					|| $linecount > 4
						|| defined $opt->{include_form}
						|| $mlabel;
	if ($extra_ok and ! $opt->{no_top} and ! $opt->{nosave}) {
	  	if($opt->{back_text}) {
		  chunk ttag(), 'WO', <<EOF; # unless $wo;
<TR class=rnorm>
<td>&nbsp;</td>
<td align=left colspan=$oddspan class=cdata>
EOF
			chunk 'WIZARD_BUTTONS_TOP', 'BOTTOM_BUTTONS', <<EOF; # if ! $opt->{bottom_buttons};
<INPUT TYPE=submit NAME=mv_click VALUE="$opt->{back_text}">&nbsp;<INPUT TYPE=submit NAME=mv_click VALUE="$opt->{cancel_text}">&nbsp;<B><INPUT TYPE=submit NAME=mv_click VALUE="$opt->{next_text}"></B>
<BR>
EOF
			chunk 'MLABEL', 'WO', $mlabel;
			chunk_alias 'MLABEL', 'FORM_TOP';
			chunk ttag(), <<EOF;
</TD>
</TR>

<tr class=rspacer>
<td colspan=$span><img src="$opt->{clear_image}" width=1 height=3 alt=x></td>
</tr>
EOF
		}
		elsif ($opt->{wizard}) {
		  chunk ttag(), 'NO_TOP', <<EOF;
<TR class=rnorm>
<td>&nbsp;</td>
<td align=left colspan=$oddspan class=cdata>
EOF
			chunk 'WIZARD_BUTTONS_TOP', 'BOTTOM_BUTTONS', <<EOF; # if ! $opt->{bottom_buttons};
<INPUT TYPE=submit NAME=mv_click VALUE="$opt->{cancel_text}">&nbsp;<B><INPUT TYPE=submit NAME=mv_click VALUE="$opt->{next_text}"></B>
<BR>
EOF
			chunk 'MLABEL', 'BOTTOM_BUTTONS', $mlabel;
			chunk ttag(), <<EOF;
</TD>
</TR>

<tr class=rspacer>
<td colspan=$span><img src="$opt->{clear_image}" width=1 height=3 alt=x></td>
</tr>
EOF
		}
		else {
		  chunk ttag(), 'BOTTOM_BUTTONS', <<EOF;
<TR class=rnorm>
<td>&nbsp;</td>
<td align=left colspan=$oddspan class=cdata>
EOF

		  $opt->{ok_button_style} = 'font-weight: bold; width: 40px; text-align: center'
		  	unless defined $opt->{ok_button_style};
		  	
		  chunk 'OK_TOP', 'BOTTOM_BUTTONS', <<EOF;
<INPUT TYPE=submit NAME=mv_click VALUE="$opt->{next_text}" style="$opt->{ok_button_style}">
EOF
		  chunk ttag(), 'NOCANCEL BOTTOM_BUTTONS', <<EOF; # unless $opt->{nocancel};
&nbsp;
<INPUT TYPE=submit NAME=mv_click VALUE="$opt->{cancel_text}" style="$opt->{cancel_button_style}">
EOF

		  chunk 'RESET_TOP', '_SHOW_RESET BOTTOM_BUTTONS', <<EOF;
&nbsp;
<INPUT TYPE=reset>
EOF

			chunk 'MLABEL', 'BOTTOM_BUTTONS', $mlabel;
			chunk ttag(), 'BOTTOM_BUTTONS', , <<EOF;
</TD>
</TR>

<tr class=rspacer>
<td colspan=$span><img src="$opt->{clear_image}" width=1 height=3 alt=x></td>
</tr>
EOF
		}
	}

	chunk 'BLOB_WIDGET', $blob_widget; # unless $wo;

	  #### Extra buttons

	if($opt->{ui_new_item} and $opt->{ui_clone_tables}) {
		my @sets;
		my %seen;
		my @tables = split /[\s\0,]+/, $opt->{ui_clone_tables};
		for(@tables) {
			if(/:/) {
				push @sets, $_;
			}
			s/:.*//;
		}

		my %tab_checked;
		for(@tables, @sets) {
			$tab_checked{$_} = 1 if s/\*$//;
		}

		@tables = grep ! $seen{$_}++ && defined $Vend::Cfg->{Database}{$_}, @tables;

		my $tab = '';
		my $set .= <<'EOF';
[flag type=write table="_TABLES_"]
[perl tables="_TABLES_"]
	delete $::Scratch->{clone_tables};
	return if ! $CGI->{ui_clone_id};
	return if ! $CGI->{ui_clone_tables};
	my $id = $CGI->{ui_clone_id};

	my $out = "Cloning id=$id...";

	my $new =  $CGI->{$CGI->{mv_data_key}}
		or do {
				$out .= ("clone $id: no mv_data_key '$CGI->{mv_data_key}'");
				$::Scratch->{ui_message} = $out;
				return;
		};

	if($new =~ /\0/) {
		$new =~ s/\0/,/g;
		Log("cannot clone multiple keys '$new'.");
		return;
	}

	my %possible;
	my @possible = qw/_TABLES_/;
	@possible{@possible} = @possible;
	my @tables = grep /\S/, split /[\s,\0]+/, $CGI->{ui_clone_tables};
	my @sets = grep /:/, @tables;
	@tables = grep $_ !~ /:/, @tables;
	for(@tables) {
		next unless $possible{$_};
		my $db = database_exists_ref($_);
		next unless $db;
		my $new = 
		my $res = $db->clone_row($id, $new);
		if($res) {
			$out .= "cloned $id to to $new in table $_<BR>\n";
		}
		else {
			$out .= "FAILED clone of $id to to $new in table $_<BR>\n";
		}
	}
	for(@sets) {
		my ($t, $col) = split /:/, $_;
		my $db = database_exists_ref($t) or next;
		my $res = $db->clone_set($col, $id, $new);
		if($res) {
			$out .= "cloned $col=$id to to $col=$new in table $t<BR>\n";
		}
		else {
			$out .= "FAILED clone of $col=$id to to $col=$new in table $t<BR>\n";
		}
	}
	$::Scratch->{ui_message} = $out;
	return;
[/perl]
EOF
		my $tabform = '';
		@tables = grep $Tag->if_mm( { table => "$_=i" } ), @tables;

		for(@tables) {
			my $db = Vend::Data::database_exists_ref($_)
				or next;
			next unless $db->record_exists($opt->{ui_clone_id});
			my $checked = $tab_checked{$_} ? ' CHECKED' : '';
			$tabform .= <<EOF;
<INPUT TYPE=CHECKBOX NAME=ui_clone_tables VALUE="$_"$checked> clone to <b>$_</B><BR>
EOF
		}
		for(@sets) {
			my ($t, $col) = split /:/, $_;
			my $checked = $tab_checked{$_} ? ' CHECKED' : '';
			$tabform .= <<EOF;
<INPUT TYPE=CHECKBOX NAME=ui_clone_tables VALUE="$_"$checked> clone entries of <b>$t</B> matching on <B>$col</B><BR>
EOF
		}

		my $tabs = join " ", @tables;
		$set =~ s/_TABLES_/$tabs/g;
		$::Scratch->{clone_tables} = $set;
		chunk ttag(), <<EOF; # unless $wo;
<tr class=rtitle>
<td colspan=$span>
EOF
		chunk 'CLONE_TABLES', <<EOF;
$tabform<INPUT TYPE=hidden NAME=mv_check VALUE="clone_tables">
<INPUT TYPE=hidden NAME=ui_clone_id VALUE="$opt->{ui_clone_id}">
EOF
		chunk ttag(), <<EOF; # unless $wo;
</td>
</tr>
EOF
	}

	my %break;
	my %break_label;
	if($opt->{ui_break_before}) {
		my @tmp = grep /\S/, split /[\s,\0]+/, $opt->{ui_break_before};
		@break{@tmp} = @tmp;
		if($opt->{ui_break_before_label}) {
			@tmp = grep /\S/, split /\s*[,\0]\s*/, $opt->{ui_break_before_label};
			for(@tmp) {
				my ($br, $lab) = split /\s*=\s*/, $_;
				$break_label{$br} = $lab;
			}
		}
	}
	if(!$db and ! $opt->{notable}) {
		return "<TR><TD>Broken table '$table'</TD></TR>";
	}

	my $passed_fields = $opt->{ui_data_fields};

	my @extra_cols;
	my %email_cols;
	my %ok_col;
	my @cols;
	my @dbcols;
	my %display_only;

	if($opt->{notable}) {
		@cols = split /[\s,\0]+/, $passed_fields;
	}
	else {

	while($passed_fields =~ s/(\w+[.:]+\S+)//) {
		push @extra_cols, $1;
	}

	my @do = grep /\S/, split /[\0,\s]+/, $opt->{ui_display_only};
	for(@do) {
		$email_cols{$_} = 1 if $opt->{mailto};
		$display_only{$_} = 1;
		push @extra_cols, $_;
	}

		@dbcols  = split /\s+/, $Tag->db_columns( {
										name	=> $table,
										columns	=> $passed_fields,
										passed_order => 1,
									});

	if($opt->{ui_data_fields}) {
		for(@dbcols, @extra_cols) {
			unless (/^(\w+)([.:]+)(\S+)/) {
				$ok_col{$_} = 1;
				next;
			}
			my $t = $1;
			my $s = $2;
			my $c = $3;
			if($s eq '.') {
				$c = $t;
				$t = $table;
			}
			else {
				$c =~ s/\..*//;
			}
			next unless $Tag->db_columns( { name	=> $t, columns	=> $c, });
			$ok_col{$_} = 1;
		}
	}
	@cols = grep $ok_col{$_}, split /\s+/, $opt->{ui_data_fields};
	}

	$keycol = $cols[0] if ! $keycol;

	if($opt->{defaults}) {
			if($opt->{force_defaults}) {
			$default->{$_} = $def->{$_} for @cols;
			}
			elsif($opt->{wizard}) {
			for(@cols) {
				$default->{$_} = $def->{$_} if defined $def->{$_};
			}
		}
			else {
			for(@cols) {
				next if defined $default->{$_};
				next unless defined $def->{$_};
				$default->{$_} = $def->{$_};
			}
		}
	}

	my $super = $Tag->if_mm('super');

	my $refkey = $key;

	my @data_enable = ($opt->{mv_blob_pointer}, $opt->{mv_blob_field});
	my @ext_enable;

	# Init the cell stuff
	my %td_extra;
	my %td_default = (
			widget_cell_class	=> 'cwidget',
			label_cell_class	=> 'clabel',
			data_cell_class	=> 'cdata',
			help_cell_class	=> 'chelp',
	);

	for my $ctype (qw/label data widget help/) {
		$td_extra{$ctype} = '';
		for my $ptype (qw/class style align valign width/) {
			my $parm = $ctype . '_cell_' . $ptype;
			if(defined $opt->{$parm}) {
				$td_extra{$ctype} .= qq{ $ptype="$opt->{$parm}"};
			}
			elsif ($td_default{$parm}) {
				$td_extra{$ctype} .= qq{ $ptype="$td_default{$parm}"};
			}
		}
		if(my $thing = $opt->{$ctype . "_cell_extra"}) {
			$td_extra{$ctype} .= " $thing";
		}
	}

	if($opt->{left_width} and ! $opt->{label_cell_width}) {
		$td_extra{label} .= qq{ width="$opt->{left_width}"};
	}

	my $show_meta;
	if($super and ! $opt->{no_meta}) {
		$show_meta = defined $def->{ui_meta_force}
					?  $def->{ui_meta_force}
					: $::Variable->{UI_META_LINK};
	}

	if($show_meta) {
		if(! $opt->{row_template} and ! $opt->{simple_row}) {
			$opt->{meta_prepend} = '<br><font size=1>'
				unless defined $opt->{meta_prepend};

			$opt->{meta_append} = '</font>'
				unless defined $opt->{meta_append};
		}
		else {
			$opt->{meta_prepend} ||= '';
			$opt->{meta_append} ||= '';
		}
		$opt->{meta_anchor} ||= errmsg('meta');
		$opt->{meta_anchor_specific} ||= errmsg('item-specific meta');
		$opt->{meta_extra} = " $opt->{meta_extra}"
			if $opt->{meta_extra};
		$opt->{meta_extra} ||= "";
		$opt->{meta_extra} .= qq{ class="$opt->{meta_class}"}
			if $opt->{meta_class};
		$opt->{meta_extra} .= qq{ class="$opt->{meta_style}"}
			if $opt->{meta_style};
	}

 	my $row_template = $opt->{row_template};
	
	if(! $row_template) {
		if($opt->{simple_row}) {
			$opt->{help_anchor} ||= 'help';
			$row_template = <<EOF;
   <td$td_extra{label}> 
     $blabel\$LABEL\$$elabel
   </td>
   <td$td_extra{widget}>\$WIDGET\${HELP_EITHER}&nbsp;<a href="\$HELP_URL\$" title="\$HELP\$">$opt->{help_anchor}</a>{/HELP_EITHER}&nbsp;{META_URL}<A HREF="\$META_URL\$">$opt->{meta_anchor}</A>{/META_URL}
   </td>
EOF
		}
		else {
			$row_template = <<EOF;
   <td$td_extra{label}> 
     $blabel\$LABEL\$$elabel~META~
   </td>
   <td$td_extra{data}>
     <table cellspacing=0 cellmargin=0 width="100%">
       <tr> 
         <td$td_extra{widget}>
           \$WIDGET\$
         </td>
         <td$td_extra{help}>~TKEY~<i>\$HELP\$</i>{HELP_URL}<BR><A HREF="\$HELP_URL\$">help</A>{/HELP_URL}</FONT></td>
       </tr>
     </table>
   </td>
EOF
		}
	}

	$row_template =~ s/~OPT:(\w+)~/$opt->{$1}/g;
	$row_template =~ s/~BLABEL~/$blabel/g;
	$row_template =~ s/~ELABEL~/$elabel/g;
	$row_template =~ s/~([A-Z]+)_EXTRA~/$td_extra{lc $1}/g;

	my %serialize;
	my %serial_data;

	if(my $jsc = $opt->{js_changed}) {
		$jsc =~ /^\w+$/
			and $jsc = qq{onChange="$jsc} . q{('$$KEY$$','$$COL$$');"};
		foreach my $c (@cols) {
			next if $extra->{$c} =~ /\bonchange\s*=/i;
			my $tpl = $jsc;
			$tpl .= $extra->{$c} if length $extra->{$c};
			$tpl =~ s/\$\$KEY\$\$/$key/g;
			$tpl =~ s/\$\$COL\$\$/$c/g;
			if ($extra->{$c} and $extra->{$c} =~ /\bonchange\s*=/i) {
				$tpl =~ s/onChange="//;
				$tpl =~ s/"\s*$/;/;
				$extra->{$c} =~ s/\b(onchange\s*=\s*["'])/$1$tpl/i;
			}
			else {
				$extra->{$c} = $tpl;
			}
		}
	}

	my %link_row;
	my %link_before;
	if($opt->{link_table} and $key) {
		my @ltable;
		my @lfields;
		my @lkey;
		my @lview;
		my @llab;
		my @ltpl;
		my @lbefore;
		my @lsort;
		my $tcount = 1;
		if(ref($opt->{link_table}) eq 'ARRAY') {
			@ltable  = @{$opt->{link_table}};
			@lfields = @{$opt->{link_fields}};
			@lview   = @{$opt->{link_view}};
			@lkey    = @{$opt->{link_key}};
			@llab    = @{$opt->{link_label}};
			@ltpl    = @{$opt->{link_template}};
			@lbefore = @{$opt->{link_before}};
			@lsort   = @{$opt->{link_sort}};
		}
		else {
			@ltable  = $opt->{link_table};
			@lfields = $opt->{link_fields};
			@lview   = $opt->{link_view};
			@lkey    = $opt->{link_key};
			@llab    = $opt->{link_label};
			@ltpl    = $opt->{link_template};
			@lbefore = $opt->{link_before};
			@lsort   = $opt->{link_sort};
		}
		while(my $lt = shift @ltable) {
			my $lf = shift @lfields;
			my $lv = shift @lview;
			my $lk = shift @lkey;
			my $ll = shift @lkey;
			my $lb = shift @lbefore;
			my $ls = shift @lsort;

			my $rcount = 0;

			$ll ||= errmsg("Settings in table %s linked by %s", $lt, $lk);

			my $tpl = $row_template;
			my $ldb = database_exists_ref($lt)
				or do {
					logError("Bad table editor link table: %s", $lt);
					next;
				};

			my $lmeta = $Tag->meta_record($lt, $lv);
			$lf ||= $lmeta->{spread_fields};

			my $l_pkey = $ldb->config('KEY');

			my @cf = grep /\S/, split /[\s,\0]+/, $lf;
			@cf = grep $_ ne $l_pkey, @cf;
			$lf = join " ", @cf;
			my $lextra = $opt->{link_extra} || '';
			$lextra = " $lextra" if $lextra;
			my $labside = <<EOF;
<input type=hidden name="mv_data_table__$tcount" value="$lt">
<input type=hidden name="mv_data_fields__$tcount" value="$lf">
<input type=hidden name="mv_data_multiple__$tcount" value="1">
<input type=hidden name="mv_data_key__$tcount" value="$l_pkey">
$ll
EOF

			my @lout = q{<table cellspacing=0 cellpadding=1>};
			push @lout, qq{<tr><td$lextra>$l_pkey</td>};
			push @lout, $Tag->row_edit({ table => $lt, columns => $lf });
			push @lout, '</tr>';

			my $tname = $ldb->name();
			my $lfor = $key;
			$lfor = $ldb->quote($key, $lk);
			my $q = "SELECT $l_pkey FROM $tname WHERE $lk = $lfor";
			$q .= " ORDER BY $ls" if $ls;
			my $ary = $ldb->query($q);
			for(@$ary) {
				my $rk = $_->[0];
				my $pp = $rcount ? "${rcount}_" : '';
				my $hid = qq{<input type=hidden name="$pp${l_pkey}__$tcount" value="};
				$hid .= HTML::Entities::encode($rk);
				$hid .= qq{">};
				push @lout, qq{<tr><td$lextra>$rk$hid</td>};
				my %o = (
					table => $lt,
					key => $_->[0],
					extra => $opt->{link_extra},
					pointer => $rcount,
					stacker => $tcount,
					columns => $lf,
					extra => $opt->{link_extra},
				);
				$rcount++;
				push @lout, $Tag->row_edit(\%o);
				push @lout, "</tr>";
			}
			my %o = (
				table => $lt,
				blank => 1,
				extra => $opt->{link_extra},
				pointer => 999999,
				stacker => $tcount,
				columns => $lf,
				extra => $opt->{link_extra},
			);
			push @lout, qq{<tr><td$lextra>};
			push @lout, qq{<input size=8 name="999999_${l_pkey}__$tcount" value="">};
			push @lout, '</td>';
			push @lout, $Tag->row_edit(\%o);
			push @lout, '</tr>';
			push @lout, "</table>";
			$tpl =~ s{\$LABEL\$}{$labside}g;
			$tpl =~ s{\$WIDGET\$}{join "", @lout}ge;
			my $murl = '';
			if($show_meta) {
				$murl = $Tag->page({
							href => 'admin/db_metaconfig_spread',
							form => qq(
									ui_table=$lt
									ui_view=$lv
								),
							});
				$murl .= errmsg('meta');
				$murl .= '</a>';
			}
			$tpl =~ s{\~META\~}{$murl}g;
			$tpl =~ s{\$HELP\$}{}g;
			$tpl =~ s{\~TKEY\~}{}g;
			$tpl =~ s!{HELP_URL}.*?{/HELP_URL}!!gs;
			$link_row{$lt} = $tpl;
			if($lb) {
				$link_before{$lb} = $lt;
			}
			my $mde_key = "mv_data_enable__$tcount";
			$::Scratch->{$mde_key} = "$lt:" . join(",", $l_pkey, @cf) . ':';
			$tcount++;
		}
	}

    if($opt->{tabbed}) {
        my $ph = $opt->{panel_height} || '600';
        my $pw = $opt->{panel_width} || '800';
        my $th = $opt->{tab_height} || '30';
        my $oh = $ph + $th;
        my $extra = $Vend::Session->{browser} =~ /Gecko/
                  ? ''
                  : " width=$pw height=$oh";
        chunk ttag(), qq{<tr><td colspan=$span$extra>\n};
    }

	foreach my $col (@cols) {
		if($link_before{$col}) {
			col_chunk "SPREAD_$link_before{$col}", delete $link_row{$link_before{$col}};
		}
		my $t;
		my $c;
		my $k;
		my $tkey_message;
		if($col eq $keycol) {
			if($opt->{ui_hide_key}) {
				my $kval = $key || $override->{$col} || $default->{$col};
				col_chunk $col, <<EOF;
	<INPUT TYPE=hidden NAME="$col" VALUE="$kval">
EOF
				next;
			}
			elsif ($opt->{ui_new_item}) {
				$tkey_message = $key_message;
			}
		}

		my $w = '';
		my $do = $display_only{$col};
		
		my $currval;
		my $serialize;

		if($col =~ /(\w+):+([^:]+)(?::+(\S+))?/) {
			$t = $1;
			$c = $2;
			$c =~ /(.+?)\.\w.*/
				and $col = "$t:$1"
					and $serialize = $c;
			$k = $3 || undef;
			push @ext_enable, ("$t:$c" . $k ? ":$k" : '')
				unless $do;
		}
		else {
			$t = $table;
			$c = $col;
			$c =~ /(.+?)\.\w.*/
				and $col = $1
					and $serialize = $c;
			push @data_enable, $col
				unless $do and ! $opt->{mailto};
		}

		my $type;
		my $overridden;

		$currval = $data->{$col} if defined $data->{$col};
		if ($opt->{force_defaults} or defined $override->{$c} ) {
			$currval = $override->{$c};
			$overridden = 1;
#::logDebug("hit override for $col,currval=$currval");
		}
		elsif (defined $CGI->{"ui_preload:$t:$c"} ) {
			$currval = delete $CGI->{"ui_preload:$t:$c"};
			$overridden = 1;
#::logDebug("hit preload for $col,currval=$currval");
		}
		elsif( ($do && ! $currval) or $col =~ /:/) {
			if(defined $k) {
				my $check = $k;
				undef $k;
				for( $override, $data, $default) {
					next unless defined $_->{$check};
					$k = $_->{$check};
					last;
				}
			}
			else {
				$k = defined $key ? $key : $refkey;
			}
			$currval = tag_data($t, $c, $k) if defined $k;
#::logDebug("hit display_only for $col, t=$t, c=$c, k=$k, currval=$currval");
		}
		elsif (defined $default->{$c} and ! length($data->{$c}) ) {
			$currval = $default->{$c};
#::logDebug("hit preload for $col,currval=$currval");
		}
		else {
#::logDebug("hit data->col for $col, t=$t, c=$c, k=$k, currval=$currval");
			$currval = length($data->{$col}) ? $data->{$col} : '';
			$overridden = 1;
		}

		my $namecol;
		if($serialize) {
#Debug("serialize=$serialize");
			if($serialize{$col}) {
				push @{$serialize{$col}}, $serialize;
			}
			else {
				my $sd;
				if($col =~ /:/) {
					my ($tt, $tc) = split /:+/, $col;
					$sd = tag_data($tt, $tc, $k);
				}
				else {
					$sd = $data->{$col} || $def->{$col};
				}
#Debug("serial_data=$sd");
				$serial_data{$col} = $sd;
				$opt->{hidden}{$col} = $data->{$col};
				$serialize{$col} = [$serialize];
			}
			$c =~ /\.(.*)/;
			my $hk = $1;
#Debug("fetching serial_data for $col hk=$hk data=$serial_data{$col}");
			$currval = dotted_hash($serial_data{$col}, $hk);
#Debug("fetched hk=$hk value=$currval");
			$overridden = 1;
			$namecol = $c = $serialize;
		}

		$namecol = $col unless $namecol;

		$type = 'value' if $do and ! ($opt->{wizard} || ! $opt->{mailto});

		if (! length $currval and defined $default->{$c}) {
			$currval = $default->{$c};
		}

		my $template = $row_template;
		if($error->{$c}) {
			my $parm = {
					name => $c,
					std_label => '$LABEL$',
					required => 1,
					};
			if($opt->{all_errors}) {
				$parm->{keep} = 1;
				$parm->{text} = <<EOF;
<FONT COLOR="$opt->{color_fail}">\$LABEL\$</FONT><!--%s-->
[else]{REQUIRED <B>}{LABEL}{REQUIRED </B>}[/else]
EOF
			}
			$template =~ s/\$LABEL\$/$Tag->error($parm)/eg;
		}

		my $meta = '';
		my $meta_url;
		my $meta_url_specific;
		if($show_meta) {
			# Get global variables
			my $base = $::Variable->{UI_BASE}
					 || $Global::Variable->{UI_BASE} || 'admin';
			my $page = $Global::Variable->{MV_PAGE};
			my $id = $t . "::$c";
			$id = $opt->{ui_meta_view} . "::$id"
				if $opt->{ui_meta_view} and $opt->{ui_meta_view} ne 'metaconfig';

			my $return = <<EOF;
ui_return_to=$page
ui_return_to=item_id=$opt->{item_id}
ui_return_to=ui_meta_view=$opt->{ui_meta_view}
ui_return_to=mv_return_table=$t
mv_return_table=$table
ui_return_stack=$CGI->{ui_return_stack}
EOF

			$meta_url = $Tag->area({
								href => "$base/meta_editor",
								form => qq{
											item_id=$id
											$return
										}
							});
			my $meta_specific = '';
			if($opt->{ui_meta_specific}) {
				$meta_url_specific = $Tag->area({
										href => "$base/meta_editor",
										form => qq{
													item_id=${t}::${c}::$key
													$return
												}
										});
				$meta_specific = <<EOF;
<br><a href="$meta_url_specific"$opt->{meta_extra}>$opt->{meta_anchor_specific}</A>
EOF
			}
								
			$opt->{meta_append} = '</FONT>'
				unless defined $opt->{meta_append};
			$meta = <<EOF;
$opt->{meta_prepend}<a href="$meta_url"$opt->{meta_extra}>$opt->{meta_anchor}</A>
$meta_specific$opt->{meta_append}
EOF
		}

		$template =~ s/~TKEY~/$tkey_message || ''/eg;
#::logDebug("col=$c currval=$currval widget=$widget->{$c} label=$label->{$c} (type=$type)");
		my $display = display($t, $c, $key, {
										applylocale => 1,
										arbitrary => $opt->{ui_meta_view},
										column => $c,
										default => $currval,
										extra => $extra->{$c},
										fallback => 1,
										field => $field->{$c},
										filter => $filter->{$c},
										height => $height->{$c},
										help => $help->{$c},
										help_url => $help_url->{$c},
										label => $label->{$c},
										key => $key,
										meta => $pmeta->{$c},
										meta_url => $meta_url,
										meta_url_specific => $meta_url_specific,
										name => $namecol,
										override => $overridden,
										passed => $passed->{$c},
										options => $options->{$c},
										outboard => $outboard->{$c},
										append => $append->{$c},
										prepend => $prepend->{$c},
										lookup => $lookup->{$c},
										lookup_query => $lookup_query->{$c},
										db => $database->{$c},
										pre_filter => $pre_filter->{$c},
										table => $t,
										type => $widget->{$c} || $type,
										width => $width->{$c},
										template => $template,
									});
#::logDebug("finished display of col=$c");

		# don't use template if we have only a hidden HTML form variable
		if ($display =~ /^\s*<input\s[^>]*type\s*=\W*hidden\b[^>]*>\s*$/i) {
			col_chunk $c, $display . "\n";
			next;
		}

		if($show_meta and $display =~ /\~META\~/) {
			$display =~ s/\~META\~/$meta/g;
		}

		$display =~ s/\~ERROR\~/$Tag->error({ name => $c, keep => 1 })/eg;
        
		my $update_ctl;
		if (! $wo and $break{$namecol}) {
			push @titles, $break_label{$namecol};
			if(@columns == 0 and @titles == 1) {
				# do nothing
			}
			else {
				$update_ctl = 1;
			}

			while($rowcount % $rowdiv) {
				$w .= '<TD>&nbsp;</td><TD>&nbsp;</td>';
				$rowcount++;
			}
			$w .= "</TR>\n";
			unless ($opt->{tabbed}) {
				$w .= <<EOF if $break{$namecol};
	<TR class=rbreak>
		<TD COLSPAN=$span class=cbreak>$break_label{$namecol}<IMG SRC="$opt->{clear_image}" WIDTH=1 HEIGHT=1 alt=x></TD>
	</TR>
EOF
			}
			$rowcount = 0;
		}
		$w .= "<tr class=rnorm>\n" unless $rowcount++ % $rowdiv;
		$w .= $display;
		$w .= "</TR>\n" unless $rowcount % $rowdiv;
		col_chunk $c, $w;
		$ctl_index++ if $update_ctl;
	}

	for(sort keys %link_row) {
		col_chunk "SPREAD_$_", delete $link_row{$_};
	}

	my $firstout = scalar(@out);

	if($opt->{tabbed}) {
		chunk ttag(), qq{</td></tr>\n};
	}

	while($rowcount % $rowdiv) {
		chunk ttag(), '<TD>&nbsp;</td><TD>&nbsp;</td>'; # unless $wo;
		$rowcount++;
	}

	$::Scratch->{mv_data_enable} = '';
	if($opt->{auto_secure}) {
		$::Scratch->{mv_data_enable} .= "$table:" . join(",", @data_enable) . ':';
		$::Scratch->{mv_data_enable_key} = $opt->{item_id};
	}
	if(@ext_enable) {
		$::Scratch->{mv_data_enable} .= " " . join(" ", @ext_enable) . " ";
	}
#Debug("setting mv_data_enable to $::Scratch->{mv_data_enable}");
	my @serial = keys %serialize;
	my @serial_fields;
	my @o;
	for (@serial) {
#Debug("$_ serial_data=$serial_data{$_}");
		$serial_data{$_} = uneval($serial_data{$_})
			if is_hash($serial_data{$_});
		$serial_data{$_} =~ s/\&/&amp;/g;
		$serial_data{$_} =~ s/"/&quot;/g;
		push @o, qq{<INPUT TYPE=hidden NAME="$_" VALUE="$serial_data{$_}">}; # unless $wo;
		push @serial_fields, @{$serialize{$_}};
	}

	if(! $wo and @serial_fields) {
		push @o, qq{<INPUT TYPE=hidden NAME="ui_serial_fields" VALUE="};
		push @o, join " ", @serial_fields;
		push @o, qq{">};
		chunk 'SERIAL_FIELDS', join("", @o);
	}

	###
	### Here the user can include some extra stuff in the form....
	###
	if($opt->{include_form}) {
		chunk 'INCLUDE_FORM', <<EOF; # if ! $wo;
<tr class=rnorm>
<td colspan=$span>$opt->{include_form}</td>
</tr>
EOF
	}
	### END USER INCLUDE

	unless ($opt->{mailto} and $opt->{mv_blob_only}) {
		@cols = grep ! $display_only{$_}, @cols;
	}
	$passed_fields = join " ", @cols;

	chunk 'MV_DATA_FIELDS', <<EOF; # unless $wo;
<INPUT TYPE=hidden NAME=mv_data_fields VALUE="$passed_fields">
EOF

	chunk ttag(), <<EOF;
<tr class=rspacer>
<td colspan=$span ><img src="$opt->{clear_image}" height=3 alt=x></td>
</tr>
EOF

  SAVEWIDGETS: {
  	last SAVEWIDGETS if $wo || $opt->{nosave}; 
		chunk ttag(), <<EOF;
<TR class=rnorm>
<td>&nbsp;</td>
<td align=left colspan=$oddspan class=cdata>
EOF
	  	if($opt->{back_text}) {

			chunk 'BOTTOM_BUTTONS', <<EOF;
<INPUT TYPE=submit NAME=mv_click VALUE="$opt->{back_text}">&nbsp;<INPUT TYPE=submit NAME=mv_click VALUE="$opt->{cancel_text}">&nbsp;<B><INPUT TYPE=submit NAME=mv_click VALUE="$opt->{next_text}"></B>
EOF
		}
		elsif($opt->{wizard}) {
			chunk 'BOTTOM_BUTTONS', <<EOF;
<TR class=rnorm>
<td>&nbsp;</td>
<td align=left colspan=$oddspan class=cdata>
<INPUT TYPE=submit NAME=mv_click VALUE="$opt->{cancel_text}">&nbsp;<B><INPUT TYPE=submit NAME=mv_click VALUE="$opt->{next_text}"></B>
EOF
		}
		else {
			chunk 'OK_BOTTOM', <<EOF;
<INPUT TYPE=submit NAME=mv_click VALUE="$opt->{next_text}" style="$opt->{ok_button_style}">
EOF

			chunk 'CANCEL_BOTTOM', 'NOCANCEL', <<EOF;
&nbsp;<INPUT TYPE=submit NAME=mv_click VALUE="$opt->{cancel_text}" style="$opt->{cancel_button_style}">
EOF

			chunk 'RESET_BOTTOM', qq{&nbsp;<INPUT TYPE=reset>}
				if $opt->{show_reset};
			chunk_alias 'BOTTOM_BUTTONS', qw/OK_BOTTOM CANCEL_BOTTOM RESET_BOTTOM/;
		}

	if(! $opt->{notable} and $Tag->if_mm('tables', "$table=x") and ! $db->config('LARGE') ) {
		my $checked = ' CHECKED';
		$checked = ''
			if defined $opt->{mv_auto_export} and ! $opt->{mv_auto_export};
		my $autoexpstr = errmsg('Auto-export');		
		chunk 'AUTO_EXPORT', 'NOEXPORT NOSAVE', <<EOF; # unless $opt->{noexport} or $opt->{nosave};
<small>
&nbsp;
&nbsp;
&nbsp;
&nbsp;
&nbsp;
	<INPUT TYPE=checkbox NAME=mv_auto_export VALUE="$table"$checked>&nbsp;$autoexpstr
EOF

	}

	if($exists and ! $opt->{nodelete} and $Tag->if_mm('tables', "$table=d")) {
		my $extra = $Tag->return_to( { type => 'click', tablehack => 1 });
		my $page = $CGI->{ui_return_to};
		$page =~ s/\0.*//s;
		my $url = $Tag->area( {
					href => $page,
					form => qq!
						deleterecords=1
						ui_delete_id=$key
						mv_data_table=$table
						mv_click=db_maintenance
						mv_action=back
						$extra
					!,
					});
		my $delstr = errmsg('Delete');
		my $delmsg = errmsg('Are you sure you want to delete %s?',$key);
		chunk 'DELETE_BUTTON', 'NOSAVE', <<EOF; # if ! $opt->{nosave};
<BR><BR><A
onClick="return confirm('$delmsg')"
HREF="$url"><IMG SRC="delete.gif" ALT="Delete $key" BORDER=0></A> $delstr
EOF

	}
	chunk ttag(), <<EOF;
</small>
</td>
</tr>
EOF
  } # end SAVEWIDGETS

	my $message = '';

#	if($opt->{bottom_errors}) {
#		my $err = $Tag->error( {
#									show_var => $error_show_var,
#									show_error => 1,
#									joiner => '<BR>',
#								}
#								);
#		push @errors, $err if $err;
#	}

	if(@errors) {
		$message .= '<P>Errors:';
		$message .= qq{<FONT COLOR="$opt->{color_fail}">};
		$message .= '<BLOCKQUOTE>';
		$message .= join "<BR>", @errors;
		$message .= '</BLOCKQUOTE></FONT>';
	}
	if(@messages) {
		$message .= '<P>Messages:';
		$message .= qq{<FONT COLOR="$opt->{color_success}">};
		$message .= '<BLOCKQUOTE>';
		$message .= join "<BR>", @messages;
		$message .= '</BLOCKQUOTE></FONT>';
	}
	$Tag->error( { all => 1 } );

	chunk ttag(), 'NO_BOTTOM _MESSAGE', <<EOF;
<tr class=rtitle>
	<td colspan=$span>
EOF

	chunk 'MESSAGE_TEXT', 'NO_BOTTOM', $message; # unless $wo or ($opt->{no_bottom} and ! $message);

	chunk ttag(), 'NO_BOTTOM _MESSAGE', <<EOF;
	</td>
</tr>
EOF
	chunk ttag(), <<EOF; # unless $wo;
</table>
</td></tr></table>
EOF

	chunk 'FORM_BOTTOM', <<EOF;
</form>$restrict_end
EOF

	my %ehash = (
	);
	for(qw/
		BOTTOM_BUTTONS
		NOCANCEL
		NOEXPORT
		NOSAVE
		NO_BOTTOM
		NO_TOP
		WO
		SHOW_RESET
		/)
	{
		$ehash{$_} = $opt->{lc $_} ? 1 : 0;
	}

	$ehash{MESSAGE} = length($message) ? 1 : 0;

	resolve_exclude(\%ehash);

	if($wo) {
		return (map { @$_ } @controls) if wantarray;
		return join "", map { @$_ } @controls;
	}
show_times("end table editor call item_id=$key") if $Global::ShowTimes;

	my @put;
	for(my $i = 0; $i < $firstout; $i++) {
#::logDebug("$out[$i] content length=" . length($outhash{$out[$i]} ));
		push @put, $outhash{$out[$i]};
	}

	if($opt->{tabbed}) {
#::logDebug("In tabbed display...controls=" . scalar(@controls) . ", titles=" . scalar(@titles));
		my @tabcont;
		for(@controls) {
			push @tabcont, join "", map { $outhash{$_} } @$_;
		}
		$opt->{panel_prepend} ||= '<table>';
		$opt->{panel_append} ||= '</table>';
		push @put, tabbed_display(\@titles,\@tabcont,$opt);
	}
	else {
		for my $c (@controls) {
			for (@$c) {
				push @put, $outhash{$_};
			}
		}
	}

	for(my $i = $firstout; $i < @out; $i++) {
#::logDebug("$out[$i] content length=" . length($outhash{$out[$i]} ));
		push @put, $outhash{$out[$i]};
	}
	return join "", @put;
}

1;
