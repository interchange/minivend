#!/usr/bin/perl -w
#
# $Id: Search.pm,v 1.28 1999/02/15 08:51:18 mike Exp mike $
#
# Vend::Search -- Base class for search engines
#
# ADAPTED from Search::Text FOR FITTING INTO MINIVEND LIBRARIES
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
#

#
#
package Vend::Search;

$VERSION = substr(q$Revision: 1.28 $, 10);
$DEBUG = 0;

my $Joiner;

if($ =~ /win32/i) {
	$Joiner = '_';
}
else {
	$Joiner = ':';
}

use strict;
use vars qw($DEBUG $VERSION);

sub new {
	my ($class, %options) = @_;
	my $s = {};

	$DEBUG = $Global::DEBUG;

	$s->{global} = {
		all_chars			=> 1,
		base_directory		=> $Vend::Cfg->{'ProductDir'},
		begin_string		=> 0,
		#column_ops			=> undef,
		coordinate			=> 0,
		error_page			=> $Vend::Cfg->{'Special'}->{'badsearch'} || 'badsearch',
		error_routine		=> \&main::display_special_page,
		exact_match			=> 0,
		first_match			=> 0,
		record_delim		=> $/,
		head_skip			=> 1,
		index_delim			=> "\t",
		#index_file			=> '',
		log_routine			=> \&Vend::Util::logError,
		match_limit			=> 50,
		max_matches			=> 2000,
		min_string			=> 1,
		next_pointer		=> 0,
		negate      		=> 0,
		or_search			=> 0,
		return_all			=> 0,
		#range_look			=> '',
		#range_min			=> '',
		#range_max			=> '',
		#range_alpha			=> '',
		#return_delim		=> undef,
		#return_fields		=> undef,
		return_file_name	=> '',
		#save_context		=> undef,
		save_dir			=> '',
		search_file			=> ($Vend::Cfg->{Variable}{MV_DEFAULT_SEARCH_FILE} || 'products.asc'),
		search_mod			=> '',
		sort_command		=> '',
		sort_crippled		=> 0,
		#sort_field			=> '',
		#sort_option			=> '',
		#session_id			=> '',
		#session_key			=> '',
		spelling_errors		=> 0,
		substring_match		=> 0,
		uneval_routine		=> \&Vend::Util::uneval_it,
	};

	for(keys %options) {
		$s->{global}->{$_} = $options{$_};
	}

	$s->{specs}       = []; # The search text, raw, per field 
							# Special case is form with only one searchspec,
							# it searches in all columns, takes its
							# options from first position

	$s->{fields}      = [];	# The columns to search, by number

	$s->{cases}       = [];	# set for NOT

	$s->{negates}     = [];	# set for NOT

	bless $s, $class;

}

sub global {
	my ($self,$term,$value) = @_;

	if (defined $value) {
		$self->{global}->{$term} = $value;
	}
	elsif (defined $term) {
		$self->{global}->{$term};
	}
	else {
		%{$self->{global}};
	}
}


sub debug {
	return unless $DEBUG;
	my $s = shift;
	print @_;
}

sub version {
	$Vend::Search::VERSION;
}

