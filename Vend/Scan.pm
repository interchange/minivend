# Vend/Scan.pm:  Prepare searches for MiniVend
#
# $Id: Scan.pm,v 1.1 1996/05/26 17:08:57 mikeh Exp mikeh $
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

package Vend::Scan;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(perform_search find_search_params);

$VERSION = substr(q$Revision: 1.1 $, 10);

use strict;
use Vend::Util;
use Vend::Interpolate;
use Vend::Data qw(product_code_exists column_exists);

my @Order = ( qw(
					mv_dict_look
					mv_searchspec
					mv_profile
					mv_base_directory
					mv_case
					mv_coordinate
					mv_dict_end
					mv_dict_fold
					mv_dict_limit
					mv_dict_order
					mv_exact_match
					mv_head_skip
					mv_index_delim
					mv_matchlimit
					mv_min_string
					mv_max_matches
					mv_orsearch
					mv_record_delim
					mv_return_delim
					mv_return_fields
					mv_return_file_name
					mv_substring_match
					mv_return_spec
					mv_spelling_errors
					mv_search_field
					mv_search_file
					mv_search_page
					mv_searchtype

));

my %Map = ( qw(
					mv_base_directory	base_directory
					mv_case				case_sensitive
					mv_coordinate		coordinate
					mv_dict_end			dict_end
					mv_dict_fold		dict_fold
					mv_dict_look		dict_look
					mv_dict_limit		dict_limit
					mv_dict_order		dict_order
					mv_exact_match		exact_match
					mv_head_skip		head_skip
					mv_index_delim		index_delim
					mv_matchlimit		match_limit
					mv_min_string		min_string
					mv_max_matches		max_matches
					mv_orsearch			or_search
					mv_profile			mv_profile
					mv_return_spec		mv_return_spec
					mv_record_delim		record_delim
					mv_return_delim		return_delim
					mv_return_fields	return_fields
					mv_search_field		search_field
					mv_search_file		search_file
					mv_search_page		search_page
					mv_searchtype		search_type
					mv_spelling_errors	spelling_errors
					mv_searchspec		search_spec
					mv_substring_match	substring_match

) );

my %Scan = ( qw(
					dl	mv_dict_look
					de	mv_dict_end
					se  mv_searchspec
					rf  mv_return_fields
					ml  mv_matchlimit
					mp  mv_profile
					sf  mv_search_field
					sp  mv_search_page
					cs  mv_case
					su  mv_substring_match
					fi  mv_search_file
					st  mv_searchtype
					bd	mv_base_directory

				) );

my %Parse = (

	case_sensitive		=>	\&_yes,
	coordinate          =>	\&_yes,
	head_skip           =>	\&_number,
	match_limit         =>	sub { $_[1] =~ /(\d+)/ ? $1 : 50 },
	max_matches         =>	sub { $_[1] =~ /(\d+)/ ? $1 : 2000 },
	min_string          =>	sub { $_[1] =~ /(\d+)/ ? $1 : 1 },
	dict_limit			=>	\&_dict_limit,
	exact_match			=>	\&_yes,
	mv_profile          =>	\&parse_profile,
	or_search           =>  \&_yes,
	return_fields       =>	\&_array,
	search_spec       	=>	\&_scalar_or_array,
	return_fields       =>	\&_array,
	return_file_name    =>	\&_yes,
	save_context        =>	\&_array,
	search_field		=>	\&_column,
	search_file         => 	\&_scalar_or_array,
	spelling_errors     => 	sub { my $n = int($_[1]); $n < 8 ? $n : 1; },
	substring_match		=>	\&_yes,

);

sub find_search_params {
	my($c,$param) = @_;
	my(@args) = split "/", $param;
	my($var,$val);
	for(@args) {
		($var,$val) = split /=/, $_, 2;
		$val =~ s!::!/!g;
		$c->{$Scan{$var}} = $val
			if defined $Scan{$var};
	}
	1;
}

sub parse_profile {
	my($ref,$profile) = @_;
	return undef unless defined $profile;
    my($codere) = '[\w-_#/.]+';
	my($params) = $Config::SearchProfile[$profile];
	return undef unless $params;
	$params =~ s#\[if\s+([^\]]+)\]([\s\S]*?)\[/if\]#
                  	tag_if($1,$2)#ige;
	my($var,$val);
	my $status = $profile;
	my(@param) = split /\n+/, $params;
	for(@param) {
		s/^\s+//;
		s/\s+$//;
		($var,$val) = split /[\s=]+/, $_, 2;
		$status = -1 if $var eq 'mv_last';
		next unless defined $Map{$var};
		$var = $Map{$var};
		$val =~ s/&#(\d+);/chr($1)/ge;
		$val = &{$Parse{$var}}($ref,$val)
				if defined $Parse{$var};
		$ref->{$var} = $val
			if defined $val;
	}
	return $status;
}


