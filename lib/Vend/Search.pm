#!/usr/bin/perl -w
#
# $Id: Search.pm,v 1.1.1.1 2000/03/09 19:08:21 mike Exp $
#
# Vend::Search -- Base class for search engines
#
# Copyright 1996-2000 by Michael J. Heins <mikeh@minivend.com>
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
#

#
#
package Vend::Search;

$VERSION = substr(q$Revision: 1.1.1.1 $, 10);

use strict;
use vars qw($VERSION);

sub new {
	my $class = shift;
	my $s = {@_};
	bless $s, $class;
	return $s;
}

sub get_scalar {
	my $s = shift;
	my @out;
	for (@_) {
		push @out, (ref $s->{$_} ? $s->{$_}[0] : $_[0] || '');
	}
	return @out;
}

sub version {
	$Vend::Search::VERSION;
}

my %maytag = (
	mv_return_fields => sub { 
		my $s = shift;
		my $i;
		while (defined ($i = shift)) {
			next if $s->{mv_return_fields}[$i] =~ /^\d+$/;
			$s->{mv_return_fields}[$i] = 255;
		}
	},
	mv_range_look    => sub { undef shift->{range_look} },
	mv_sort_field    => sub {
		my $s = shift;
		my $i;
		while (defined ($i = shift)) {
#::logDebug("checking sort field $s->{mv_sort_field}[$i]");
			# Assume they know what they are doing
			next if $s->{mv_sort_field}[$i] =~ /^\d+$/;
			if ($s->{mv_sort_field}[$i] =~ s/:([frn]+)$//) {
			  $s->{mv_sort_option}[$i] = $1;
			}
			if(! defined $s->{field_hash}{$s->{mv_sort_field}[$i]})
			{
				splice(@{$s->{mv_sort_field}}, $i, 1);
				splice(@{$s->{mv_sort_option}}, $i, 1);
			}
			else {
				$s->{mv_sort_field}[$i] =
					$s->{field_hash}{$s->{mv_sort_field}[$i]};
			}
		}
	},
	mv_search_field  => sub {
			my $s = shift;
			my $i;
			while (defined ($i = shift)) {
				# Assume they know what they are doing
				next if $s->{mv_search_field}[$i] =~ /^\d+$/;
				next if $s->{mv_search_field}[$i] =~ /[*:]/;
				$s->splice_specs($i);
			}
		},
);

my (@hashable) = (qw/mv_return_fields mv_range_look mv_search_field mv_sort_field/);

sub hash_fields {
	my ($s, $fn, @laundry) = @_;
	my %fh;
	my $idx = 0;
	for (@$fn) {
		$fh{$_} = $idx++;
	}
	$s->{field_hash} = \%fh;
	my $fa;
	my %wash;
	@laundry = @hashable if ! @laundry;
#::logDebug("washing laundry @laundry");
	foreach $fa (@laundry) {
		next unless defined $s->{$fa};
		my $i = 0;
		for( @{$s->{$fa}} ) {
			if(! defined $fh{$_}) {
				if($_ eq '*') {
					$idx--;
					@{$s->{$fa}} = (0 .. $idx);
					last;
				}
				$wash{$fa} = [] if ! defined $wash{$fa};
				push @{$wash{$fa}}, $i++;
				next;
			}
			$_ = $fh{$_};
			$i++;
		}
	}
	$s->{mv_field_names} = [@$fn] if ! defined $s->{mv_field_names};
	foreach $fa (keys %wash) {
#::logDebug("washing $fa:" . ::uneval($wash{$fa}) );
		$maytag{$fa}->($s, reverse @{$wash{$fa}});
	}
}

sub escape {
    my($s, @text) = @_;
#::logDebug( "text=@text");
	return @text if ! $s->{mv_all_chars}[0];
	@text = map {quotemeta $_} @text;
#::logDebug( "text=@text");
    return @text;
}

my (@splice) = qw(
	mv_all_chars
	mv_begin_string
	mv_case
	mv_negate
	mv_numeric
	mv_orsearch
	mv_search_group
	mv_search_field
	mv_searchspec
	mv_substring_match
);

