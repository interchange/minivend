#!/usr/bin/perl -w
#
# Search.pm -- Base class for MiniVend and Vend searches
#

package Vend::Search;

$VERSION = substr(q$Revision: 1.1 $, 10);

=head1 NAME

Search.pm - provide framework for multiple searches

=head1 SYNOPSIS

    use Vend::Search;

=head1 DESCRIPTION

This module is a base class for MiniVend and Vend search
engines. It defines an interface that can be used by any of the Vend
search modules, such as Vend::Glimpse or Vend::AsciiSearch, which
are the standard ones include with MiniVend.

It exports no routines, just provides methods for the other classes.

=head2 Search Comparisons

                         Ascii         Glimpse 
			            -------        --------
 Speed                   Medium        Dependent on uniqueness of terms
 Requires add'l software No            Yes   
 Usable limit on items   20,000        unlimited
 Search individually     No            Yes
  for fields               


=head1 Methods

Only virtual methods are supported by the Vend::Search class. Those search
modules that inherit from it may export static methods if desired. There are
the L<Global Parameter Method>, L<Column Setting Functions>, and 
L<Row Setting Functions>. L<SEE ALSO> Vend::Glimpse, Vend::Ascii.

=head2 Global Parameter Method

	$s->global(param,val); 
	$status = $s->global(param); 
	%globals = $s->global();

Allows setting of the parameters that are global to the search. The standard
ones are:

=over 4

=item match_limit

The number of matches to return.  Not to be confused with max_matches,
at which number the search will terminate. Additional matches will be
stored in the file pointed to by I<save_dir>, I<session_id>, and I<search_mod>.

=item match_over

Set by the search routine if it matched the maximum number before reaching
the end of the search. Set to undef if not supported.

=item min_string

The minimum size of search string that is supported. Using a size of less
than 4 for Glimpse, for example, is not wise.  

=item speed

The speed of search desired, in an integer value from one to 10. Those engines
that have a faster method to search (possibly at a cost of comprensivity) can
adjust their routines accordingly.

=item spelling_errors

Those engines that support "tolerant matching" can honor this parameter
to set the number of spelling errors that they will allow for.
I<This can slow search dramatically on big databases.> Ignored by
search engines that don't have the capability.

=item base_directory

Those engines which look for matches in index files can read this
to get the base directory of the images.

=item index_file

A specification of an index file (or files) to search.  The usage
is left to the module -- it could, for example, be an anonymous array
or wild-card specification for multiple indices.

=item matches

Set by the search routine to indicate the number of matches in the
last search. If the engine can return the total number of matches
(without the data) then that is the result.

=item error_routine

Reference to a subroutine which will send errors to the user. The
default is \&main::display_special_page in the MiniVend search
modules.

=item error_page

A Vend/MiniVend page name to be displayed when a user error occurs.
Passed along with a single string parameter to the error_routine,
as in:
  
     &{$self->{global}->{error_routine}}
	 	($self->{global}->{error_page}, $msg);

=item index_delim

The delimiter character to terminate the return code in an ascii
index file. In Vend::Glimpse and Vend::AsciiSearch, the default
is "\t", or TAB.

=item log_routine

A reference to a subroutine to log an error or status indication.
In MiniVend, it is \&main::logError.

=item error_routine

A reference to a subroutine to return an indication to the user. In
MiniVend, it is \&main::display_special_page.

=item next_pointer

The pointer to the next list of matches. This is for engines that
can return only a subset of the elements starting from an element.
For making a (next match) list.

=item search_history 

An anonymous array [size history] of 'unevaled' strings that contain
the search history.  When evaled by the Vend::Search module, will
create an environment in the object that duplicates a previous search.

=item history

The number of searches to keep in the history.

=back

=head2 Column Setting Methods

Column setting functions allow the setting of a series of columns of
match criteria:

	$search->fields('author', 'title');

This is an example for the I<fields> match criteria,
which is the names of the fields in the database to match. Similar
functions are provided for I<mods>, I<links>, I<cases>, I<negates>,
I<open_parens>, and I<close_parens>.

For simple searches, only one term need be set, and the grouping
functions I<links>, I<open_parens>, and I<close_parens> are ignored.
In most cases, if the setting for a particular column is not defined
for a row, the value in position 0 (the first row) is used.

=over 4

=item fields

The column names to search. The Ascii engine doesn't match on
particular fields, just text in a row. Otherwise the name must
match a field in the database, or it will be ignored. (Should
an exception be raised?).

=item specs

The search text, raw, per field. A special case is form with
only one searchspec, it searches in all columns, takes its
options from first position in all other rows.

=item mods        

Modifies the match criteria. Recognized modifications are:

	start	Matches when the field starts with the spec
	whole	Matches whole words only

=item links

The link to the previous row. If there are two I<fields> to search, with two
different I<specs>, this determines whether the search is AND, OR, or NEAR.
For engines that support it, NEAR matches with in $self->global('near') words
of the previous word (forward only). 

=item cases

Determines whether the match will be case-sensitive or not.  If the search
engine doesn't support independent case-sensitivity (like glimpse), the
value in position 0 will be used.

=item negates

Negates the sense of the match for that term.  Allows searches like 
"spec1 AND NOT spec2" or "NOT spec1 AND spec2".

=item open_parens

Determines whether a logical parentheses will be placed on the left 
of the term. Allows grouping of search terms for more expressive matching,
i.e. "(AUTHOR Shakespeare AND TYPE Play ) NOT TITLE Hamlet".

