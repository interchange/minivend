# Vend/DbSearch.pm:  Search indexes with Perl
#
# $Id: DbSearch.pm,v 1.4 1999/08/15 19:03:01 mike Exp mike $
#
# ADAPTED FOR USE WITH MINIVEND from Search::TextSearch
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

package Vend::DbSearch;
require Vend::Search;

@ISA = qw(Vend::Search);

$VERSION = substr(q$Revision: 1.4 $, 10);

use Search::Dict;
use strict;

sub array {
	my ($self, $opt) = @_;
	$self->{global}{return_reference} = 1;
	$self->{global}{mv_one_sql_table} = 1;
	$self->{global}{list_only} = 1;
	Vend::Scan::perform_search($opt, undef, $self);
}

sub hash {
	my ($self, $opt) = @_;
	$self->{global}{return_reference} = 'HASH';
	$self->{global}{mv_one_sql_table} = 1;
	$self->{global}{list_only} = 1;
	Vend::Scan::perform_search($opt, undef, $self);
}

sub list {
	my ($self, $opt) = @_;
	$self->{global}{list_only} = 1;
	$self->{global}{mv_one_sql_table} = 1;
	Vend::Scan::perform_search($opt, undef, $self);
}

sub init {
	my ($s, $options) = @_;

	$s->{global} = {
		all_chars			=> 1,
		base_directory		=> $Vend::Cfg->{ProductFiles}[0],
		begin_string		=> 0,
		#column_ops			=> undef,
		coordinate			=> 0,
		error_page			=> $Vend::Cfg->{Special}{badsearch},
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
		return_delim		=> "\t",
		#return_fields		=> undef,
		return_file_name	=> '',
		#save_context		=> undef,
		save_dir			=> '',
		search_file			=> $Vend::Cfg->{ProductFiles}[0],
		search_mod			=> '',
		sort_command		=> '',
		sort_crippled		=> 0,
		#sort_field			=> '',
		#sort_option			=> '',
		#session_id			=> '',
		#session_key			=> '',
		verbatim_columns	=> 1,
		spelling_errors		=> 0,
		substring_match		=> 0,
		uneval_routine		=> \&Vend::Util::uneval_it,
	};

	for(keys %$options) {
		$s->{global}->{$_} = $options->{$_};
	}

	$s->{specs}       = []; # The search text, raw, per field 
							# Special case is form with only one searchspec,
							# it searches in all columns, takes its
							# options from first position

	$s->{fields}      = [];	# The columns to search, by number

	$s->{cases}       = [];	# set for NOT

	$s->{negates}     = [];	# set for NOT

	return;
}

sub new {
    my ($class, %options) = @_;
	my $self = new Vend::Search;
	bless $self, $class;
	$self->init(\%options);
	return $self;
}

sub version {
	$Vend::DbSearch::VERSION;
}

sub escape {
    my($self, @text) = @_;
    if($self->{'global'}->{all_chars}) {
		@text = map {quotemeta $_} @text;
    }
    for(@text) {
        s!([^\\]?)([}])!$1\\$2!g;
    }   
    return @text;
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
			if(
				$g->{coordinate}
				and defined $g->{column_op}
				and $g->{column_op}[$i] =~ /^(==?|eq)$/
				)
			{
				my $spec = $specs[$i];
				$g->{eq_specs} = []
					unless $g->{eq_specs};
				$spec = $g->{dbref}->quote($spec)
					if ! $s->{numeric} || (ref $s->{numeric} and ! $s->{numeric}[$i]);
				$spec = $g->{field_names}[ $s->{fields}[$i] ] . " = $spec";
				push(@{$g->{eq_specs}}, $spec);
			}
			$i++;
		}
	}

# DEBUG
#Vend::Util::logError
#($s->dump_options() . "\nspecs=" . join("|", @specs) . "|\n")
#	if $g->{mv_search_debug};
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
#Vend::Util::logDebug
#("spec='" . (join "','", @specs) . "'\n")
#	if ::debug(0x10 );
# END DEBUG

	# untaint
	for(@specs) {
		/(.*)/s;
		push @pats, $1;
	}
	@{$s->{'specs'}} = @pats;