sub save_specs {
	my $s = shift;
	return if defined $s->{save_specs};
	return if @{$s->{mv_search_file}} < 2;
	my $ary = [];
	for (@splice) {
#::logDebug("saving $_:" . ::uneval($s->{$_}));
		push @$ary, defined $s->{$_} ? [ @{$s->{$_}} ] : undef;
	}
	$s->{save_specs} = $ary;
	return;
}

sub restore_specs {
	my $s = shift;
	return if ! defined $s->{save_specs};
	my $ary = $s->{save_specs};
	my $i;
	for ($i = 0; $i < @splice; $i++) {
		 my $val = $ary->[$i];
#::logDebug("restoring $splice[$i] from $_:" . ::uneval( $s->{$splice[$i]} ));
		 $s->{$splice[$i]} = $val ? [ @{$val} ] : undef;
#::logDebug("restoring $splice[$i] to   $_:" . ::uneval( $val ));
	}
	return;
}

sub splice_specs {
	my ($s, $i) = @_;
	for (@splice) {
		splice(@{$s->{$_}}, $i, 1);
	}
	return;
}

sub dump_coord {
	my $s = shift;
	my $specs = shift;
	my $msg = shift;
	return 
		sprintf "%s coord=%s specs=%s(%s) fields=%s(%s) op=%s(%s) nu=%s(%s) ne=%s(%s)",
			$msg,
            $s->{mv_coordinate},
			scalar @$specs,
			::uneval($specs),
			scalar @{$s->{mv_search_field}},
			::uneval($s->{mv_search_field}),
			scalar @{$s->{mv_column_op}},
			::uneval($s->{mv_column_op}),
			scalar @{$s->{mv_numeric}},
			::uneval($s->{mv_numeric}),
			scalar @{$s->{mv_negate}},
			::uneval($s->{mv_negate}),
			;
}