sub spec_check {
  my ($s, $g, @specs) = @_;
  my @pats;
  SPEC_CHECK: {
	last SPEC_CHECK if $g->{return_all};
	# Patch supplied by Don Grodecki
	# Now ignores empty search strings if coordinated search
	my $i = 0;

	unless ($g->{coordinate} and @specs == @{$s->{fields}}) {
		for(qw! case_sensitive substring_match negate !) {
			next unless ref $g->{$_};
			$g->{$_} = $g->{$_}->[0];
		}
		$g->{coordinate} = '';
	}

	while ($i < @specs) {
		if($#specs and length($specs[$i]) == 0) { # should add a switch
			if($g->{coordinate}) {
		        splice(@{$s->{fields}}, $i, 1);
		        splice(@{$g->{column_op}}, $i, 1)
					if ref $g->{column_op};
		        splice(@{$g->{case_sensitive}}, $i, 1)
					if ref $g->{case_sensitive};
		        splice(@{$g->{numeric}}, $i, 1)
					if ref $g->{numeric};
		        splice(@{$g->{substring_match}}, $i, 1)
					if ref $g->{substring_match};
		        splice(@{$g->{negate}}, $i, 1)
					if ref $g->{negate};
			}
		    splice(@specs, $i, 1);
			splice(@{$s->{specs}}, $i, 1);
		}
		else {
			if($g->{coordinate} and $g->{column_op} and $g->{column_op}[$i] =~ /([~]|rm|em)/) {
				if(length($specs[$i]) < $g->{min_string}) {
					my $msg = <<EOF;
Search strings must be at least $g->{min_string} characters.
You had '$specs[$i]' as one of your search strings.
EOF
					&{$g->{error_routine}}($g->{error_page}, $msg);
					$g->{matches} = -1;
					return undef;
				}
				$g->{regex_specs} = []
					unless $g->{regex_specs};
				$specs[$i] =~ /(.*)/;
				push @{$g->{regex_specs}}, $1;
			}
			$i++;
		}
	}

# DEBUG
Vend::Util::logDebug
($s->dump_options() . "\nspecs=" . join("|", @specs) . "|\n")
	if ::debug(0x10);
# END DEBUG

	if ( ! $g->{exact_match} and ! $g->{coordinate}) {
		my $string = join ' ', @specs;
		eval {
			@specs = Text::ParseWords::shellwords( $string );
		};
		if($@ or ! @specs) {
			$string =~ s/['"]/./g;
			$g->{all_chars} = 0;
			@specs = Text::ParseWords::shellwords( $string );
		}
	}

	@specs = $s->escape(@specs);

# DEBUG
Vend::Util::logDebug
("spec='" . (join "','", @specs) . "'\n")
	if ::debug(0x10 );
# END DEBUG

	# untaint
	for(@specs) {
		/(.*)/s;
		push @pats, $1;
	}
	@{$s->{'specs'}} = @pats;

# DEBUG
Vend::Util::logDebug
("pats: '" . join("', '", @pats) . "'\n")
	if ::debug(0x10);
# END DEBUG

  } # last SPEC_CHECK
  return @pats;
}


sub more_matches {
	my($self,$session,$next,$last,$mod) = @_;
	my $g = $self->{'global'};
	$g->{more_in_progress} = $Joiner;
	my @out;
	my $count = 0;
	my ($filemod,$first,$save);
	my $id = $g->{session_key} || $g->{session_id};
	$mod = defined $mod ? $mod : 1;
	$g->{search_mod} = $mod;
	$id = ref $id ? $$id : $id;
	$id .= "$Joiner$mod";
	
	my $file = $g->{save_dir} . '/' . $id if $g->{save_dir};

	if($file) {
		open(Vend::Search::MORE, $file)
			or do { $g->{matches} = -1;
			&{$g->{error_routine}}($g->{error_page}, "couldn't open $file: $!\n");
			};
		$first = <Vend::Search::MORE>;

		#Get any saved parameters
		if($first =~ s/^~$id\s+//) {
			$save = eval $first;
			foreach(keys %$save) {
				$g->{$_} = $save->{$_};
			}
		}
		else {
			push(@out, $first) if $count++ >= $next;
		}

		while (<Vend::Search::MORE>) {
			next unless $count++ >= $next;
			next if ($count - 1) > $last;
			chomp;
			push(@out, $_);
		}
		close Vend::Search::MORE;
	}
	elsif (ref $g->{save_hash}) {
		my $h = $g->{save_hash};
		#Get any saved parameters
		if(exists $h->{"~$id"}) {
			$save = eval $h->{"~$id"};
			foreach(keys %$save) {
				$g->{$_} = $save->{$_};
			}
		}
		return undef unless exists $h->{$id};
		$count = (@out = split /\r?\n/, $h->{$id});
		@out = splice(@out,$next,$g->{match_limit});
	}
	else {
		$g->{matches} = -1;
		my $msg = <<EOF;
MISCONFIGURATION: No save method was specified to enable paging of
matches.  Please re-do the search with a tighter specification, and
contact the webmaster.
EOF
     &{$g->{error_routine}} ($g->{error_page}, $msg);
		return undef;
	}

	$g->{matches} = $count;
	$g->{first_match} = $next;
	if( $last >= ($g->{matches} - 1) ) {
		$g->{next_pointer} = 0;
	}
	else {
		$g->{next_pointer} = $last + 1;
	}
	\@out;
}

# Returns a field weeding function based on the search specification.
# Input is the raw line and the delimiter, output is the fields
# specified in the return_field specification
sub get_return {
	my($s) = @_;
	my $g = $s->{'global'};
	my ($return_sub);

	if(!defined $g->{return_fields}) {
		$return_sub = sub { substr($_[0], 0, index($_[0], $g->{index_delim})) };
#::logGlobal("default return_fields");
	}
	elsif ( ref($g->{return_fields}) =~ /^ARRAY/ ) {
		$return_sub = sub {
			chomp($_[0]);
			return join $g->{return_delim},
						(split /\Q$g->{index_delim}/, $_[0])[@{$g->{return_fields}}];
		};
#::logGlobal("array return_fields");
	}
	elsif ( ref($g->{return_fields}) =~ /^HASH/ ) {
		$return_sub = sub {
			my($line) = @_;
			my($key,$val);
			my(@return);
			my(%strings) = %{$g->{return_fields}};
			while ( ($key,$val) = each %strings) {
				$val = '\s' unless $val;
				1 while $line =~ s/($key)\s*(\S.*?)($val)/push(@return, $2)/ge;
			}
			return undef unless @return;
			join $g->{index_delim}, @return;
		};
#::logGlobal("hash return_fields");
	}
	elsif( $g->{return_fields} ) {
		$return_sub = sub { substr($_[0], 0, index($_[0], $g->{return_fields})) };
#::logGlobal("scalar return_fields");
	}
	else {
#::logGlobal("return all fields");
		$return_sub = sub { @_ };
	}

	# We will pick out the return fields later if sorting
	if($g->{sort_field} and ! $g->{sort_command}) {
		return ( sub {@_}, $return_sub);
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
	my $g = $s->{'global'};
	my $c = $g->{column_op} or return ();
	my $i;
	my $op;
	$g->{numeric} = [ $g->{numeric} ]
		unless ref $g->{numeric};
	for($i = 0; $i < $count; $i++) {
		next unless $c->[$i];
		$c->[$i] =~ tr/ 	//;
		$c->[$i] = $g->{numeric}[$i]
				? $numopmap{$c->[$i]}
				: $stropmap{$c->[$i]};
	}
	@{$g->{column_op}};
}

# Returns a screening function based on the search specification.
# The $f is a reference to previously created search function which does
# a pattern match on the line.
sub get_limit {
	my($s, $f) = @_;
	my $g = $s->{'global'};
	my $limit_sub;
	my $range_code = '';
	my $code       = "sub {\nmy \$line = shift; chomp \$line;\n";
	my $join_key;
	$join_key = defined $g->{return_fields} ? $g->{return_fields}[0] : 0;
	my $sub;
	my $wild_card;
	my @join_fields;
	my $joiner;
	my $ender;
	if($g->{or_search}) {
		$joiner = '1 if';
		$ender = 'return undef;';
	}
	else {
		$joiner = 'undef unless';
		$ender = 'return 1;';
	}
	#my $joiner = $g->{or_search} ? '1 if' : 'undef unless';
	#my $ender = $g->{or_search} ? 'return undef;' : 'return 1;';
	# Here we join data if we are passed a non-numeric field. The array
	# index comes from the end to avoid counting the fields.
	my $k = 0;
	for(@{$s->{'fields'}}) {
#::logError("join_field $_");
		next unless /:+.+/;
		unshift(@join_fields, $_);
		$_ = --$k;
#::logError("join_field $_");
	}
	# Add the code to get the join data if it is there
	if(@join_fields) {
		$code .= <<EOF;
my \$key = (split m{$g->{index_delim}}, \$line)[$join_key];
EOF
		for(@join_fields) {
			my ($table, $col) = split /:+/, $_, 2;
			if($table) {
				$wild_card = 0;
				$code .= <<EOF;
\$line .= qq{$g->{index_delim}} .
		  Vend::Data::database_field('$table', \$key, '$col');
EOF
			}
			elsif ($col =~ tr/:/,/) {
				$wild_card = 1;
				$col =~ s/[^\d,.]//g;
			$code .= <<EOF;
my \$addl = join " ", (split m{$g->{index_delim}}, \$line)[$col];
\$line .= qq{$g->{index_delim}} . \$addl;
EOF
			}
			else {
				$wild_card = 1;
				$code .= <<EOF;
my \$addl = \$line;
\$addl =~ tr/$g->{index_delim}/ /;
\$line .= qq{$g->{index_delim}} . \$addl;
EOF
			}
		}
	}

	my $fields = join ",", @{$s->{'fields'}};

	if ( ref $g->{range_look} )  {
		$range_code = <<EOF;
return $joiner \$s->range_check(qq{$g->{index_delim}},\$line);
EOF
	}
	if ( $g->{coordinate} )
	{
		 undef $f;
		 $code .= <<EOF;
	my \@fields = (split /\\Q$g->{index_delim}/, \$line)[$fields];
#::logError("fields=\@fields");
EOF
		my @specs;
		# For a limiting function, can't if or_search
		my $candidate = $g->{or_search} ? undef : '';

		my $field_count = @specs = @{$s->{'specs'}};

		my @cases = ref $g->{case_sensitive}
						?	@{$g->{case_sensitive}}
						:	($g->{case_sensitive}) x $field_count;
		my @bounds = ref $g->{substring_match}
						?	@{$g->{substring_match}}
						:	($g->{substring_match}) x $field_count;
		my @ops;
		@ops = $s->map_ops($field_count);
		my @negates = ref $g->{negate}
						?	@{$g->{negate}}
						:	($g->{negate}) x $field_count;
		my @begin = ref $g->{begin_string}
						?	@{$g->{begin_string}}
						:	($g->{begin_string}) x $field_count;
		my ($i, $start, $term, $like);
		for($i = 0; $i < $field_count; $i++) {
			if($ops[$i]) {
				$start = $ops[$i][0];
				($term  = $ops[$i][1] || '')
					and $cases[$i]
					and $term =~ s/i$//
					and defined $candidate
					and $candidate = 1;
			}
			else {
				$start = $negates[$i] ? '!~ m{' : '=~ m{';
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
#::logError("triggered wild_card: $wild_card");
				 $wild_card = 0;
			 }
			 if(defined $candidate and ! $like) {
				undef $f if $candidate;
			 	$f = "sub { return 1 if \$_ $start$specs[$i]$term ; return 0}"
					if ! defined $f and $start =~ m'=~';
				undef $candidate if $candidate;
			 }
			 $code .= <<EOF;
		return $joiner \$fields[$i] $start$specs[$i]$term;
EOF
		}
#::logError("coordinate search func is: $f");
# DEBUG
Vend::Util::logDebug
("coordinate search\ncode is: $code\nfunc is:\n$f")
	if ::debug(0x10);
# END DEBUG
		$f = eval $f if $f;
		die($@) if $@;
		$code .= <<EOF;
$range_code
$ender
}
EOF
#::logError("coordinate search code is:\n$code\n");
	}
	elsif ( @{$s->{'fields'}} )  {
		if(! $g->{begin_string}) {
			$sub = $f;
		}
		elsif (! $g->{or_search} ) {
			$sub = create_search_and(
						$g->{index_delim},		# Passing non-reference first
						$g->{case_sensitive},	# means beginning of string search
						$g->{substring_match},
						$g->{negate},
						@{$s->{'specs'}});
		}
		else {
			$sub = create_search_or(
						$g->{index_delim},
						$g->{case_sensitive},
						$g->{substring_match},
						$g->{negate},
						@{$s->{'specs'}});
		}
		 $code .= $range_code;
		 $code .= <<EOF;
	my \@fields = (split /\\Q$g->{index_delim}/, \$line)[$fields];
	my \$field = join q{$g->{index_delim}}, \@fields;
	\$_ = \$field;
	return(\$_ = \$line) if &\$sub();
	return undef;
}
EOF
	} 
	# In case range_look only
	elsif ($g->{range_look})  {
		$code .= <<EOF;
	$range_code
	$ender
}
EOF
	}
	# If there is to be no limit_sub
	else {
		die("no limit and no search") unless defined $f;
		return ($f);
	}
