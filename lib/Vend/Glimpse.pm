# Vend/Glimpse.pm:  Search indexes with Glimpse
#
# $Id: Glimpse.pm,v 2.5 1996/12/16 08:53:44 mike Exp $
#
# ADAPTED FOR USE WITH MINIVEND from Search::Glimpse
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
##  vi regex to delete debugs     %s/^\(.*$s->debug\)/#\1/
##  vi regex to restore debugs     %s/^\([^#]*\)#\(.*$s->debug\)/\1\2/
#

package Vend::Glimpse;
require Vend::Search;
@ISA = qw(Vend::Search);

$VERSION = substr(q$Revision: 2.5 $, 10);
use Text::ParseWords;
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

	$s->{global}->{base_directory} = $Vend::Cfg->{'ProductDir'};
	$s->{global}->{glimpse_cmd} = $Vend::Cfg->{'Glimpse'} || 'glimpse';
	$s->{global}->{min_string} = 4;
	$s->{global}->{search_file} = '';
	$s->{global}->{search_server} = undef;
	$s->{global}->{search_port} = undef;

}

sub version {
	$Vend::Glimpse::VERSION;
}

sub quoted_string {

my ($s, $text) = @_;
my (@fields);
push(@fields, $+) while $text =~ m{
   "([^\"\\]*(?:\\.[^\"\\]*)*)"\s?  ## standard quoted string, w/ possible comma
   | ([^\s]+)\s?                    ## anything else, w/ possible comma
   | \s+                            ## any whitespace
	    }gx;
   return grep /\w/, @fields;
}

