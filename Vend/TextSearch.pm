# TextSearch.pm:  Search indexes with Perl
#
# $Id: TextSearch.pm,v 1.1 1996/03/21 04:05:54 mike Exp mike $

# Copyright 1996 by Michael J. Heins <mikeh@iac.net>
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

$VERSION = substr(q$Revision: 1.1 $, 10);
use Carp;
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

	$g->{base_directory}	= $Config::ProductDir || '';
	$g->{error_page}		= 'badsearch';
	$g->{error_routine}		= \&main::display_special_page || \&die;
	$g->{index_delim}		= "\t";
	$g->{index_file}		= 'products.asc';
	$g->{log_routine}		= \&main::logError || \&warn;
	$g->{match_limit}		= 0;
	$g->{max_matches}		= 2000;
	$g->{min_string}		= 1;
	$g->{next_pointer}		= 0;
	$g->{next_tag}			= '';
	$g->{save_dir}			= '';
	$g->{search_history}	= [];
	$g->{search_mod}		= '';
	$g->{session_id}		= '';
	$g->{spelling_errors}	= 0;
	$g->{uneval_routine}	= \&main::uneval || '';

}

sub version {
	$Vend::TextSearch::VERSION;
}

sub search {

    my($s,%options) = @_;
	my($delim,$string);
	my($max_matches,$case,$mod,$link,$spec);
	my($count,$code,$matches_to_send,@out);
	my($g) = $s->{global};
	my($key,$val);
	my(@pats);

	while (($key,$val) = each %options) {
		$g->{$key} = $val;
	}

	$g->{matches} = 0;

 	unless (${$s->{cases}}[0])	{ $case = 0 }
	else						{ $case = 1 }

	foreach $string (@{$s->{specs}}) {
		if(length($string) < $g->{min_string}) {
			my $msg = <<EOF;
Search strings must be at least $g->{min_string} characters.
You had '$string' as one of your search strings.
EOF
			&{$g->{error_routine}}($g->{error_page}, $msg);
			return undef;
		}
	}

	$spec = join ' ', @{$s->{specs}};

	$spec =~ s/[^$\d\w\s*]//g;
	$spec =~ s'\*'\S+'g;
	$spec =~ /(.*)/;
	$spec = $1;
	@pats = split(/\s+/,$spec);

	my $f;
	if (${$s->{mods}}[0] =~ /\bor\b/i ) {
		eval {$f = create_search_or($case,@pats)};
	}
	else  {	
		eval {$f = create_search_and($case,@pats)};
	}

	$max_matches = int($g->{max_matches});

	
	my $file = "$g->{base_directory}/$g->{index_file}";
    if (!open(Vend::TextSearch::SEARCH,$file)) {
		&{$g->{log_routine}}("Can't open search index: $!\n");
		&{$g->{error_routine}}('badsearch', 'Search index not found.');
    	close Vend::TextSearch::SEARCH;
		return;
    }

	$g->{overflow} = 0;
 	my $index_delim = $g->{index_delim};

	while(<Vend::TextSearch::SEARCH>) {
		next unless &$f();
		push @out, substr($_, 0, index($_, $index_delim));
	}
    close Vend::TextSearch::SEARCH;

	$g->{matches} = scalar(@out) || 0;
	$g->{first_match} = 0;

	if ($g->{matches} > $g->{match_limit}) {
		$matches_to_send = $g->{match_limit};
		my $file;
		$g->{overflow} = 1;
		$g->{next_pointer} = $g->{match_limit};
		if($file = $g->{save_dir}) {
			$file .= '/' . $g->{session_id} . ':' . $g->{search_mod};

			open(Vend::Search::MATCHES, ">$file") ||
				croak "Couldn't write $file: $!\n";
			print Vend::Search::MATCHES join "\n", @out;
			close Vend::Search::MATCHES;
		}
		elsif(ref $g->{save_hash}) {
			my $id = $g->{session_id} . ':' . $g->{search_mod};
			$g->{save_hash}->{$id} = join "\n", @out;
		}
	}
	else {
		$matches_to_send = $g->{matches};
		$g->{next_pointer} = 0;
	}

	#$s->save_history();
	@out[0..($matches_to_send - 1)]
}


sub create_search_and {

	my ($case) = shift(@_) ? '' : 'i';
    croak("create_search_and: create_search_and case_sens patterns") unless @_;
	my $pat;

    my $code = <<EOCODE;
sub {
EOCODE

    $code .= <<EOCODE if @_ > 5;
    study;
EOCODE

    for $pat (@_) {
	$code .= <<EOCODE;
    return 0 unless /$pat/$case;
EOCODE
    } 

    $code .= "}\n";

    my $func = eval $code;
    croak "bad pattern: $@" if $@;

    return $func;
} 

sub create_search_or {

	my ($case) = shift(@_) ? '' : 'i';
    croak("create_search_or: create_search_or case_sens patterns") unless @_;
	my $pat;

    my $code = <<EOCODE;
sub {
EOCODE

    $code .= <<EOCODE if @_ > 5;
    study;
EOCODE

    for $pat (@_) {
	$code .= <<EOCODE;
    return 1 if /$pat/$case;
EOCODE
    } 

    $code .= "}\n";

    my $func = eval $code;
    croak "bad pattern: $@" if $@;

    return $func;
} 

1;
__END__