# DEBUG
#Vend::Util::logDebug
#("pats: '" . join("', '", @pats) . "'\n")
#	if ::debug(0x10);
# END DEBUG

  } # last SPEC_CHECK
  return @pats;
}

sub search {

	my($s,%options) = @_;
    my $g = $s->{global};

	my($delim);
	my($max_matches,$mod,$spec);
	my($code,$count,$matches_to_send,@out);
	my($index_delim,$limit_sub,$return_sub,$delayed_return);
	my($dict_limit,$f,$key,$val,$range_op);
	my($return_file_name,$searchfile,@searchfiles);
	my(@specs);
	my(@pats);

	while (($key,$val) = each %options) {
		$g->{$key} = $val;
	}

	if(ref($g->{search_file})) {
		@searchfiles = @{$g->{search_file}};
	}
	elsif ($g->{search_file}) {
		@searchfiles = $g->{search_file};
	}
	else {
		@searchfiles = $g->{base_directory};
	}

	my $dbref = $s->{table} || undef;

	$g->{base_directory} =~ s/\..*//;
	if( ! $dbref ) {
	 	$dbref = Vend::Data::database_exists_ref($g->{base_directory});
		$dbref = $g->{dbref} = $dbref->ref();
	}

	if(! $dbref) {
		&{$g->{error_routine}}($g->{error_page},
			"{base_directory} must be a valid database reference, was $g->{base_directory}.\n");
		$g->{matches} = -1;
		return undef; # If it makes it this far
	}

	my (@fn) = ($dbref->config('FIRST_COLUMN_NAME') || 'code', $dbref->columns());
#::logError("DbSearch: fn=@fn");

	$g->{field_names} = \@fn;
	my %fh;
	my $idx = 0;
	for (@fn) {
		$fh{$_} = $idx++;
	}
	my $fa;
	foreach $fa ( qw/ return_fields range_look search_field sort_field /) {
		next unless $g->{$fa};
		for( @{$g->{$fa}} ) {
			$_ = $fh{$_} if defined $fh{$_};
		}
	}

	$g->{matches} = 0;

	if($g->{search_spec}) {
	  	@specs = $g->{search_spec};
	}
	else {
		@specs = @{$s->{specs}};
	}

    if(ref $g->{range_look}) {
        no strict 'refs';
        unless( scalar(@{$g->{range_look}}) == scalar(@{$g->{range_min}}) and
                scalar(@{$g->{range_look}}) == scalar(@{$g->{range_max}}) ) {
			&{$g->{error_routine}} ($g->{error_page},
					"Must have min and max values for range.");
			$g->{matches} = -1;
			return undef;
		}
		$range_op = 1;
	}

	@specs = '' if @specs == 0;

	@pats = $s->spec_check($g, @specs);


	if ($g->{coordinate}) {
		undef $f;
	}
	elsif ($g->{return_all}) {
		$f = sub {1};
	}
	elsif ($g->{or_search}) {
		eval {$f = $s->create_search_or(	$g->{case_sensitive},
										$g->{substring_match},
										$g->{negate},
										@pats					)};
	}
	else  {	
		eval {$f = $s->create_search_and(	$g->{case_sensitive},
										$g->{substring_match},
										$g->{negate},
										@pats					)};
	}
	if($@) {
		&{$g->{error_routine}}($g->{error_page}, $@);
		$g->{matches} = -1;
		return undef;
	}

	my $prospect;

	eval {
		($limit_sub, $prospect) = $s->get_limit($f);
	};

	if($@) {
		&{$g->{error_routine}}($g->{error_page}, $@);
		$g->{matches} = -1;
		return undef;
	}

	$f = $prospect if $prospect;

#::logError("f=$f limit=$limit_sub");

	eval {($return_sub, $delayed_return) = $s->get_return()};
	if($@) {
		&{$g->{error_routine}}($g->{error_page}, $@);
		$g->{matches} = -1;
		return undef;
	}

	$max_matches = int($g->{max_matches});

	$g->{overflow} = 0;
	my $qual;

#::logError("DbSearch return subroutines: $return_sub and $delayed_return");

	foreach $searchfile (@searchfiles) {
		$searchfile =~ s/\..*//;
		my $db;
		if (! $g->{mv_one_sql_table} and $db = Vend::Data::database_exists_ref($searchfile)) {
			$dbref = $db->ref();
			$g->{field_names} = [ $dbref->config('FIRST_COLUMN_NAME') || 'code', $dbref->columns() ];
		}
		if(! $qual and $g->{eq_specs}) {
			$qual = ' WHERE ';
			my $joiner = ' AND ';
			$joiner = ' OR ' if $g->{or_search};
			$qual .= join $joiner, @{$g->{eq_specs}};
		}

		if(! defined $f and defined $limit_sub) {
			while($_ = join "\t", $dbref->each_record($qual || undef) ) {
				next unless &$limit_sub($_);
				(push @out, $searchfile and last)
					if defined $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		elsif(defined $limit_sub) {
			while($_ = join "\t", $dbref->each_record($qual || undef) ) {
				next unless &$f();
#::logError("matched f");
				next unless &$limit_sub($_);
				(push @out, $searchfile and last)
					if defined $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		elsif (!defined $f) {
			&{$g->{error_routine}}($g->{error_page}, 'No search definition');
			$g->{matches} = -1;
			return undef;
		}
		else {
			while($_ = join "\t", $dbref->each_record($qual || undef) ) {
				next unless &$f();
				(push @out, $searchfile and last)
					if defined $return_file_name;
				push @out, &$return_sub($_);
			}
		}
	}

	if($delayed_return) {
		$s->sort_search_return(\@out);
		@out = map { $delayed_return->($_) } @out;
	}

	if($g->{unique_result}) {
		my %seen;
		@out = grep ! $seen{$_}++, @out;
	}

	$g->{matches} = scalar(@out);

    if ($g->{matches} > $g->{match_limit}) {
        $s->save_more(\@out)
            or &{$g->{log_routine}}("Error saving matches: $!");
		if ($g->{first_match}) {
			splice(@out,0,$g->{first_match}) if $g->{first_match};
			$g->{next_pointer} = $g->{first_match} + $g->{match_limit};
			$g->{next_pointer} = 0
				if $g->{next_pointer} > $g->{matches};
		}
        $#out = $g->{match_limit} - 1;
    }

	return \@out unless $g->{return_reference};

	if($g->{return_reference} ne 'HASH') {
		my $col = scalar @{$g->{return_fields}};
		@out = map { [ split /\t/, $_, $col ] } @out;
	}
	else {
		my $col = scalar @{$g->{return_fields}};
		my @col;
		my @names;
		@names = @{$g->{field_names}};
		$names[0] eq '0' and $names[0] = 'code';
		my %hash;
		my $key;
		for (@out) {
			@col = split /\t/, $_, $col;
			$hash{$col[0]} = {};
			@{ $hash{$col[0]} } {@names} = @col;
		}
		return \%hash;
	}

	\@out;
}

# Unfortunate hack need for Safe searches

*more_matches       = \&Vend::Search::more_matches;
*get_return         = \&Vend::Search::get_return;
*map_ops            = \&Vend::Search::map_ops;
*get_limit          = \&Vend::Search::get_limit;
*saved_params       = \&Vend::Search::saved_params;
*range_check        = \&Vend::Search::range_check;
*create_search_and  = \&Vend::Search::create_search_and;
*create_search_or   = \&Vend::Search::create_search_or;
*save_context       = \&Vend::Search::save_context;
*find_sort          = \&Vend::Search::find_sort;
*dump_options       = \&Vend::Search::dump_options;
*save_more          = \&Vend::Search::save_more;
*sort_search_return = \&Vend::Search::sort_search_return;

1;
__END__