#::logError("code is $code");
	$limit_sub = eval $code;
	die "Bad code: $@" if $@;
	return ($limit_sub, $f);
}

sub saved_params {
	qw(
		next_pointer
		first_match
		matches
		save_dir
		session_id
		search_mod
	);
}

# Check to see if the fields specified in the range_look array
# meet the criteria
sub range_check {
	my($s,$index_delim,$line) = @_;
	my $g = $s->{'global'};
	my @fields = (split /\Q$index_delim/, $line)[@{$g->{range_look}}];
# DEBUG
Vend::Util::logDebug
("range_look: '" . join("','", @fields) . "'\n")
	if ::debug(0x10);
Vend::Util::logDebug
("range_min:  '" . join("','", @{$g->{range_min}}) . "'\n")
	if ::debug(0x10);
Vend::Util::logDebug
("range_max:  '" . join("','", @{$g->{range_max}}) . "'\n")
	if ::debug(0x10);
# END DEBUG
	my $i = 0;
	for(@fields) {
		no strict 'refs';
		unless(defined $g->{range_alpha}->[$i] and $g->{range_alpha}->[$i]) {
			return 0 unless $_ >= $g->{range_min}->[$i];
			return 0 unless
				(! $g->{range_max}->[$i] or $_ <= $g->{range_max}->[$i]);
		}
		elsif (! $g->{case_sensitive}) {
			return 0 unless "\L$_" ge (lc $g->{range_min}->[$i]);
			return 0 unless "\L$_" le (lc $g->{range_max}->[$i]);
		}
		else {
			return 0 unless $_ ge $g->{range_min}->[$i];
			return 0 unless $_ le $g->{range_max}->[$i];
		}
		$i++;
	}
	1;
}