sub spec_check {
  my ($s, @specs) = @_;
  my @pats;
  SPEC_CHECK: {
	last SPEC_CHECK if $s->{mv_return_all};
	# Patch supplied by Don Grodecki
	# Now ignores empty search strings if coordinated search
	my $i = 0;
#::logDebug($s->dump_coord(\@specs, 'BEFORE'));

	$s->{mv_coordinate} = ''
		unless $s->{mv_coordinate} and @specs == @{$s->{mv_search_field}};

	my $all_chars = $s->{mv_all_chars}[0];

	while ($i < @specs) {
#::logDebug("i=$i specs=$#specs");
		if($#specs and length($specs[$i]) == 0) { # should add a switch
			if($s->{mv_coordinate}) {
		        splice(@{$s->{mv_search_group}}, $i, 1);
		        splice(@{$s->{mv_search_field}}, $i, 1);
		        splice(@{$s->{mv_column_op}}, $i, 1);
		        splice(@{$s->{mv_begin_string}}, $i, 1);
		        splice(@{$s->{mv_case}}, $i, 1);
		        splice(@{$s->{mv_numeric}}, $i, 1);
		        splice(@{$s->{mv_all_chars}}, $i, 1);
		        splice(@{$s->{mv_substring_match}}, $i, 1);
		        splice(@{$s->{mv_negate}}, $i, 1);
			}
		    splice(@specs, $i, 1);
		}
		else {
			if(length($specs[$i]) < $s->{mv_min_string}) {
				my $msg = <<EOF;
Search strings must be at least $s->{mv_min_string} characters.
You had '$specs[$i]' as one of your search strings.
EOF
				$s->{matches} = -1;
				return undef;
			}
			COLOP: {
				last COLOP unless $s->{mv_coordinate};
				$s->{mv_all_chars}[$i] = $all_chars
					if ! defined $s->{mv_all_chars}[$i];
				if(	$s->{mv_column_op}[$i] =~ /([=][~]|rm|em)/ ) {
					$specs[$i] = quotemeta $specs[$i]
						if $s->{mv_all_chars}[$i];
					$s->{regex_specs} = []
						unless $s->{regex_specs};
					$specs[$i] =~ /(.*)/;
					push @{$s->{regex_specs}}, $1;
				}
				elsif(	$s->{mv_column_op}[$i] =~ /^(==?|eq)$/ ) {
					$s->{eq_specs} = []
						unless $s->{eq_specs};
					$specs[$i] =~ /(.*)/;
					my $spec = $1;
					push @{$s->{eq_specs}}, $spec;
					last COLOP unless $s->{dbref};
					$spec = $s->{dbref}->quote($spec, $s->{mv_search_field}[$i]);
					$spec = $s->{mv_search_field}[$i] . " = $spec";
					push(@{$s->{eq_specs_sql}}, $spec);
				}
			}
			$i++;
		}
	}

	if ( ! $s->{mv_exact_match} and ! $s->{mv_coordinate}) {
		my $string = join ' ', @specs;
		eval {
			@specs = Text::ParseWords::shellwords( $string );
		};
		if($@ or ! @specs) {
			$string =~ s/['"]/./g;
			$s->{mv_all_chars}[0] = 0;
			@specs = Text::ParseWords::shellwords( $string );
		}
	}

	@specs = $s->escape(@specs) if ! $s->{mv_coordinate};

	if(! scalar @specs or ! $s->{mv_coordinate}) {
		my $passed;
		my $msg;
		for (@specs) {
			$passed = 1;
		    next if length($_) >= $s->{mv_min_string};
			$msg = <<EOF;
Search strings must be at least $s->{mv_min_string} characters.
You had '$_' as one of your search strings.
EOF
			undef $passed;
			last;
		}
		$passed = 1 if ! $s->{mv_min_string};
		if(! defined $passed) {
			$msg = <<EOF if ! $msg;
Search strings must be at least $s->{mv_min_string} characters.
You had no search string specified.
EOF
			return $s->search_error($msg);
		}
	}

	# untaint
	for(@specs) {
		/(.*)/s;
		push @pats, $1;
	}
	$s->{mv_searchspec} = \@pats;
#::logDebug($s->dump_coord(\@specs, 'AFTER '));
	return @pats;

  } # last SPEC_CHECK
  return @pats;
}


sub more_matches {
	my($s) = @_;
	$s->{more_in_progress} = 1;

	my $id = $s->{mv_session_id};
	$id .= ".$s->{mv_cache_key}";
	
	my $file = Vend::Util::get_filename($id);
#::logDebug("more_matches: $id from $file");

	my $obj;
	eval {
		$obj = Vend::Util::eval_file($file);
	};
	$@ and return $s->search_error("Object saved wrong in $file for search ID $id.");
	for(qw/mv_cache_key mv_matchlimit /) {
		$obj->{$_} = $s->{$_};
	}
	if($obj->{matches} > ($s->{mv_last_pointer} + 1) ) {
		$obj->{mv_next_pointer} = $s->{mv_last_pointer} + 1;
	}
	else {
		$obj->{mv_next_pointer} = 0;
	}
	$obj->{mv_first_match} = $s->{mv_next_pointer};
	$obj->{more_in_progress} = 1;
#::logDebug("object:" . ::uneval($obj));
	return $obj;
}

# Returns a field weeding function based on the search specification.
# Input is the raw line and the delimiter, output is the fields
# specified in the return_field specification
sub get_return {
	my($s, $final) = @_;
	my ($return_sub);

	# We will pick out the return fields later if sorting
	if(! $final and $s->{mv_sort_field}) {
		return ( sub {@_}, 1);
	}

	if(! $s->{mv_return_fields}) {
		my $delim = $s->{mv_index_delim} || "\t";
#::logDebug("code return. delim='$delim'");
		$return_sub = sub {
				$_[0] =~ s/$delim.*//s;
				my $ary = [ $_[0] ];
#::logDebug("ary is:" . ::uneval($ary));
				return $ary;
				};
	}
	else {
		my $delim = $s->{mv_index_delim};
#::logDebug("rf[0]='$s->{mv_return_fields}[0]'");
		my @fields = @{$s->{mv_return_fields}};
#::logDebug("delim='$delim' fields='@fields'");
		$return_sub = sub {
			chomp($_[0]);
			my $ary = [
				(split /\Q$delim/o, $_[0])[@fields]
				];
#::logDebug("line is:$_[0]\nary is:" . ::uneval($ary));
				return $ary;
		};
	}
	return $return_sub;
}

my %numopmap  = (
				'!=' => [' != '],
				'!~' => [' !~ m{', '}'],
				'<'  => [' < '],
				'<=' => [' <= '],
				'<>' => [' != '],
				'='  => [' == '],
				'==' => [' == '],
				'=~' => [' =~ m{', '}'],
				'>'  => [' > '],
				'>=' => [' >= '],
				'em' => [' =~ m{^', '$}'],
				'eq' => [' == '],
				'ge' => [' >= '],
				'gt' => [' > '],
				'le' => [' <= '],
				'lt' => [' < '],
				'ne' => [' != '],
				'rm' => [' =~ m{', '}'],
				'rn' => [' !~ m{', '}'],
				'like' => [' =~ m{LIKE', '}i'],
				'LIKE' => [' =~ m{LIKE', '}i'],
);
               

my %stropmap  = (
				'!=' => [' ne q{', '}'],
				'!~' => [' !~ m{', '}'],
				'<'  => [' lt q{', '}'],
				'>'  => [' gt q{', '}'],
				'<=' => [' le q{', '}'],
				'<>' => [' ne q{', '}'],
				'='  => [' eq q{', '}'],
				'==' => [' eq q{', '}'],
				'=~' => [' =~ m{', '}'],
				'>=' => [' ge q{', '}'],
				'eq' => [' eq q{', '}'],
				'ge' => [' ge q{', '}'],
				'gt' => [' gt q{', '}'],
				'le' => [' le q{', '}'],
				'lt' => [' lt q{', '}'],
				'ne' => [' ne q{', '}'],
				'em' => [' =~ m{^', '$}i'],
				'rm' => [' =~ m{', '}i'],
				'rn' => [' !~ m{', '}i'],
				'like' => [' =~ m{LIKE', '}i'],
				'LIKE' => [' =~ m{LIKE', '}i'],
);
               

sub map_ops {
	my($s, $count) = @_;
	my $c = $s->{mv_column_op} or return ();
	my $i;
	my $op;
	for($i = 0; $i < $count; $i++) {
		next unless $c->[$i];
		$c->[$i] =~ tr/ 	//;
		$c->[$i] = $s->{mv_numeric}[$i]
				? $numopmap{$c->[$i]}
				: $stropmap{$c->[$i]};
	}
	@{$s->{mv_column_op}};
}

sub code_join {
	my ($coderef, $num) = @_;
	return $num unless defined $coderef->[$num];
	my $out = ' ( ';
	$out .= join("", @{$coderef->[$num]});
	$out .= ' ) ';
}

# Returns a screening function based on the search specification.
# The $f is a reference to previously created search function which does
# a pattern match on the line.
sub get_limit {
	my($s, $f) = @_;
	my $limit_sub;
	my $range_code = '';
	my $code       = "sub {\nmy \$line = shift; chomp \$line;\n";
	my $join_key;
	$join_key = defined $s->{mv_return_fields} ? $s->{mv_return_fields}[0] : 0;
	$join_key = 0 if $join_key eq '*';
	my $sub;
	my $wild_card;
	my @join_fields;
	my $joiner;
	my $ender;
	if($s->{mv_orsearch}[0]) {
		$joiner = '1 if';
		$ender = 'return undef;';
	}
	else {
		$joiner = 'undef unless';
		$ender = 'return 1;';
	}
	#my $joiner = $s->{mv_orsearch}[0] ? '1 if' : 'undef unless';
	#my $ender = $s->{mv_orsearch}[0] ? 'return undef;' : 'return 1;';
	# Here we join data if we are passed a non-numeric field. The array
	# index comes from the end to avoid counting the fields.
	my $k = 0;
	for(@{$s->{mv_search_field}}) {
#::logDebug("join_field $_");
		next unless /[\*:]+/;
		unshift(@join_fields, $_);
		$_ = --$k;
#::logDebug("join_field $_");
	}
	# Add the code to get the join data if it is there
	if(@join_fields) {
		$code .= <<EOF;
my \$key = (split m{$s->{mv_index_delim}}, \$line)[$join_key];
EOF
		for(@join_fields) {
			my ($table, $col) = split /:+/, $_, 2;
			if($table) {
				$wild_card = 0;
				$code .= <<EOF;
\$line .= qq{$s->{mv_index_delim}} .
		  Vend::Data::database_field('$table', \$key, '$col');
EOF
			}
			elsif ($col =~ tr/:/,/) {
				$col =~ tr/ \t//d;
				$wild_card = 1;
				$col =~ s/[^\d,.]//g;
			$code .= <<EOF;
my \$addl = join " ", (split m{\Q$s->{mv_index_delim}\E}, \$line)[$col];
\$line .= qq{$s->{mv_index_delim}} . \$addl;
EOF
			}
			else {
				$wild_card = 1;
				$code .= <<EOF;
my \$addl = \$line;
\$addl =~ tr/$s->{mv_index_delim}/ /;
\$line .= qq{$s->{mv_index_delim}} . \$addl;
EOF
			}
		}
	}

	my $fields = join ",", @{$s->{mv_search_field}};

	if ( ref $s->{mv_range_look} )  {
		$range_code = <<EOF;
return $joiner \$s->range_check(qq{$s->{mv_index_delim}},\$line);
EOF
	}
	if ( $s->{mv_coordinate} ) {
		 undef $f;
		 $ender = '';
		 if($range_code) {
		 	::logError("Range look not compatible with mv_coordinate. Disabling.");
		 }
		 $code .= <<EOF;
	my \@fields = split /\\Q$s->{mv_index_delim}/, \$line;
	\@fields = \@fields[$fields];
#::logDebug("fields=" . join "|", \@fields);
EOF
		my @specs;
		# For a limiting function, can't if orsearch

		my $field_count = @specs = @{$s->{mv_searchspec}};

		my @cases = @{$s->{mv_case}};
		my @bounds = @{$s->{mv_substring_match}};
		my @ops;
		@ops = $s->map_ops($field_count);
		my @negates =  map { $_ ? 'not ' : ''} @{$s->{mv_negate}};
		my @begin = 	@{$s->{mv_begin_string}};
		my @group = 	@{$s->{mv_search_group}};
		my @code;
		my $candidate = '';
		my ($i, $start, $term, $like);
		for($i = 0; $i < $field_count; $i++) {
			undef $candidate, undef $f 
				if $s->{mv_orsearch}[$i];
			if($ops[$i]) {
				$start = $ops[$i][0];
				($term  = $ops[$i][1] || '')
					and $cases[$i]
					and $term =~ s/i$//
					and defined $candidate
					and $candidate = 1;
			}
			else {
				$start = '=~ m{';
				$start .=  '^' if $begin[$i];
				if($bounds[$i]) {
					$term = '}';
				}
				else {
					$term = '\b}';
					$start .= '\b' unless $begin[$i];
				}
				$term .= 'i' unless $cases[$i];
				$candidate = 1 if defined $candidate;
			}
			if ($start =~ s/LIKE$//) {
				$specs[$i] =~ s/^(%)?([^%]*)(%)?$/$2/;
				# Substitute if only one present
				# test $1
				undef $like;
				if($1 ne $3) {
					$specs[$i] = $1
								? $specs[$i] . '$'
								: '^' . $specs[$i];
					$like = 1;
				}
			 }
			 if ($i >= $k + $field_count) {
				 undef $candidate if ! $wild_card;
#::logDebug("triggered wild_card: $wild_card");
				 $wild_card = 0;
			 }
			 if(defined $candidate and ! $like) {
				undef $f if $candidate;
			 	$f = "sub { return 1 if $negates[$i]\$_ $start$specs[$i]$term ; return 0}"
					if ! defined $f and $start =~ m'=~';
				undef $candidate if $candidate;
			 }
			 my $grp = $group[$i] || 0;
			 my $frag = qq{($negates[$i]\$fields[$i] $start$specs[$i]$term )};
			 unless ($code[$grp]) {
				 $code[$grp] = [ $frag ];
			 }
			 else {
			 	 my $join = $s->{mv_orsearch}[$i] ? ' or ' : ' and ';
				 push @{$code[$grp]}, "$join$frag";
			 }
		}
#::logDebug("coderef=" . ::uneval(\@code));

		DOLIMIT: {
#::logDebug(::uneval({%$s}));
			last DOLIMIT if $f;
			last DOLIMIT if $s->{mv_small_data};
			last DOLIMIT if defined $s->{mv_search_relate}
							&& $s->{mv_search_relate} =~ /\bor\b/;
			my @pats;
			for(@{$s->{regex_specs}}) {
				push @pats, $_;
			}
			for(@{$s->{eq_specs}}) {
				push @pats, quotemeta $_;
			}
			if(defined $pats[1]) {
				@pats = sort { length($b) <=> length($a) } @pats;
			}
			elsif(! defined $pats[0]) {
				last DOLIMIT;
			}
			eval {
				if(grep $_, @{$s->{mv_orsearch}}) {
					$f = $s->create_search_or( 0, 1, 0, @pats);
				}
				else {
					$f = $s->create_search_and( 0, 1, 0, @pats);
				}
			};
			undef $f if $@;
		}
#::logDebug("filter function code is: $f");
		use locale;
		$f = eval $f if $f and ! ref $f;
		die($@) if $@;
		my $relate;
		if(scalar @code > 1) {
			$relate = 'return ( ';
			if ($s->{mv_search_relate}) {
				$relate .= $s->{mv_search_relate};
				$relate =~ s/([0-9]+)/code_join(\@code,$1)/eg;
			}
			else {
				$relate .= '(';
				$relate .= join ') and (', (map { join "", @$_ } @code);
				$relate .= ')';
			}
			$relate .= ' );';
		}
		else {
			$relate = "return ( " . join("", @{$code[0]}) . " );";
		}
		$code .= $relate;
		$code .= "\n}\n";
#::logDebug("coordinate search code is:\n$code");
	}
	elsif ( @{$s->{mv_search_field}} )  {
		if(! $s->{mv_begin_string}[0]) {
			$sub = $f;
		}
		elsif (! $s->{mv_orsearch}[0] ) {
			$sub = create_search_and(
						$s->{mv_index_delim},		# Passing non-reference first
						$s->{mv_case}[0],	# means beginning of string search
						$s->{mv_substring_match}[0],
						$s->{mv_negate}[0],
						@{$s->{mv_searchspec}});
		}
		else {
			$sub = create_search_or(
						$s->{mv_index_delim},
						$s->{mv_case}[0],
						$s->{mv_substring_match}[0],
						$s->{mv_negate}[0],
						@{$s->{mv_searchspec}});
		}
		 $code .= $range_code;
		 $code .= <<EOF;
	my \@fields = (split /\\Q$s->{mv_index_delim}/, \$line)[$fields];
	my \$field = join q{$s->{mv_index_delim}}, \@fields;
	\$_ = \$field;
	return(\$_ = \$line) if &\$sub();
	return undef;
}
EOF
	} 
	# In case range_look only
	elsif ($s->{mv_range_look})  {
		$code .= <<EOF;
	$range_code
	$ender
}
EOF
	}
	# If there is to be no limit_sub
	else {
		die("no limit and no search") unless defined $f;
		return;
	}
