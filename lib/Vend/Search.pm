#!/usr/bin/perl -w
#
# Vend::Search -- Base class for search engines
#
# ADAPTED from Search::Text FOR FITTING INTO MINIVEND LIBRARIES
#
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
#

#
#
package Vend::Search;

$VERSION = substr(q$Revision: 1.15 $, 10);
$DEBUG = 0;

=head1 NAME

Search.pm - provide framework for multiple searches

=head1 SYNOPSIS

    use Search::TextSearch;
    use Search::Glimpse;

=cut

=head1 DESCRIPTION

This module is a base class interfacing to search engines. It defines an
interface that can be used by any of the Search search modules, such as
Search::Glimpse or Search::TextSearch, which are the standard ones included
with the module.

It exports no routines, just provides methods for the other classes.

=head2 Search Comparisons

                         Text           Glimpse 
                        -------        --------
 Speed                   Medium        Dependent on uniqueness of terms
 Requires add'l software No            Yes   
 Search individually     Yes           Yes
  for fields               
 Search multiple files   Yes           Yes
 Allows spelling errors  No            Yes
 Fully grouped matching  No            No


=head1 Methods

Only virtual methods are supported by the Search::Base class. Those search
modules that inherit from it may export static methods if desired. There are
the L<Global Parameter Method>, L<Column Setting Functions>, and 
L<Row Setting Functions>. L<SEE ALSO> Search::Glimpse, Search::TextSearch.

=head2 Global Parameter Method

    $s->global(param,val); 
    $status = $s->global(param); 
    %globals = $s->global();

Allows setting of the parameters that are global to the search. The standard
ones are listed below.

=over 4

=item base_directory

Those engines which look for matches in index files can read this
to get the base directory of the images.

=item case_sensitive

This is a global version of the I<cases> field. If set, the search
engine should return only matches which exactly match, including
distinction between lower- and upper-case letters.  The default is not
set, to ignore case.

=item error_page

A page or filename to be displayed when a user error occurs.
Passed along with a single string parameter to the error_routine,
as in:
  
     &{$self->{global}->{error_routine}}
        ($self->{global}->{error_page}, $msg);

=item error_routine

Reference to a subroutine which will send errors to the user. The
default is '\&croak'.

=item exact_match

Strings sent as match specifications will have double quotes put around
them, meaning the words must be found in the order they are put in. Any
double quotes contained in the string will be silently deleted.

=item first_match

The number of the first match returned in a of I<more_matches>. This
tells the calling program where to start their increment.

=item head_skip

Used for the TextSearch module to indicate lines that should be skipped
at the beginning of the file. Allows a header to be skipped if
it should not be searched.

=item index_delim

The delimiter character to terminate the return code in an ascii
index file. In Search::Glimpse and Search::TextSearch, the default
is "\t", or TAB.  This is also the default for {return_delim}
if that is not set.

If field-matching is being used, this the character/string used
for splitting the fields.  If properly escaped, and {return_delim}
is used for joining fields, it can be a regular expression -- Perl
style.

=item index_file

A specification of an index file (or files) to search.  The usage
is left to the module -- it could, for example, be an anonymous array
(as in Search::TextSearch) or wild-card specification for multiple indices
(as in Search::Glimpse).

=item log_routine

A reference to a subroutine to log an error or status indication.
By default, it is '\&Carp::carp';

=item match_limit

The number of matches to return.  Not to be confused with max_matches,
at which number the search will terminate. Additional matches will be
stored in the file pointed to by I<save_dir>, I<session_id>, and I<search_mod>.
The default is 50.

=item matches

Set by the search routine to indicate the number of matches in the
last search. If the engine can return the total number of matches
(without the data) then that is the result.

=item min_string

The minimum size of search string that is supported. Using a size of less
than 4 for Glimpse, for example, is not wise.  

=item next_pointer

The pointer to the next list of matches. This is for engines that
can return only a subset of the elements starting from an element.
For making a next match list.

=item next_url

