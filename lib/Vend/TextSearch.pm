# Vend/TextSearch.pm:  Search indexes with Perl
#
# $Id: TextSearch.pm,v 1.22 1999/02/15 08:51:31 mike Exp mike $
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

package Vend::TextSearch;
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
	$g->{'dict_look'}	= '';
	$g->{'dict_end'}	= '';
}

sub version {
	$Vend::TextSearch::VERSION;
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

sub search {

	my($s,%options) = @_;
    my $g = $s->{global};

# DEBUG
Vend::Util::logDebug
("Text search using Vend::TextSearch\n")
	if ::debug(0x10);
# END DEBUG

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

	if($g->{base_directory}) {
		for(@searchfiles) {
			$_ = Vend::Util::catfile($g->{base_directory}, $_)
				unless Vend::Util::file_name_is_absolute($_);
		}
	}

	# Auto-index search
	if($g->{dict_look} and $g->{dict_limit} =~ /[^-0-9]/) {
		my $f = $g->{dict_limit};
		$g->{dict_limit} = -1;
		for (@searchfiles) {
			next unless -f "$_.$f"; 
			$_ .= ".$f";
			$g->{return_fields} = [1];
		}
	}

 	$return_file_name = $g->{return_file_name} || undef;
 	$index_delim = $g->{index_delim};
	$g->{return_delim} = $index_delim
		unless defined $g->{return_delim};

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

# DEBUG
Vend::Util::logDebug
($s->dump_options() )
	if ::debug(0x10);
Vend::Util::logError
($s->dump_options() . "specs: " . join('|', @pats) )
    if $CGI::values{mv_search_debug};
# END DEBUG

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

#::logGlobal("f=$f limit=$limit_sub");

	eval {($return_sub, $delayed_return) = $s->get_return()};
	if($@) {
		&{$g->{error_routine}}($g->{error_page}, $@);
		$g->{matches} = -1;
		return undef;
	}

	$max_matches = int($g->{max_matches});

	$g->{overflow} = 0;

# DEBUG
Vend::Util::logDebug
('fields/specs: ' .  scalar @{$s->{fields}} . "/" .  scalar @{$s->{specs}} . "\n")
	if ::debug(0x10);
Vend::Util::logError
('fields/specs: ' .  scalar @{$s->{fields}} . "/" .  scalar @{$s->{specs}} . "\n")
    if $CGI::values{mv_search_debug};
# END DEBUG

	if($g->{dict_end}) {
		if(!$g->{dict_order} && !$g->{dict_fold}) {
			$dict_limit = sub {
					$_[0] gt $g->{dict_end};
			};
		}
		elsif(!$g->{dict_order}) {
			$dict_limit = sub {
					"\L$_[0]" gt "\L$g->{dict_end}";
			};
		}
		elsif(!$g->{dict_fold}) {
			$dict_limit = sub {
					my($line) = @_;
					my($end) = $g->{dict_end};
					$line =~ tr/A-Za-z0-9_ //cd;
					$end =~ tr/A-Za-z0-9_ //cd;
					$line gt $end;
			};
		}
		else {
			$dict_limit = sub {
					my($line) = lc @_;
					my($end) = lc $g->{dict_end};
					$line =~ tr/a-z0-9_ //cd;
					$end =~ tr/a-z0-9_ //cd;
					$line gt $end;
			};
		}
	}

    my $sort_string = $s->find_sort();
	# If the string is set, append the joined searcfiles;
	if($sort_string and !$Global::Windows) {
		#$sort_string =~ s!\|\s*$!join ' ', @searchfiles, '|'!e;
		@searchfiles = join ' ', 'cat', @searchfiles, '|', $sort_string;
	}
# DEBUG
Vend::Util::logDebug
("sort_string:  $sort_string\n")
	if ::debug(0x10) ;
# END DEBUG

	local($/) = $g->{record_delim};

	foreach $searchfile (@searchfiles) {
		open(Vend::TextSearch::SEARCH, $searchfile)
			or &{$g->{log_routine}}( "Couldn't open search file '$searchfile': $!"), next;
		my $line;

		# Get field names only if no sort (will throw it off) or
		# not already defined
        if($g->{head_skip} == 1) {
            my $field_names;
            chomp($field_names = <Vend::TextSearch::SEARCH>);
            $g->{field_names} = [ split /\Q$index_delim/, $field_names]
                unless defined $g->{field_names} || $sort_string;
        }
        elsif($g->{head_skip} > 1) {
            while(<Vend::TextSearch::SEARCH>) {
                last if $. >= $g->{head_skip};
            }
        }

		if($g->{dict_look}) {
# DEBUG
Vend::Util::logDebug
("Dict search:  look='$g->{dict_look}'\n")
	if ::debug(0x10);
Vend::Util::logDebug
("Dict search:   end='$g->{dict_end}'\n")
	if ::debug(0x10);
# END DEBUG
			look \*Vend::TextSearch::SEARCH,
				$g->{dict_look}, $g->{dict_order}, $g->{dict_fold};
		}

		if($g->{dict_end} && defined $limit_sub) {
# DEBUG
Vend::Util::logDebug
("Dict search: with limit\n")
	if ::debug(0x10);
# END DEBUG
			while(<Vend::TextSearch::SEARCH>) {
				last if &$dict_limit($_);
# DEBUG
Vend::Util::logDebug
("Dict search: found='$_'\n")
	if ::debug(0x10);
# END DEBUG
				next unless ! defined $f or &$f();
				next unless &$limit_sub($_);
				(push @out, $searchfile and last)
					if defined $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		elsif($g->{dict_end}) {
# DEBUG
Vend::Util::logDebug
("Dict search: NO limit\n")
	if ::debug(0x10);
# END DEBUG
			while(<Vend::TextSearch::SEARCH>) {
				last if &$dict_limit($_);
# DEBUG
Vend::Util::logDebug
("Dict search: found='$_'\n")
	if ::debug(0x10);
# END DEBUG
				next unless &$f();
				(push @out, $searchfile and last)
					if defined $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		elsif(! defined $f and defined $limit_sub) {
#::logGlobal("no f, limit");
			while(<Vend::TextSearch::SEARCH>) {
				next unless &$limit_sub($_);
				(push @out, $searchfile and last)
					if defined $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		elsif(defined $limit_sub) {
#::logGlobal("f and limit");
			while(<Vend::TextSearch::SEARCH>) {
				next unless &$f();
#::logGlobal("matched f");
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
#::logGlobal("just f");
			while(<Vend::TextSearch::SEARCH>) {
				next unless &$f();
				(push @out, $searchfile and last)
					if defined $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		close Vend::TextSearch::SEARCH;
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

# DEBUG
Vend::Util::logDebug
("$g->{matches} matches\n")
	if ::debug(0x10);
Vend::Util::logError
("$g->{matches} matches")
	if $CGI::values{mv_search_debug};
Vend::Util::logDebug
("0 .. " . (scalar(@out) - 1) . "\n" )
	if ::debug(0x10);
# END DEBUG

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
