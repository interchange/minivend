# Vend/TextSearch.pm:  Search indexes with Perl
#
# $Id: TextSearch.pm,v 1.7 1997/05/05 20:14:20 mike Exp $
#
# ADAPTED FOR USE WITH MINIVEND from Search::TextSearch
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
##  vi regex to delete debugs     %s/^\(.*$s->debug\)/#\1/
##  vi regex to restore debugs     %s/^\([^#]*\)#\(.*$s->debug\)/\1\2/
#

package Vend::TextSearch;
require Vend::Search;

# AUTOLOAD
#use AutoLoader;
#@ISA = qw(Vend::Search);
#sub import {}
# END AUTOLOAD

# NOAUTO
@ISA = qw(Vend::Search);
# END NOAUTO

$VERSION = substr(q$Revision: 1.7 $, 10);

use Text::ParseWords;
use Search::Dict;
use strict;

# AUTOLOAD
#1;
#__END__
# END AUTOLOAD

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
	$g->{'dict_order'}	= 0;
	$g->{'dict_case'} 	= 0;
}

sub version {
	$Vend::TextSearch::VERSION;
}

sub escape {
    my($self, @text) = @_;
    if($self->{'global'}->{all_chars}) {
		@text = grep quotemeta $_, @text;
    }
    for(@text) {
        s!([^\\]?)([}])!$1\\$2!g;
    }   
    return @text;
}

sub search {

	my($s,%options) = @_;
    my $g = $s->{global};

#	$s->debug("Vend::TextSearch");

	my($delim,$string);
	my($max_matches,$mod,$spec);
	my($code,$count,$matches_to_send,@out);
	my($index_delim,$limit_sub,$return_sub);
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
	@searchfiles = grep s!^([^/])!$g->{base_directory}/$1!, @searchfiles
			if $g->{base_directory};

 	$return_file_name = $g->{return_file_name};
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

#	$s->debug($s->dump_options() . "\n");

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
		$string = $specs[$i];
		if($#specs and length($string) == 0) { # should add a switch
			if($g->{coordinate}) {
		        splice(@{$s->{fields}}, $i, 1);
		        splice(@{$g->{case_sensitive}}, $i, 1)
					if ref $g->{case_sensitive};
		        splice(@{$g->{substring_match}}, $i, 1)
					if ref $g->{substring_match};
		        splice(@{$g->{negate}}, $i, 1)
					if ref $g->{negate};
			}
		    splice(@specs, $i, 1);
			splice(@{$s->{specs}}, $i, 1);
		}
		elsif(length($string) < $g->{min_string}) {
			my $msg = <<EOF;
Search strings must be at least $g->{min_string} characters.
You had '$string' as one of your search strings.
EOF
			&{$g->{error_routine}}($g->{error_page}, $msg);
			$g->{matches} = -1;
			return undef;
		}
		else {
			$i++;
		}
	}

#	$s->debug($s->dump_options() . "\n");

	if ( ! $g->{exact_match} and ! $g->{coordinate}) {
		@specs = $s->quoted_string( join ' ', @specs);
	}

	@specs = $s->escape(@specs);

#	$s->debug("spec='" . (join "','", @specs) . "'");

	# untaint
	for(@specs) {
		/(.*)/;
		push @pats, $1;
	}
	@{$s->{'specs'}} = @specs;

#	$s->debug("pats: '", join("', '", @pats), "'");
  } # last SPEC_CHECK

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

	eval {$limit_sub = $s->get_limit($f)};
	if($@) {
		&{$g->{error_routine}}($g->{error_page}, $@);
		$g->{matches} = -1;
		return undef;
	}

	eval {$return_sub = $s->get_return()};
	if($@) {
		&{$g->{error_routine}}($g->{error_page}, $@);
		$g->{matches} = -1;
		return undef;
	}

	$max_matches = int($g->{max_matches});

	$g->{overflow} = 0;

#	$s->debug('fields/specs: ', scalar @{$s->{fields}}, " ", scalar @{$s->{specs}});

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
	if($sort_string) {
		#$sort_string =~ s!\|\s*$!join ' ', @searchfiles, '|'!e;
		@searchfiles = join ' ', 'cat', @searchfiles, '|', $sort_string;
	}
#	$s->debug("sort_string:  $sort_string");

	local($/) = $g->{record_delim};

	foreach $searchfile (@searchfiles) {
		$searchfile = "$g->{base_directory}/$searchfile"
			unless ($sort_string || $searchfile =~ m:^/: || ! $g->{base_directory});
		open(Vend::TextSearch::SEARCH, $searchfile)
			or &{$g->{log_routine}}( "Couldn't open $searchfile: $!\n"), next;
		my $line;

		# Get field names only if no sort (will throw it off) or
		# not already defined
        if($g->{head_skip} == 1) {
            my $field_names;
            chomp($field_names = <Vend::TextSearch::SEARCH>);
            $g->{field_names} = [ split /$index_delim/, $field_names]
                unless defined $g->{field_names} || $sort_string;
        }
        elsif($g->{head_skip} > 1) {
            while(<Search::TextSearch::SEARCH>) {
                last if $. >= $g->{head_skip};
            }
        }

		if($g->{dict_look}) {
#			$s->debug("Dict search:  look='$g->{dict_look}'");
#			$s->debug("Dict search:   end='$g->{dict_end}'");
			look \*Vend::TextSearch::SEARCH,
				$g->{dict_look}, $g->{dict_order}, $g->{dict_fold};
		}

		if($g->{dict_end} && defined $limit_sub) {
#			$s->debug("Dict search: with limit");
			while(<Vend::TextSearch::SEARCH>) {
				last if &$dict_limit($_);
#				#$s->debug("Dict search: found='$_'");
				next unless &$f();
				next unless &$limit_sub($_);
				(push @out, $searchfile and last)
					if $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		elsif($g->{dict_end}) {
#			$s->debug("Dict search: NO limit");
			while(<Vend::TextSearch::SEARCH>) {
				last if &$dict_limit($_);
#				# #$s->debug("Dict search: found='$_'");
				next unless &$f();
				(push @out, $searchfile and last)
					if $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		elsif(! defined $f and defined $limit_sub) {
			while(<Vend::TextSearch::SEARCH>) {
				next unless &$limit_sub($_);
				(push @out, $searchfile and last)
					if $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		elsif(defined $limit_sub) {
			while(<Vend::TextSearch::SEARCH>) {
				next unless &$f();
				next unless &$limit_sub($_);
				(push @out, $searchfile and last)
					if $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		else {
			while(<Vend::TextSearch::SEARCH>) {
				next unless &$f();
				(push @out, $searchfile and last)
					if $return_file_name;
				push @out, &$return_sub($_);
			}
		}
		close Vend::TextSearch::SEARCH;
	}

	$g->{matches} = scalar(@out);
	$g->{first_match} = 0;


    if ($g->{matches} > $g->{match_limit}) {
        $s->save_more(\@out)
            or &{$g->{log_routine}}("Error saving matches: $!\n");
        $#out = $g->{match_limit} - 1;
    }

#	$s->debug($g->{matches}, " matches");
#	$s->debug("0 .. ", (scalar(@out) - 1));

	\@out;
}

1;
__END__