The base URL that should be used to invoke the I<more_matches>
function. Provided as an object-contained scratchpad value for
the calling routine -- it will not be used or modified by Search::Base.

There are a couple of useful ways to use this to invoke the 
proper I<more_matches> search that are shown in the example
search CGI provided with this module set. Both involve setting
the next_url and combining it with a random I<session_id> and
I<search_mod>.

=item or_search

If set, the search engine should return matches which match any of the
search patterns.  The default is not set, requiring matches to all
of the keywords for a match return.

=item overflow

Set by the search routine if it matched the maximum number before reaching
the end of the search. Set to undef if not supported.

=item record_delim 

This sets the type of record that will be searched. For the
Search::TextSearch module, this is the same as Perl -- in fact,
the default is to use $/ (at the time of object creation) as
the default.

For the Search::Glimpse module, the following mappings occur:

    $/ = "\n"        Glimpse default
    $/ = "\n\n"      -d '$$'
    $/ = ""          -d '$$'
    $/ = undef       -d 'NeVAiRbE'
    anything else    passed on as is (-d 'whatever')

One useful pattern is '^From ', which will make each email
message in a folder a separate record.

If you are doing this, and expect to be doing field returns,
it will probably be useful to set "\n\n" or "\n" as the
default I<index_delim>. If used in combination with the obscure
anonymous hash definition of I<return_fields>, you can
search and return mail headers on each message that matches.

=item return_delim

The delimiter character to join fields that are cut out of
the matched line/paragraph/page. The default is to set it
to be the same as {index_delim} if not explicitly set.

=item return_fields 

The fields that will be returned from the line/paragraph/page
matched.  This is not to be confused with the I<fields> setting --
it will not affect the matching, only the returned fields.
The default (when it is undefined) is to return only the first
field.  There are several options for this field.

If the value is an ARRAY reference, an integer list of the columns to be
returned is assumed.

If the value is a HASH reference, then all words found AFTER the
I<key> of the hash (with assumed but not required whitespace as a separator)
up to the I<value> of the item (used as a delimiter).  The following  example
will print the value of the From:, Reply-to: and Date: headers from any
message in your (UNIX) system mailbox that contains 'foobar'.

    $s = new Search::TextSearch
            return_fields => {
                            From: => "\n",
                            Reply-To: => "\n",
                            Date: => "\n",
                            },
            record_delim    => "\nFrom ",
            search_file     => $ENV{MAIL};

    print $s->search('foobar');

=item return_file_name

All return options will be ignored, and the file names of any matches
will be returned instead. The limit match-to-field routines are still
enabled for Search::TextSearch, but not for Glimpse, since the 'glimpse B<-l>'
option is used for that.

=item save_dir

The directory that search caches (for the I<more_matches> function)
will be saved in.  Only applies to file save mode.

=item search_mod

This is used to develop a unique search save id for a user with
a consistent I<session_id>.  For the I<more_matches> function.

=item search_port

The port (passed to glimpse with the B<-K> option) that is to be
used for a network-attached search server.

=item search_server

The host name of a network-attached search server, passed to glimpse
with the B<-J> option.

=item session_id

This is used to determine the save file name or hash key used to
cache a search (for the I<more_matches>) function.

=item speed

The speed of search desired, in an integer value from one to 10. Those engines
that have a faster method to search (possibly at a cost of comprensivity) can
adjust their routines accordingly.

=item spelling_errors

Those engines that support "tolerant matching" can honor this parameter
to set the number of spelling errors that they will allow for.
I<This can slow search dramatically on big databases.> Ignored by
search engines that don't have the capability.

=item substring_match

If set, the search engine should return partial, or substring, matches.
The default is not set, to indicate whole word matching.
I<This can slow search dramatically on big databases.> 

=item uneval_routine

A reference to a subroutine to save the search parameters to a cache.
By default, it is '\&uneval', the routine supplied with Search::Base.

=back

=head1 METHODS

=head2 Virtual methods provided

=item more_matches