sub create_search_and {

	my ($case, $bound, $negate, $begin);

	$begin = shift(@_);
	$begin = ref $begin ? '' : "(?:^|\Q$begin\E)";
	$case = shift(@_) ? '' : 'i';
	$bound = shift(@_) ? '' : '\b';
	$negate = shift(@_) ? '$_ !~ ' : '';
	$begin = $bound if ! $begin;

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
		$code .= <<EOCODE;
    return 0 unless $negate m{$begin$pat$bound}$case;
EOCODE
		$begin = $bound;
    } 

    $code .= "}\n";
# DEBUG
Vend::Util::logDebug
("create search: $code")
	if ::debug(0x10);
# END DEBUG

    my $func = eval $code;
    die "bad pattern: $@" if $@;

    return $func;
} 

sub create_search_or {
	my ($case, $bound, $negate, $begin);

	$begin = shift(@_);
	$begin = ref $begin ? '' : "(?:^|\Q$begin\E)";

	$case  = shift(@_) ? '' : 'i';
	$bound = shift(@_) ? '' : '\b';
	$negate = shift(@_) ? '$_ !~ ' : '';
	$begin = $bound if ! $begin;

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
	$code .= <<EOCODE;
    return 1 if $negate m{$begin$pat$bound}$case;
EOCODE
    } 

    $code .= "}\n";

