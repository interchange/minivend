#!/usr/bin/perl
# Interpolate.pm - Interpret Interchange tags
# 
# $Id$
#
# Copyright (C) 1996-2000 Akopia, Inc. <info@akopia.com>
#
# This program was originally based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
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
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA.

package Vend::Interpolate;

require Exporter;
@ISA = qw(Exporter);

$VERSION = substr(q$Revision$, 10);

@EXPORT = qw (

cache_html
interpolate_html
subtotal
tag_data

);

# SQL
push @EXPORT, 'tag_sql_list';
# END SQL

@EXPORT_OK = qw( sort_cart );

use Safe;

my $hole;
BEGIN {
	eval {
		require Safe::Hole;
		$hole = new Safe::Hole;
	};
}

use strict;
use Vend::Util;
use Vend::Data;
require Vend::Cart;


use Vend::Server;
use Vend::Scan;
use Vend::Tags;
use Vend::Document;
use Vend::Parse;
use POSIX qw(ceil strftime);

use constant MAX_SHIP_ITERATIONS => 100;
use constant MODE  => 0;
use constant DESC  => 1;
use constant CRIT  => 2;
use constant MIN   => 3;
use constant MAX   => 4;
use constant COST  => 5;
use constant QUERY => 6;
use constant OPT   => 7;

use vars qw(%Data_cache);

my $wantref = 1;
my $CacheInvalid = 1;

# MVASP

my @Share_vars;
my @Share_routines;

BEGIN {
	@Share_vars = qw/
							$mv_filter_value
							$mv_filter_name
							$s
							$q
							$item
							$CGI_array
							$CGI
							$Document
							%Db
							$DbSearch
							$Search
							$Carts
							$Config
							%Sql
							%Safe
							$Items
							$Scratch
							$Shipping
							$Session
							$Tag
							$Tmp
							$TextSearch
							$Values
							$Variable
						/;
	@Share_routines = qw/
							&tag_data
							&Log
							&uneval
							&HTML
							&interpolate_html
						/;
}

use vars @Share_vars, @Share_routines, qw/$Calc_initialized $Calc_reset $ready_safe/;
use vars qw/%Filter %Ship_handler/;

$ready_safe = new Safe;
$ready_safe->untrap(qw/sort ftfile/);

sub reset_calc {
#::logGlobal("resetting calc");
	if(defined $Vend::Cfg->{ActionMap}{_mvsafe}) {
#::logGlobal("already made");
		$ready_safe = $Vend::Cfg->{ActionMap}{_mvsafe};
	}
	else {
#::logGlobal("new one made");
		$ready_safe = new Safe 'MVSAFE';
		$ready_safe->untrap(@{$Global::SafeUntrap});
		no strict 'refs';
		$Document   = new Vend::Document;
		*Log = \&Vend::Util::logError;
		*uneval = \&Vend::Util::uneval_it;
		*HTML = \&Vend::Document::HTML;
		$ready_safe->share(@Share_vars, @Share_routines);
		$DbSearch   = new Vend::DbSearch;
		$TextSearch = new Vend::TextSearch;
		$Tag        = new Vend::Tags;
		$Tmp        = {};
	}
	$Calc_reset = 1;
	undef $Calc_initialized;
	return $ready_safe;
}

sub init_calc {
#::logGlobal("initting calc");
	reset_calc() unless $Calc_reset;
	$CGI_array                   = \%CGI::values_array;
	$CGI        = $Safe{cgi}     = \%CGI::values;
	$Carts      = $Safe{carts}   = $::Carts;
	$Items      = $Safe{items}   = $Vend::Items;
	$Config     = $Safe{config}  = $Vend::Cfg;
	$Scratch    = $Safe{scratch} = $::Scratch;
	$Values     = $Safe{values}  = $::Values;
	$Session                     = $Vend::Session;
	$Search                      = $Vend::SearchObject ||= {};
	$Variable   = $::Variable;
	$Calc_initialized = 1;
	return;
}

sub uninit_calc {
}

# Regular expression pre-compilation
my %T;
my %QR;

my $All = '[\000-\377]*';
my $Some = '[\000-\377]*?';
my $Codere = '[\w-#/.]+';
my $Coderex = '[\w-:#=/.%]+';
my $Mandx = '\s+([\w-:#=/.%]+)';
my $Mandf = '(?:%20|\s)+([\w-#/.]+)';
my $Spacef = '(?:%20|\s)+';
my $Spaceo = '(?:%20|\s)*';

my $Optx = '(?:\s+)?([\w-:#=/.%]+)?';
my $Mand = '\s+([\w-#/.]+)';
my $Opt = '(?:\s+)?([\w-#/.]+)?';
my $T    = '\]';
my $D    = '[-_]';

my $XAll = qr{[\000-\377]*};
my $XSome = qr{[\000-\377]*?};
my $XCodere = qr{[\w-#/.]+};
my $XCoderex = qr{[\w-:#=/.%]+};
my $XMandx = qr{\s+([\w-:#=/.%]+)};
my $XMandf = qr{(?:%20|\s)+([\w-#/.]+)};
my $XSpacef = qr{(?:%20|\s)+};
my $XSpaceo = qr{(?:%20|\s)*};
my $XOptx = qr{(?:\s+)?([\w-:#=/.%]+)?};
my $XMand = qr{\s+([\w-#/.]+)};
my $XOpt = qr{(?:\s+)?([\w-#/.]+)?};
my $XD    = qr{[-_]};

my %Comment_out = ( '<' => '&lt;', '[' => '&#91;', '_' => '&#95;', );



my @th = (qw!

		/_alternate
		/_calc
		/_change
		/_exec
		/_filter
		/_last
		/_modifier
		/_next
		/_param
		/_pos
		/_sub
		/col
		/comment
		/condition
		/else
		/elsif
		/more_list
		/no_match
		/on_match
		/sort
		/then
		_accessories
		_alternate
		_calc
		_change
		_code
		_data
		_description
		_discount
		_exec
		_field
		_filter
		_increment
		_last
		_line
		_match
		_modifier
		_next
		_param
		_pos
		_price
		_quantity
		_subtotal
		_sub
		col
		comment
		condition
		discount_price
		discount_subtotal
		else
		elsif
		matches
		modifier_name
		more
		more_list
		no_match
		on_match
		quantity_name
		sort
		then

		! );

	my $shown = 0;
	my $tag;
	for (@th) {
		$tag = $_;
		s/([A-Za-z0-9])/[\u$1\l$1]/g;
		s/[-_]/[-_]/g;
		$T{$tag} = $_;
		next if $tag =~ m{^_};
		$T{$tag} = "\\[$T{$tag}";
		next unless $tag =~ m{^/};
		$T{$tag} = "$T{$tag}\]";
	}

%QR = (
	'/_alternate'	=> qr($T{_alternate}\]),
	'/_calc'		=> qr($T{_calc}\]),
	'/_change'		=> qr([-_]change\s+)i,
	'/_data'		=> qr($T{_data}\]),
	'/_exec'		=> qr($T{_exec}\]),
	'/_field'		=> qr($T{_field}\]),
	'/_filter'		=> qr($T{_filter}\]),
	'/_last'		=> qr($T{_last}\]),
	'/_modifier'	=> qr($T{_modifier}\]),
	'/_next'		=> qr($T{_next}\]),
	'/_param'		=> qr($T{_param}\]),
	'/_pos'			=> qr($T{_pos}\]),
	'/_sub'			=> qr($T{_sub}\]),
	'/order'		=> qr(\[/order\])i,
	'/page'			=> qr(\[/page(?:target)?\])i,
	'_accessories'  => qr($T{_accessories}($Spacef[^\]]+)?\]),
	'_alternate'	=> qr($T{_alternate}$Opt\]($Some)),
	'_calc' 		=> qr($T{_calc}\]($Some)),
	'_exec' 		=> qr($T{_exec}$Mand\]($Some)),
	'_filter' 		=> qr($T{_filter}\s+($Some)\]($Some)),
	'_sub'	 		=> qr($T{_sub}$Mand\]($Some)),
	'_change'		=> qr($T{_change}$Mand$Opt\] \s*
						$T{condition}\]
						($Some)
						$T{'/condition'}
						($Some))xi,
	'_code'			=> qr($T{_code}\]),
	'col'			=> qr(\[col(?:umn)?\s+
				 		([^\]]+)
				 		\]
				 		($Some)
				 		\[/col(?:umn)?\] )ix,

	'comment'		=> qr($T{comment}\]
						(?!$All$T{comment}\])
						$Some
						$T{'/comment'})x,

	'_description'	=> qr($T{_description}\]),
	'_discount'		=> qr($T{_discount}(?:\s+(?:quantity=)?"?(\d+)"?)?$Optx\]),
	'_field'		=> qr($T{_field}$Mandf\]),
	'_field_if'		=> qr($T{_field}$Spacef(!?)\s*($Codere)\]($Some)),
	'_field_if_wo'	=> qr($T{_field}$Spacef(!?)\s*($Codere)\]),
	'_increment'	=> qr($T{_increment}\]),
	'_last'			=> qr($T{_last}\]\s*($Some)\s*),
	'_line'			=> qr($T{_line}$Opt\]),
	'_modifier'		=> qr($T{_modifier}$Spacef(\w+)\]),
	'_modifier_if'	=> qr($T{_modifier}$Spacef(!?)$Spaceo($Codere)\]($Some)),
	'_next'			=> qr($T{_next}\]\s*($Some)\s*),
	'_param'		=> qr($T{_param}$Mandf\]),
	'_param_if'		=> qr($T{_param}$Spacef(!?)\s*($Codere)\]($Some)),
	'_pos' 			=> qr($T{_pos}$Spacef(\d+)\]),
	'_pos_if'		=> qr($T{_pos}$Spacef(!?)\s*(\d+)\]($Some)),
	'_price'		=> qr!$T{_price}(?:\s+(\d+))?$Optx\]!,
	'_quantity'		=> qr($T{_quantity}\]),
	'_subtotal'		=> qr($T{_subtotal}$Opt\]),
	'condition'		=> qr($T{condition}$T($Some)$T{'/condition'}),
	'condition_begin' => qr(^\s*$T{condition}\]($Some)$T{'/condition'}),
	'discount_price' => qr($T{discount_price}(?:\s+(\d+))?$Opt\]),
	'discount_subtotal' => qr($T{discount_subtotal}$Opt\]),
	'else_end'		=> qr($T{else}\]($All)$T{'/else'}\s*$),
	'elsif_end'		=> qr($T{elsif}\s+($All)$T{'/elsif'}\s*$),
	'matches'		=> qr($T{matches}\]),
	'modifier_name'	=> qr($T{modifier_name}$Spacef(\w+)\]),
	'more'			=> qr($T{more}\]),
	'more_list'		=> qr($T{more_list}$Optx$Optx$Optx$Optx$Optx\]($Some)$T{'/more_list'}),
	'no_match'   	=> qr($T{no_match}\]($Some)$T{'/no_match'}),
	'on_match'   	=> qr($T{on_match}\]($Some)$T{'/on_match'}),
	'quantity_name'	=> qr($T{quantity_name}\]),
	'then'			=> qr(^\s*$T{then}$T($Some)$T{'/then'}),
);

FINTAG: {
	for(keys %T) {
		$QR{$_} = qr($T{$_})
			if ! defined $QR{$_};
	}
}

undef @th;
undef %T;

sub comment_out {
	my ($bit) = @_;
	$bit =~ s/([[<_])/$Comment_out{$1}/ge;
	return '<!--' . $bit . '-->';
}

sub substitute_image {
	my ($text) = @_;

	my $dir = $CGI::secure											?
		($Vend::Cfg->{ImageDirSecure} || $Vend::Cfg->{ImageDir})	:
		$Vend::Cfg->{ImageDir};

    if ($dir) {
        $$text =~ s#(<i\w+\s+[^>]*?src=")(?!https?:)([^/][^"]+)#
                         $1 . $dir . $2#ige;
        $$text =~ s#(<body\s+[^>]*?background=")(?!https?:)([^/][^"]+)#
                         $1 . $dir . $2#ige;
    }
    if($Vend::Cfg->{ImageAlias}) {
		for (keys %{$Vend::Cfg->{ImageAlias}} ) {
        	$$text =~ s#(<i\w+\s+[^>]*?src=")($_)#
                         $1 . ($Vend::Cfg->{ImageAlias}->{$2} || $2)#ige;
		}
    }
}

#
# This is one entry point for page display.
# Evaluates all of the Interchange tags. Does some basic cache management
# for static page building.
#

sub cache_html {
	my ($html,$wantref) = @_;
	my ($name, @post);
	my ($bit, %post);

	# Comment facility

	reset_calc() unless $Calc_reset;

	$CacheInvalid = 0;
#
#	# Substitute defines from configuration file
#	$html =~ s#\@\@([A-Za-z0-9]\w+[A-Za-z0-9])\@\@#$Global::Variable->{$1}#ge;
#	if ($Vend::Session->{logged_in}) {
#		$html =~ s#__([A-Za-z0-9]\w*?[A-Za-z0-9])__#
#			$Vend::Cfg->{Member}->{$1} || $::Variable->{$1}#ge;
#	}
#	else {
#		$html =~ s#__([A-Za-z0-9]\w*?[A-Za-z0-9])__#$::Variable->{$1}#g;
#	}
#	1 while $html =~ s%$QR{comment}%%go;
#	$html =~ s,$QR{'/page'},</A>,g;
#	$html =~ s,$QR{'/order'},</A>,g;
#	$html =~ s/\[new\]//g;
#	$html =~ s/\[old\]//g;
#

	vars_and_comments(\$html);

	1 while $html =~ s/\[pragma\s+(\w+)(?:\s+(\w+))?\]/$Vend::Cfg->{Pragma}{$1} = $2, ''/ige;

#::logDebug("Vend::Cfg->{Pragma} -> " . ::uneval(\%$Vend::Cfg->{Pragma}));
	my $complete;
	my $full = '';
	my $parse = new Vend::Parse;
	$parse->parse($html);
	while($parse->{_buf}) {
		substitute_image(\$parse->{OUT});
		::response( \$parse->{OUT});
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
}

#
# This is one entry point for page display.
# Evaluates all of the Interchange tags.
#

sub vars_and_comments {
	my $html = shift;
	# Substitute defines from configuration file
	local($^W) = 0;
	$$html =~ s/\[new\]//g;

	if(shift) {
		$$html =~ s#
				^\s*
					\@\@
						([A-Za-z0-9]\w+[A-Za-z0-9])
					\@\@
				\s*$
				#	"<!-- BEGIN GLOBAL template substitution: $1 -->\n"	.
					$Global::Variable->{$1}								.
					"\n<!-- END GLOBAL template substitution: $1 -->"
					#gemx; 
		$$html =~ s#
				^\s*
					__
						([A-Za-z0-9]\w*?[A-Za-z0-9])
					__
				\s*$
				#	"<!-- BEGIN template substitution: $1 -->\n"	.
					$::Variable->{$1}							.
					"\n<!-- END template substitution: $1 -->"
					#gemx; 

	}
	$$html =~ s#\@\@([A-Za-z0-9]\w+[A-Za-z0-9])\@\@#$Global::Variable->{$1}#g;
	$$html =~ s#\@_([A-Za-z0-9]\w+[A-Za-z0-9])_\@#$::Variable->{$1} || $Global::Variable->{$1}#ge
		and
	$$html =~ s#\@_([A-Za-z0-9]\w+[A-Za-z0-9])_\@#$::Variable->{$1} || $Global::Variable->{$1}#ge;
	$$html =~ s#__([A-Za-z0-9]\w*?[A-Za-z0-9])__#$::Variable->{$1}#g;
	# Comment facility
	1 while $$html =~ s%$QR{comment}%%go;

	$$html =~ s,\[/page(?:target)?\],</A>,ig;
	$$html =~ s,\[/order\],</A>,ig;
}

sub interpolate_html {
	my ($html, $wantref) = @_;
	my ($name, @post);
	my ($bit, %post);

	reset_calc() unless $Calc_reset;

	1 while $html =~ s/\[pragma\s+(\w+)(?:\s+(\w+))?\]/$Vend::Cfg->{Pragma}{$1} = $2, ''/ige;

#::logDebug("Vend::Cfg->{Pragma} -> " . ::uneval(\%Vend::Cfg->{Pragma}));

	vars_and_comments(\$html);

	$html =~ s/<!--+\[/[/g
		and $html =~ s/\]--+>/]/g;

	defined $::Variable->{MV_AUTOLOAD}
		and $html =~ s/^/$::Variable->{MV_AUTOLOAD}/;

    # Returns, could be recursive
	my $parse = new Vend::Parse;
	$parse->parse($html);
	while($parse->{_buf}) {
		$parse->parse('');
	}
	substitute_image(\$parse->{OUT});
	return \$parse->{OUT} if defined $wantref;
	return $parse->{OUT};

}

sub filter_value {
	my($filter, $value, $tag) = @_;
	my @filters = Text::ParseWords::shellwords($filter); 
	my @args;
	for (@filters) {
		@args = ();
		if(/%/) {
			$value = sprintf($_, $value);
			next;
		}
		while( s/\.([^.]+)$//) {
			unshift @args, $1;
		}
		if(/^\d+$/) {
			substr($value , $_) = ''
				if length($value) > $_;
			next;
		}
		next unless defined $Filter{$_};
		unshift @args, $value, $tag;
		$value = $Filter{$_}->(@args);
	}
	return $value;
}

sub tag_record {
	my ($opt) = @_;
	my $db = $Vend::Database{$opt->{table}};
	return undef if ! $db;
	$db = $db->ref();
	# This can be called from Perl
	my (@cols, @vals);
	my $hash   = $opt->{col};
	my $filter = $opt->{filter};

	return undef unless defined $opt->{key};
	my $key = $opt->{key};
	return undef unless ref $hash;
	undef $filter unless ref $filter;
	@cols = keys %$hash;
	@vals = values %$hash;

	RESOLVE: {
		my $i = -1;
		for(@cols) {
			$i++;
			if(! defined $db->test_column($_) ) {
				splice (@cols, $i, 1);
				my $tmp = splice (@vals, $i, 1);
				::logError("bad field $_ in record update, value=$_");
				redo RESOLVE;
			}
			next unless defined $filter->{$_};
			$vals[$i] = filter_value($filter->{$_}, $vals[$i], $_);
		}
	}

	if($opt->{new}) {
		$db->set_row($key, '');
	}
	elsif($opt->{create}) {
		$db->set_row($key, '') unless $db->record_exists($key);
	}
	my $settor = $db->row_settor('code', @cols);
	return undef unless $settor;
	my $status = defined $settor->($key, @vals);
	return $status;
}

sub try {
	my ($label, $opt, $body) = @_;
	$label = 'default' unless $label;
	delete $Vend::Session->{try}{$label};
	my $out;
	my $save;
	$save = delete $SIG{__DIE__} if defined $SIG{__DIE__};
	eval {
		$out = interpolate_html($body);
	};
	$SIG{__DIE__} = $save if defined $save;
	$Vend::Session->{try}{$label} = $@ if $@;
	if ($opt->{status}) {
		return $@ ? 0 : 1;
	}
	elsif ($opt->{hide}) {
		return '';
	}
	return $out;
}

sub catch {
	my ($label, $opt, $body) = @_;
	$label = 'default' unless $label;
	my $patt;
	return pull_else($body) 
		unless $patt = $Vend::Session->{try}{$label};
	$body =~ m{\[([^\]]*$patt[^\]]*)\](.*)\[/\1\]}s
		and return $2;
	$body =~ s{\[([^\]]*)\].*\[/\1\]}{}s;
	return $body;
}