Given a file with return codes from previous searches, one per line,
returns an array with the correct matches in the array.  Opens the
file in directory I<save_dir>, with session information appended
(the I<session_id> and I<search_mod>), and returns I<match_limit> matches,
starting at I<next_pointer>.

=item search

This is the main method defined in the individual search engine.
You can submit a single parameter for a quick search, which will
be interpreted as the one and only search specification, overriding
any settings residing in the I<specs> array.  Options can be specified
at object creation, or separately with the I<global> method. Or a
I<search_spec> can be specified, which will temporarily override
the setting in I<specs> (for that invocation only).

Otherwise, the parameters are named search options as documented
above.  Examples:

    # Simple search with default options for 'foobar' in the named file
    $s = new Search::TextSearch search_file => '/var/adm/messages');
    @found = $s->search('foobar');

    # Search for 'foobar' in /var/adm/messages, return only fields 0 and 2
    # where fields are separated by spaces
    $s = new Search::TextSearch;
    @found = $s->search( search_file   => '/var/adm/messages',
                         search_spec   => 'foobar',
                         return_fields => [0,2],
                         return_delim  => ' ',
                         index_delim   => '\s+'                 );

    # Search for 'foobar' in any file containing 'messages' in
    # the default glimpse index, return the file names
    $s = new Search::Glimpse;
    @found = $s->search( search_spec   => 'foobar',
                         search_file   => 'messages',
                         return_file_name  => 1,       );

    # Same as above except use glimpse index located in /var directory
    $s = new Search::Glimpse;
    @found = $s->search( search_spec       => 'foobar',
                         base_directory    => '/var',
                         search_file       => 'messages',
                         return_file_name  => 1,       );

    # Search all files in /etc
    # Return file names with  lines that have 'foo' in field 1
    # and 'bar' in field 3, with case sensitivity
    # (using the default field delimiter of \t)
    $s = new Search::TextSearch;
    $s->rowpush('foo', 1);
    $s->rowpush('bar', 3);
    chop(@files = `ls /etc`);
    @found = $s->search( search_file   => [@files],
                         case_sensitive  => 1,
                         return_file_name  => 1,       );

    # Same as above using direct access to specs/fields
    $s = new Search::TextSearch;
    $s->specs('foo', 'bar');
    $s->fields(1, 3);
    chop(@files = `ls /etc`);
    @found = $s->search( search_file   => [@files],
                         case_sensitive  => 1,
                         return_file_name  => 1,       );
    # Repeat search with above settings, except for specs,
    # if less than 4 matches are found
    if(@found < 4) {
        @found = $s->search('foo');
    }


=head2 Column Setting Methods

Column setting functions allow the setting of a series of columns of
match criteria:

    $search->specs('foo', 'foo bar', 'foobar');
    $search->fields(1, 3, 4);

This is an example for the I<specs> and I<fields> match criteria, which
are the search specifications and  the the fields to search,
respectively. Similar functions are provided for I<mods>, I<links>,
I<cases>, I<negates>, I<open_parens>, and I<close_parens>.

For the included Search::Glimpse and Search::TextSearch modules, an item will
match the above example only if field (or column) 1 contains 'foo',
field 3 contains 'foo' and/or 'bar', and field 4 contains foobar.  The
setting of the case_sensitive, or_search, and substring_match terms will
be honored as well.

For simple searches, only one term need be set, and the grouping
functions I<links>, I<open_parens>, and I<close_parens> are ignored.
In most cases, if the setting for a particular column is not defined
for a row, the value in the global setting is used.

=over 4

=item specs

The search text, raw, per field. This is the only item that
necessarily needs to be set to do a search.

If more than one specification is present, there are three forms of
behavior supported by the included Search::TextSearch and Search::Glimpse
modules. First, if there are multiple search specifications, they are
combined together, just as they would if separated by spaces (and not
quoted).  Second, if the number of specs matches the number of
I<fields>, each spec must match the field that it is associated with
(subject to the I<or_search> and I<case_sensitive> settings within that
field). Last, if there are more I<fields> than I<specs>, only the columns
in I<fields> are searched for the combined specs.