# DEBUG
Vend::Util::logDebug
("create search: $code")
	if ::debug(0x10);
# END DEBUG

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
		$return->{$_} = $s->{'global'}->{$_};
	}
	&{$s->{'global'}->{uneval_routine}}($return);
}

# Builds a GNU sort statement for standard input piping
# Will do AT&T sort if sort_crippled is set
sub find_sort {
	my($s) = @_;
	my $g = $s->{'global'};
	
	return '' unless ref $g->{sort_field};

	my ($crippled, $i);

	my $sort_string;
	$sort_string = $g->{sort_command} or return '';
	$sort_string .= " -t'$g->{index_delim}'";
	if($g->{sort_crippled}) {
		$sort_string .= " -$g->{sort_option}[0]"
			if ref($g->{sort_option});
		$crippled = 1;
	}

	$i = 0;
	for(@{$g->{sort_field}}) {
		$sort_string .= " +$_";
		next unless ref $g->{sort_option};
		$sort_string .= $g->{sort_option}[$i - 1];
	}

	$sort_string .= ' |';
}

sub dump_options {
	my $self = shift;
	eval {require Data::Dumper};
	if(!$@) {
		$Data::Dumper::Indent = 3;
		$Data::Dumper::Terse = 1;
	}
	return &{$self->{'global'}->{uneval_routine}}($self->{'global'});
}