sub escape {
	my($self, @text) = @_;
	if($self->{'global'}->{all_chars}) {
			@text = grep quotemeta $_, @text;
	}
	for(@text) {
		s!([';])!.!g;
	}
	return @text;
}

sub search {

    my($s,%options) = @_;
	my $g = $s->{global};
	my($delim,$string);
	my($max_matches,$mod,$index_delim,$return_delim);
	my($cmd,$code,$count,$joiner,$matches_to_send,@out);
	my($limit_sub,$return_sub);
	my($f,$key,$spec,$val,$range_op);
	my($searchfile,@searchfiles);
	my(@pats);
	my(@specs);
	my(@cmd);
	while (($key,$val) = each %options) {
		$g->{$key} = $val;
	}
 	$index_delim = $g->{index_delim};
    $g->{return_delim} = $index_delim
	        unless defined $g->{return_delim};

#	$s->debug($s->dump_options());

	$g->{matches} = 0;
	$max_matches = $g->{max_matches};

	if(defined $g->{search_spec}) {
	  	@specs = $g->{search_spec};
	}
	else {
		@specs = @{$s->{specs}};
	}

	for(qw! case_sensitive substring_match !) {
		next unless ref $g->{$_};
		$g->{$_} = $g->{$_}->[0];
	}

	if(ref $g->{range_look}) {
		no strict 'refs';
        unless( scalar(@{$g->{range_look}}) == scalar(@{$g->{range_min}})    and
                scalar(@{$g->{range_look}}) == scalar(@{$g->{range_max}})    
                ) {
			&{$g->{error_routine}} ($g->{error_page},
					"Must have min and max values for range.");
			$g->{matches} = -1;
			return undef;
		}
		$range_op = 1;
	}

	@specs = '' if @specs == 0;

  CHECKFATAL: {
	my (@fatal_error) = ();
    if (!$g->{glimpse_cmd}) {
        push @fatal_error,
            "Attempt to search with glimpse, no glimpse configured.";
    }
    if ($g->{return_all}) {
        push @fatal_error,
            "Cannot use return_all specification with Glimpse.";
	}
	last CHECKFATAL unless @fatal_error;

	unshift @fatal_error, "ERRORS in glimpse search:";
    &{$g->{log_routine}}(@fatal_error);
    &{$g->{error_routine}}($g->{error_page}, join "\n", @fatal_error);
	$g->{matches} = -1;
	return undef;

  } #end CHECKFATAL

    # Build glimpse line
    push @cmd, $g->{glimpse_cmd};
    unless (defined $g->{search_server}) {
    	push @cmd, "-H $g->{base_directory}";
	}
	else {
    	push @cmd, "-C $g->{search_server}";
		push (@cmd, "-K $g->{search_port}")
			if defined $g->{search_port} && $g->{search_port};
	}

    if ($g->{spelling_errors}) {
        $g->{spelling_errors} = int  $g->{spelling_errors};
        push @cmd, '-' . $g->{spelling_errors};
    }

    push @cmd, "-i" unless $g->{case_sensitive};
    push @cmd, "-h" unless $g->{return_file_name};
    push @cmd, "-y -L $max_matches:0:$max_matches";
    push(@cmd, "-F '$g->{search_file}'")
		if defined $g->{search_file} && $g->{search_file};

	push(@cmd, '-w') unless $g->{substring_match};
	push(@cmd, '-O -X') if $g->{return_file_name};
	
	# Calls and returns sort string based on
	# sort_field and sort_options settings
	my $sort_string = $s->find_sort();

	if(! defined $g->{record_delim}) { 
		push @cmd, "-d 'NeVAiRbE'";
	}
	elsif ($g->{record_delim} eq "\n") { } #intentionally empty 
	elsif ($g->{record_delim} =~ /^\n+(.*)/) {
		#This doesn't handle two newlines, unfortunately
		push @cmd, "-d '^$1'";
	}
	elsif (! $g->{record_delim}) { 
		push @cmd, q|-d '$$'|;
	}
	else {
		# Should we modify it? Yes, to give indication that
		# it was done
		&{$g->{log_routine}}
			("Vend::Glimpse: escaped single quote in record_delim, value changed.\n")
			if $g->{record_delim} =~ s/'/\\'/g; 
		push @cmd, "-d '$g->{record_delim}'";
	}

	$g->{coordinate} = '';

    if (! $g->{exact_match}) {
        @specs = $s->quoted_string( join ' ', @specs);
    }

    @specs = $s->escape(@specs);

#    $s->debug("spec='" . (join "','", @specs) . "'");

    # untaint
    for(@specs) {
        /(.*)/;
        push @pats, $1;
    }
	@{$s->{'specs'}} = @specs;

#    $s->debug("pats: '", join("', '", @pats), "'");

#	$s->debug($s->dump_options());

  CREATE_LIMIT: {
  	last CREATE_LIMIT unless scalar @{$s->{'fields'}};
  	last CREATE_LIMIT if $g->{'coordinate'};
	if ($g->{or_search}) {
		$joiner = ',';
		eval {$f = $s->create_search_or(	$g->{case_sensitive},
											$g->{substring_match}, '',
											@pats);
						};
	}
	else  {	
		$joiner = ';';
		eval {$f = $s->create_search_and(	$g->{case_sensitive},
											$g->{substring_match}, '',
											@pats);
						};
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
  } # last CREATE_LIMIT:

	$spec = join $joiner, @pats;
    push @cmd, "'$spec'";
#	$s->debug("spec: '", $spec, "'");

	$joiner = $spec;
	$joiner =~ s/['";,]//g;
#	$s->debug("joiner: '", $spec, "'");
	if(length($joiner) < $g->{min_string}) {
		my $msg = <<EOF;
Search strings must be at least $g->{min_string} characters.
You had '$joiner' as the operative characters  of your search strings.
EOF
		&{$g->{error_routine}}($g->{error_page}, $msg);
		$g->{matches} = -1;
		return undef;
	}

    $cmd = join ' ', @cmd;

#	$s->debug("Glimpse command line: $cmd");

    # searches for debug

    if (!open(Vend::Glimpse::SEARCH,qq!$cmd |$sort_string !)) {
		$g->{matches} = -1;
        &{$g->{log_routine}}("Can't fork glimpse: $!\n");
        &{$g->{error_routine}}($g->{error_page},
								'Search command could not be run.');
        close Vend::Glimpse::SEARCH;
        return;
    }

	$g->{overflow} = 0;


	if($g->{return_file_name}) {
#		$s->debug("Got to return_fields FILENAME");
		$return_sub = sub {@_};
	}
	else {
		eval {$return_sub = $s->get_return()};
		if($@) {
			&{$g->{error_routine}}($g->{error_page}, $@);
			$g->{matches} = -1;
			return undef;
		}
	}

#	$s->debug('fields/specs: ', scalar @{$s->{fields}}, " ", scalar @{$s->{specs}});

	local($/) = $g->{record_delim};

	if(defined $limit_sub and $g->{return_file_name}) {
		&{$g->{log_routine}}
			("Vend::Glimpse.pm: non-fatal error\n" .
			"Can't field-limit matches in return_file_name mode. Ignoring.\n");
		undef $limit_sub;
	}

	if(defined $limit_sub) {
		while(<Vend::Glimpse::SEARCH>) {
			next unless &$limit_sub($_);
			push @out, &$return_sub($_);
		}
	}
	else {
		while(<Vend::Glimpse::SEARCH>) {
			push @out, &$return_sub($_);
		}
	}
	close Vend::Glimpse::SEARCH;
	if($?) {
		&{$g->{error_routine}}
			($g->{error_page},"glimpse returned error $?: $!");
		$g->{matches} = -1;
		return undef;
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

1;

__END__