#::logDebug("code is $code");
	use locale;
	$limit_sub = eval $code;
	die "Bad code: $@" if $@;
	return ($limit_sub, $f);
}

# Check to see if the fields specified in the range_look array
# meet the criteria
sub range_check {
	my($s,$index_delim,$line) = @_;
	my @fields = (split /\Q$index_delim/, $line)[@{$s->{mv_range_look}}];
	my $i = 0;
	for(@fields) {
		no strict 'refs';
		unless(defined $s->{mv_range_alpha}->[$i] and $s->{mv_range_alpha}->[$i]) {
			return 0 unless $_ >= $s->{mv_range_min}->[$i];
			return 0 unless
				(! $s->{mv_range_max}->[$i] or $_ <= $s->{mv_range_max}->[$i]);
		}
		elsif (! $s->{mv_case}) {
			return 0 unless "\L$_" ge (lc $s->{mv_range_min}->[$i]);
			return 0 unless "\L$_" le (lc $s->{mv_range_max}->[$i]);
		}
		else {
			return 0 unless $_ ge $s->{mv_range_min}->[$i];
			return 0 unless $_ le $s->{mv_range_max}->[$i];
		}
		$i++;
	}
	1;
}

sub create_search_and {

	my ($begin, $case, $bound, $negate);

	$begin = shift(@_);
	$begin = ref $begin ? '' : "(?:^|\Q$begin\E)";
	$case = shift(@_) ? '' : 'i';
	$bound = shift(@_) ? '' : '\b';
	$negate = shift(@_) ? '$_ !~ ' : '';

	# We check for no patterns earlier, so we just want true for
	# empty search string
	#die "create_search_and: create_search_and case_sens sub_match patterns" 
	return sub{1}
		unless @_;
	my $pat;

    my $code = <<EOCODE;
sub {
EOCODE

    $code .= <<EOCODE if @_ > 5;
    study;
EOCODE

	my $i = 0;
    for $pat (@_) {
		$pat = "$begin$pat" if $begin;
		$pat =~ s/(\w+)/$bound$1$bound/g if $bound;
		$code .= <<EOCODE;
    return 0 unless $negate m{$pat}$case;
EOCODE
		undef $begin;
    } 

    $code .= "\treturn 1;\n}";
#::logDebug("search_and: $code");

	use locale;
    my $func = eval $code;
    die "bad pattern: $@" if $@;

    return $func;
} 

sub create_search_or {
	my ($begin, $case, $bound, $negate);

	$begin = shift(@_);
	$begin = ref $begin ? '' : "(?:^|\Q$begin\E)";

	$case  = shift(@_) ? '' : 'i';
	$bound = shift(@_) ? '' : '\b';
	$negate = shift(@_) ? '$_ !~ ' : '';

	# We check for no patterns earlier, so we just want true for
	# empty search string
	#die "create_search_or: create_search_or case_sens sub_match patterns" 
	return sub{1} unless @_;
	my $pat;

    my $code = <<EOCODE;
sub {
EOCODE

    $code .= <<EOCODE if @_ > 5;
    study;
EOCODE

    for $pat (@_) {
		$pat = "$begin$pat" if $begin;
		$pat =~ s/(\w+)/$bound$1$bound/g if $bound;
		$code .= <<EOCODE;
    return 1 if $negate m{$pat}$case;
EOCODE
		undef $begin;
    } 

    $code .= "\treturn 0;\n}\n";

#::logDebug("search_or: $code");

	use locale;
    my $func = eval $code;
    die "bad pattern: $@" if $@;

    return $func;
} 

# Returns an unevaled string with saved 
# global parameters, for putting at beginning
# of more file or hash.
sub save_context {
	my ($s,@save) = @_;
	my $return = {};
	for (@save) {
		$return->{$_} = $s->{$_};
	}
	::uneval_fast($return);
}

sub dump_options {
	my $s = shift;
	eval {require Data::Dumper};
	if(!$@) {
		$Data::Dumper::Indent = 3;
		$Data::Dumper::Terse = 1;
	}
	return ::uneval($s);
}

sub search_error {
	my ($s, $msg) = @_;
	$s->{mv_search_error} = [] if ! $s->{mv_search_error};
	push @{$s->{mv_search_error}}, $msg;
	$s->{matches} = -1;
	::logError ("search error: $msg");
	return undef;
}

sub save_more {
	my($s, $out) = @_;
	return if $MVSAFE::Safe;
	my $file;
	delete $s->{dbref} if defined $s->{dbref};
	my $id = $s->{mv_save_general}
			? "more.$s->{mv_cache_key}"
			: "$Vend::SessionID.$s->{mv_cache_key}";
	if ($s->{matches} > $s->{mv_matchlimit}) {
		$s->{overflow} = 1;
		$s->{mv_next_pointer} = $s->{mv_matchlimit};
	}
	
	$file = Vend::Util::get_filename($id); 
#::logDebug("save_more: $id to $file.");
	my $new = { %$s };
	$new->{mv_results} = $out;
#::logDebug("save_more:object:" . ::uneval($new));
	eval {
		Vend::Util::uneval_file($new, $file);
	};
	$@ and return $s->search_error("failed to store more matches");
	return 1;
}

my (@Opts);
my (@Flds);

use vars qw/ %Sort_field /;
%Sort_field = (

	none	=> sub { $_[0] cmp $_[1]			},
	f	=> sub { (lc $_[0]) cmp (lc $_[1])	},
	fr	=> sub { (lc $_[1]) cmp (lc $_[0])	},
	n	=> sub { $_[0] <=> $_[1]			},
	nr	=> sub { $_[1] <=> $_[0]			},
	r	=> sub { $_[1] cmp $_[0]			},
	rf	=> sub { (lc $_[1]) cmp (lc $_[0])	},
	rn	=> sub { $_[1] <=> $_[0]			},
);


sub sort_search_return {
    my ($s, $target) = @_;

	@Flds	= @{$s->{mv_sort_field}};
	for(@Flds) {
		next if /^\d+$/;
		$_ = $s->{field_hash}{$_}
			 if defined $s->{field_hash}{$_};
		$_ = $s->{mv_field_hash}{$_} || 0;
	}

	return $target unless @Flds;

	@Opts	= @{$s->{mv_sort_option}};

my %Sorter = (

	none	=> sub { $_[0] cmp $_[1]			},
	f	=> sub { (lc $_[0]) cmp (lc $_[1])	},
	fr	=> sub { (lc $_[1]) cmp (lc $_[0])	},
	n	=> sub { $_[0] <=> $_[1]			},
	nr	=> sub { $_[1] <=> $_[0]			},
	r	=> sub { $_[1] cmp $_[0]			},
	rf	=> sub { (lc $_[1]) cmp (lc $_[0])	},
	rn	=> sub { $_[1] <=> $_[0]			},
);

	my $last = 'none';
	my $i;
	my $max = 0;
	for($i = 0; $i < @Flds; $i++) {
		$max = $Flds[$i] if $Flds[$i] > $max;
		if (! $Opts[$i]) {
			$Opts[$i] = $last;
			next;
		}
		$Opts[$i] = lc $Opts[$i];
		$Opts[$i] = 'none' unless defined $Sort_field{$Opts[$i]};
		$last = $Opts[$i];
	}
#::logDebug("sort_search_return: flds='@Flds' opts='@Opts'");

	$max += 2;
	my $f_string = join ",", @Flds;
	my $delim = quotemeta $s->{mv_index_delim};
	my $code = <<EOF;
sub {
	my \@a = (split /$delim/, \$a, $max)[$f_string];
	my \@b = (split /$delim/, \$b, $max)[$f_string];
	my \$r;
EOF
#::logDebug("No define of Sort_field") if ! defined $Sort_field{'none'};

	if($MVSAFE::Safe) {
		for($i = 0; $i < @Flds; $i++) {
			$code .= <<EOF;
	\$r = &{\$Sorter{'$Opts[$i]'}}(\$a[$i], \$b[$i]) and return \$r;
EOF
		}
	}
	else {
		for($i = 0; $i < @Flds; $i++) {
			$code .= <<EOF;
	\$r = &{\$Vend::Search::Sort_field{'$Opts[$i]'}}(\$a[$i], \$b[$i]) and return \$r;
EOF
		}
	}

	$code .= "return 0\n}\n";

	my $routine;
	$routine = eval $code;
	die "Bad sort routine:\n$code\n$@" if ! $routine or $@;
eval {

	use locale;
	if($::Scratch->{mv_locale}) {
		POSIX::setlocale(POSIX::LC_COLLATE(),
			$::Scratch->{mv_locale});
	}

};
#::logDebug("Routine is $routine:\n$code");

	# Prime sort routine
	use locale;
	sort { $routine } ('30','31') or 1;

	@$target = sort { &$routine } @$target;
#::logDebug("target is $target: " . Vend::Util::uneval_it($target));

}

1;

__END__
