# Vend/DbSearch.pm:  Search indexes with Perl
#
# $Id: DbSearch.pm,v 1.22 1999/02/15 08:51:31 mike Exp mike $
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

$VERSION = substr(q$Revision: 1.22 $, 10);

use Search::Dict;
use strict;

sub new {
    my ($class, %options) = @_;
	my $self = new Vend::Search;
	my ($key,$val);
	init($self);
	while ( ($key,$val) = each %options) {
		$self->{global}->{$key} = $val;
	}
	bless $self, $class;
}

sub init {
	my $s = shift;
	my $g = $s->{global};
	$s->{global}->{base_directory} = 'products';
	$s->{global}->{search_file} = '';
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
Vend::Util::logError
($s->dump_options() . "\nspecs=" . join("|", @specs) . "|\n")
	if $g->{mv_search_debug};
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

	if(ref($g->{search_file}) =~ /^ARRAY/) {
		@searchfiles = @{$g->{search_file}};
	}
	elsif ($g->{search_file}) {
		@searchfiles = $g->{search_file};
	}
	else {
		&{$g->{error_routine}}($g->{error_page},
			"{search_file} must be array reference or scalar.\n");
		$g->{matches} = -1;
		return undef; # If it makes it this far
	}

	$g->{base_directory} =~ s/\..*//;
	my $dbref = Vend::Data::database_exists_ref($g->{base_directory});

	if(! $dbref) {
		&{$g->{error_routine}}($g->{error_page},
			"{base_directory} must be a valid database reference, was $g->{base_directory}.\n");
		$g->{matches} = -1;
		return undef; # If it makes it this far
	}

#::logError("DbSearch: made it past ref check");

	$dbref = $g->{dbref} = $dbref->ref();
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

#::logError("DbSearch: made it past spec check");

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

#::logError("DbSearch: made it past return subroutines");

	foreach $searchfile (@searchfiles) {
		$searchfile =~ s/\..*//;
#::logError("DbSearch: searching $searchfile");
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
#::logError("no f, limit");
			while($_ = join "\t", $dbref->each_record($qual || undef) ) {
				next unless &$limit_sub($_);
				(push @out, $searchfile and last)
					if defined $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		elsif(defined $limit_sub) {
#::logError("f and limit");
			while($_ = join "\t", $dbref->each_record($qual || undef) ) {
				next unless &$f();
#::logGlobal("matched f");
				next unless &$limit_sub($_);
				(push @out, $searchfile and last)
					if defined $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		elsif (!defined $f) {
#::logError("no f!!!!??!!");
			&{$g->{error_routine}}($g->{error_page}, 'No search definition');
			$g->{matches} = -1;
			return undef;
		}
		else {
#::logError("just f");
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
		@out = map { &{$delayed_return}($_) } @out;
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

	if($g->{return_reference} eq 'ARRAY') {
		my $col = scalar @{$g->{return_fields}};
		@out = map { [ split /$g->{return_delim}/, $_, $col ] } @out;
	}
	elsif($g->{return_format} eq 'HASH') {
		my $col = scalar @{$g->{return_fields}};
		my @col;
		my @names;
		@names = @{$g->{field_names}};
		$names[0] eq '0' and $names[0] = 'code';
		my %hash;
		my $key;
		for (@out) {
			@col = split /$g->{return_delim}/, $_, $col;
			$hash{$col[0]} = {};
			@{ $hash{$col[0]} } {@names} = @col;
		}
		return \%hash;
	}

	\@out;
}

1;
__END__