=item close_parens

Determines whether a logical parentheses will be placed on the right
of the term.

=back

=head2 Row Setting Methods

Row setting functions allow the setting of all columns in a row.

	$query->rowpush($field,$spec,$case,$mod,$link,$left,$right);
	($field,$spec,$case,$mod,$link,$left,$right) = $query->rowpop();
	@oldvals = $query->rowset(n,$field,$spec,$case,$mod,$link,$left,$right);

You can ignore the trailing parameters for a simple search. For example:

	$field = 'author';
	$spec = 'forsythe';
	$limit = 25;
	$query = new Vend::Glimpse;
	$query->rowpush($field,$spec);
	@rows = $query->search($limit);

This searches the field 'author' for the name 'forsythe', with all other
options at their defaults (ignore case, match substrings, not negated, no
links, no grouping), and will return 25 matches (sets the matchlimit global).
For a more complex search, you can add the rest of the parameters as needed.

=head2 Search Paging Methods

Routines useful for creating lists of matches that can be paged include:

=over 4

=item more_matches

Given a file with return codes from previous searches, one per line,
returns an array with the correct matches in the array.  Opens the
file in directory I<save_dir>, with session information appended
(the I<session_id> and I<search_mod>), and returns I<match_limit> matches,
starting at I<next_pointer>.

=back

=head1 SEE ALSO

glimpse(1), Vend::Glimpse(3L), Vend::AsciiSearch(3L)

=head1 AUTHOR

Mike Heins, <mikeh@iac.net>

=cut

use Carp;
use strict;

sub new {
	my ($class, %options) = @_;
	my $s = {};

	$s->{global} = {%options}; # The search to call, global options, etc.

	$s->{fields}      = [''];	# The column names to search

	$s->{specs}       = []; # The search text, raw, per field 
							# Special case is form with only one searchspec,
							# it searches in all columns, takes its
							# options from first position

	$s->{mods}        = [0];	# whole_word -> whole words
							# one_spelling_error -> ignored in some searches
							# starts_with -> 

	$s->{links}       = [0];# Can contain 'and', 'or',
							# 'near',
							# undef defaults to AND

	$s->{cases}       = [0];	# set for case-sensitive
	$s->{negates}     = [0];	# set for NOT

	$s->{open_parens} = [];	# Associated with searchfields
							# Open parentheses to stop association
							# with left-hand column.

	$s->{close_parens}= [];	# Associated with searchfields
							# Close parentheses to stop association
							# with right-hand column.

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


sub set_param {

	my($self,$term,@fields) = @_;

	unless (defined $self->{$term}) {
		my $caller = caller();
		my $name = sub {caller()};
		croak "$caller calling $name: accessed non-existent array $term.";
	}

	if(@fields) {
		@{$self->{$term}} = @fields;
	}
	else {
		@{$self->{$term}};
	}

}

sub version {
	$Vend::Search::VERSION;
}

sub fields {
	my ($self,@fields) = @_;
	$self->set_param('fields', @fields);
}

sub specs {
	my ($self,@specs) = @_;
	$self->set_param('specs',@specs);
}

sub cases {
	my ($self,@cases) = @_;
	$self->set_param('cases',@cases);
}

sub negates {
	my ($self,@negates) = @_;
	$self->set_param('negates',@negates);
}

sub links {
	my ($self,@links) = @_;
	$self->set_param('links',@links);
}

sub mods {
	my ($self,@mods) = @_;
	$self->set_param('mods',@mods);
}

sub open_parens {
	my ($self,@open_parens) = @_;
	$self->set_param('open_parens',@open_parens);
}

sub close_parens {
	my ($self,@close_parens) = @_;
	$self->set_param('close_parens',@close_parens);
}

sub rowpush {
	my $self = shift;
	my @out;

	for(field_order()) {
		push @out, push(@{$self->{$_}}, shift @_);
	}
	@out;
}

sub rowpop {
	my $self = shift;
	my @out;

	for(field_order()) {
		push @out, pop(@{$self->{$_}});
	}
	@out;
}

sub rowset {
	my $self = shift;
	my $col = shift;
	my @out;
	my $val;

	for(field_order()) {
		$val = splice(@{$self->{$_}},$col,1,shift);
		push @out, $val;
	}
	@out;
}

sub field_order {
	qw(
		fields
		specs
		mods
		cases
		links 
		negates
		open_parens
		close_parens
	);
}

sub more_matches {
	my($self,$next,$last,$mod) = @_;
	my $g = $self->{'global'};
	my @out;
	my $count = 0;
	my $filemod;
	my $id = $g->{session_id};
	$mod = defined $mod ? $mod : 1;
	$g->{search_mod} = $mod;
	$id = ref $id ? $$id : $id;
	$id .= ":$mod";
	if(defined $next and $last) {
		$g->{match_limit} = 1 + $last - $next;
	}
	my $file = $g->{save_dir} . '/' . $id if $g->{save_dir};

	if($file) {
		open(Vend::Search::MORE, $file) || croak "couldn't open $file: $!\n";

		while (<Vend::Search::MORE>) {
			next unless $count++ >= $next;
			next if ($count - 1) > $last;
			push(@out, $_);
		}
		close Vend::Search::MORE;
	}
	elsif (ref $g->{save_hash}) {
		my $h = $g->{save_hash};
		return undef unless exists $h->{$id};
		$count = (@out = split /\n/, $h->{$id});
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
	@out;
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
1;
__END__