# Returns the text of a configurable database field or a 
# variable
sub tag_data {
	my($selector,$field,$key,$opt,$flag) = @_;
	$CacheInvalid = 1 if defined $Vend::Cfg->{DynamicData}->{$selector};

	if ( not defined $Vend::Database{$selector}) {
		if($selector eq 'session') {
			$CacheInvalid = 1;
			if(defined $opt->{value}) {
				$opt->{value} = filter_value($opt->{filter}, $opt->{value}, $field)
					if $opt->{filter};
				if ($opt->{increment}) {
					$Vend::Session->{$field} += (+ $opt->{value} || 1);
				}
				elsif ($opt->{append}) {
					$Vend::Session->{$field} .= $opt->{value};
				}
				else  {
					$Vend::Session->{$field} = $opt->{value};
				}
				return '';
			}
			else {
				my $value = $Vend::Session->{$field} || '';
				$value = filter_value($opt->{filter}, $value, $field)
					if $opt->{filter};
				return $value;
			}
		}
		else {
			logError( "Bad data selector='%s' field='%s' key='%s'",
						$selector,
						$field,
						$key,
			);
			return '';
		}
	}
	elsif($opt->{increment}) {
		$CacheInvalid = 1;
#::logDebug("increment_field: key=$key field=$field value=$opt->{value}");
		return increment_field($Vend::Database{$selector},$key,$field,$opt->{value} || 1);
	}
	elsif (defined $opt->{value}) {
		$CacheInvalid = 1;
		if($opt->{filter}) {
			$opt->{value} = filter_value($opt->{filter}, $opt->{value}, $field);
		}
		return set_field($selector,$key,$field,$opt->{value},$opt->{append});
	}
	elsif ($opt->{hash}) {
		my $db = ::database_exists_ref($selector);
		return $db->row_hash($key);
	}

	#The most common , don't enter a block, no accoutrements
	return database_field($selector,$key,$field);

}

