# Glimpse.pm:  Search indexes with Glimpse
#
# $Id: Glimpse.pm,v 1.1 1996/03/21 04:07:18 mike Exp mike $

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

package Vend::Glimpse;
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

	$s->{global}->{base_directory} = $Config::ProductDir;
	$s->{global}->{cmd} = $Config::Glimpse || 'glimpse';
	$s->{global}->{error_page} = 'badsearch';
	$s->{global}->{error_routine} = \&main::display_special_page;
	$s->{global}->{index_delim} = "\t";
	$s->{global}->{log_routine} = \&main::logError;
	$s->{global}->{match_limit} = 50;
	$s->{global}->{max_matches} = 2000;
	$s->{global}->{min_string} = 4;
	$s->{global}->{next_pointer} = 0;
	$s->{global}->{save_file} = '';
	$s->{global}->{search_history} = [];
	$s->{global}->{spelling_errors} = 0;

}

sub version {
	$Vend::Glimpse::VERSION;
}

sub search {

    my($s,%options) = @_;
	my($delim,$string,$cmd,@cmd);
	my($max_matches,$case,$mod,$link,$spec);
	my($count,$code,$matches_to_send,@out);
	my($g) = $s->{global};
	my($key,$val);

	$mod = $options{mod} || 1;

	while (($key,$val) = each %options) {
		$g->{$key} = $val;
	}


    if (!$g->{cmd}) {
		&{$g->{log_routine}}
			("Attempt to search with glimpse, no glimpse configured.\n");
		&{$g->{error_routine}}($g->{error_page},
			"Attempt to search with glimpse, no glimpse present.\n");
		return;
    }

	$g->{matches} = 0;

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

	if (${$s->{mods}}[0] =~ /\bor\b/i ) {
			$delim = ',';
	}
	else  {	$delim = ';' }

	$spec = join ' ', @{$s->{specs}};

	$spec =~ s/[^\d\w\s\*]//g;
	$spec =~ tr[*][#];
	$spec =~ /(.*)/;
	$spec = $1;

	$spec =~ s/\s+/$delim/ge;
	if(length($spec) < $g->{min_string}) {
		my $msg = <<EOF;
Assembled search strings must be at least $g->{min_string} characters.
You had: $spec
EOF
		&{$g->{error_routine}}($g->{error_page}, $msg);
		return undef;
	}
		

	$max_matches = int($g->{max_matches});

	# Build glimpse line
	push @cmd, $g->{cmd};
	(push @cmd, "-H $g->{base_directory}")
		unless $cmd[0] =~ /\s-C\b/;

	unless (${$s->{cases}}[0]) { push @cmd, '-i' }

	if ($g->{spelling_errors}) { 
		$g->{spelling_errors} = int  $g->{spelling_errors};
		push @cmd, '-' . $g->{spelling_errors};
	}

	push @cmd, "-y -h -L $max_matches:0:$max_matches";
	push @cmd, "'$spec'";
	
	$cmd = join ' ', @cmd;

	# Uncomment this to log searches for debug
	# &{$g->{log_routine}} ("Glimpse command line:\n$cmd\n");

    if (!open(Vend::Glimpse::SEARCH,qq!$cmd | !)) {
		&{$g->{log_routine}}("Can't fork Glimpse: $!\n");
		&{$g->{error_routine}}('badsearch', 'Search command could not be run.');
    	close Vend::Glimpse::SEARCH;
		return;
    }

	$g->{overflow} = 0;
 	my $index_delim = $g->{index_delim};

	while(<Vend::Glimpse::SEARCH>) {
		push @out, substr($_, 0, index($_, $index_delim));
	}
    close Vend::Glimpse::SEARCH;

	$g->{matches} = scalar(@out) || 0;
	$g->{first_match} = 0;

	if ($g->{matches} > $g->{match_limit}) {
		$matches_to_send = $g->{match_limit};
		my $file;
		$g->{overflow} = 1;
		$g->{next_pointer} = $g->{match_limit};
		if($file = $g->{save_file}) {
			open(Vend::Search::MATCHES, ">$file") ||
				croak "Couldn't write $file: $!\n";
			print Vend::Search::MATCHES "$mod\n";
			print Vend::Search::MATCHES join "\n", @out;
			close Vend::Search::MATCHES;
		}
		elsif(ref $g->{save_hash}) {
			my $id = $g->{session_id} . ':' . $g->{mod};
			$g->{save_hash}->{$id} = join "\n", @out;
		}
	}
	else {
		$matches_to_send = $g->{matches};
		$g->{next_pointer} = 0;
	}

	@out[0..($matches_to_send - 1)]
}

1;
__END__