=item fields

The column B<numbers> to search, where a column is a field separated by
I<index_delim>. In the Search::TextSearch and Search::Glimpse modules,
this becomes operative in one of two ways. If the number of I<specs>
match the number of fields, each specification is separately checked
against its associated field.  If the number of fields is different from
the number of I<specs>, all specs are applied, but only to the text in
the specified fields.  Both first match on all of the text in the row,
then filter the match with another routine that checks for matches in
the specified fields.

=item mods        

Modifies the match criteria. Recognized modifications might be:

    start   Matches when the field starts with the spec
    sub     Match substrings.

Not supported in the included modules.

=item links

The link to the previous row. If there are two I<fields> to search, with
two different I<specs>, this determines whether the search is AND, OR,
or NEAR.  For engines that support it, NEAR matches with in
$self->global('near') words of the previous word (forward only). Not
supported in the included modules.

=item cases

For advanced search engines that support full associative
case-sensitivity.  Determines whether the particular match in this set
will be case-sensitive or not.  If the search engine doesn't support
independent case-sensitivity (like the Search::TextSearch and Search::Glimpse
modules), the value in I<or_search> will be used. Not supported in
the included modules.

=item negates

Negates the sense of the match for that term.  Allows searches like 
"spec1 AND NOT spec2" or "NOT spec1 AND spec2". Not supported in
the included modules.

=item open_parens

Determines whether a logical parentheses will be placed on the left 
of the term. Allows grouping of search terms for more expressive matching,
i.e. "(AUTHOR Shakespeare AND TYPE Play ) NOT TITLE Hamlet". Not supported in
the included modules.

=item close_parens

Determines whether a logical parentheses will be placed on the right
of the term. Not supported in the included modules.

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
    $query = new Search::Glimpse;
    $query->rowpush($field,$spec);
    @rows = $query->search( match_limit => 25 );

This searches the field 'author' for the name 'forsythe', with all other
options at their defaults (ignore case, match substrings, not negated, no
links, no grouping), and will return 25 matches (sets the matchlimit global).
For a more complex search, you can add the rest of the parameters as needed.

=over 4

=back

=head1 SEE ALSO

glimpse(1), Search::Glimpse(3L), Search::TextSearch(3L)

=head1 AUTHOR

Mike Heins, <mikeh@iac.net>

=cut

use Carp;
use strict;
use vars qw($DEBUG $VERSION);

sub new {
	my ($class, %options) = @_;
	my $s = {};

	$DEBUG = $Global::DEBUG;

	$s->{global} = {
		all_chars			=> 1,
		base_directory		=> $Vend::Cfg->{'ProductDir'},
		case_sensitive		=> 0,
		coordinate			=> 0,
		error_page			=> $Vend::Cfg->{'Special'}->{'badsearch'},
		error_routine		=> \&main::display_special_page,
		exact_match			=> 0,
		first_match			=> 0,
		record_delim		=> $/,
		head_skip			=> 1,
		index_delim			=> "\t",
		index_file			=> '',
		log_routine			=> \&Vend::Util::logError,
		match_limit			=> 50,
		max_matches			=> 2000,
		min_string			=> 1,
		next_pointer		=> 0,
		negate      		=> 0,
		or_search			=> 0,
		return_all			=> 0,
		range_look			=> '',
		range_min			=> '',
		range_max			=> '',
		range_alpha			=> '',
		return_delim		=> undef,
		return_fields		=> undef,
		return_file_name	=> '',
		save_context		=> undef,
		save_dir			=> '',
		search_file			=> 'products.asc',
		search_mod			=> '',
		sort_command		=> 'sort',
		sort_crippled		=> 0,
		sort_field			=> '',
		sort_option			=> '',
		session_id			=> '',
		session_key			=> '',
		spelling_errors		=> 0,
		substring_match		=> 0,
		uneval_routine		=> \&Vend::Util::uneval,
	};

	for(keys %options) {
		$s->{global}->{$_} = $options{$_};
	}

	$s->{specs}       = []; # The search text, raw, per field 
							# Special case is form with only one searchspec,
							# it searches in all columns, takes its
							# options from first position

	$s->{fields}      = [];	# The columns to search, by number

	$s->{mods}        = [];	# i.e. whole_word -> whole words

	$s->{links}       = []; # Can contain 'and', 'or',
							# 'near',
							# undef defaults to AND

	$s->{cases}       = [];	# set for case-sensitive
	$s->{negates}     = [];	# set for NOT

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
		&{$self->{'global'}->{error_routine}}
			($self->{'global'}->{error_page},
			"$caller calling $name: accessed non-existent array $term.");
	}

	if(@fields) {
		@{$self->{$term}} = @fields;
	}
	else {
		@{$self->{$term}};
	}

}