%Filter = (
	
	'value' =>	sub {
					return $::Values->(shift);
				},
	'cgi' =>	sub {
					return $CGI::values(shift);
				},
	'filesafe' =>	sub {
						return Vend::Util::escape_chars(shift);
				},
	'currency' =>	sub {
						my ($val, $tag, $locale) = @_;
						my $convert = $locale ? 1 : 0;
						return Vend::Util::currency(
								$val,
								0,
								$convert,
								{ locale => $locale }
							);
				},
	'mailto' =>	sub {
						my ($val,$tag,@arg) = @_;
						my $out = qq{<A HREF="mailto:$val">};
						my $anchor = $val;
						if(@arg) {
							$anchor = join " ", @arg;
						}
						$out .= "$anchor</A>";
				},
	'tt' =>			sub { return '<TT>' . shift(@_) . '</TT>'; },
	'pre' =>		sub { return '<PRE>' . shift(@_) . '</PRE>'; },
	'bold' =>		sub { return '<B>' . shift(@_) . '</B>'; },
	'italics' =>	sub { return '<I>' . shift(@_) . '</I>'; },
	'strikeout' =>	sub { return '<strike>' . shift(@_) . '</strike>'; },
	'small' =>		sub { return '<small>' . shift(@_) . '</small>'; },
	'large' =>		sub { return '<large>' . shift(@_) . '</large>'; },
	'commify' =>	sub {
						my ($val, $tag, $places) = @_;
						$places = 2 unless defined $places;
						$val = sprintf("%.${places}f", $val) if $places;
						return Vend::Util::commify($val);
				},
	'lookup' =>	sub {
						my ($val, $tag, $table, $column) = @_;
						return tag_data($table, $column, $val) || $val;
				},
	'uc' =>		sub {
					use locale;
					return uc(shift);
				},
	'date_change' =>		sub {
					my $val = shift;
					$val =~ s/\0+//g;
					return $val 
						unless $val =~ m:(\d+)[-/]+(\d+)[-/]+(\d+):;
					my ($yr, $mon, $day) = ($3, $1, $2);
					if(length($yr) < 4) {
						$yr =~ s/^0//;
						$yr = $yr < 50 ? $yr + 2000 : $yr + 1900;
					}
					$mon =~ s/^0//;
					$day =~ s/^0//;
					$val = sprintf("%d%02d%02d", $yr, $mon, $day);
					return $val;
				},
	'null_to_space' =>		sub {
					my $val = shift;
					$val =~ s/\0+/ /g;
					return $val;
				},
	'null_to_comma' =>		sub {
					my $val = shift;
					$val =~ s/\0+/,/g;
					return $val;
				},
	'null_to_colons' =>		sub {
					my $val = shift;
					$val =~ s/\0+/::/g;
					return $val;
				},
	'space_to_null' =>		sub {
					my $val = shift;
					$val =~ s/\s+/\0/g;
					return $val;
				},
	'colons_to_null' =>		sub {
					my $val = shift;
					$val =~ s/::/\0/g;
					return $val;
				},
	'last_non_null' =>		sub {
					my @some = reverse split /\0+/, shift;
					for(@some) {
						return $_ if length $_;
					}
					return '';
				},
	'nullselect' =>		sub {
					my @some = split /\0+/, shift;
					for(@some) {
						return $_ if length $_;
					}
					return '';
				},
	'lc' =>		sub {
					use locale;
					return lc(shift);
				},
	'digits_dot' => sub {
					my $val = shift;
					$val =~ s/[^\d.]+//g;
					return $val;
				},
	'backslash' => sub {
					my $val = shift;
					$val =~ s/\\+//g;
					return $val;
				},
	'crypt' => sub {
					my $val = shift;
					return crypt($val, ::random_string(2));
				},
	'namecase' => sub {
					use locale;
					my $val = shift;
					$val =~ s/([A-Z]\w+)/\L\u$1/g;
					return $val;
				},
	'name' => sub {
					my $val = shift;
					return $val unless $val =~ /,/;
					my($last, $first) = split /\s*,\s*/, $val, 2;
					return "$first $last";
				},
	'digits' => sub {
					my $val = shift;
					$val =~ s/\D+//g;
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
	'sql'		=> sub {
					my $val = shift;
					$val =~ s:':'':g; # '
					return $val;
				},
	'text2html' => sub {
					my $val = shift;
					$val =~ s|\r?\n\r?\n|<P>|;
					$val =~ s|\r?\n|<BR>|;
					return $val;
				},
	'urlencode' => sub {
					my $val = shift;
					$val =~ s|[^\w:]|sprintf "%%%02x", ord $1|eg;
					return $val;
				},
	'pagefile' => sub {
					$_[0] =~ s:^[./]+::;
					return $_[0];
				},
	'strftime' => sub {
					return scalar localtime(shift);
				},
	'entities' => sub {
					return HTML::Entities::encode(shift);
				},
	);

sub input_filter_do {
	my($varname, $opt, $routine) = @_;
#::logDebug("filter var=$varname opt=" . ::uneval($opt));
	return undef unless defined $CGI::values{$varname};
#::logDebug("before filter=$CGI::values{$varname}");
	$routine = $opt->{routine} || ''
		if ! $routine;
	if($routine =~ /\S/) {
		$Vend::Interpolate::mv_filter_value = $CGI::values{$varname};
		$Vend::Interpolate::mv_filter_name = $varname;
		$routine = interpolate_html($routine);
		$CGI::values{$varname} = tag_calc($routine);
	}
	if ($opt->{op}) {
		$CGI::values{$varname} = filter_value($opt->{op}, $CGI::values{$varname}, $varname);
	}
#::logDebug("after filter=$CGI::values{$varname}");
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
	local($^W) = 0;
	undef $@;
#::logDebug("cond: base=$base term=$term op=$operator comp=$comp\n");
#::logDebug (($reverse ? '!' : '') . "cond: base=$base term=$term op=$operator comp=$comp");
	my %stringop = ( qw! eq 1 ne 1 gt 1 lt 1! );

	if(defined $stringop{$operator}) {
		$comp =~ /^(["']).*\1$/ or
		$comp =~ /^qq?([{(]).*[})]$/ or
		$comp =~ /^qq?(\S).*\1$/ or
		(index ($comp, '}') == -1 and $comp = 'q{' . $comp . '}')
			or
		(index ($comp, '!') == -1 and $comp = 'q{' . $comp . '}')
	}

#::logDebug ("cond: base=$base term=$term op=$operator comp=$comp\n");


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
	elsif($base eq 'variable') {
		$CacheInvalid = 1;
		$op =	qq%$::Variable->{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base =~ /^value/) {
		$CacheInvalid = 1;
		$op =	qq%$::Values->{$term}%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'explicit') {
		undef $noop;
		$status = $ready_safe->reval($comp);
	}
    elsif($base eq 'items') {
        $CacheInvalid = 1;
		my $cart;
        if($term) {
        	$cart = $::Carts->{$term} || undef;
		}
		else {
			$cart = $Vend::Items;
		}
		$op =   defined $cart ? scalar @{$cart} : 0;

        $op .=  qq% $operator $comp%
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
#::logDebug ("tag_if db=$d fld=$f key=$k\n");
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'field') {
		my($f,$k) = split /::/, $term;
		$op = product_field($f,$k);
#::logDebug("tag_if field fld=$f key=$k\n");
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}
	elsif($base eq 'discount') {
		$CacheInvalid = 1;
		$op =	qq%$Vend::Session->{discount}->{$term}%;
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
		foreach $i (@{$::Carts->{$operator}}) {
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
	elsif($base =~ /^errors?$/) {
		my $err_ref = $Vend::Session->{errors}
			or return '';
		return scalar (keys %$err_ref);
	}
	elsif($base eq 'validcc') {
		$CacheInvalid = 1;
		no strict 'refs';
		$status = ::validate_whole_cc($term, $operator, $comp);
	}
    elsif($base eq 'config') {
		$op = qq%$Vend::Cfg->{$term}%;
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
	else {
		$op =	qq%$term%;
		$op = "q{$op}" unless defined $noop;
		$op .=	qq%	$operator $comp%
				if defined $comp;
	}

#::logDebug("noop='$noop' op='$op'");

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
#::logDebug("if status=$status");

	return $status;
}

sub find_close_square {
    my $chunk = shift;
    my $first = index($chunk, ']');
    return undef if $first < 0;
    my $int = index($chunk, '[');
    my $pos = 0;
    while( $int > -1 and $int < $first) {
        $pos   = $int + 1;
        $first = index($chunk, ']', $first + 1);
        $int   = index($chunk, '[', $pos);
    }
    return substr($chunk, 0, $first);
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

	$body =~ s#$QR{then}##o
		and $then = $1;

	$body =~ s#$QR{else_end}##o
		and $else = $1;

	$body =~ s#$QR{elsif_end}##o
		and $elsif = $1;

	$body = $then if defined $then;

	return($body, $elsif, $else, @addl);
}

sub tag_if {
	my ($cond,$body) = @_;
#::logDebug("Called tag_if: $cond\n$body\n");
	my ($base, $term, $op, $operator, $comp);
	my ($else, $elsif, $else_present, @addl);

	($base, $term, $operator, $comp) = split /\s+/, $cond, 4;
	if ($base eq 'explicit') {
		$body =~ s#$QR{condition_begin}##o
			and ($comp = $1, $operator = '');
	}
#::logDebug("tag_if: base=$base term=$term op=$operator comp=$comp");

	$else_present = 1 if
		$body =~ /\[[EeTtAaOo][hHLlNnRr][SsEeDd\s]/;

	($body, $elsif, $else, @addl) = split_if($body)
		if $else_present;

#::logDebug("Additional ops found:\n" . join("\n", @addl) ) if @addl;

	unless(defined $operator) {
		undef $operator;
		undef $comp;
	}

	my $status = conditional ($base, $term, $operator, $comp, @addl);

#::logDebug("Result of if: $status\n");

	my $out;
	if($status) {
		$out = $body;
	}
	elsif ($elsif) {
		$else = '[else]' . $else . '[/else]' if $else;
		$elsif =~ s#(.*?)$QR{'/elsif'}(.*)#$1${2}[/elsif]#s;
		$out = '[if ' . $elsif . $else . '[/if]';
	}
	elsif ($else) {
		$out = $else;
	}
	return $out;
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
	my($name, $type, $default, $opt, @opts) = @_;

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
	my($name, $type, $default, $opt, @opts) = @_;

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
	my($name, $type, $default, $opt, @opts) = @_;

	my ($inc, $select, $xlt, $template, $header, $footer, $row_hdr, $row_ftr);

	$header = $template = $footer = $row_hdr = $row_ftr = '';

	my $font;
	my $variant = ($type =~ /check/i) ? 'checkbox' : 'radio';
	if ($type  =~ /font(?:size)?[\s_]*(-?\d)/i ) {
		$font = qq{<FONT SIZE="$1">};
	}

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
<TD>$font<INPUT TYPE="$variant" NAME="$name" VALUE="__VALUE__"__SEL__></TD><TD>__LABEL__</TD>
EOF
		$template .= '</TR>' unless $inc;
	}
	elsif ($type  =~ /right[\s_]*(\d?)/i ) {
		$inc = $1 || undef;
		$header = '<TABLE>';
		$footer = '</TABLE>';
		$template = '<TR>' unless $inc;
		$template .= <<EOF;
<TD>${font}__LABEL__</TD><TD><INPUT TYPE="$variant" NAME="$name" VALUE="__VALUE__"__SEL__></TD>
EOF
		$template .= '</TR>' unless $inc;
	}
	else {
		$template = <<EOF;
<INPUT TYPE="$variant" NAME="$name" VALUE="__VALUE__"__SEL__>&nbsp;__LABEL__
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

		if(length $value) {
			my $regex	= $opt->{contains}
						? qr/\Q$value\E/ 
						: qr/\b\Q$value\E\b/;
			$default =~ $regex and $select = "CHECKED";
		}

		$label =~ s/ /&nbsp;/g if $xlt;

		$run =~ s/__SEL__/ $select/;
		$run =~ s/__VALUE__/$value/;
		$run =~ s/__LABEL__/$label/;
		$run .= '</TR>' if $inc && ! ($i % $inc);
		
	}
	$run .= $footer;
}

sub tag_price {
	my($code,$ref) = @_;
	my $amount = Vend::Data::item_price($ref,$ref->{quantity} || 1);
	$amount = discount_price($ref,$amount, $ref->{quantity})
			if $ref->{discount};
	return currency( $amount, $ref->{noformat} );
}

sub tag_accessories {
	my($code,$extra,$opt,$item) = @_;

	# Had extra if got here
#::logDebug("tag_accessories: code=$code opt=" . ::uneval_it($opt) . " item=" . ::uneval($item) . " extra=$extra");
	my($attribute, $type, $field, $db, $name, $outboard, $passed);
	$opt = {} if ! $opt;
	if($extra) {
		$extra =~ s/^\s+//;
		$extra =~ s/\s+$//;
		@{$opt}{qw/attribute type column table name outboard passed/} =
			split /\s*,\s*/, $extra;
	}
	($attribute, $type, $field, $db, $name, $outboard, $passed) = 
		@{$opt}{qw/attribute type column table name outboard passed/};

	my $p = $opt->{prepend} || '';
	my $a = $opt->{append} || '';

	$type = 'select' unless $type;
	$field = $attribute unless $field;
	$code = $outboard if $outboard;
#::logDebug("accessory db=$db type=$type field=$field attr=$attribute name=$name passed=$passed");

	my $data;
	if($passed) {
		$data = $passed;
	}
	else {
		$data = $db ? tag_data($db, $field, $code) : product_field($field,$code);
	}

	unless ($data || $type =~ /^text|^hidden/i) {
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

	return qq|$p<INPUT TYPE="hidden" NAME="$name" VALUE="$attrib_value">$a|
		if "\L$type" eq 'hidden';
	return qq|$p<INPUT TYPE="hidden" NAME="$name" VALUE="$attrib_value">$attrib_value$a|
		if $type =~ /hidden/;
	if($type =~ /^text/i) {
		HTML::Entities::encode($attrib_value);
		return qq|$p<TEXTAREA NAME="$name" ROWS=$1 COLS=$2>$attrib_value</TEXTAREA>$a|
			if "\L$type" =~ /^textarea_(\d+)_(\d+)$/;
		return qq|$p<INPUT TYPE=text NAME="$name" SIZE=$1 VALUE="$attrib_value">$a|
			if "\L$type" =~ /^text_(\d+)$/;
		return qq|$p<INPUT TYPE=text NAME="$name" SIZE=60 VALUE="$attrib_value">$a|
			if "\L$type" =~ /^text/;
	}

	my ($default, $label, $select, $value, $run);
	my @opts = split /\s*,\s*/, $data;

	if($item) {
		$default = $item->{$attribute};
	}
	elsif ($name) {
		$default = $::Values->{$name};
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
		return $p . build_accessory_box($name, $type, $default, $opt, @opts) . $a;
	}
	elsif($type =~ /^textarea/i) {
		return $p . build_accessory_textarea($name, $type, $default, $opt, @opts) . $a;
	}
	elsif($type =~ /^combo[ _]*(?:(\d+)(?:[ _]+(\d+))?)?/i) {
		$opt->{rows} = $opt->{rows} || $1 || 1;
		$opt->{cols} = $opt->{cols} || $2 || 16;
		unless($opts[0] =~ /^=/) {
			unshift @opts, ($opt->{new} || "=&lt;-- New");
		}
		my $out = qq|<INPUT TYPE=text NAME="$name" SIZE=$opt->{cols} VALUE="">|;
		$out .= build_accessory_select($name, $type, $default, $opt, @opts);
		return "$p$out$a";
	}
	elsif($type =~ /^reverse_combo[ _]*(?:(\d+)(?:[ _]+(\d+))?)?/i) {
		$opt->{rows} = $opt->{rows} || $1 || 1;
		$opt->{cols} = $opt->{cols} || $2 || 16;
		unless($opts[0] =~ /^=/) {
			unshift @opts, ($opt->{new} || "=Current --&gt;");
		}
#warn("building reverse combo");
		my $out = build_accessory_select($name, $type, $default, $opt, @opts);
		$out .= qq|<INPUT TYPE=text NAME="$name" SIZE=$opt->{cols} VALUE="$default">|;
		return "$p$out$a";
	}
	else {
		return $p . build_accessory_select($name, $type, $default, $opt, @opts) . $a;
	}

}

# MVASP

sub mvasp {
	my ($tables, $opt, $text) = @_;
	my @code;
	$opt->{no_return} = 1 unless defined $opt->{no_return};
	
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
#::logDebug("ASP CALL:\n$asp\n");
	return tag_perl ($tables, $opt, $asp);
}

# END MVASP

use vars qw/$ready_safe/;
use vars qw/$Calc_initialized/;
use vars qw/$Items/;

sub tag_perl {
	my ($tables, $opt,$body) = @_;
	my ($result,@share);
#::logDebug("tag_perl MVSAFE=$MVSAFE::Safe opts=" . ::uneval($opt));

	return undef if $MVSAFE::Safe;
#::logDebug("tag_perl: tables=$tables opt=" . ::uneval($opt) . " body=$body");
#::logDebug("tag_perl initialized=$Calc_initialized: carts=" . ::uneval($::Carts));
	if($opt->{subs} || (defined $opt->{arg} and $opt->{arg} =~ /\bsub\b/)) {
		no strict 'refs';
		for(keys %{$Global::GlobalSub}) {
#::logDebug("tag_perl share subs: GlobalSub=$_");
			next if defined $Global::AdminSub->{$_}
				and ! $Global::AllowGlobal{$Vend::Cfg->{CatalogName}};
			*$_ = \&{$Global::GlobalSub->{$_}};
			push @share, "&$_";
		}
		for(keys %{$Vend::Cfg->{Sub} || {}}) {
#::logDebug("tag_perl share subs: Sub=$_");
			*$_ = \&{$Vend::Cfg->{Sub}->{$_}};
			push @share, "&$_";
		}
	}

	if($tables) {
		my (@tab) = grep /\S/, split /\s+/, $tables;
		for(@tab) {
#::logDebug("tag_perl: priming table $_, current=$Db{$_}");
			next if $Db{$_};
#::logDebug("tag_perl: getting ref $_");
			my $db = Vend::Data::database_exists_ref($_);
#::logDebug("tag_perl: ref returned $db");
			next unless $db;
#::logDebug("tag_perl: need to init table $_, ref=$db");
			$db = $db->ref();
			if($hole) {
#::logDebug("tag_perl: wrapped table $_ db=$db");
			$db = $db->ref();
#::logDebug("recall db: db=$db");
				$Sql{$_} = $hole->wrap($db->[$Vend::Table::DBI::DBI])
					if $db =~ /::DBI/;
				$Sql{$_} = $hole->wrap($db->[$Vend::Table::LDAP::TIE_HASH])
					if $db =~ /::LDAP/;
				$Db{$_} = $hole->wrap($db);
			}
			else {
				$Sql{$_} = $db->[$Vend::Table::DBI::DBI]
					if $db =~ /::DBI/;
				$Db{$_} = $db;
			}
		}
	}

	#init_calc() if ! $Calc_initialized;
	init_calc() if ! $Calc_initialized;
	$ready_safe->share(@share) if @share;

	$MVSAFE::Safe = 1;
	if (
		$opt->{global}
			and
		$Global::AllowGlobal->{$Vend::Cfg->{CatalogName}}
		)
	{
		$MVSAFE::Safe = 0 unless $MVSAFE::Unsafe;
	}

	$body = readfile($opt->{file}, $Global::NoAbsolute) . $body
		if $opt->{file};

	$body =~ tr/\r//d if $Global::Windows;

	if(! $MVSAFE::Safe) {
		$result = eval($body);
	}
	else {
		$result = $ready_safe->reval($body);
	}
	if ($@) {
#::logDebug("tag_perl failed $@");
		my $msg = $@;
		logError( "Safe: %s\n%s\n" , $msg, $body );
		logGlobal({}, "Safe: %s\n%s\n" , $msg, $body );
		return $opt->{failure};
	}
#::logDebug("tag_perl initialized=$Calc_initialized: carts=" . ::uneval($::Carts));

	undef $MVSAFE::Safe;
	if ($opt->{no_return}) {
		$Vend::Session->{mv_perl_result} = $result;
		$result = join "", @Vend::Document::Out;
		@Vend::Document::Out = ();
	}
#::logDebug("tag_perl succeeded result=$result\nEND");
	return $result;
}

sub show_tags {
	my($type, $opt, $text) = @_;

	$type = 'html minivend' unless $type;

	if ($type =~ /minivend/i) {
		$text =~ s/\[/&#91;/g;
	}
	if($type =~ /html/i) {
		$text =~ s/\</&lt;/g;
	}
	return $text;
}

sub pragma {
	my($pragma, $opt, $text) = @_;
	$pragma =~ s/\W+//g;

	my $value = defined $opt->{value} ? $opt->{value} : 1;
	if(! defined $opt->{value} and $text =~ /\S/) {
		$value = $text;
	}

	$Vend::Cfg->{Pragma}{$pragma} = $value;
	if($pragma eq 'no_html_parse') {
		$Vend::Cfg->{Pragma}{no_html_parse} = $value;
		$Vend::Parse::Find_tag	= $value
									?  qr{^([^[]+)}
									:  qr{^([^[<]+)}
									;
	}
	return;
}

sub flag {
	my($flag, $opt, $text) = @_;
	$flag = lc $flag;

	if(! $text) {
		($flag, $text) = split /\s+/, $flag;
	}
	my $value = defined $opt->{value} ? $opt->{value} : 1;
	my $fmt = $opt->{status} || '';
	my @status;

#::logDebug("tag flag=$flag text=$text value=$value opt=". ::uneval($opt));
	if($flag eq 'write' || $flag eq 'read') {
		my $arg = $opt->{table} || $text;
		$value = 0 if $flag eq 'read';
		my (@args) = Text::ParseWords::shellwords($arg);
		my $dbname;
		foreach $dbname (@args) {
#::logDebug("tag flag write $dbname=$value");
			$Vend::WriteDatabase{$dbname} = $value;
			$Vend::Cfg->{DynamicData}->{$dbname} = $value;
		}
	}
	elsif($flag eq 'build') {
		$Vend::ForceBuild = $value;
		$text = $opt->{name} if $opt->{name};
		if($text) {
			$Vend::ScanName = Vend::Util::escape_chars(interpolate_html($text));
		}
		@status = ("Set build flag: %s name=%s", $value, $Vend::ScanName);
	}
	elsif($flag eq 'checkhtml') {
		$value = $text if ! defined $opt->value;
		$Vend::CheckHTML = $value;
		@status = ("Set CheckHTML flag: %s", $value);
	}
	else {
		@status = ("Unknown flag operation '%s', ignored.", $flag);
		$status[0] = $opt->{status} if $opt->{status};
		logError( @status );
	}
	return '' unless $opt->{show};
	$status[0] = $opt->{status} if $opt->{status};
	return errmsg(@status);
}

sub tag_export {
	my ($args, $opt, $text) = @_;
	$opt->{base} = $opt->{table} || $opt->{database} || undef
		unless defined $opt->{base};
	unless (defined $opt->{base}) {
		@{$opt}{ qw/base file type/ } = split /\s+/, $args;
	}
	if($opt->{delete}) {
		undef $opt->{delete} unless $opt->{verify};
	}
#::logDebug("exporting " . join (",", @{$opt}{ qw/base file type field delete/ }));
	my $status = Vend::Data::export_database(
			@{$opt}{ qw/base file type/ }, $opt,
		);
	return $status unless $opt->{hide};
	return '';
}

sub export {
	my ($table, $opt, $text) = @_;
	if($opt->{delete}) {
		undef $opt->{delete} unless $opt->{verify};
	}
#::logDebug("exporting " . join (",", @{$opt}{ qw/table file type field delete/ }));
	my $status = Vend::Data::export_database(
			@{$opt}{ qw/table file type/ }, $opt,
		);
	return $status unless $opt->{hide};
	return '';
}

sub mime {
	my ($option, $opt, $text) = @_;
	my $id;

	my $out;

#::logDebug("mime call, opt=" . ::uneval($opt));
	$Vend::TIMESTAMP = POSIX::strftime("%y%m%d%H%M%S", localtime())
		unless defined $Vend::TIMESTAMP;

	$::Instance->{MIME_BOUNDARY} =
							$::Instance->{MIME_TIMESTAMP} . '-' .
							$Vend::SessionID . '-' .
							$Vend::Session->{pageCount} . 
							':=' . $$
		unless defined $::Instance->{MIME_BOUNDARY};

	my $msg_type = $opt->{attach_only} ? "multipart/mixed" : "multipart/alternative";
	if($option eq 'reset') {
		undef $::Instance->{MIME_TIMESTAMP};
		undef $::Instance->{MIME_BOUNDARY};
		$out = '';
	}
	elsif($option eq 'boundary') {
		$out = "--$::Instance->{MIME_BOUNDARY}";
	}
	elsif($option eq 'id') {
		$::Instance->{MIME} = 1;
		$out =	_mime_id();
	}
	elsif($option eq 'header') {
		$id = _mime_id();
		$out = <<EndOFmiMe;
MIME-Version: 1.0
Content-Type: $msg_type; BOUNDARY="$::Instance->{MIME_BOUNDARY}"
Content-ID: $id
EndOFmiMe
	}
	elsif ( $text !~ /\S/) {
		$out = '';
	}
	else {
		$id = _mime_id();
		$::Instance->{MIME} = 1;
		my $desc = $opt->{description} || $option;
		my $type = $opt->{type} || 'TEXT/PLAIN; CHARSET=US-ASCII';
		$out = <<EndOFmiMe;
--$::Instance->{MIME_BOUNDARY}
Content-Type: $type
Content-ID: $id
Content-Description: $desc

$text
EndOFmiMe

	}
#::logDebug("tag mime returns:\n$out");
	return $out;
}

sub log {
	my($file, $opt, $data) = @_;
	my(@lines);
	my(@fields);

	my $status;

	$file = $opt->{file} || $Vend::Cfg->{LogFile};
	$file = Vend::Util::escape_chars($file);

	unless($opt->{process} =~ /\bnostrip\b/i) {
		$data =~ s/\r\n/\n/g;
		$data =~ s/^\s+//;
		$data =~ s/\s+$/\n/;
	}

	my ($delim, $record_delim);
	for(qw/delim record_delim/) {
		next unless defined $opt->{$_};
		$opt->{$_} = $ready_safe->reval(qq{$opt->{$_}});
	}
	if($opt->{type} =~ /^text/) {
		$status = Vend::Util::writefile($file, $data, $opt);
	}
	elsif($opt->{type} =~ /^\s*quot/) {
		$record_delim = $opt->{record_delim} || "\n";
		@lines = split /$record_delim/, $data;
		for(@lines) {
			@fields = Text::ParseWords::shellwords $_;
			$status = logData($file, @fields)
				or last;
		}
	}
	elsif($opt->{type} =~ /^error/) {
		if($opt->{file}) {
			$data = format_log_msg($data) unless $data =~ s/^\\//;;
			$status = Vend::Util::writefile($file, $data, $opt);
		}
		else {
			$status = Vend::Util::logError($data);
		}
	}
	else {
		$record_delim = $opt->{record_delim} || "\n";
		$delim = $opt->{delimiter} || "\t";
		@lines = split /$record_delim/, $data;
		for(@lines) {
			@fields = split /$delim/, $_;
			$status = logData($file, @fields)
				or last;
		}
	}

	return $status unless $opt->{hide};
	return '';
}

sub _mime_id {
	'<Interchange.' . $::VERSION . '.' .
	$Vend::TIMESTAMP . '.' .
	$Vend::SessionID . '.' .
	++$Vend::Session->{pageCount} . '@' .
	$Vend::Cfg->{VendURL} . '>';
}

sub http_header {
	my ($op, $opt, $text) = @_;
	$text =~ s/^\s+//;
	if($Vend::StatusLine and ! $opt->{replace}) {
		$Vend::StatusLine =~ s/\s+$/\r\n/;
		$Vend::StatusLine .= $text;
	}
	else {
		$Vend::StatusLine = $text;
	}
	return $text if $opt->{show};
	return '';
}

sub mvtime {
	my ($locale, $opt, $fmt) = @_;
	my $current;

	if($locale) {
		$current = POSIX::setlocale(&POSIX::LC_TIME);
		POSIX::setlocale(&POSIX::LC_TIME, $locale);
	}

	my $now = $opt->{time} || time();
	$fmt = '%Y%m%d' if $opt->{sortable};

	if($opt->{adjust}) {
		$opt->{adjust} =~ s/00$//;
        $opt->{adjust} =~ s/^(-)?[0+]/$1/;
        $now += (60 * 60) * $opt->{adjust};
	}
    my $out = $opt->{gmt} ? ( POSIX::strftime($fmt, gmtime($now)    ))
                          : ( POSIX::strftime($fmt, localtime($now) ));
	POSIX::setlocale(&POSIX::LC_TIME, $current) if defined $current;
	return $out;
}

use vars qw/ %Tag_op_map /;
%Tag_op_map = (
			PRAGMA	=> \&pragma,
			FLAG	=> \&flag,
			LOG		=> \&log,
			TIME	=> \&mvtime,
			HEADER	=> \&http_header,
			EXPORT	=> \&tag_export,
			TOUCH	=> sub {1},
			EACH	=> sub {
							my $table = shift;
							my $opt = shift;
							$opt->{search} = "ra=yes\nst=db\nml=100000\nfi=$table";
#::logDebug("tag each: table=$table opt=" . ::uneval($opt));
							return tag_loop_list('', $opt, shift);
						},
			MIME	=> \&mime,
			SHOW_TAGS	=> \&show_tags,
		);

sub do_tag {
	my $op = uc $_[0];
#::logDebug("tag op: op=$op opt=" . ::uneval(\@_));
	return $_[3] if !  defined $Tag_op_map{$op};
	shift;
#::logDebug("tag args now: op=$op opt=" . ::uneval(\@_));
	return &{$Tag_op_map{$op}}(@_);
}

# Returns the text of a user entered field named VAR.
sub tag_cgi {
    my($var, $opt) = @_;
    my($value);

	local($^W) = 0;
	$CGI::values->{$var} = $opt->{set} if defined $opt->{set};
	$value = $CGI::values{$var} || '';
    if ($value) {
		# Eliminate any Interchange tags
		$value =~ s~<([A-Za-z]*[^>]*\s+[Mm][Vv]\s*=\s*)~&lt;$1~g;
		$value =~ s/\[/&#91;/g;
    }
	if($opt->{filter}) {
		$value = filter_value($opt->{filter}, $value, $var);
		$CGI::values{$var} = $value unless $opt->{keep};
	}
    return $value unless $opt->{hide};
    return '';
}

# Returns the text of a user entered field named VAR.
sub tag_value_extended {
    my($var, $opt) = @_;

	my $yes = $opt->{yes} || 1;
	my $no = $opt->{'no'} || '';

	if($opt->{test}) {
		$opt->{test} =~ /(?:is)?file/i
			and
			return defined $CGI::file{$var} ? $yes : $no;
		$opt->{test} =~ /defined/i
			and
			return defined $CGI::values{$var} ? $yes : $no;
		return length $CGI::values{$var}
			if $opt->{test} =~ /length|size/i;
		return '';
	}

	my $val = $CGI::values{$var} || $::Values->{$var} || return undef;
	
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
#::logDebug(">$file \$CGI::file{$var}" . ::uneval($opt)); 
		Vend::Util::writefile(">$file", \$CGI::file{$var}, $opt)
			and return $opt->{yes} || '';
		return $opt->{'no'} || '';
	}

	my $joiner;
	if (defined $opt->{joiner}) {
		$joiner = $opt->{joiner};
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
	if (!ref $val) {
		@ary = split /\0/, $val;
	}
	elsif($val =~ /ARRAY/) {
		@ary = @$val;
	}
	else {
		::logError( "value-extended %s: passed non-scalar, non-array object", $var);
	}

	return join " ", 0 .. $#ary if $opt->{elements};

	eval {
		@ary = @ary[$ready_safe->reval( $index eq '*' ? "0 .. $#ary" : $index )];
	};
	logError("value-extend $var: bad index") if $@;

	if($opt->{filter}) {
		for(@ary) {
			$_ = filter_value($opt->{filter}, $_, $var);
		}
	}
	return join $joiner, @ary;
}

sub initialize_banner_directory {
	my ($dir, $category, $opt) = @_;
	mkdir $dir, 0777 if ! -d $dir;
	my $t = $opt->{table} || 'banner';
	my $c_field;
	my $append = '';
	if($category) {
		$append = ' AND ';
		$append .= ($opt->{c_field} || 'category');
		$category =~ s/'/''/g;
		$append .= " = '$category'";
	}
	my $db = database_exists_ref($t);
	if(! $db) {
		my $weight_file = "$dir/total_weight";
		return undef if -f $weight_file;
		$t = "no banners db $t\n";
		Vend::Util::writefile( $weight_file, $t, $opt);
		::logError($t);
		return undef;
	}
	my $w_field = $opt->{w_field} || 'weight';
	my $b_field = $opt->{b_field} || 'banner';
	my $q = "select $w_field, $b_field from $t where $w_field >= 1$append";
#::logDebug("banner query: $q");
	my $banners = $db->query({
							query => $q,
							st => 'db',
						});
	my $i = 0;
#::logDebug("banner query result: " . ::uneval($banners));
	for(@$banners) {
		my ($weight, $text) = @$_;
		for(1 .. $weight) {
			Vend::Util::writefile(">$dir/$i", $text, $opt);
			$i++;
		}
	}
	Vend::Util::writefile(">$dir/total_weight", $i, $opt);
}

sub tag_weighted_banner {
	my ($category, $opt) = @_;
	my $dir = catfile($Vend::Cfg->{ScratchDir}, 'Banners');
	mkdir $dir, 0777 if ! -d $dir;
	if($category) {
		my $c = $category;
		$c =~ s/\W//g;
		$dir .= "/$c";
	}
#::logDebug("banner category=$category dir=$dir");
	my $statfile =	$Vend::Cfg->{ConfDir};
	$statfile .= "/status.$Vend::Cfg->{CatalogName}";
#::logDebug("banner category=$category dir=$dir statfile=$statfile");
	my $start_time;
	if($opt->{once}) {
		$start_time = 0;
	}
	elsif(! -f $statfile) {
		Vend::Util::writefile( $statfile, "banners initialized " . time() . "\n");
		$start_time = time();
	}
	else {
		$start_time = (stat(_))[9];
	}
	my $weight_file = "$dir/total_weight";
#::logDebug("banner category=$category dir=$dir statfile=$statfile wfile=$weight_file");
	initialize_banner_directory($dir, $category, $opt)
		if  (	
				! -f $weight_file
					or
				(stat(_))[9] < $start_time
			);
	my $n = int( rand( readfile($weight_file) ) );
#::logDebug("weight total n=$n, file=$dir/$n");
	return Vend::Util::readfile("$dir/$n");
}

sub tag_banner {
    my ($place, $opt) = @_;

	return tag_weighted_banner($place, $opt) if $opt->{weighted};

#::logDebug("banner, place=$place opt=" . ::uneval_it($opt));
	my $table	= $opt->{table}		|| 'banner';
	my $r_field	= $opt->{r_field}	|| 'rotate';
	my $b_field	= $opt->{b_field}	|| 'banner';
	my $sep		= $opt->{separator} || ':';
	my $delim	= $opt->{delimiter} || "{or}";
	$place = 'default' if ! $place;
    my $totrot;
    do {
		my $banner_data;
        $totrot = tag_data($table, $r_field, $place);
        if(! length $totrot) {
			# No banner present
            unless ($place =~ /$sep/ or $place eq 'default') {
				$place = 'default';
				redo;
			}
        }
        elsif ($totrot) {
            my $current = $::Scratch->{"rotate_$place"}++ || 0;
            my $data = tag_data($table, $b_field, $place);
            my(@banners) = split /\Q$delim/, $data;
            return '' unless @banners;
            return $banners[$current % scalar(@banners)];
        }
        else {
            return tag_data($table, $b_field, $place);
        }
    } while $place =~ s/(.*)$sep.*/$1/;
	return;
}

# Returns the text of a user entered field named VAR.
sub tag_value {
    my($var,$opt) = @_;
    my($value);

	local($^W) = 0;
	$::Values->{$var} = $opt->{set} if defined $opt->{set};
	$value = defined $::Values->{$var} ? ($::Values->{$var}) : '';
    if ($value) {
		# Eliminate any Interchange tags
		$value =~ s~<([A-Za-z]*[^>]*\s+[Mm][Vv]\s*=\s*)~&lt;$1~g;
		$value =~ s/\[/&#91;/g;
    }
	if($opt->{filter}) {
		$value = filter_value($opt->{filter}, $value, $var);
		$::Values->{$var} = $value unless $opt->{keep};
	}
	$::Scratch->{$var} = $value if $opt->{scratch};
	return '' if $opt->{hide};
    return $opt->{default} if ! $value and defined $opt->{default};
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
    my($var, $default, $opt) = @_;
	$opt->{default} = !(length $default) ? 'default' : $default;
    return tag_value($var, $opt);
}

sub esc {
	my $string = shift;
	$string =~ s!(\W)!'%' . sprintf '%02x', ord($1)!eg;
	return $string;
}

# Escapes a scan reliably in three different possible ways
sub escape_scan {
	my ($scan, $ref) = @_;
#::logDebug("escape_scan: scan=$scan");
	if (ref $scan) {
		for(@$scan) {
			my $add = '';
			$_ = "se=$_" unless /[=\n]/;
			$add .= "\nos=0"  unless m{^\s*os=}m;
			$add .= "\nne=0"  unless m{^\s*ne=}m;
			$add .= "\nop=rm" unless m{^\s*op=}m;
			$add .= "\nbs=0"  unless m{^\s*bs=}m;
			$add .= "\nsf=*"  unless m{^\s*sf=}m;
			$add .= "\ncs=0"  unless m{^\s*cs=}m;
			$add .= "\nsg=0"  unless m{^\s*sg=}m;
			$add .= "\nnu=0"  unless m{^\s*nu=}m;
			$_ .= $add;
		}
		$scan = join "\n", @$scan;
		$scan .= "\nco=yes" unless m{^\s*co=}m;
#::logDebug("escape_scan: scan=$scan");
	}

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
	my ($href, $arg, $opt) = @_;

	if( $href and $opt->{alias}) {
		my $aloc = $opt->{once} ? 'one_time_path_alias' : 'path_alias';
		$Vend::Session->{$aloc}{$href} = {}
			if not defined $Vend::Session->{path_alias}{$href};
		$Vend::Session->{$aloc}{$href} = $opt->{alias};
	}

	my $base = ! $opt->{secure} ? ($Vend::Cfg->{VendURL}) : $Vend::Cfg->{SecureURL};

	$href = 'process' unless $href;
	$href =~ s:^/+::;
	$href = "$base/$href"     unless $href =~ /^\w+:/;

	my $extra = <<EOF;
mv_session_id=$Vend::Session->{id}
EOF
	$arg = '' if ! $arg;
	$arg = "mv_arg=$arg\n" if $arg && $arg !~ /\n/; 
	$extra .= $arg . $opt->{form};
	$extra = escape_mv('&', $extra, 1);
	return $href . '?' . $extra;
}

PAGELINK: {

my ($urlroutine, $page, $arg, $opt);

sub static_url {
	return $Vend::Cfg->{StaticPath} . "/" . shift;
}

sub resolve_static {
#::logDebug("entering resolve_static...");
	return if ! $Vend::Cookie;
#::logDebug("have cookie...");
	return if ! $Vend::Cfg->{Static};
#::logDebug("are static...");
	my $key = $page;
	if($arg) {
		my $tmp = $arg;
		$tmp =~ s:([^\w/]): sprintf '%%%02x', ord($1) :eg;
		$key .= "/$arg";
	}
#::logDebug("checking $key...");

	if(defined $Vend::StaticDBM{$key}) {
#::logDebug("found DBM $key...");
		$page = $Vend::StaticDBM{$key} || "$key$Vend::Cfg->{StaticSuffix}";
	}
	elsif(defined $Vend::Cfg->{StaticPage}{$key}) {
#::logDebug("found StaticPage $key...");
		$page = $Vend::Cfg->{StaticPage}{$key} || "$key$Vend::Cfg->{StaticSuffix}";
	}
	else {
#::logDebug("not found $key...");
		return;
	}
	$urlroutine = \&static_url;
	return;
}

sub tag_page {
    ($page, $arg, $opt) = @_;

#::logDebug("tag_page opt=" . ::uneval($opt));
	return '<A HREF="' . form_link(@_) . '">' if defined $opt and $opt->{form};

	if ($opt->{search}) {
		$page = escape_scan($opt->{search});
	}
	elsif ($page eq 'scan') {
		$page = escape_scan($arg);
		undef $arg;
	}

	$urlroutine = $opt->{secure} ? \&secure_vendUrl : \&vendUrl;

	resolve_static();

    return '<a href="' . $urlroutine->($page,$arg || undef) . '">';
}

# Returns an href which will call up the specified PAGE.

sub tag_area {
    ($page, $arg, $opt) = @_;

	return form_link(@_) if defined $opt and $opt->{form};

	$page = '' if ! defined $page;

	if ($opt->{search}) {
		$page = escape_scan($opt->{search});
	}
	elsif ($page eq 'scan') {
		$page = escape_scan($arg);
		undef $arg;
	}

	$urlroutine = $opt->{secure} ? \&secure_vendUrl : \&vendUrl;

	resolve_static();

	return $urlroutine->($page, $arg);
}

}

# Sets the default shopping cart for display
sub tag_cart {
	$Vend::CurrentCart = shift;
	return '';
}

# Returns the shipping description.

sub tag_shipping_desc {
	my $mode = 	shift;
	$CacheInvalid = 1 unless $mode;
	$mode = $mode || $::Values->{mv_shipmode} || 'default';
	return '' unless defined $Vend::Cfg->{Shipping_desc}->{$mode};
	$Vend::Cfg->{Shipping_desc}->{$mode};
}

# Returns the href to process the completed order form or do the search.

sub tag_process {
	my($target,$secure,$opt) = @_;
	if($opt->{order}) {
		$secure = $Vend::Session->{secure} ? 1 : 0; 
	}
	my $url = $secure ? secure_vendUrl('process') : vendUrl('process');
	return $url unless $target;
	return qq{$url" TARGET="$target};
}

sub tag_calc {
	my($body) = @_;
	my $result = 0;

	init_calc() if ! $Calc_initialized;

	$result = $ready_safe->reval($body);
	if ($@) {
		my $msg;
		$msg .= $@;
		logGlobal({}, "Safe: %s\n%s\n" , $msg, $body);
		logError("Safe: %s\n%s\n" , $msg, $body);
		return 0;
	}
	return $result;
}

sub tag_self_contained_if {
	my($base, $term, $operator, $comp, $body) = @_;

	my ($else,$elsif,@addl);
	
	local($^W) = 0;
#::logDebug("self_if: base=$base term=$term op=$operator comp=$comp");
	if ($body =~ s#$QR{condition_begin}##) {
		$comp = $1;
	}
#::logDebug("self_if: base=$base term=$term op=$operator comp=$comp");

	if ( $body =~ /\[[EeTtAaOo][hHLlNnRr][SsEeDd\s]/ ) {
		($body, $elsif, $else, @addl) = split_if($body);
	}

#::logDebug("Additional ops found:\n" . join("\n", @addl) ) if @addl;

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
		$elsif =~ s#(.*?)$QR{'/elsif'}(.*)#$1${2}[/elsif]#s;
		$out = '[if ' . $elsif . $else . '[/if]';
	}
	elsif ($else) {
		$out = $else;
	}
	else {
		return '';
	}

	return $out;
}


sub pull_if {
	my($string, $reverse) = @_;
	return pull_else($string) if $reverse;
	$string =~ s:$QR{else_end}::o;
	return $string;
}

sub pull_else {
	my($string, $reverse) = @_;
	return pull_if($string) if $reverse;
	return $1 if $string =~ s:$QR{else_end}::;
	return;
}

## ORDER PAGE

my (@Opts);
my (@Flds);
my %Sort = (

	''	=> sub { $_[0] cmp $_[1]				},
	none	=> sub { $_[0] cmp $_[1]				},
	f	=> sub { (lc $_[0]) cmp (lc $_[1])	},
	fr	=> sub { (lc $_[1]) cmp (lc $_[0])	},
    l  => sub {
            my ($a1,$a2) = split /[,.]/, $_[0], 2;
            my ($b1,$b2) = split /[,.]/, $_[1], 2;
            return $a1 <=> $b1 || $a2 <=> $b2;
    },  
    lr  => sub {
            my ($a1,$a2) = split /[,.]/, $_[0], 2;
            my ($b1,$b2) = split /[,.]/, $_[1], 2;
            return $b1 <=> $a1 || $b2 <=> $a2;
    },      
	n	=> sub { $_[0] <=> $_[1]				},
	nr	=> sub { $_[1] <=> $_[0]				},
	r	=> sub { $_[1] cmp $_[0]				},
);

@Sort{qw/rf rl rn/} = @Sort{qw/fr lr nr/};

use vars qw/%Sort_field/;
%Sort_field = %Sort;

sub tag_sort_ary {
    my($opts, $list) = (@_); 
    $opts =~ s/^\s+//; 
    $opts =~ s/\s+$//; 
#::logDebug("tag_sort_ary: opts=$opts list=" . ::uneval($list));
	my @codes;
	my $key = 0;

	my ($start, $end, $num);
	my $glob_opt = 'none';

    my @opts =  split /\s+/, $opts;
    my @option; my @bases; my @fields;

    for(@opts) {
        my ($base, $fld, $opt) = split /:/, $_;

		if($base =~ /^(\d+)$/) {
			$key = $1;
			$glob_opt = $fld || $opt || 'none';
			next;
		}
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
			$routine .= '&{$Vend::Interpolate::Sort_field{"' .
						$option[$i] .
						'"}}(' . "\n";
			$routine .= "tag_data('$bases[$i]','$fields[$i]', \$_[0]->[$key]),\n";
			$routine .= "tag_data('$bases[$i]','$fields[$i]', \$_[1]->[$key]) ) or ";
	}
	$routine .= qq!0 or &{\$Vend::Interpolate::Sort_field{"$glob_opt"}}!;
	$routine .= '($_[0]->[$key],$_[1]->[$key]); }';
#::logDebug("tag_sort_ary routine: $routine\n");

    my $code = eval $routine;  
    die "Bad sort routine\n" if $@;

	#Prime the sort? Prevent variable suicide??
	#&{$Vend::Interpolate::Sort_field{'n'}}('31', '30');

	use locale;
	if($::Scratch->{mv_locale}) {
		POSIX::setlocale(POSIX::LC_COLLATE(),
			$::Scratch->{mv_locale});
	}

	@codes = sort {&$code($a, $b)} @$list;

	if(defined $start and $start > 1) {
		splice(@codes, 0, $start - 1);
	}

	if(defined $num) {
		splice(@codes, $num);
	}
#::logDebug("tag_sort_ary routine returns: " . ::uneval(\@codes));
	return \@codes;
}

sub tag_sort_hash {
    my($opts, $list) = (@_); 
    $opts =~ s/^\s+//; 
    $opts =~ s/\s+$//; 
#::logDebug("tag_sort_hash: opts=$opts list=" . ::uneval($list));
	my @codes;
	my $key = 'code';

	my ($start, $end, $num);
	my $glob_opt = 'none';

    my @opts =  split /\s+/, $opts;
    my @option; my @bases; my @fields;

    for(@opts) {

		if(/^(\w+)(:([flnr]+))?$/) {
			$key = $1;
			$glob_opt = $3 || 'none';
			next;
		}
		if(/^([-=+])(\d+)-?(\d*)/) {
			my $op = $1;
			if    ($op eq '-') { $start = $2 }
			elsif ($op eq '+') { $num   = $2 }
			elsif ($op eq '=') {
				$start = $2;
				$end = ($3 || undef);
			}
			next;
		}
        my ($base, $fld, $opt) = split /:/, $_;
		
        push @bases, $base;
        push @fields, $fld;
        push @option, (defined $Vend::Interpolate::Sort_field{$opt} ? $opt : 'none');
    }

	if(defined $end) {
		$num = 1 + $end - $start;
		$num = undef if $num < 1;
 	}

	if (! defined $list->[0]->{$key}) {
		::logError("sort key '$key' not defined in list. Skipping sort.");
		return $list;
	}

    my $i;
    my $routine = 'sub { ';
	for( $i = 0; $i < @bases; $i++) {
			$routine .= '&{$Vend::Interpolate::Sort_field{"' .
						$option[$i] .
						'"}}(' . "\n";
			$routine .= "tag_data('$bases[$i]','$fields[$i]', \$_[0]->{$key}),\n";
			$routine .= "tag_data('$bases[$i]','$fields[$i]', \$_[1]->{$key}) ) or ";
	}
	$routine .= qq!0 or &{\$Vend::Interpolate::Sort_field{"$glob_opt"}}!;
	$routine .= '($a->{$key},$_[1]->{$key}); }';

#::logDebug("tag_sort_hash routine: $routine\n");
    my $code = eval $routine;  
    die "Bad sort routine\n" if $@;

	#Prime the sort? Prevent variable suicide??
	#&{$Vend::Interpolate::Sort_field{'n'}}('31', '30');

	use locale;
	if($::Scratch->{mv_locale}) {
		POSIX::setlocale(POSIX::LC_COLLATE(),
			$::Scratch->{mv_locale});
	}

	@codes = sort {&$code($a,$b)} @$list;

	if(defined $start and $start > 1) {
		splice(@codes, 0, $start - 1);
	}

	if(defined $num) {
		splice(@codes, $num);
	}
#::logDebug("tag_sort_hash routine returns: " . ::uneval(\@codes));
	return \@codes;
}

my %Prev;

sub compile_sub {
}

sub check_sub {
}

sub check_change {
	my($name, $value, $text, $substr) = @_;
	# $value is case-sensitive flag if passed text;
	if(defined $text) {
		$text =~ s:$QR{condition}::;
		$value = $value ? lc $1 : $1;
	}
	$value = substr($value, 0, $substr) if $substr;
	my $prev = $Prev{$name} || undef;
	$Prev{$name} = $value || '';
	if(defined $text) {
		return pull_if($text) if ! defined $prev or $value ne $prev;
		return pull_else($text);
	}
	return 1 unless defined $prev;
	return $value eq $prev ? 0 : 1;
}

sub list_compat {
	my $prefix = shift;
	my $textref = shift;

	$$textref =~ s:\[if[-_]data\s:[if-$prefix-data :gi
		and $$textref =~ s:\[/if[-_]data\]:[/if-$prefix-data]:gi;

	$$textref =~ s:\[if[-_]modifier\s:[if-$prefix-modifier :gi
		and $$textref =~ s:\[/if[-_]modifier\]:[/if-$prefix-modifier]:gi;

	$$textref =~ s:\[if[-_]field\s:[if-$prefix-field :gi
		and $$textref =~ s:\[/if[-_]field\]:[/if-$prefix-field]:gi;

	$$textref =~ s:\[on[-_]change\s:[$prefix-change :gi
		and $$textref =~ s:\[/on[-_]change\s:[/$prefix-change :gi;

	return;
}

sub tag_search_region {
	my($params, $opt, $text) = @_;
	$opt->{search} = $params if $params;
	$opt->{prefix}      = 'item'           if ! defined $opt->{prefix};
	$opt->{list_prefix} = 'search[-_]list' if ! defined $opt->{list_prefix};
# LEGACY
	list_compat($opt->{prefix}, \$text);
# END LEGACY
	return region($opt, $text);
}

sub find_sort {
	my($text) = @_;
	return undef unless defined $$text and $$text =~ s#\[sort(([\s\]])[\000-\377]+)#$1#io;
	my $options = find_close_square($$text);
	$$text = substr( $$text,length($options) + 1 )
				if defined $options;
	$options = interpolate_html($options) if index($options, '[') != -1;
	return $options || '';
}

sub tag_search_list {
    my($opt, $text) = @_;
	$opt->{prefix} = 'item';
	my $obj;

	$obj = $opt->{object}
			|| $Vend::SearchObject{$opt->{label}}
			|| perform_search()
			|| return;
	$text =~ s:\[if-(field\s+|data\s+):[if-item-$1:gi
		and $text =~ s:\[/if${D}(field|data)\]:[/if-item-$1]:gi;
	$text =~ s:\[on${D}change\b:[item-change:gi
		and $text =~ s:\[/on${D}change\b:[/item-change:gi;
   	return labeled_list($opt, $text, $obj);
}

# Artificial for better variable passing
{
	my( $next_anchor,
		$prev_anchor,
		$page_anchor,
		$border,
		$border_selected,
		$opt,
		$r,
		$chunk,
		$total,
		$current,
		$page,
		$prefix,
		$more_id,
		$form_arg,
		$session,
		);

sub more_link {
	my($inc, $pa) = @_;
	my ($next, $last, $arg);
	my $list = '';
	$pa =~ s/__PAGE__/$inc/g;
	my $form_arg = "mv_more_ip=1\nmv_nextpage=$page";
	$form_arg .= "\npf=$prefix" if $prefix;
	$form_arg .= "\nmi=$prefix" if $more_id;
	$next = ($inc-1) * $chunk;
#::logDebug("more_link: inc=$inc current=$current");
	$last = $next + $chunk - 1;
	$last = ($last+1) < $total ? $last : ($total - 1);
	if($inc == $current) {
		$pa =~ s/__BORDER__/$border_selected || $border || ''/e;
		$list .= qq|<STRONG>$pa</STRONG> | ;
	}
	else {
		$pa =~ s/__BORDER__/$border/e;
		$arg = "$session:$next:$last:$chunk";
		$list .= '<A HREF="';
		$list .= tag_area( "scan/MM=$arg", '', { form => $form_arg });
		$list .= '">';
		$list .= $pa;
		$list .= '</A> ';
	}
	return $list;
}

sub tag_more_list {
	(
		$next_anchor,
		$prev_anchor,
		$page_anchor,
		$border,
		$border_selected,
		$opt,
		$r,
	) = @_;
#::logDebug("more_list: opt=$opt label=$opt->{label}");
	return undef if ! $opt;
	$q = $opt->{object} || $Vend::SearchObject{$opt->{label}};
	return '' unless $q->{matches} > $q->{mv_matchlimit};
	my($arg,$inc,$last,$m);
	my($adder,$pages);
	my $next_tag = '';
	my $list = '';
	$session = $q->{mv_cache_key};
	my $first = $q->{mv_first_match} || 0;
	$chunk = $q->{mv_matchlimit};
	$total = $q->{matches};
	my $next = defined $q->{mv_next_pointer}
				? $q->{mv_next_pointer}
				: $first + $chunk;
	$page = $q->{mv_search_page} || $Global::Variable->{MV_PAGE};
	$prefix = $q->{prefix} || '';
	my $form_arg = "mv_more_ip=1\nmv_nextpage=$page";
	$form_arg .= "\npf=$q->{prefix}" if $q->{prefix};
	$form_arg .= "\nmi=$q->{mv_more_id}" if $q->{mv_more_id};

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
			$arg .= ":$chunk";
			$list .= '<A HREF="';
			$list .= tag_area( "scan/MM=$arg", '', { form => $form_arg });
			$list .= '">';
			$list .= $prev_anchor;
			$list .= '</A> ';
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
		$arg = "$session:$next:$last:$chunk";
		$next_tag .= '<A HREF="';
		$next_tag .= tag_area( "scan/MM=$arg", '', { form => $form_arg });
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

	my ($decade_next, $decade_prev, $decade_div);
	if( $q->{mv_more_decade} or $r =~ m:\[decade[-_]next\]:) {
		$r =~ s:\[decade[-_]next\]($All)\[/decade[-_]next\]::i
			and $decade_next = $1;
		$decade_next = '<SMALL>&#91;more&gt;&gt;&#93;</SMALL>' if ! $decade_next;
		$r =~ s:\[decade[-_]prev\]($All)\[/decade[-_]prev\]::i
			and $decade_prev = $1;
		$decade_prev = '<SMALL>&#91;&lt;&lt;more&#93;</SMALL>' if ! $decade_prev;
		$decade_div = $q->{mv_more_decade} > 1 ? $q->{mv_more_decade} : 10;
	}

	my ($b, $e, @b, @e);
	if(defined $decade_div and $pages > $decade_div) {
		if($current > $decade_div) {
			$b = ( int ($current / $decade_div) * $decade_div ) + 1;
			$list .= " ";
			$list .= more_link($b - $decade_div, $decade_prev);
		}
		else {
			$b = 1;
		}
		if($b + $decade_div <= $pages) {
			$e = $b + $decade_div;
			$decade_next = more_link($e, $decade_next);
			$e--;
		}
		else {
			$e = $pages;
			undef $decade_next;
		}
#::logDebug("more_list: decade found pages=$pages current=$current b=$b e=$e next=$next last=$last decade_div=$decade_div");
	}
	else {
		($b, $e) = (1, $pages);
		undef $decade_next;
	}
#::logDebug("more_list: pages=$pages current=$current b=$b e=$e next=$next last=$last decade_div=$decade_div");

	foreach $inc ($b .. $e) {
		last if $page_anchor eq 'none';
		$list .= more_link($inc, $page_anchor);
	}

	$list .= " $decade_next " if defined $decade_next;
	$list .= $next_tag;
	$first = $first + 1;
	$last = $first + $chunk - 1;
	$last = $last > $total ? $total : $last;
	$m = $first . '-' . $last;
	$r =~ s,$QR{more},$list,g;
	$r =~ s,$QR{matches},$m,g;

	$r;

}

}

sub sort_cart {
	my($options, $cart) = @_;
	my ($item,$code);
	my %order; my @codes; my @out;
	my $sort_order;
	foreach $item  (@$cart) {
		$code = $item->{code};
		$order{$code} = [] unless defined $order{$code};
		push @{$order{$code}}, $item;
		push @codes, $code;
	}

	$sort_order = tag_sort_hash($options, \@codes);

	foreach $code (@$sort_order) {
		push @out, @{$order{$code}};
	}
	return \@out;
}

# Naming convention
# Ld  Label Data
# B   Begin
# E   End
# D   Data
# I   If
my $LdD = qr{\s+([\w-:#/.]+)\]};
my $LdI = qr{\s+([\w-:#/.]+)\]($Some)};
my $LdB;
my $LdIB;
my $LdIE;
my $LdExpr;
my $B;
my $E;
my $IB;
my $IE;
my $Prefix;

sub tag_labeled_data_row {
	my ($key, $text) = @_;
	my ($row, $table, $tabRE);
	my $done;
	my $prefix;
	if(defined $Prefix) {
		$prefix = $Prefix;
		undef $Prefix;
		$LdB = qr(\[$prefix[-_]data$Spacef)i;
		$LdIB = qr(\[if[-_]$prefix[-_]data$Spacef(!?)(?:%20|\s)*)i;
		$LdIE = qr(\[/if[-_]$prefix[-_]data\])i;
		$LdExpr = qr{ \[(?:$prefix[-_]data|if[-_]$prefix[-_]data)
	                \s+ !?\s* ($Codere) \s
					(?!$All\[(?:$prefix[-_]data|if[-_]$prefix[-_]data))  }xi;
		%Data_cache = ();
	}
	# Want the last one
#::logDebug(<<EOF);
#tag_labeled_data_row:
#	prefix=$prefix
#	LdB   =$LdB
#	LdIB  =$LdIB
#	LdIE  =$LdIE
#	LdD   =$LdD
#	LdI   =$LdI
#	LdExpr=$LdExpr
#EOF

    while($$text =~ $LdExpr) {
		$table = $1;
		$tabRE = qr/$table/;
#::logDebug("In row: table=$table tabRE=$tabRE");
		if($Vend::UPPERCASE{$table}) {
			$$text =~ s#($LdB$tabRE)$LdD#$1 \U$2]#g;
			$$text =~ s#($LdIB$tabRE)$LdD#$1 \U$2]#g;
		}
		$row = $Data_cache{"$table.$key"}
				|| ( $Data_cache{"$table.$key"}
						= Vend::Data::database_row($table, $key)
					)
				|| {};
		$done = 1;
		$$text =~ s#$LdIB$tabRE$LdI$LdIE#
					$row->{$2}	? pull_if($3,$1)
								: pull_else($3,$1)#ge
			and undef $done;
#::logDebug("after if: table=$table 1=$1 2=$2 3=$3 $$text =~ s#$LdIB $tabRE $LdI $LdIE#");

		$$text =~ s/$LdB$tabRE$LdD/$row->{$1}/g
			and undef $done;
		last if $done;
	}
	return $_;
}

sub random_elements {
	my($ary, $wanted) = @_;
	$wanted = 1 if ! $wanted || $wanted =~ /\D/;
	return undef unless ref $ary;
	my %seen;
	my ($j, @out);
	my $count = scalar @$ary;
	return (0 .. $#$ary) if $count <= $wanted;
	for($j = 0; $j < $wanted; $j++) {
		my $cand = int rand($count);
		redo if $seen{$cand}++;
		push(@out, $cand);
	}
	return (@out);
}

my $opt_select;
my $opt_table;
my $opt_field;
my $opt_value;

sub labeled_list {
    my($opt, $text, $obj) = @_;
	my($count);
	$obj = $opt->{object} if ! $obj;
	return '' if ! $obj;

	my $ary = $obj->{mv_results};
	return if (! $ary or ! ref $ary or ! $text or ! defined $ary->[0]);
	
	my $save_unsafe = $MVSAFE::Unsafe || '';
	$MVSAFE::Unsafe = 1;

	if($opt->{prefix} eq 'item') {
#::logDebug("labeled list: opt:\n" . ::uneval($opt) . "\nobj:" . ::uneval($obj) . "text:" . substr($text,0,100));
	}
	$Prefix = $opt->{prefix} || 'item';

	$B  = qr(\[$Prefix)i;
	$E  = qr(\[/$Prefix)i;
	$IB = qr(\[if[-_]$Prefix)i;
	$IE = qr(\[/if[-_]$Prefix)i;

	my $end;
	# List more
	if (	defined $CGI::values{mv_more_matches}
			and     $CGI::values{mv_more_matches} eq 'loop'  )
	{
		undef $CGI::values{mv_more_matches};
		$opt->{fm}	= $CGI::values{mv_next_pointer} + 1;
		$end		= $CGI::values{mv_last_pointer}
			if defined $CGI::values{mv_last_pointer};
		$opt->{ml}	= $CGI::values{mv_matchlimit}
			if defined $CGI::values{mv_matchlimit};
	}
	# get the number to start the increment from
	my $i = 0;
	if (defined $obj->{more_in_progress} and $obj->{mv_first_match}) {
		$i = $obj->{mv_first_match};
	}
	elsif (defined $opt->{random}) {
		@$ary = @$ary[random_elements($ary, $opt->{random})];
		$i = 0; $end = $#$ary;
		undef $obj->{mv_matchlimit};
	}
	elsif (defined $opt->{fm}) {
		$i = $opt->{fm} - 1;
	}

	$count = $obj->{mv_first_match} || $i;
	$count++;
	# Zero the on-change hash
	undef %Prev;

	if(defined $opt->{option}) {
		$opt_value = $opt->{option};
		if($opt_value =~ s/\s*($Codere)::($Codere)\s*//) {
            $opt_table = $1;
            $opt_field = $2;
			$opt_value = lc($::Values->{$opt_value}) || undef;
            $opt_select = sub {
                return lc(tag_data($opt_table, $opt_field, shift)) eq $opt_value;
            }
				if $opt_value;
        }
		elsif(defined $::Values->{$opt_value} and length $::Values->{$opt_value} ) {
			$opt_value = lc($::Values->{$opt_value});
			$opt_select = ! $opt->{multiple} 
						  ? sub { return "\L$_[0]" eq $opt_value }
						  : sub { $opt_value =~ /^$_[0](?:\0|$)/i or  
						  		  $opt_value =~ /\0$_[0](?:\0|$)/i
								  };
		}
	}
	else {
		undef $opt_select;
	}

	my $return;
	if($Vend::OnlyProducts) {
		$text =~ s#$B$QR{_field}#[$Prefix-data $Vend::OnlyProducts $1]#g
			and $text =~ s#$E$QR{'/_field'}#[/$Prefix-data]#g;
		$text =~ s,$IB$QR{_field_if_wo},[if-$Prefix-data $1$Vend::OnlyProducts $2],g
			and $text =~ s,$IE$QR{'/_field'},[/if-$Prefix-data],g;
	}
#::logDebug("Past only products.");
	$end =	$obj->{mv_matchlimit}
			? $i + ($opt->{ml} || $obj->{mv_matchlimit}) - 1
			: $#$ary;
	$end = $#$ary if $#$ary < $end;

# LEGACY
	$text =~ /^\s*\[sort\s+.*/si
		and $opt->{sort} = find_sort(\$text);
# END LEGACY

	my $r;
	if($ary->[0] =~ /HASH/) {
		for (my $i = 0; $i < @$ary; $i++) {
			$ary->[$i]{mv_ip} = $i;
		}
		$ary = tag_sort_hash($opt->{sort}, $ary) if $opt->{sort};
		$r = iterate_hash_list($i, $end, $count, $text, $ary, $opt_select);
	}
	else {
		my $fa;
		my $fa = $obj->{mv_return_fields} || undef;
		my $fh = $obj->{mv_field_hash}    || undef;
		my $fn = $obj->{mv_field_names}   || undef;
#::logDebug("fa: " . ::uneval($fa));
#::logDebug("fh: " . ::uneval($fh));
#::logDebug("fn: " . ::uneval($fn));
		$ary = tag_sort_ary($opt->{sort}, $ary) if $opt->{sort};
		if($fa) {
			my $idx = 0;
			$fh = {};
			for(@$fa) {
				$fh->{$fn->[$_]} = $idx++;
			}
		}
		elsif (! $fh and $fn) {
			my $idx = 0;
			$fh = {};
			for(@$fn) {
				$fh->{$fn->[$_]} = $idx++;
			}
		}
		$r = iterate_array_list($i, $end, $count, $text, $ary, $opt_select, $fh);
	}
	$MVSAFE::Unsafe = $save_unsafe;
	return $r;
}

sub iterate_array_list {
	my ($i, $end, $count, $text, $ary, $opt_select, $fh) = @_;

	my $r = '';
	my ($run, $row, $code, $return);
my $once = 0;
#::logDebug("iterating array $i to $end. count=$count opt_select=$opt_select ary=" . ::uneval($ary));
	if($text =~ m/^$B$QR{_line}\s*$/is) {
		my $i = $1 || 0;
		my $count = scalar values %$fh;
		$count--;
		my (@ary) = sort { $fh->{$a} <=> $fh->{$b} } keys %$fh;
		$r .= join "\t", @ary[$i .. $count];
		$r .= "\n";
	}
	while($text =~ s#$B$QR{_sub}$E$QR{'/_sub'}##i) {
		my $name = $1;
		my $routine = $2;
		## Not necessary?
		## $Vend::Cfg->{Sub}{''} = sub { ::errmsg('undefined sub') }
		##	unless defined $Vend::Cfg->{Sub}{''};
		$routine = 'sub { ' . $routine . ' }' unless $routine =~ /^\s*sub\s*{/;
		my $sub;
		eval {
			$sub = $ready_safe->reval($routine);
		};
		if($@) {
			::logError( ::errmsg("syntax error on %s-sub %s]: $@", $B, $name) );
			$sub = sub { ::errmsg('ERROR') };
		}
#::logDebug("sub $name: $sub --> $routine");
		$Vend::Cfg->{Sub}{$name} = $sub;
	}
	for( ; $i <= $end ; $i++, $count++ ) {
		$row = $ary->[$i];
		last unless defined $row;
		$code = $row->[0];

#::logDebug("Doing $code substitution, count $count++");
#::logDebug("Doing '" . substr($code, 0, index($code, "\n") + 1) . "' substitution, count $count++");

	    $run = $text;
		$run =~ s#$B$QR{_alternate}$E$QR{'/_alternate'}#
				  $count % ($1 || $::Values->{mv_item_alternate} || 2)
				  							?	pull_else($2)
											:	pull_if($2)#ige;
		$run =~ s#$IB$QR{_param_if}$IE$QR{'/_param'}#
				  (defined $fh->{$2} ? $row->[$fh->{$2}] : '')
				  					?	pull_if($3,$1)
									:	pull_else($3,$1)#ige;
	    $run =~ s#$B$QR{_param}#defined $fh->{$1} ? $row->[$fh->{$1}] : ''#ige;
		$run =~ s#$IB$QR{_pos_if}$IE$QR{'/_pos'}#
				  $row->[$2] 
						?	pull_if($3,$1)
						:	pull_else($3,$1)#ige;
	    $run =~ s#$B$QR{_pos}#$row->[$1]#ig;
#::logDebug("fh: " . ::uneval($fh) . ::uneval($row)) unless $once++;
		$run =~ s#$IB$QR{_field_if}$IE$QR{'/_field'}#
				  product_field($2, $code)	?	pull_if($3,$1)
											:	pull_else($3,$1)#ige;
		$run =~ s:$B$QR{_line}:join "\t", @{$row}[ ($1 || 0) .. $#$row]:ige;
	    $run =~ s:$B$QR{_increment}:$count:ig;
		$run =~ s:$B$QR{_accessories}:
						tag_accessories($code,$1,{}):ige;
		$run =~ s:$B$QR{_code}:$code:ig;
		$run =~ s:$B$QR{_description}:product_description($code):ige;
		$run =~ s:$B$QR{_field}:product_field($1, $code):ige;
		tag_labeled_data_row($code, \$run);
		$run =~ s!$B$QR{_price}!
					currency(product_price($code,$1), $2)!ige;

		1 while $run =~ s!$B$QR{_change}$E$QR{'/_change'}\1\]!
							check_change($1,$3,undef,$2)
											?	pull_if($4)
											:	pull_else($4)!ige;
		$run =~ s#$B$QR{_calc}$E$QR{'/_calc'}#tag_calc($1)#ige;
		$run =~ s#$B$QR{_exec}$E$QR{'/_exec'}#($Vend::Cfg->{Sub}{$1} || sub { 'ERROR' })->($2,$row)#ige;
		$run =~ s#$B$QR{_filter}$E$QR{'/_filter'}#filter_value($1,$2)#ige;
		$run =~ s#$B$QR{_last}$E$QR{'/_last'}#
                    my $tmp = interpolate_html($1);
                    if($tmp && $tmp < 0) {
                        last;
                    }
                    elsif($tmp) {
                        $return = 1;
                    }
                    '' #ixge;
		$run =~ s#$B$QR{_next}$E$QR{'/_next'}#
                    interpolate_html($1) != 0 ? next : '' #ixge;
		$run =~ s/<option\s*/<OPTION SELECTED /i
			if $opt_select and $opt_select->($code);	

		$r .= $run;
		last if $return;
    }
	return $r;
}

sub iterate_hash_list {
	my($i, $end, $count, $text, $hash, $opt_select) = @_;

	my $r = '';
	my ($run, $item, $code, $return);

#::logDebug("iterating hash $i to $end. count=$count opt_select=$opt_select hash=" . ::uneval($hash));

	for ( ; $i <= $end; $i++, $count++) {
		$item = $hash->[$i];
		$item->{mv_cache_price} = undef;
		$code = $item->{code};

#::logDebug("Doing $code substitution, count $count++");

		$run = $text;
		$run =~ s#$B$QR{_alternate}$E$QR{'/_alternate'}#
				  ($i + 1) % ($1 || $::Values->{mv_item_alternate} || 2)
				  							?	pull_else($2)
											:	pull_if($2)#ge;
		tag_labeled_data_row($code,\$run);
		$run =~ s:$B$QR{_line}:join "\t", @{$hash}:ge;
		$run =~ s#$IB$QR{_param_if}$IE$QR{'/_param'}#
				  $item->{$2}	?	pull_if($3,$1)
								:	pull_else($3,$1)#ige;
		$run =~ s#$IB$QR{_field_if}$IE$QR{'/_field'}#
				  product_field($2, $code)	?	pull_if($3,$1)
											:	pull_else($3,$1)#ge;
		$run =~ s#$IB$QR{_modifier_if}$IE$QR{'/_modifier'}#
				  $item->{$2}	?	pull_if($3,$1)
								:	pull_else($3,$1)#ge;
		$run =~ s:$B$QR{_increment}:$i + 1:ge;
		$run =~ s:$B$QR{_accessories}:
						tag_accessories($code,$1,{},$item):ge;
		$run =~ s:$B$QR{_quantity}:$item->{quantity}:g;
		$run =~ s:$B$QR{_modifier}:$item->{$1}:g;
		$run =~ s:$B$QR{_param}:$item->{$1}:g;
		$run =~ s:$QR{quantity_name}:quantity$item->{mv_ip}:g;
		$run =~ s:$QR{modifier_name}:$1$item->{mv_ip}:g;
		$run =~ s!$B$QR{_subtotal}!currency(item_subtotal($item),$1)!ge;
		$run =~ s!$B$QR{discount_subtotal}!
						currency( discount_price(
										$item,item_subtotal($item)
									),
								$1
								)!ge;
		$run =~ s:$B$QR{_code}:$code:g;
		$run =~ s:$B$QR{_field}:item_field($item, $1) || $item->{$1}:ge;
		$run =~ s:$B$QR{_description}:
							item_description($item) || $item->{description}
							:ge;
		$run =~ s!$B$QR{_price}!currency(item_price($item,$1), $2)!ge;
		$run =~ s!$QR{discount_price}!
					currency(
						discount_price($item, item_price($item,$1), $1 || 1)
						, $2
						)!ge;
		$run =~ s!$B$QR{_discount}!
					currency(item_discount($item->{code},
											item_price($item, $1),
											$item->{quantity}), $2)!ge;
		1 while $run =~ s!$B$QR{_change}$E$QR{'/_change'}\1\]!
							check_change($1,$3,undef,$2)
											?	pull_if($4)
											:	pull_else($4)!ige;
		$run =~ s#$B$QR{_last}$E$QR{'/item_last'}#
                    my $tmp = interpolate_html($1);
                    if($tmp && $tmp < 0) {
                        last;
                    }
                    elsif($tmp) {
                        $return = 1;
                    }
                    '' #xoge;
		$run =~ s#$B$QR{_next}$E$QR{'/_next'}#
                    interpolate_html($1) != 0 ? next : '' #oge;
		$run =~ s/<option\s*/<OPTION SELECTED /i
			if $opt_select and $opt_select->($code);	

		$r .= $run;
		delete $item->{mv_cache_price};
		last if $return;
	}

	return $r;
}

sub query {
	if(ref $_[0]) {
		unshift @_, '';
	}
	my ($query, $opt, $text) = @_;
	$opt = {} if ! $opt;
	if($opt->{more} and $Vend::More_in_progress) {
		undef $Vend::More_in_progress;
		return region($opt, $text);
	}
	$opt->{table} = $Vend::Cfg->{ProductFiles}[0]
		unless $opt->{table};
	my $db = $Vend::Database{$opt->{table}} ;
	return $opt->{failure} if ! $db;

	$opt->{query} = $query
		if $query;

	if (! $opt->{wantarray} and ! defined $MVSAFE::Safe) {
		my $result = $db->query($opt, $text);
		return (ref $result) ? '' : $result;
	}
	$db->query($opt, $text);
}

sub tag_item_list {
	my($cart,$opt,$text) = @_;
#::logDebug("tag_item_list: " . ::uneval(\@_));
	my $obj = {
				mv_results => $cart ? ($::Carts->{$cart} ||= [] ) : $Vend::Items,
					};
	return if ! $text;
#::logDebug("tag_item_list obj=" . ::uneval($obj));
#::logDebug("Vend::Items obj=" . ::uneval($Vend::Items));
	$CacheInvalid = 1;
	$opt->{prefix} = 'item' unless defined $opt->{prefix};
# LEGACY
	list_compat($opt->{prefix}, \$text);
# END LEGACY
	return labeled_list($opt, $text, $obj);
}

sub html_table {
    my($opt, $ary, $na) = @_;

	if (!$na) {
		$na = [ split /\s+/, $opt->{columns} ];
	}
	if(! ref $ary) {
		$ary =~ s/^\s+//;
		$ary =~ s/\s+$//;
		my $delimiter = quotemeta $opt->{delimiter} || "\t";
		my $splittor = quotemeta $opt->{record_delim} || "\n";
		my (@rows) = split /$splittor/, $ary;
		$na = [ split /$delimiter/, shift @rows ] if $opt->{th};
		$ary = [];
		my $count = scalar @$na || -1;
		for (@rows) {
			push @$ary, [split /$delimiter/, $_, $count];
		}
	}

	my ($tr, $td, $th, $fc, $fr) = @{$opt}{qw/tr td th fc fr/};

	for($tr, $td, $th, $fc, $fr) {
		next unless defined $_;
		s/(.)/ $1/;
	}

	my $r = '';
	$tr = '' if ! defined $tr;
	$td = '' if ! defined $td;
	if(! defined $th || $th and scalar @$na ) {
		$th = '' if ! defined $th;
		$r .= "<TR$tr>";
		for(@$na) {
			$r .= "<TH$th><B>$_</B></TH>";
		}
		$r .= "</TR>\n";
	}
	my $row;
	if($fr) {
		$r .= "<TR$fr>";
		my $val;
		$row = shift @$ary;
		if($fc) {
			$val = (shift @$row) || '&nbsp;';
			$r .= "<TD$fc>$val</TD>";
		}
		foreach (@$row) {
			$val = $_ || '&nbsp;';
			$r .= "<TD$td>$val</TD>";
		}
		$r .= "</TR>\n";
		
	}
	foreach $row (@$ary) {
		$r .= "<TR$tr>";
		my $val;
		if($fc) {
			$val = (shift @$row) || '&nbsp;';
			$r .= "<TD$fc>$val</TD>";
		}
		foreach (@$row) {
			$val = $_ || '&nbsp;';
			$r .= "<TD$td>$val</TD>";
		}
		$r .= "</TR>\n";
	}
	return $r;
}

#
# Tests of above routines
#
#print html_table( {	
#					td => "BGCOLOR=#FFFFFF",
#					},
#[
#	[qw/ data1a	data2a	data3a/],
#	[qw/ data1b	data2b	data3b/],
#	[qw/ data1c	data2c	data3c/],
#],
#[ qw/cell1 cell2 cell3/ ],
#);
#
#print html_table( {	
#					td => "BGCOLOR=#FFFFFF",
#					columns => "cell1 cell2 cell3",
#					}, <<EOF);
#data1a	data2a	data3a
#data1b	data2b	data3b
#data1c	data2c	data3c
#EOF


# SQL
sub tag_sql_list {
    my($text,$ary,$nh,$opt) = @_;
	$opt = {} unless defined $opt;
	$opt->{prefix}      = 'sql' if ! defined $opt->{prefix};
	$opt->{list_prefix} = 'sql[-_]list' if ! defined $opt->{prefix};

	$opt->{object} = {
					mv_results => $ary,
					mv_field_hash => $nh,
					matches => scalar @$ary,
				};
    return region($opt, $text);
}
# END SQL

# Displays a search page with the special [search-list] tag evaluated.

sub region {

	my($opt,$page) = @_;

	my $obj;
	if($opt->{object}) {
		$obj = $opt->{object};
	}
	else {
#::logDebug("no object.");
		my $c;
		if($CGI::values{mv_more_matches} || $CGI::values{MM}) {
#::logDebug("more object = $CGI::values{mv_more_matches}");
			find_search_params();
			delete $CGI::values{mv_more_matches};
#::logDebug("more object = " . ::uneval($c));
		}
		elsif ($opt->{search}) {
#::logDebug("opt->search object label=$opt->{label}.");
			if($opt->{more} and $Vend::SearchObject{''}) {
				$obj = $Vend::SearchObject{''};
			}
			else {
				$c = {	mv_search_immediate => 1,
							mv_search_label => $opt->{label} || 'current',
						};
				my $params = escape_scan($opt->{search});
				Vend::Scan::find_search_params($c, $params);
				$obj = perform_search($c);
			}
		}
		else {
#::logDebug("try labeled object label=$opt->{label}.");
			$obj = $Vend::SearchObject{$opt->{label}};
		}
#::logDebug("no found object") if ! $obj;
		if(! $obj) {
			$obj = perform_search();
			$obj = {
						matches => 0,
						mv_search_error => ['No search was found'],
				} if ! $obj;
		}
		finish_search($obj);
		$Vend::SearchObject{$opt->{label}} = $opt->{object} = $obj;
#::logDebug("labeling as '$opt->{label}'");
	}
	my $prefix = defined $opt->{list_prefix} ? $opt->{list_prefix} : 'list';

#::logDebug("region: opt:\n" . ::uneval($opt) . "\npage:" . substr($page,0,100));

	if($opt->{ml} and ! defined $obj->{mv_matchlimit}) {
		$obj->{mv_matchlimit} = $opt->{ml};
		$obj->{matches} = scalar @{$obj->{mv_results}};
		$obj->{mv_cache_key} = generate_key(substr($page,0,100));
		$obj->{mv_first_match} = $opt->{fm} if $opt->{fm};
		$obj->{mv_search_page} = $opt->{sp} if $opt->{sp};
		$obj->{prefix} = $opt->{prefix} if $opt->{prefix};
		my $out = delete $obj->{mv_results};
		Vend::Search::save_more($obj, $out);
		$obj->{mv_results} = $out;
	}

	$opt->{prefix} = $obj->{prefix} if $obj->{prefix};

	$page =~ s!$QR{more_list}! tag_more_list($1,$2,$3,$4,$5,$opt,$6)!ge;
	$page =~ s!$QR{no_match}!
					$obj->{matches} > 0 ? '' : $1
					!ge;
	$page =~ s!$QR{on_match}!
					$obj->{matches} == 0 ? '' : $1
					!ge;
	$page =~ s:\[$prefix\]($Some)\[/$prefix\]:labeled_list($opt,$1,$obj):ige
		or $page = labeled_list($opt,$page,$obj) ;
#::logDebug("past labeled_list");

    return $page;
}

my $List_it = 1;

sub tag_loop_list {
	my ($list, $opt, $text) = @_;

#::logDebug("loop list opt=" . ::uneval($opt));
	my $fn;
	my @rows;

	$opt->{prefix} = 'loop' unless defined $opt->{prefix};
	$opt->{label}  =  "loop" . $List_it++ . $Global::Variable->{MV_PAGE}
						unless defined $opt->{label};
	my $delim;

  RESOLVELOOP: {
	if($opt->{search}) {
#::logDebug("loop resolve search");
		if($opt->{more} and $Vend::More_in_progress) {
			undef $Vend::More_in_progress;
			return region($opt, $text);
		}
		else {
			return region($opt, $text);
		}
	}
	elsif ($opt->{file}) {
#::logDebug("loop resolve file");
		$list = Vend::Util::readfile($opt->{file});
		$opt->{lr} = 1 unless
						defined $opt->{lr}
						or $opt->{quoted};
		redo RESOLVELOOP;
	}
	elsif ($opt->{lr}) {
#::logDebug("loop resolve line");
		$list =~ s/^\s+//;
		$list =~ s/\s+$//;
		last RESOLVELOOP unless $list;
		$delim	 = $opt->{delimiter} || "\t";
		my $splittor = $opt->{record_delim} || "\n";
		if ($splittor eq "\n") {
			$list =~ s/\r\n/\n/g;
		}

		eval {
			@rows = map { [ split /\Q$delim/o, $_ ] } split /\Q$splittor/, $list;
		};
	}
	elsif($opt->{acclist}) {
#::logDebug("loop resolve acclist");
		if($fn = $opt->{fn} || $opt->{mv_field_names}) {
			$fn = [ grep /\S/, split /[\s,]+/, $fn ];
		}
		else {
			$fn = [ qw/option label/ ];
		}
		eval {
			my @items = split /\s*,\s*/, $list;
			for(@items) {
				my ($o, $l) = split /=/, $_;
				$l = $o unless $l;
				push @rows, [ $o, $l ];
			}
		};
#::logDebug("rows:" . ::uneval(\@rows));
	}
	elsif($opt->{quoted}) {
#::logDebug("loop resolve quoted");
		eval {
			@rows = map { [$_] } Text::ParseWords::shellwords($list);
		};
	}
	else {
#::logDebug("loop resolve default");
		$delim = $opt->{delimiter} || '[,\s]+';
		eval {
			@rows = map { [$_] } split /$delim/, $list;
		};
	}
  }
	if($@) {
		::logError("bad split delimiter in loop list: $@");
#::logDebug("loop resolve error $@");
	}
	$opt->{object} = { } if ! $opt->{object};
	if ($opt->{head_skip}) {
		my $i = 0;
		$fn = shift(@rows) while $i++ < $opt->{head_skip};
	}
	$opt->{object}{mv_results} = \@rows;
	$opt->{object}{mv_field_names} = $fn
		if defined $fn;
	return region($opt, $text);
}

# Tries to display the on-the-fly page if page is missing
sub fly_page {
	my($code, $opt, $page) = @_;

	my $selector;

	return $page if (! $code and $Vend::Flypart eq $Vend::FinalPath);

	$code = $Vend::FinalPath
		unless $code;

	$Vend::Flypart = $code;

	my $base = product_code_exists_ref($code);
#::logDebug("fly_page: code=$code base=$base page=" . substr($page, 0, 100));
	return undef unless $base || $opt->{onfly};

	$base = $Vend::Cfg->{ProductFiles}[0] unless $base;

    if($page) {
		$selector = 'passed in tag';
	}
	elsif(	$selector = $Vend::Cfg->{PageSelectField}
			and db_column_exists($base,$selector)
		)
	{
			$selector = database_field($base, $code, $selector)
	}

	$selector = find_special_page('flypage')
		unless $selector;

    $page = readin($selector) unless defined $page;
#::logDebug("fly_page: selector=$selector");
    if(! defined $page) {
		logError("attempt to display code=$code with bad flypage '$selector'");
		return undef;
	}

# TRACK
	$Vend::Track->view_product($code);
# END TRACK
	
# LEGACY
	list_compat($opt->{prefix}, \$page);
# END LEGACY

	return labeled_list( {}, $page, { mv_results => [[$code]] });
}

sub item_discount {
	my($code,$price,$q) = @_;
	return ($price * $q) - discount_price($code,$price,$q);
}

sub discount_price {
	my ($item, $price, $quantity) = @_;
	my $extra;
	my $code;

	unless (ref $item) {
		$code = $item;
		$item = { code => $code, quantity => ($quantity || 1) };
	}

	$Vend::Interpolate::item = $item;

	($code, $extra) = ($item->{code}, $item->{mv_discount});

	$Vend::Session->{discount} = {}
		if $extra and !$Vend::Session->{discount};

	return $price unless defined $Vend::Session->{discount};

	$quantity = $item->{quantity};

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
	push(@formulae, $Vend::Session->{discount}->{$item->{code}})
		if defined $Vend::Session->{discount}->{$item->{code}};
	# Check for all item discount
	push(@formulae, $Vend::Session->{discount}->{ALL_ITEMS})
		if defined $Vend::Session->{discount}->{ALL_ITEMS};
	push(@formulae, $item->{mv_discount})
		if defined $item->{mv_discount};

	my $subtotal = item_subtotal($item);

	init_calc() unless $Calc_initialized;
	# Calculate any formalas found
	foreach $formula (@formulae) {
		next unless $formula;
		$formula =~ s/\$q\b/$item->{quantity}/g; 
		$formula =~ s/\$s\b/$subtotal/g; 
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

my %Ship_remap = ( qw/
							CRITERION   CRIT
							CRITERIA    CRIT
							MAXIMUM     MAX
							MINIMUM     MIN
							PRICE       COST
							QUALIFIER   QUAL
							CODE        PERL
							SUB         PERL
							UPS_TYPE    TABLE
							DESCRIPTION DESC
							ZIP         GEO 
							LOOKUP      TABLE
							DEFAULT_ZIP DEFAULT_GEO 
							SQL         QUERY
					/);

sub make_three {
	my ($zone, $len) = @_;
	$len = 3 if ! $len;
	while ( length($zone) < $len ) {
		$zone = "0$zone";
	}
	return $zone;
}

%Ship_handler = (
		TYPE =>
					sub { 
							my ($v,$k) = @_;
							$$v =~ s/^(.).*/$1/;
							$$v = lc $$v;
							$$k = 'COST';
					}
		,
);

sub read_shipping {
	my ($file, $opt) = @_;
	$opt = {} unless $opt;
    my($code, $desc, $min, $criterion, $max, $cost, $mode);

	if ($file) {
		#nada
	}
	elsif($opt->{add} or $Vend::Cfg->{Variable}{MV_SHIPPING}) {
		$file = "$Vend::Cfg->{ScratchDir}/shipping.asc";
		Vend::Util::writefile(">$file", $opt->{add} || $Vend::Cfg->{Variable}{MV_SHIPPING});
	}
	else {
		$file = $Vend::Cfg->{Special}{'shipping.asc'}
				|| Vend::Util::catfile($Vend::Cfg->{ProductDir},'shipping.asc');
	}

    open(SHIPPING, "< $file") or do {
			if ($Vend::Cfg->{CustomShipping} =~ /^select\s+/i) {
				($Vend::Cfg->{SQL_shipping} = 1, return)
					if $Vend::Foreground;
				$file = "$Vend::Cfg->{ScratchDir}/shipping.asc";
				my $ary;
				my $query = interpolate_html($Vend::Cfg->{CustomShipping});
				eval {
					$ary = query($query, { wantarray => 1} );
				};
				if(! ref $ary) {
					logError("Could not make shipping query %s: %s" ,
								$Vend::Cfg->{CustomShipping},
								$@);
					return undef;
				}
				my $out;
				for(@$ary) {
					$out .= join "\t", @$_;
					$out .= "\n";
					Vend::Util::writefile(">$file", $out);
				}
				open(SHIPPING, "< $file") or do {
					logError("Could not make shipping query %s: %s" ,
								$Vend::Cfg->{CustomShipping},
								$!);
					return undef;
				};
			}
			else {
				logError("Could not open shipping file %s: %s" , $file, $!)
					if $Vend::Cfg->{CustomShipping};
				return undef;
			}
		};
	$Vend::Cfg->{Shipping_desc} = {}
		if ! $Vend::Cfg->{Shipping_desc};
	my %seen;
	my $append = '00000';
	my @line;
	my @shipping;
	my $first;
    while(<SHIPPING>) {
		chomp;
		if(s/\\$//) {
			$_ .= <SHIPPING>;
			redo;
		}
		elsif (s/<<(\w+)$//) {
			my $mark = $1;
			my $line = $_;
			$line .= Vend::Config::read_here(\*SHIPPING, $mark);
			$_ = $line;
			redo;
		}
		next unless /\S/;
		s/\s+$//;
		if(/^[^\s:]+\t/) {
			push (@shipping, [@line]) if @line;
			@line = split(/\t/, $_);
			$Vend::Cfg->{Shipping_desc}->{$line[0]} = $line[1]
				unless $seen{$line[0]}++;
			push @shipping, [@line];
			@line = ();
		}
		elsif(/^(\w+)\s*:\s*(.*)/s) {
			push (@shipping, [@line]) if @line;
			@line = ($1, $2, 'quantity', 0, 999999999, 0);
			$first = 1;
			$Vend::Cfg->{Shipping_desc}->{$line[0]} = $line[1]
				unless $seen{$line[0]}++;
			next;
		}
		elsif(/^\s+min(?:imum)?\s+(\S+)/i) {
			my $min = $1;
			if ($first) {
				undef $first;
				$line[MIN] = $min;
			}
			else {
				push @shipping, [ @line ];
				$line[MIN] = $min;
				if(ref $line[OPT]) {
					my $ref = $line[OPT];
					$line[OPT] = { %$ref };
				}

			}
		}
		else {
			no strict 'refs';
			s/^\s+//;
			my($k, $v) = split /\s+/, $_, 2;
			my $prospect;
			$k = uc $k;
			$k = $Ship_remap{$k}
				if defined $Ship_remap{$k};
			$Ship_handler{$k}->(\$v, \$k, \@line)
				if defined $Ship_handler{$k};
			eval {
				if(defined &{"$k"}) {
						$line[&{"$k"}] = $v;
				}
				else {
					$line[OPT] = {} unless $line[OPT];
					$k = lc $k;
					$line[OPT]->{$k} = $v;
				}
			};
			::logError(
				"bad shipping index %s for mode %s in $file",
				$k,
				$line[0],
				) if $@;
		}
	}
    close SHIPPING;

	push @shipping, [ @line ]
		if @line;

	my $row;
	my %zones;
	foreach $row (@shipping) {
		my $cost = $row->[COST];
		my $o = get_option_hash($row->[OPT]);
		$row->[OPT] = $o;
		my $zone;
		if ($zone = $o->{zone} or $cost =~ s/^\s*c\s+(\w+)\s*//) {
			$zone = $1 if ! $zone;
			next if defined $zones{$zone};
			my $ref;
			if ($o->{zone}) {
				$ref = {};
				my @common = qw/
							mult_factor				
							str_length				
							zone_data
							zone_file				
							zone_name				
						/; 
				@{$ref}{@common} = @{$o}{@common};
				$ref->{zone_name} = $zone
					if ! $ref->{zone_name};
			}
			elsif ($cost =~ /^{[\000-\377]+}$/ ) {
				eval { $ref = eval $cost };
			}
			else {
				$ref = {};
				my($name, $file, $length, $multiplier) = split /\s+/, $cost;
				$ref->{zone_name} = $name || undef;
				$ref->{zone_file} = $file if $file;
				$ref->{mult_factor} = $multiplier if defined $multiplier;
				$ref->{str_length} = $length if defined $length;
			}
			if ($@
				or ref($ref) !~ /HASH/
				or ! $ref->{zone_name}) {
				logError(
					"Bad shipping configuration for mode %s, skipping.",
					$row->[MODE]
				);
				$row->[MODE] = 'ERROR';
				next;
			}
			$ref->{zone_key} = $zone;
			$ref->{str_length} = 3 unless defined $ref->{str_length};
			$zones{$zone} = $ref;
		}
    }

	if($Vend::Cfg->{UpsZoneFile} and ! defined $Vend::Cfg->{Shipping_zone}{'u'} ) {
			 $zones{'u'} = {
				zone_file	=> $Vend::Cfg->{UpsZoneFile},
				zone_key	=> 'u',
				zone_name	=> 'UPS',
				};
	}
	UPSZONE: {
		for (keys %zones) {
			my $ref = $zones{$_};
			if (! $ref->{zone_data}) {
				$ref->{zone_file} = Vend::Util::catfile(
											$Vend::Cfg->{ProductDir},
											"$ref->{zone_name}.csv",
										) if ! $ref->{zone_file};
				$ref->{zone_data} =  readfile($ref->{zone_file});
			}
			unless ($ref->{zone_data}) {
				logError( "Bad shipping file for zone '%s', lookup disabled.",
							$ref->{zone_key},
						);
				next;
			}
			my (@zone) = grep /\S/, split /[\r\n]+/, $ref->{zone_data};
			if($zone[0] !~ /\t/) {
				my $len = $ref->{str_len} || 3;
				@zone = grep /\S/, @zone;
				@zone = grep /^[^"]/, @zone;
				$zone[0] =~ s/[^\w,]//g;
				$zone[0] =~ s/^\w+/low,high/;
				@zone = grep /,/, @zone;
				$zone[0] =~	s/\s*,\s*/\t/g;
				for(@zone[1 .. $#zone]) {
					s/^\s*(\w+)\s*,/make_three($1, $len) . ',' . make_three($1, $len) . ','/e;
					s/^\s*(\w+)\s*-\s*(\w+),/make_three($1, $len) . ',' . make_three($2, $len) . ','/e;
					s/\s*,\s*/\t/g;
				}
			}
			$ref->{zone_data} = \@zone;
		}
	}
	for (keys %zones) {
		$Vend::Cfg->{Shipping_zone}{$_} = $zones{$_};
	}
	$Vend::Cfg->{Shipping_line} = []
		if ! $Vend::Cfg->{Shipping_line};
	unshift @{$Vend::Cfg->{Shipping_line}}, @shipping;
	1;
}

*custom_shipping = \&shipping;

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

	if( $ref eq "\L$value" or ! length($ref) && $default) {
		$r = 'CHECKED';
	}
	elsif ($multiple) {
		my $regex = quotemeta $value;
		$r = 'CHECKED' if $ref =~ /(?:^|\0)$regex(?:$|\0)/i;
	}
	else {$r = ''}
	return $r;
}

# Returns an href to place an order for the product PRODUCT_CODE.
# If AlwaysSecure is set, goes by the page accessed, otherwise 
# if a secure order has been started (with a call to at least
# one secure_vendUrl), then it will be given the secure URL
 
sub tag_order {
    my($code,$quantity,$opt) = @_;
	$opt = {} unless $opt;
    my($r);
	my @parms = (
					"mv_action=refresh",
				  );

	push(@parms, "mv_order_item=$code");
	push(@parms, "mv_order_mv_ib=$opt->{base}")
		if($opt->{base});

	push(@parms, "mv_order_quantity=$quantity")
		if($quantity);

	$opt->{form} = join "\n", @parms;

	$opt->{page} = find_special_page('order')
		unless $opt->{page};

	return form_link($opt->{area}, $opt->{arg}, $opt)
		if $opt->{area};
	return tag_page($opt->{page}, $opt->{arg}, $opt);
}

# Sets the value of a discount field
sub tag_discount {
	my($code, $opt, $value) = @_;

	# API compatibility
	if(! ref $opt) {
		$value = $opt;
		$opt = {};
	}

	if($opt->{subtract}) {
		$value = <<EOF;
my \$tmp = \$s - $opt->{subtract};
\$tmp = 0 if \$tmp < 0;
return \$tmp;
EOF
	}
	elsif ($opt->{level}) {
		$value = <<EOF;
return (\$s * \$q) if \$q < $opt->{level};
my \$tmp = \$s / \$q;
return \$s - \$tmp;
EOF
	}
    $Vend::Session->{discount}{$code} = $value;
	delete $Vend::Session->{discount}->{$code}
		unless (defined $value and $value);
	return '';
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

	if (defined $opt->{if}) {
		$abort = 1 if ! $opt->{if}; 
	}

	my $saved_file;
	if($opt->{scan}) {
		$saved_file = $Vend::ScanPassed;
		$abort = 1 if ! $saved_file || $file =~ m:MM=:;
	}

	return Vend::Interpolate::interpolate_html(shift)
		if $abort
		or !  $CGI::cookie
		or $Vend::BuildingPages
		or ! $opt->{login} && $Vend::Session->{logged_in};

    if($opt->{noframes} and $Vend::Session->{frames}) {
        return '';
    }

	my $secs;
	my $static;
	my $fullfile;
	CHECKDIR: {
		last CHECKDIR if $file;
		my $dir = $Vend::Cfg->{StaticDir};
		$dir = ! -d $dir || ! -w _ ? 'timed' : do { $static = 1; $dir };

		$file = $saved_file || $Vend::Flypart || $Global::Variable->{MV_PAGE};
#::logDebug("static=$file");
		if($saved_file) {
			$file = $saved_file;
			$file =~ s:^scan/::;
			$file = ::generate_key($file);
			$file = "scan/$file";
		}
		else {
		 	$saved_file = $file = ($Vend::Flypart || $Global::Variable->{MV_PAGE});
		}
		$file .= $Vend::Cfg->{StaticSuffix};
		$fullfile = $file;
		$dir .= "/$1" 
			if $file =~ s:(.*)/::;
		if(! -d $dir) {
			require File::Path;
			File::Path::mkpath($dir);
		}
		$file = Vend::Util::catfile($dir, $file);
	}

#::logDebug("saved=$saved_file");
#::logDebug("file=$file exists=" . -f $file);
	if($opt->{minutes}) {
        $secs = int($opt->{minutes} * 60);
    }
	elsif ($opt->{period}) {
		$secs = Vend::Config::time_to_seconds($opt->{period});
	}

    if( ! -f $file or $secs && (stat(_))[9] < (time() - $secs) ) {
        my $out = Vend::Interpolate::interpolate_html(shift);
		$opt->{umask} = '22' unless defined $opt->{umask};
        Vend::Util::writefile(">$file", $out, $opt );
# STATICPAGE
		if ($Vend::Cfg->{StaticDBM} and ::tie_static_dbm(1) ) {
			if ($opt->{scan}) {
				$saved_file =~ s!=([^/]+)=!=$1%3d!g;
				$saved_file =~ s!=([^/]+)-!=$1%2d!g;
#::logDebug("saved_file=$saved_file");
				$Vend::StaticDBM{$saved_file} = $fullfile;
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
			$cart = $::Carts->{$opt->{name}};
		}
		else {
			$cart = $Vend::Items;
		}
		return if ! ref $cart;
		Vend::Cart::toss_cart($cart);
	}
	elsif ($func eq 'process') {
		::do_process();
	}
	elsif ($func eq 'values') {
		::update_user();
	}
	elsif ($func eq 'data') {
		::update_data();
	}
	return;
}

my $Ship_its = 0;

sub tag_error {
	my($var, $opt) = @_;
	$Vend::Session->{errors} = {}
		unless defined $Vend::Session->{errors};
	my $err_ref = $Vend::Session->{errors};
	my $text;
	$text = $opt->{text} if $opt->{text};
	my @errors;
	my $found_error = '';
#::logDebug("tag_error: var=$var text=$text opt=" . ::uneval($opt));
#::logDebug("tag_error: var=$var text=$text");
	if($opt->{all}) {
		$opt->{joiner} = "\n" unless defined $opt->{joiner};
		for(sort keys %$err_ref) {
			my $err = $err_ref->{$_};
			delete $err_ref->{$_} unless $opt->{keep};
			next unless $err;
			$found_error++;
			my $string = '';
			$string .= "$_: " if $opt->{show_var};
			$string .= $err;
			push @errors, $string;
		}
#::logDebug("error all=1 found=$found_error contents='@errors'");
		return $found_error unless $text || $opt->{show_error};
		$text .= "%s" if $text !~ /\%s/;
		$text = pull_else($text, $found_error);
		return sprintf $text, join($opt->{joiner}, @errors);
	}
	$found_error = ! (not $err_ref->{$var});
	my $err = $err_ref->{$var} || '';
	delete $err_ref->{$var} unless $opt->{keep};
#::logDebug("error found=$found_error contents='$err'");
	return !(not $found_error)
		unless $opt->{std_label} || $text || $opt->{show_error};
	if($opt->{std_label}) {
		if(defined $::Variable->{MV_ERROR_STD_LABEL}) {
			$text = $::Variable->{MV_ERROR_STD_LABEL};
		}
		else {
			$text = <<EOF;
<FONT COLOR=RED>{LABEL} <SMALL><I>(%s)</I></SMALL></FONT>
[else]{REQUIRED <B>}{LABEL}{REQUIRED </B>}[/else]
EOF
		}
		$text =~ s/{LABEL}/$opt->{std_label}/g;
		$text =~ s/{REQUIRED\s+([^}]*)}/$opt->{required} ? $1 : ''/ge;
	}
	$text = '' unless defined $text;
	$text .= '%s' unless $text =~ /\%s/;
	$text = pull_else($text, $found_error);
	return sprintf($text, $err);
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
		::logError("tag_column: can't have 'wrap' and 'html' specified at same time.");
		$spec{wrap} = 0;
	}

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
	#while( $text =~ s!$QR{col}!!    ) {
	while( $text =~ s!\[col(?:umn)?\s+
				 		([^\]]+)
				 		\]
				 		([\000-\377]*?)
				 		\[/col(?:umn)?\] !!ix    ) {
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

sub shipping {
	my($mode, $opt) = @_;
	return undef unless $mode;
    my $save = $Vend::Items;
	my $qual;
	my $final;

	$Vend::Session->{ship_message} = '' if ! $Ship_its;
	die "Too many levels of shipping recursion ($Ship_its)" 
		if $Ship_its++ > MAX_SHIP_ITERATIONS;
	my @bin;

#::logDebug("Check BEGIN, must get to FINAL. Vend::Items=$Vend::Items main=$::Carts->{main}");
	if ($opt->{cart}) {
		my @carts = grep /\S/, split /[\s,]+/, $opt->{cart};
		for(@carts) {
			next unless $::Carts->{$_};
			push @bin, @{$::Carts->{$_}};
		}
	}
	else {
		@bin = @$Vend::Items;
	}
#::logDebug("doing shipping, mode=$mode bin=" . ::uneval(\@bin));

	$Vend::Session->{ship_message} = '' if $opt->{reset_message};

	my($field, $code, $i, $total, $cost, $multiplier, $formula, $error_message);

	my $ref = $Vend::Cfg;
#
#	if(defined $Vend::Cfg->{Shipping_criterion}->{$mode}) {
#		$ref = $Vend::Cfg;
#	}
#	elsif($Vend::Cfg->{Shipping}) {
#		my $locale = 	$::Scratch->{mv_currency}
#						|| $::Scratch->{mv_locale}
#						|| $::Vend::Cfg->{DefaultLocale}
#						|| 'default';
#		$ref = $Vend::Cfg->{Shipping}{$locale};
#		$field = $ref->{$mode};
#	}
#
#	if(defined $ref->{Shipping_code}{$mode}) {
#		$final = tag_perl($opt->{table}, $opt, $Vend::Cfg->{Shipping_code});
#		goto SHIPFORMAT;
#	}

	$@ = 1;

	# Security hole if we don't limit characters
	$mode !~ /[\s,;{}]/ and 
		eval {'what' =~ /$mode/};

	if ($@) {
#::logDebug("Check ERROR, must get to FINAL. Vend::Items=$Vend::Items main=$::Carts->{main}");
		logError("Bad character(s) in shipping mode '$mode', returning 0");
		goto SHIPFORMAT;
	}

	my $row;
	my @lines;
	@lines = grep $_->[0] =~ /^$mode/, @{$Vend::Cfg->{Shipping_line}};
	goto SHIPFORMAT unless @lines;
#::logDebug("shipping lines selected: " . ::uneval(\@lines));
	my $q;
	if($lines[0][QUERY]) {
		my $q = interpolate_html($lines[0][QUERY]);
		$q =~ s/=\s+?\s*/= '$mode' /g;
		$q =~ s/\s+like\s+?\s*/ LIKE '%$mode%' /ig;
		my $ary = query($q);
		@lines = @$ary;
#::logDebug("shipping lines reselected with SQL: " . ::uneval(\@lines));
	}

	my $o = get_option_hash($lines[0][OPT]) || {};

#::logDebug("shipping opt=" . ::uneval($o));

	if($o->{limit}) {
		$o->{filter} = '(?i)\s*[1ty]' if ! $o->{filter};
#::logDebug("limiting, filter=$o->{filter} limit=$o->{limit}");
		my $patt = qr{$o->{filter}};
		@bin = grep $_->{$o->{limit}} =~ $patt, @bin;
	}
	$::Carts->{mv_shipping} = \@bin;

	tag_cart('mv_shipping');

#::logDebug("Check 2, must get to FINAL. Vend::Items=" . ::uneval($Vend::Items) . " main=" . ::uneval($::Carts->{main}) . " mv_shipping=" . ::uneval($::Carts->{mv_shipping}));

	if($o->{perl}) {
		$Vend::Interpolate::Shipping   = $lines[0];
		$field = $lines[0][CRIT];
		$field = tag_perl($opt->{tables}, $opt, $field)
			if $field =~ /[^\w:]/;
		$qual  = tag_perl($opt->{tables}, $opt, $o->{qual})
					if $o->{qual};
	}
	elsif ($o->{mml}) {
		$Vend::Interpolate::Shipping   = $lines[0];
		$field = tag_perl($opt->{tables}, $opt, $lines[0][CRIT]);
		$qual =  tag_perl($opt->{tables}, $opt, $o->{qual})
					if $o->{qual};
	}
	elsif($lines[0][CRIT] =~ /[[\s]|__/) {
		($field, $qual) = split /\s+/, interpolate_html($lines[0][CRIT]), 2;
		if($qual =~ /{}/) {
			logError("Bad qualification code '%s', returning 0", $qual);
			goto SHIPFORMAT;
		}
	}
	else {
		$field = $lines[0][CRIT];
	}

	goto SHIPFORMAT unless $field;

	# See if the field needs to be returned by a Interchange function.
	# If a space is encountered, a qualification code
	# will be set up, with any characters after the first space
	# used to determine geography or other qualifier for the mode.
	
	# Uses the quantity on the order form if the field is 'quantity',
	# otherwise goes to the database.
    $total = 0;

	if($field =~ /^[\d.]+$/) {
#::logDebug("Is a number selection");
		$total = $field;
	}
	elsif($field eq 'quantity') {
#::logDebug("quantity selection");
    	foreach $i (0 .. $#$Vend::Items) {
			$total = $total + $Vend::Items->[$i]->{$field};
    	}
	}
	elsif ( index($field, ':') != -1) {
#::logDebug("outboard field selection");
		my ($base, $field) = split /:+/, $field;
		my $db = database_exists_ref($base);
		unless ($db and db_column_exists($db,$field) ) {
			logError("Bad shipping field '$field' or table '$base'. Returning 0");
			goto SHIPFORMAT;
		}
    	foreach $i (0 .. $#$Vend::Items) {
			my $item = $Vend::Items->[$i];
			$total += (database_field($base, $item->{code}, $field) || 0) *
						$item->{quantity};
		}
	}
	else {
#::logDebug("standard field selection");
		unless (column_exists $field) {
			logError("Custom shipping field '$field' doesn't exist. Returning 0");
			goto SHIPFORMAT;
		}
    	foreach my $item (@$Vend::Items) {
			my $base = $item->{mv_ib} || $Vend::Cfg->{ProductFiles}[0];
			my $value = tag_data($base, $field, $item->{code});
			$total += $value * $item->{quantity};
		}
	}

	# We will LAST this loop and go to SHIPFORMAT if a match is found
	SHIPIT: 
	foreach $row (@lines) {
#::logDebug("processing mode=$row->[MODE] field=$field total=$total min=$row->[MIN] max=$row->[MAX]");

		next unless  $total <= $row->[MAX] and $total >= $row->[MIN];

		if($qual) {
			next unless
				$row->[CRIT] =~ m{(^|\s)$qual(\s|$)} or
				$row->[CRIT] !~ /\S/;
		}

		$o = get_option_hash($row->[OPT], $o)
			if $row->[OPT];
		# unless field begins with 'x' or 'f', straight cost is returned
		# - otherwise the quantity is multiplied by the cost or a formula
		# is applied
		my $what = $row->[COST];
		if($what !~ /^[a-zA-Z]\w+$/) {
			$what =~ s/^\s+//;
			$what =~ s/[ \t\r]+$//;
		}
		if($what =~ /^(-?(?:\d+(?:\.\d*)?|\.\d+))$/) {
			$final += $1;
			last SHIPIT unless $o->{continue};
		}
		elsif ($what =~ /^f\s*(.*)/i) {
			$formula = $o->{formula} || $1;
			$formula =~ s/\@\@TOTAL\@\\?\@/$total/ig;
			$formula = interpolate_html($formula)
				if $formula =~ /__\w+__|\[\w/;
			$cost = $Vend::Interpolate::ready_safe->reval($formula);
			if($@) {
				$error_message   = errmsg(
								"Shipping mode '%s': bad formula. Returning 0.",
								$mode,
							);
				logError($error_message);
				last SHIPIT;
			}
			$final += $cost;
			last SHIPIT unless $o->{continue};
		}
		elsif ($what eq 'x') {
			$final += ($o->{multiplier} * $total);
			last SHIPIT unless $o->{continue};
		}
		elsif ($what =~ s/^x\s*(-?[\d.]+)\s*$/$1/) {
			$final += ($what * $total);
			last SHIPIT unless $o->{continue};
		}
		elsif ($what =~ s/^([uA-Z])\s*//) {
			my $zselect = $o->{zone} || $1;
			my ($type, $geo, $adder, $mod, $sub);
			($type, $geo, $adder) = @{$o}{qw/table geo adder/};
			if(! $type) {
				$what = interpolate_html($what);
				($type, $geo, $adder, $mod, $sub) = split /\s+/, $what, 5;
				$o->{adder}    = $adder;
				$o->{round}    = 1  if $mod =~ /round/;
				$o->{at_least} = $1 if $mod =~ /min\s*([\d.]+)/;
			}
			elsif (! $o->{geo}) {
				$geo = interpolate_html($what);
			}
			else {
				$geo = $::Values->{$o->{geo}} || $o->{default_geo};
			}

			$cost = tag_ups($type,$geo,$total,$zselect,$o);
			FIGURE: {
				last FIGURE unless $cost;
			}
			$final += $cost;
			last SHIPIT unless $o->{continue};
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
						$item->{$_} = tag_data($1, $_, $item->{code});
					}
					else {
						$item->{$_} = product_field($_, $item->{code});
					}
					$sum->{$_} += $item->{$_} if defined $sum;
				}
			}
			@items = ($sum) if defined $sum;
			for(@items) {
				$cost = Vend::Data::chain_cost($_, $what);
				if($cost =~ /[A-Za-z]/) {
					$cost = shipping($cost);
				}
				$final += $cost;
			}
			last SHIPIT unless $o->{continue};
		}
		elsif ($what =~ s/^e\s*//) {
			$error_message = $what;
			$error_message =~ s/\@\@TOTAL\@\@/$total/ig;
			$final = 0 unless $final;
			last SHIPIT unless $o->{continue};
		}
		else {
			$error_message = errmsg( "Unknown shipping call '%s'", $what);
			undef $final;
			last SHIPIT;
		}
	}

	if ($final == 0 and $o->{'next'}) {
		return shipping($o->{'next'}, $opt);
	}
	elsif(defined $o->{additional}) {
		my @extra = grep /\S/, split /[\s\0,]+/, $row->[OPT]->{additional};
		for(@extra) {
			$final += shipping($_, {});
		}
	}

#::logDebug("Check 3, must get to FINAL. Vend::Items=$Vend::Items main=$::Carts->{main}");


	SHIPFORMAT: {
		$Vend::Session->{ship_message} .= $error_message
			if defined $error_message;
		undef $::Carts->{mv_shipping};
		$Vend::Items = $save;
#::logDebug("Check FINAL. Vend::Items=$Vend::Items main=$::Carts->{main}");
		last SHIPFORMAT unless defined $final;
		unless ($o->{free}) {
			return '' if $final == 0;
			$o->{adder} =~ s/\bx\b/$final/g;
			$o->{adder} =~ s/\@\@TOTAL\@\\?\@/$final/g;
			$o->{adder} = $ready_safe->reval($o->{adder});
			$final += $o->{adder} if $o->{adder};
			$final = POSIX::ceil($final) if is_yes($o->{round});
			if($o->{at_least}) {
				$final = $final > $o->{at_least} ? $final : $o->{at_least};
			}
		}
		if($opt->{default}) {
			if(! $opt->{handling}) {
				$::Values->{mv_shipmode} = $mode;
			}
			else {
				$::Values->{mv_handling} = $mode;
			}
			undef $opt->{default};
		}
		return $final unless $opt->{label};
		my $number;
		if($o->{free}) {
			$number = $opt->{free}
				if $final == 0;
		}
		else {
			return $final unless $opt->{label};
			$number = Vend::Util::currency( 
											$final,
											$opt->{noformat},
											$row->[OPT]->{PriceDivide},
									);
		}
		my $label = $opt->{format} || '<OPTION VALUE="%M"%S>%D (%F)';
		my $sel = $::Values->{mv_shipmode} eq $mode;
#::logDebug("label start: $label");
		my %subst = (
						'%' => '%',
						M => $mode,
						T => $total,
						S => $sel ? ' SELECTED' : '',
						C => $sel ? ' CHECKED' : '',
						D => $row->[DESC] || $Vend::Cfg->{Shipping_desc}{$mode},
						L => $row->[MIN],
						H => $row->[MAX],
						O => '$O',
						F => $number,
						N => $final,
						E => defined $error_message ? "(ERROR: $error_message)" : '',
						e => $error_message,
						Q => $qual,
					);
		$label =~ s/(%(.))/exists $subst{$2} ? $subst{$2} : $1/eg;
#::logDebug("label intermediate: $label");
		$label =~ s/(\$O{(.*?)})/$o->{$2}/eg;
#::logDebug("label returning: $label");
		return $label;
	}

	# If we got here, the mode and quantity fit was not found
	$Vend::Session->{ship_message} .=
		"No match found for mode '$mode', quantity '$total', "	.
		($qual ? "qualifier '$qual', " : '')					.
		"returning 0. ";
	return undef;
}

*custom_shipping = \&shipping;

sub taxable_amount {
	my($cart) = @_;
    my($taxable, $i, $code, $item, $tmp, $quantity);

	return subtotal($cart || undef) unless $Vend::Cfg->{NonTaxableField};

	my($save);

    if ($cart) {
        $save = $Vend::Items;
        tag_cart($cart);
    }

    $taxable = 0;

    foreach $i (0 .. $#$Vend::Items) {
		$item =	$Vend::Items->[$i];
		next if is_yes( $item->{mv_nontaxable} );
		next if is_yes( item_field($item, $Vend::Cfg->{NonTaxableField}) );
		$tmp = item_subtotal($item);
		unless (defined $Vend::Session->{discount}) {
			$taxable += $tmp;
		}
		else {
			$taxable += apply_discount($item);
		}
    }

	$Vend::Items = $save if defined $save;

	$taxable;
}

sub tag_handling {
	my ($mode, $opt) = @_;
	$opt = { noformat => 1, convert => 1 } unless $opt;

	if($opt->{default}) {
		undef $opt->{default}
			if tag_shipping( undef, {handling => 1});
	}

	$opt->{handling} = 1;
	if(! $mode) {
		$mode = $::Values->{mv_handling} || undef;
	}
	return tag_shipping($mode, $opt);
}

sub tag_shipping {
	my($mode, $opt) = @_;
	$opt = { noformat => 1, convert => 1 } unless $opt;
	$Ship_its = 0;
	if(! $mode) {
		$mode = $opt->{handling}
				? ($::Values->{mv_handling})
				: ($::Values->{mv_shipmode} || 'default');
	}
	$Vend::Cfg->{shipping_line} = [] 
		if $opt->{reset_modes};
	read_shipping(undef, $opt) if $Vend::Cfg->{SQL_shipping};
	read_shipping(undef, $opt) if $opt->{add};
	read_shipping($opt->{file}) if $opt->{file};
	my $out;


	my (@modes) = grep /\S/, split /[\s,\0]+/, $mode;
	if($opt->{default}) {
		undef $opt->{default}
			if tag_shipping($::Values->{mv_shipmode});
	}
	if($opt->{label}) {
		for(@modes) {
			$out .= shipping($_, $opt);
		}
	}
	else {
		$out = 0;
		for(@modes) {
			$out += shipping($_, $opt);
		}
		$out = currency($out, $opt->{noformat}, $opt->{convert});
	}
	return $out unless $opt->{hide};
	return;
}


sub fly_tax {
	my ($area) = @_;
	if(! $area) {
		my $zone = $Vend::Cfg->{SalesTax};
		while($zone =~ m/(\w+)/g) {
			last if $area = $::Values->{$1};
		}
	}
#::logDebug("flytax area=$area");
	return 0 unless $area;
	my $rates = $::Variable->{TAXRATE};
	my $taxable_shipping = $::Variable->{TAXSHIPPING} || '';
	my $taxable_handling = $::Variable->{TAXHANDLING} || '';
	$rates =~ s/^\s+//;
	$rates =~ s/\s+$//;
	$area =~ s/^\s+//;
	$area =~ s/\s+$//;
	my (@rates) = split /\s*,\s*/, $rates;
	my $rate;
	for(@rates) {
		my ($k,$v) = split /\s*=\s*/, $_, 2;
		next unless "\U$k" eq "\U$area";
		$rate = $v;
		$rate = $rate / 100 if $rate > 1;
		last;
	}
#::logDebug("flytax rate=$rate");
	return 0 unless $rate;
	my $amount = taxable_amount();
#::logDebug("flytax before shipping amount=$amount");
	$amount   += tag_shipping()
		if $taxable_shipping =~ m{(^|[\s,])$area([\s,]|$)}i;
	$amount   += tag_handling()
		if $taxable_handling =~ m{(^|[\s,])$area([\s,]|$)}i;
#::logDebug("flytax amount=$amount return=" . $amount*$rate);
	return $amount * $rate;
}

# Calculate the sales tax
sub salestax {
	my($cart) = @_;
	my($save);

    if ($cart) {
        $save = $Vend::Items;
        tag_cart($cart);
    }

	my $amount = taxable_amount();
	my($r, $code);
	# Make it upper case for state and overseas postal
	# codes, zips don't matter
	my(@code) = map { (uc $::Values->{$_}) || '' }
					split /[,\s]+/, $Vend::Cfg->{SalesTax};
	push(@code, 'DEFAULT');

	my $tax_hash;
	if($Vend::Cfg->{SalesTaxFunction}) {
		$tax_hash = tag_calc($Vend::Cfg->{SalesTaxFunction});
#::logDebug("found custom tax function: " . ::uneval($tax_hash));
	}
	else {
		$tax_hash = $Vend::Cfg->{SalesTaxTable};
#::logDebug("looking for tax function: " . ::uneval($tax_hash));
	}

	if(! $tax_hash) {
		my $cost = fly_tax();
		$Vend::Items = $save if $save;
		return $cost;
	}
#::logDebug("got to tax function: " . ::uneval($tax_hash));

	$tax_hash = { DEFAULT => } if ! ref($tax_hash) =~ /HASH/;

	if(! defined $tax_hash->{DEFAULT}) {
#::logDebug("Sales tax failed, no tax source, returning 0");
		return 0;
	}

	CHECKSHIPPING: {
		last CHECKSHIPPING unless $Vend::Cfg->{TaxShipping};
		foreach $code (@code) {
			next unless $Vend::Cfg->{TaxShipping} =~ /\b\Q$code\E\b/i;
			$amount += tag_shipping();
			last;
		}
	}

	foreach $code (@code) {
		next unless $code;
		# Trim the zip+4
#::logDebug("salestax: check code '$code'");
		$code =~ s/(\d{5})-\d{4}/$1/;
		next unless defined $tax_hash->{$code};
		my $tax = $tax_hash->{$code};
#::logDebug("salestax: found tax='$tax' for code='$code'");
		if($tax =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/) {
			$r = $amount * $tax;
		}
		else {
			$r = Vend::Data::chain_cost(
					{	mv_price	=> $amount, 
						code		=> $code,
						quantity	=> $amount, }, $tax);
		}
#::logDebug("salestax: final tax='$r' for code='$code'");
		last;
	}

	$Vend::Items = $save if defined $save;

	return Vend::Util::round_to_frac_digits($r);
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
	my $discount = defined $Vend::Session->{discount};

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



	if (defined $Vend::Session->{discount}->{ENTIRE_ORDER}) {
		$formula = $Vend::Session->{discount}->{ENTIRE_ORDER};
		$formula =~ s/\$q\b/tag_nitems()/eg; 
		$formula =~ s/\$s\b/$subtotal/g; 
		$cost = $Vend::Interpolate::ready_safe->reval($formula);
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

# Returns the total cost of items ordered.

sub total_cost {
	my($cart) = @_;
    my($total, $i, $save);

	if ($cart) {
		$save = $Vend::Items;
		tag_cart($cart);
	}

	$total = 0;

	my $shipping = 0;
	$shipping += tag_shipping()
		if $::Values->{mv_shipmode};
	$shipping += tag_handling()
		if $::Values->{mv_shipmode};
    $total += subtotal();
    $total += $shipping;
    $total += salestax();

	$Vend::Items = $save if defined $save;
	$Vend::Session->{latest_total} = $total;
    return $total;
}

sub tag_total_cost {
	my($cart, $noformat) = @_;
	return currency( total_cost($cart), $noformat);
}

sub tag_ups {
	my($type,$zip,$weight,$code,$opt) = @_;
	my(@data);
	my(@fieldnames);
	my($i,$point,$zone);

#::logDebug("tag_ups: type=$type zip=$zip weight=$weight code=$code opt=" . ::uneval($opt));
	$code = 'u' unless $code;

	unless (defined $Vend::Database{$type}) {
		logError("Shipping lookup called, no database table named '%s'", $type);
		return undef;
	}
	unless (ref $Vend::Cfg->{Shipping_zone}{$code}) {
		logError("Shipping '%s' lookup called, no zone defined", $code);
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
	$weight = POSIX::ceil($weight);

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

	my $eas_point;
	my $eas_zone;
	if($zref->{eas}) {
		for($i = 2; $i < @fieldnames; $i++) {
			next unless $fieldnames[$i] eq $zref->{eas};
			$eas_point = $i;
			last;
		}
	}

	for(@{$zdata}[1..$#{$zdata}]) {
		@data = split /\t/, $_;
		next unless ($zip ge $data[0] and $zip le $data[1]);
		$zone = $data[$point];
		$eas_zone = $data[$eas_point] if defined $eas_point;
		return 0 unless $zone;
		last;
	}

	if (! defined $zone) {
		$Vend::Session->{ship_message} .=
			"No zone found for geo code $zip, type $type. ";
		return undef;
	}
	elsif (!$zone or $zone eq '-') {
		$Vend::Session->{ship_message} .=
			"No $type shipping allowed for geo code $zip.";
		return undef;
	}

	my $cost;
	$cost =  tag_data($type,$zone,$weight);
	$cost += tag_data($type,$zone,$eas_zone)  if defined $eas_point;
	$Vend::Session->{ship_message} .=
								errmsg(
									"Zero cost returned for mode %s, geo code %s.",
									$type,
									$zip,
								)
		unless $cost;
#::logDebug("tag_ups cost: $cost");
	return $cost;
}

1;