sub save_more {
	my($s, $out) = @_;
	my $g = $s->{'global'};
	my $file;
	my $id = $g->{session_key} || $g->{session_id};
	$id .=  $Joiner . $g->{search_mod};
	$g->{overflow} = 1;
	$g->{next_pointer} = $g->{match_limit};
	my $save = $s->save_context( @{$g->{'save_context'}} )
			if defined $g->{'save_context'};
	if($file = $g->{save_dir}) {
		$file .= '/' . $id;

		if(open(Vend::Search::MATCHES, ">$file")) {
			(print Vend::Search::MATCHES "~$id $save\n")
				if defined $save;
			chomp(@$out);
			print Vend::Search::MATCHES join "\n", @$out;
			close Vend::Search::MATCHES;
		}
		else {
			&{$g->{log_routine}}("search: Couldn't write $file: $!");
		}
	}
	elsif(ref $g->{save_hash}) {
		$g->{save_hash}->{"~$id"} = $save
				if defined $save;
		my $id = $g->{session_key} . $Joiner . $g->{search_mod};
		$g->{save_hash}->{$id} = join "\n", @$out;
	}
	else {
		$g->{matches} = $g->{match_limit};
		$g->{next_pointer} = 0;
		return undef;
	}
	1;
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
	my $g = $s->{'global'};

	@Flds	= @{$g->{sort_field}};

    if(ref $g->{sort_option}) {
		@Opts	= @{$g->{sort_option}};
	}
	else {
		@Opts = ($g->{sort_option}) x scalar @Flds;
	}

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
#::logError("Flds: @Flds\nOpts: @Opts\n");

	$max += 2;
	my $f_string = join ",", @Flds;
	my $delim = quotemeta $g->{index_delim};
	my $code = <<EOF;
sub {
	my \@a = (split /$delim/, \$a, $max)[$f_string];
	my \@b = (split /$delim/, \$b, $max)[$f_string];
	my \$r;
EOF
	for($i = 0; $i < @Flds; $i++) {
		$code .= <<EOF;
	\$r = &{\$Vend::Search::Sort_field{'$Opts[$i]'}}(\$a[$i], \$b[$i]) and return \$r;
EOF
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
#::logError("Routine is $routine:\n$code");

	# Prime sort routine
	sort { $routine } ('30','31') or 1;

	@$target = sort { &$routine } @$target;

}

1;

__END__