sub debug {
	return unless $Vend::Search::DEBUG;
	my $s = shift;
	print @_;
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
		specs
		fields
		mods
		cases
		links 
		negates
		open_parens
		close_parens
	);
}

sub more_matches {
	my($self,$session,$next,$last,$mod) = @_;
	my $g = $self->{'global'};
	my @out;
	my $count = 0;
	my ($filemod,$first,$save);
	my $id = $session || $g->{session_id};
	$mod = defined $mod ? $mod : 1;
	$g->{search_mod} = $mod;
	$id = ref $id ? $$id : $id;
	$id .= ":$mod";
	
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
# DEBUG
#Vend::Util::logDebug
#("Got to return_fields default")
#	if ::debug(0x10);
# END DEBUG
		$return_sub = sub { substr($_[0], 0, index($_[0], $g->{index_delim})) };
	}
	elsif ( ref($g->{return_fields}) =~ /^HASH/ ) {
# DEBUG
#Vend::Util::logDebug
#("Got to return_fields HASH")
#	if ::debug(0x10);
# END DEBUG
		$return_sub = sub {
			my($line) = @_;
			my($key,$val);
			my(@return);
			my(%strings) = %{$g->{return_fields}};
			while ( ($key,$val) = each %strings) {
				$val = '\s' unless $val ||= 0;
				1 while $line =~ s/($key)\s*(\S.*?)($val)/push(@return, $2)/ge;
			}
			return undef unless @return;
			join $g->{index_delim}, @return;
		};
	}
	elsif ( ref($g->{return_fields}) =~ /^ARRAY/ ) {
# DEBUG
#Vend::Util::logDebug
#("Got to return_fields ARRAY")
#	if ::debug(0x10);
# END DEBUG
# DEBUG
#Vend::Util::logDebug
#("ret: '$g->{return_delim}' ind: '$g->{index_delim}'")
#	if ::debug(0x10);
# END DEBUG
		$return_sub = sub {
			chomp($_[0]);
			return join $g->{return_delim},
						(split /\Q$g->{index_delim}/, $_[0])[@{$g->{return_fields}}];
		};
	}
	elsif( $g->{return_fields} ) {
# DEBUG
#Vend::Util::logDebug
#("Got to return_fields SCALAR")
#	if ::debug(0x10);
# END DEBUG
		$return_sub = sub { substr($_[0], 0, index($_[0], $g->{return_fields})) };
	}
	else {
# DEBUG
#Vend::Util::logDebug
#("Got to return_fields ALL")
#	if ::debug(0x10);
# END DEBUG
		$return_sub = sub { @_ };
	}

}


