# Vend/Glimpse.pm:  Search indexes with Glimpse
#
# $Id: Glimpse.pm,v 1.5 1996/05/18 20:02:39 mike Exp mike $
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

package Vend::Glimpse;
require Vend::Search;
@ISA = qw(Vend::Search);

$VERSION = substr(q$Revision: 1.5 $, 10);
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

	# This line is a DOS/NT/MAC portability problem
	$s->{global}->{base_directory} = $Config::ProductDir;
	$s->{global}->{glimpse_cmd} = $Config::Glimpse || 'glimpse';
	$s->{global}->{min_string} = 4;
	$s->{global}->{search_server} = undef;
	$s->{global}->{search_port} = undef;

}

sub version {
	$Vend::Glimpse::VERSION;
}

sub search {

    my($s,%options) = @_;
	my $g = $s->{global};
	my($delim,$string);
	my($max_matches,$mod,$index_delim,$return_delim);
	my($cmd,$code,$count,$joiner,$matches_to_send,@out);
	my($limit_sub,$return_sub);
	my($f,$key,$spec,$val);
	my($searchfile,@searchfiles);
	my(@pats);
	my(@specs);
	my(@cmd);
	while (($key,$val) = each %options) {
		$g->{$key} = $val;
	}
 	$index_delim = $g->{index_delim};
	$return_delim = defined $g->{return_delim}
						? $g->{return_delim}
						: $index_delim;

	$g->{matches} = 0;
	$max_matches = $g->{max_matches};

	if(defined $g->{search_spec}) {
	  	@specs = $g->{search_spec};
	}
	else {
		@specs = @{$s->{specs}};
	}

    if (!$g->{glimpse_cmd}) {
        &{$g->{log_routine}}
            ("Attempt to search with glimpse, no glimpse configured.\n");
		$g->{matches} = -1;
        &{$g->{error_routine}}($g->{error_page},
            "Attempt to search with glimpse, no glimpse present.\n");
        return undef; # if it makes it to here
    }

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
	push(@cmd, '-l') if $g->{return_file_name};
	
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

	if($g->{exact_match}) {
		for(@specs) {
			s/"//g;
			$_ = '"' . $_ . '"';
		}
	}

	$spec = join ' ', @specs;

	if ($g->{or_search}) {
		$joiner = ',';
	}
	else  {	
		$joiner = ';';
	}

	$spec =~ s/[^"$\d\w\s*]//g;
	$spec =~ /(.*)/;
	$spec = $1;
	@pats = shellwords($spec);
	$s->debug("pats: '", join("', '", @pats), "'");
	$spec = join $joiner, @pats;
    push @cmd, "'$spec'";
	$s->debug("spec: '", $spec, "'");

	$joiner = $spec;
	$joiner =~ s/['";,]//g;
	$s->debug("joiner: '", $spec, "'");
	if(length($joiner) < $g->{min_string}) {
		$g->{matches} = -1;
		my $msg = <<EOF;
Search strings must be at least $g->{min_string} characters.
You had '$joiner' as the operative characters  of your search strings.
EOF
		&{$g->{error_routine}}($g->{error_page}, $msg);
		return undef;
	}

    $cmd = join ' ', @cmd;

    # searches for debug

    if (!open(Vend::Glimpse::SEARCH,qq!$cmd | !)) {
		$g->{matches} = -1;
        &{$g->{log_routine}}("Can't fork glimpse: $!\n");
        &{$g->{error_routine}}($g->{error_page},
								'Search command could not be run.');
        close Vend::Glimpse::SEARCH;
        return;
    }

	$g->{overflow} = 0;

	if($g->{return_file_name}) {
		$s->debug("Got to return_fields FILENAME");
		$return_sub = sub {@_};
	}
	elsif(!defined $g->{return_fields}) {
		$s->debug("Got to return_fields DEFAULT");
		$return_sub = sub { substr($_[0], 0, index($_[0], $index_delim)) };
	}
	elsif ( ref($g->{return_fields}) =~ /^ARRAY/ ) {
		$s->debug("Got to return_fields ARRAY");
		my @fields = @{$g->{return_fields}};
		$return_sub = sub {
			my $line = join $return_delim,
						(split /$index_delim/, $_[0])[@fields];
			$line;
		};
	}
	elsif ( ref($g->{return_fields}) =~ /^HASH/ ) {
		$s->debug("Got to return_fields HASH");
		$return_sub = sub {
			my($line) = @_;
			my(@return);
			my(%strings) = %{$g->{return_fields}};
			while ( ($key,$val) = each %strings) {
				print "key: '$key' val: '$val'";
				$val = '\s' unless $val ||= 0;
				1 while $line =~ s/($key)\s*(\S.*?)($val)/push(@return, $2)/ge;
			}
			return undef unless @return;
			join $index_delim, @return;
		};
	}
	elsif( $return_delim = $g->{return_fields} ) {
		$s->debug("Got to return_fields TRIM");
		$return_sub = sub { substr($_[0], 0, index($_[0], $return_delim)) };
	}
	else {
		$s->debug("Got to return_fields ALL");
		$return_sub = sub { @_ };
	}

	$s->debug('fields/specs: ', scalar @{$s->{fields}}, " ", scalar @{$s->{specs}});

	if ( scalar @{$s->{fields}} == scalar @{$s->{specs}} and 
		 $g->{coordinate} 			)  {
		$limit_sub = sub {
			my ($line) = @_;
			my @fields = (split /$index_delim/, $line)[@{$s->{fields}}];
			my @specs = @{$s->{specs}};
			my $i;
			if($g->{case_sensitive}) {
				for($i = 0; $i < scalar @fields; $i++) {
					return undef unless $fields[$i] =~ /$specs[$i]/;
				}
			}
			else { 
				for($i = 0; $i < scalar @fields; $i++) {
					return undef unless $fields[$i] =~ /$specs[$i]/i;
				}
			}
			1;
		};
	}
	elsif ( @{$s->{fields}} )  {
		unless ($g->{or_search}) {
			eval {$f = $s->create_search_and(	$g->{case_sensitive},
											$g->{substring_match},
											@pats);
						};
		}
		else	{
			eval {$f = $s->create_search_or(	$g->{case_sensitive},
											$g->{substring_match},
											@pats);
						};
		}
		if($@) {
			$g->{matches} = -1;
			&{$g->{error_routine}}($g->{error_page}, $@);
			return undef;
		}
		$limit_sub = sub {
			my ($line) = @_;
			my @fields = (split /$index_delim/, $line)[@{$s->{fields}}];
			my $field = join $index_delim, @fields;
			$_ = $field;
			return ($_ = $line) if &$f();
			return undef;
		};
	}

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
		return undef;
	}

	$g->{matches} = scalar(@out);
	$g->{first_match} = 0;

	if ($g->{matches} > $g->{match_limit}) {
		$matches_to_send = $g->{match_limit};
		my $file;
		my $id = $g->{session_id} . ':' . $g->{search_mod};
		$g->{overflow} = 1;
		$g->{next_pointer} = $g->{match_limit};
		my $save = $s->save_context( @{$g->{'save_context'}} )
				if defined $g->{save_context};
		if($file = $g->{save_dir}) {
			$file .= '/' . $id;

			if(open(Vend::Glimpse::MATCHES, ">$file")) {
				(print Vend::Glimpse::MATCHES "~$id $save\n")
					if defined $save;
				chomp(@out);
				print Vend::Glimpse::MATCHES join "\n", @out;
				close Vend::Glimpse::MATCHES;
			}
			else {
				&{$g->{log_routine}}("search: Couldn't write $file: $!\n");
			}
		}
		elsif(ref $g->{save_hash}) {
			$g->{save_hash}->{"~$id"} = $save
					if defined $save;
			my $id = $g->{session_id} . ':' . $g->{search_mod};
			$g->{save_hash}->{$id} = join "\n", @out;
		}
	}
	else {
		$matches_to_send = $g->{matches};
		$g->{next_pointer} = 0;
	}

	$s->debug($g->{matches}, " matches");
	$s->debug("0 .. ", ($matches_to_send - 1));
	$s->save_history() if $g->{history};

	@out[0..($matches_to_send - 1)];
}

1;
__END__