# Search for an item with glimpse or text engine
sub perform_search {
	my($c,$more_matches) = @_;
	my($next,$last,$chunk,$mod) = split(/:/,$more_matches);
	my($v) = $Vend::Session->{'values'};
    my($param);
	my(@fields);
	my(@specs);
	my(@out);
	my ($p, $q, $matches);

	unless (defined $v->{'mv_search_over_msg'}) {
		$v->{'mv_search_over_msg'} =
			$Config::SearchOverMsg;
	}

	my %options = (
			session_id => $Vend::SessionID,
			search_mod => ++$Vend::Session->{pageCount},
			);

	if(defined %Vend::Cache) {
		$options{'save_hash'} = \%Vend::Cache;
	}
	else {
		$options{'save_dir'} = $Config::ScratchDir;
	}

	foreach $param (@Order) {
		$p = $Map{$param};
		next unless defined ($c->{$param});
		$options{$p} = $c->{$param};
		$options{$p} =
			&{$Parse{$p}}(\%options, $options{$p})
				if defined $Parse{$p};
		last if $options{$p} == -1 and $p eq 'mv_profile';
		delete $options{$p} unless defined $options{$p};
	}


 	$options{'search_type'} = 'text'
		unless ($Config::Glimpse);

	unless(defined $options{'search_file'}) {
		if ($Config::Delimiter eq 'CSV') {
			$options{'index_delim'} = ',';
		}
		elsif ($Config::Delimiter ne "\t") {
			$options{'index_delim'} = $Config::Delimiter;
		}
	}

    if (defined $options{'search_page'}) {
		$options{'save_context'} = [ 'search_page', 'search_spec', 'dict_look' ];
	}

  SEARCH: {
	unless($more_matches) {

		$options{'search_spec'} = $options{'dict_look'} 
			unless defined $options{'search_spec'};

		if(ref $options{'search_spec'}) {
			@specs = @{$options{'search_spec'}};
			delete $options{'search_spec'};
		}

		if ($options{'search_type'} =~ /glimpse/){
			 		$q = new Vend::Glimpse %options;
		}
		else	{ 	$q = new Vend::TextSearch %options }

		@specs = ($options{'search_spec'}) 
			unless defined @specs;

		if(defined $options{mv_return_spec}) {
			$q->global('matches', 1) 
				if product_code_exists($specs[0]);
			@out = $specs[0];
			last SEARCH;
		}

		delete $options{'search_type'};

		$q->fields(@{$options{'search_field'}}) 
			if defined $options{'search_field'} ;
		$q->specs(@specs);

		@out = $q->search();
	}
	else {
		$options{'match_limit'} = $chunk;
		$q = new Vend::TextSearch %options;
		@out = $q->more_matches($next,$last,$mod);
	}
  } # last SEARCH

	$matches = $q->global('matches');

	if ( $matches > 0 ) {
	 	$v->{'mv_search_match_count'} = $matches;
		$v->{'mv_searchspec'} = $c->{'mv_searchspec'} 
							  || $c->{'mv_dict_look'};
		$v->{'mv_dict_look'} = $c->{'mv_dict_look'}
							  || $q->global('dict_look');
	}
	elsif ($matches == 0) {
		my $msg = join " ", $q->specs();
		::display_special_page($Config::Special{'nomatch'}, $msg);
		return;
	}
	else {
		# Got an error handled by search module
		return;
	}

	if($Config::Delimiter ne "\t") {
		for(@out) { s/^"//; s/[",|].*$//; }
	}

	undef $v->{'mv_search_over_msg'}
    			 unless $q->global('overflow');

	search_page($q,\@out);

}

sub _column {
	return undef unless defined $_[1];
	my @fields = split /\s*[,\0]\s*/, $_[1];
	my $col;
	for(@fields) {
		($_ = column_exists($_) + 1)
			unless /^\d+$/;
	}
	\@fields;
}

sub _array {
	return undef unless defined $_[1];
	[split /\s*[,\0]\s*/, $_[1]]
}

sub _yes {
	return( defined($_[1]) && ($_[1] =~ /^[yYtT1]/));

}
sub _number {
	defined $_[1] ? $_[1] : 0;
}

sub _scalar {
	defined $_[1] ? $_[1] : '';
}

sub _scalar_or_array {
	my(@fields) = split /\s*[,\0]\s*/, $_[1];
	scalar @fields > 1 ? [@fields] : $fields[0];
}

sub _dict_limit {
	my ($ref,$limit) = @_;
	return undef unless	defined $ref->{dict_look};
    $ref->{'dict_end'} = $ref->{'dict_look'};
    substr($ref->{'dict_end'},$limit,1) =~ s/(.)/chr(ord($1) + 1)/e;
	1;
}
         