# Returns a screening function based on the search specification.
# The $f is a reference to previously created search function which does
# a pattern match on the line.
sub get_limit {
	my($s, $f) = @_;
	my $g = $s->{'global'};
	my ($code,$limit_sub);
	my $range_code = '';

	if ( ref $g->{range_look} )  {
		$range_code = <<'EOF';
return undef unless $s->range_check($g->{index_delim},$_[0]);
EOF
	}

	if ( $g->{coordinate} )
	{
		 $code .= <<'EOF';
sub {
	my @fields = (split /\Q$g->{index_delim}/, $_[0])[@{$s->{'fields'}}];
EOF
		my @specs = @{$s->{'specs'}};
		my @cases = ref $g->{case_sensitive}
						?	@{$g->{case_sensitive}}
						:	($g->{case_sensitive}) x scalar @specs;
		my @bounds = ref $g->{substring_match}
						?	@{$g->{substring_match}}
						:	($g->{substring_match}) x scalar @specs;
		my @negates = ref $g->{negate}
						?	@{$g->{negate}}
						:	($g->{negate}) x scalar @specs;
		my ($i, $start, $term);
		for($i = 0; $i < scalar @specs; $i++) {
			if($negates[$i]) {
				$start = '!~ m{';
			}
			else {
				$start = '=~ m{';
			}
			if($bounds[$i]) {
				$term = '}';
			}
			else {
				$term = '\b}';
				$start .= '\b';
			}
			$term .= 'i' unless $cases[$i];

			 $code .= <<EOF;
		return undef unless \$fields[$i] $start$specs[$i]$term;
EOF
		}
		$code .= <<EOF;
$range_code
return 1;
}
EOF
	}
	elsif ( @{$s->{'fields'}} )  {
		 $code = <<'EOF';
sub {
	my $line = $_[0];
EOF
		 $code .= $range_code;
		 $code .= <<'EOF';
	my @fields = (split /\Q$g->{index_delim}/, $_[0])[@{$s->{'fields'}}];
	my $field = join $g->{index_delim}, @fields;
	$_ = $field;
	return($_ = $line) if &$f();
	return undef;
}
EOF
	} 
	# In case range_look only
	elsif ($g->{range_look})  {
		$code = <<EOF;
sub {
	$range_code
	return 1;
}
EOF
	}
	# If there is to be no limit_sub
	else {
		return undef;
	}
	$limit_sub = eval $code;
	die "Bad code: $@" if $@;
	return $limit_sub;
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
#Vend::Util::logDebug
#("range_look: '" . join("','", @fields) . "'\n")
#	if ::debug(0x10);
#Vend::Util::logDebug
#("range_min:  '" . join("','", @{$g->{range_min}}) . "'\n")
#	if ::debug(0x10);
#Vend::Util::logDebug
#("range_max:  '" . join("','", @{$g->{range_max}}) . "'\n")
#	if ::debug(0x10);
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
	shift(@_);	# Toss the object reference

	my ($case, $bound, $negate);

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
	$code .= <<EOCODE;
    return 0 unless $negate m{$bound$pat$bound}$case;
EOCODE
    } 

    $code .= "}\n";

    my $func = eval $code;
    die "bad pattern: $@" if $@;

    return $func;
} 

sub create_search_or {
	shift(@_);	# Toss the object reference

	my ($case)  = shift(@_) ? '' : 'i';
	my ($bound) = shift(@_) ? '' : '\b';
	my ($negate) = shift(@_) ? '$_ !~ ' : '';

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
    return 1 if $negate m{$bound$pat$bound}$case;
EOCODE
    } 

    $code .= "}\n";

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
	my ($crippled, $i);
	
	return '' unless ref $g->{sort_field};

	my $sort_string = $g->{sort_command};
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
	$id .=  ':' . $g->{search_mod};
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
		my $id = $g->{session_id} . ':' . $g->{search_mod};
		$g->{save_hash}->{$id} = join "\n", @$out;
	}
	else {
		$g->{matches} = $g->{match_limit};
		$g->{next_pointer} = 0;
		return undef;
	}
	1;
}

sub quoted_string {

my ($s, $text) = @_;
my (@fields);
push(@fields, $+) while $text =~ m{
   "([^\"\\]*(?:\\.[^\"\\]*)*)"\s?  ## standard quoted string, w/ possible comma
   | ([^\s]+)\s?                    ## anything else, w/ possible comma
   | \s+                            ## any whitespace
	    }gx;
	@fields;
}

1;

__END__
