# Vend/Scan.pm:  Prepare searches for MiniVend
#
# $Id: Scan.pm,v 1.18 1997/11/08 17:34:49 mike Exp mike $
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
@EXPORT = qw(
			check_scan_cache
			check_search_cache
			find_search_params
			perform_search
			);

$VERSION = substr(q$Revision: 1.18 $, 10);

use strict;
use Vend::Util;
use Vend::Interpolate;
use Vend::Data qw(product_code_exists_ref column_exists);

my @Sql = ( qw(
					mv_searchspec
					mv_search_file
					mv_sql_query
					mv_range_look
					mv_cache_key
					mv_matchlimit
					mv_orsearch
					mv_list_only
					mv_range_min
					mv_range_max
					mv_numeric
					mv_return_fields
					mv_substring_match
					mv_search_field
					mv_search_page
					mv_sort_field
					mv_sort_option

));

my @Order = ( qw(
					mv_dict_look
					mv_searchspec
					mv_search_file
					mv_base_directory
					mv_field_names
					mv_range_look
					mv_cache_key
					mv_profile
					mv_case
					mv_negate
					mv_coordinate
					mv_dict_end
					mv_dict_fold
					mv_dict_limit
					mv_dict_order
					mv_failpage
					mv_all_chars
					mv_return_all
					mv_exact_match
					mv_head_skip
					mv_index_delim
					mv_list_only
					mv_matchlimit
					mv_min_string
					mv_max_matches
					mv_orsearch
					mv_range_min
					mv_range_max
					mv_range_alpha
					mv_record_delim
					mv_return_delim
					mv_return_fields
					mv_return_file_name
					mv_substring_match
					mv_return_spec
					mv_spelling_errors
					mv_search_field
					mv_search_page
					mv_sort_field
					mv_sort_option
					mv_sort_command
					mv_sort_crippled
					mv_searchtype

));

my %Map = ( qw(
					mv_base_directory	base_directory
					mv_case				case_sensitive
					mv_coordinate		coordinate
					mv_cache_key        cache_key
					mv_dict_end			dict_end
					mv_dict_fold		dict_fold
					mv_dict_look		dict_look
					mv_dict_limit		dict_limit
					mv_dict_order		dict_order
					mv_failpage			error_page
					mv_exact_match		exact_match
					mv_field_names      field_names
					mv_all_chars		all_chars
					mv_return_all		return_all
					mv_head_skip		head_skip
					mv_index_delim		index_delim
					mv_list_only        list_only
					mv_matchlimit		match_limit
					mv_min_string		min_string
					mv_max_matches		max_matches
					mv_negate      		negate
					mv_orsearch			or_search
					mv_profile			mv_profile
					mv_range_look		range_look
					mv_range_min		range_min
					mv_range_max		range_max
					mv_range_alpha		range_alpha
					mv_return_spec		mv_return_spec
					mv_record_delim		record_delim
					mv_return_delim		return_delim
					mv_return_fields	return_fields
					mv_return_file_name	return_file_name
					mv_search_field		search_field
					mv_search_file		search_file
					mv_search_page		search_page
					mv_searchtype		search_type
					mv_sort_field		sort_field
					mv_sort_option		sort_option
					mv_sort_command		sort_command
					mv_sort_crippled	sort_crippled
					mv_spelling_errors	spelling_errors
					mv_sql_query     	sql_query
					mv_searchspec		search_spec
					mv_substring_match	substring_match

) );

my %Scan = ( qw(
                    ac  mv_all_chars
                    bd  mv_base_directory
                    co  mv_coordinate
                    cs  mv_case
                    de  mv_dict_end
                    df  mv_dict_fold
                    di  mv_dict_limit
                    dl  mv_dict_look
                    DL  mv_raw_dict_look
                    do  mv_dict_order
                    dr  mv_record_delim
                    em  mv_exact_match
                    er  mv_spelling_errors
                    fi  mv_search_file
                    fn  mv_field_names
                    hs  mv_head_skip
                    id  mv_index_delim
                    ml  mv_matchlimit
                    mm  mv_max_matches
                    sq  mv_sql_query
                    mp  mv_profile
                    ms  mv_min_string
                    ne  mv_negate
					nu  mv_numeric
                    os  mv_orsearch
                    ra  mv_return_all
                    rd  mv_return_delim
                    rf  mv_return_fields
                    rg  mv_range_alpha
                    rl  mv_range_look
                    rm  mv_range_min
                    rn  mv_return_file_name
                    rs  mv_return_spec
                    rx  mv_range_max
                    SE  mv_raw_searchspec
                    se  mv_searchspec
                    sf  mv_search_field
                    sp  mv_search_page
                    st  mv_searchtype
                    su  mv_substring_match
					tf	mv_sort_field
					to	mv_sort_option
					tc	mv_sort_command
					ty	mv_sort_crippled

				) );

my %Parse = (

	case_sensitive		=>	\&_yes_array,
	negate         		=>	\&_yes_array,
	coordinate          =>	\&_yes,
	head_skip           =>	\&_number,
	match_limit         =>	sub { $_[1] =~ /(\d+)/ ? $1 : 50 },
	max_matches         =>	sub { $_[1] =~ /(\d+)/ ? $1 : 2000 },
	min_string          =>	sub { $_[1] =~ /(\d+)/ ? $1 : 1 },
	dict_limit			=>	\&_dict_limit,
	exact_match			=>	\&_yes,
	mv_profile          =>	\&parse_profile,
	or_search           =>  \&_yes,
	return_fields       =>	\&_column,
	range_look	        =>	\&_column,
	range_min	        =>	\&_array,
	range_max	        =>	\&_array,
	range_alpha	        =>	\&_array,
	numeric				=>	\&_array,
	search_spec       	=>	\&_scalar_or_array,
	return_file_name    =>	\&_yes,
	all_chars		    =>	\&_yes,
	return_all		    =>	\&_yes,
	save_context        =>	\&_array,
	search_field		=>	\&_column,
	sort_command		=>	\&_command,
	sort_field			=>	\&_column,
	sort_option			=>	\&_array,
	sort_crippled		=>	\&_yes,
	search_file         => 	\&_scalar_or_array,
	field_names         =>	\&_array,
	spelling_errors     => 	sub { my $n = int($_[1]); $n < 8 ? $n : 1; },
	substring_match		=>	\&_yes_array,

);

sub check_scan_cache {
	return() unless $Vend::Cfg->{SearchCache};
	my($path) = @_;
	check_cache_key( generate_key($path) );
}

sub check_search_cache {
	return() unless $Vend::Cfg->{SearchCache};
	my($ref) = @_;
	return () unless defined $ref->{mv_cache_params};

	my(@params) = split /[\s,]+/, $ref->{mv_cache_params};
	for(@params) {
		$_ .= $ref->{$_};
	}

	check_cache_key( generate_key(@params) );

}

sub check_cache_key {
	my($key) = @_;
	
	my $page = readfile ($Vend::Cfg->{ScratchDir}.'/SearchCache/'.$key.'.html');

	return($key,undef) unless defined $page;
	return(undef,$page);
}

sub find_search_params {
	my($c,$param) = @_;
	my(@args) = split "/", $param;
	my($var,$val);
	for(@args) {
		($var,$val) = split /=/, $_, 2;
		$val =~ s!::!/!g;
		$val =~ s/%([A-Fa-f0-9][A-Fa-f0-9])/chr(hex($1))/ge;
		if ($var eq 'dl' || $var eq 'se') {
			$val =~ s/\.(..)/chr(hex($1))/ge;
			unless
			(defined $c->{$Scan{uc $var}})	{ $c->{$Scan{uc $var}} =  $val		}
			else   							{ $c->{$Scan{uc $var}} .= ".00$val" }
		}
		if (defined $Scan{$var}) {
			unless
			(defined $c->{$Scan{$var}})	{ $c->{$Scan{$var}} =  $val		}
			else   						{ $c->{$Scan{$var}} .= "\0$val"	}
		}
	}
	1;
}

my %Save;

sub parse_profile {
	my($ref,$profile) = @_;
	return undef unless defined $profile;
    my($codere) = '[\w-_#/.]+';
    unless($profile =~ /^\d+$/) {
        return undef
            unless defined $Vend::Cfg->{'SearchProfileName'}->{$profile};
        $profile = $Vend::Cfg->{'SearchProfileName'}->{$profile};
    }
	my($params) = $Vend::Cfg->{'SearchProfile'}->[$profile];
	return undef unless $params;
	if($params =~ /\[\[/) {
		$params = interpolate_html($params);
	}
	else {
		$params =~ s:\[value\s+($codere)\]:tag_value($1):igeo;
		$params =~ s#\[if\s+([^\]]+)\]([\s\S]*?)\[/if\]#
						tag_if($1,$2)#ige;
	}
	my($p, $var,$val);
	my $status = $profile;
	undef %Save;
	my(@param) = split /\n+/, $params;
	for(@param) {
		next unless /\S/;
		s/^\s+//;
		s/\s+$//;
		($p,$val) = split /[\s=]+/, $_, 2;
		$status = -1 if $p eq 'mv_last';
		next unless defined $Map{$p};
		$var = $Map{$p};
		$val =~ s/&#(\d+);/chr($1)/ge;
		$Save{$p} = $val;
		$val = &{$Parse{$var}}($ref,$val)
				if defined $Parse{$var};
		$ref->{$var} = $val if defined $val;
	}
	return $status;
}

sub do_more {
	my($c,$opt,$more) = @_;
	my($session,$next,$last,$chunk,$mod) = split(/:/,$more);
	$opt->{'match_limit'} = $chunk;
	my $q = new Vend::Search %{$opt};
	my $out = $q->more_matches($session,$next,$last,$mod);
	finish_up($c,$q,$out) or return 0;
   	return($q,$out);
}


sub sql_search {
	my($c,$options,$second) = @_;
	my ($out, $table, @fields);
	my ($i, $op, @out);
	my (@range);
	my (@range_min);
	my (@range_max);
	my (@numeric);

	unless(defined $second) {
		for( @Sql ) {
			$options->{$Map{$_}} = $c->{$_}
				if defined $c->{$_};
		}
	}
	else {
		for( @Sql ) {
			$options->{$Map{$_}} = $Save{$_};
		}
	}

	my @specs = split /\000/, $options->{search_spec};

    if (defined $options->{'search_page'} or $options->{session_key}) {
		$options->{'save_context'} = [	'session_key', 'search_page',
										'search_spec', 'dict_look' ];
	}

	@numeric	= _yes_array(split /[,\000]/, $options->{numeric});

	my(@tables) = split /[\s,\000]+/, ($options->{search_file} || 'products');

	my $db = Vend::Data::database_exists_ref($tables[0])
				or do {
					logError("non-existent database '$tables[0]'");
					return undef;
				};
	$db = $db->ref();

FORMULATE: {
	# See if we have the simple query. If sql_query is set,
	# then we will just do it by skipping the rest
	# of the parse. If fi=table is not set, we
	# will use 'products' and hope for the best.
	# 
	# We substitute search specs for ? if appropriate.
	#

	if($options->{sql_query}) {
		$i = 0;
		for(@specs) {
			$specs[$i] = "'$specs[$i]'" unless $numeric[$i];
			$options->{sql_query} =~ s/([\s=%])\?([\s%]|$)/$1$specs[$i]$2/;
			$i++;
		}
print("mv_sql_query: $options->{sql_query}\n") if $Global::DEBUG;
		$out = $db->array_query ($options->{sql_query},$tables[0])
					or return 0;
		last FORMULATE;
	}
	elsif($options->{range_look}) {
		@range			= split /[,\000]/, $options->{range_look};
		@range_min		= split /[,\000]/, $options->{range_min};
		@range_max		= split /[,\000]/, $options->{range_max};
	}

	if($options->{sort_field}) {
		$options->{sort_field} =~ s/[\0,\s]+/,/g;
	}

	if($options->{return_fields}) {
		$options->{return_fields} =~ s/[\0,\s]+/,/g;
	}
	else {
		$options->{return_fields} = 'code';
	}


	if($options->{return_fields} eq '*') {
		$options->{field_names} = $db->columns();
	}
	$options->{return_fields} =~ s/\b0\b/code/;

	if ($options->{search_field}) {
		@fields = split /[\0,\s]+/, $options->{search_field};
	}
	else {
		@fields = $db->columns();
	}

	my $query = "select $options->{return_fields} from ";
	$query .= join ",", @tables;


	$query .= " where ";

	my ($range,$val,$spec,$qb,$qe,@query);

	my $coord = scalar @specs <=> scalar @fields;

	my $joiner = ' AND ';

	$joiner = ' OR ' if _yes($options->{or_search});

	if($coord == 0) {
		$i = 0;
		$op = '=';
		$qb = $qe = "'";
		for (@specs) {

			if( _yes($options->{substring_match} and ! $numeric[$i]) ) {
					$op  = 'like';
					$qb = "'%";
					$qe = "%'";
			}

			push(@query, "$fields[$i] $op $qb$specs[$i]$qe");
			$i++;
		}
	}
	elsif ($coord == -1) {
		$joiner = ' OR ';
		$i = 0;
		for(@fields) {
			if( _yes($options->{substring_match} and ! $numeric[0]) ) {
					$op  = 'like';
					$qb = "'%";
					$qe = "%'";
			}
			push(@query, "$fields[$i] $op $qb$specs[0]$qe");
		}
	}
	else {
		$joiner = ' OR ';
		$i = 0;
		for(@specs) {
			if( _yes($options->{substring_match} and ! $numeric[$i]) ) {
				unless ($numeric[$i]) {
					$op  = 'like';
					$qb = "'%";
					$qe = "%'";
				}
			}
			push(@query, "$fields[0] $op $qb$specs[$i]$qe");
		}
	}



	$query .= join $joiner, @query;

	@query = ();

	$i = 0;
	foreach $range (@range) {
		$qe = $qb = "'";
		if ($numeric[$i]) {
			$qe = $qb = "";
		}
		if(length $range_min[$i]) {
			$op = '>=';
			push @query, "$range $op $qb$range_min[$i]$qe";
		}
		if(length $range_max[$i]) {
			$op = '<=';
			push @query, "$range $op $qb$range_max[$i]$qe";
		}
		$i++;
	}

	if(@query) {
		$query .= scalar(@specs) ? ' AND ' : '';
		$query .= join ' AND ', @query;
	}

	if ($options->{sort_field}) {
		$query .= " ORDER by $options->{sort_field}";
		if($options->{sort_option} =~ /r/i) {
			$query .= ' DESC';
		}
	}

print("complex query: $query\n") if $Global::DEBUG;
	$out = $db->array_query ($query,$tables[0])
			or return 0;

  } # last FORMULATE

	for(@$out) {
		push @out, join "\t", @{$_};
	}
	my $q = new Vend::Search %{$options};
	my $matches = $q->{'global'}->{matches} = scalar @$out;
#print("matches: $matches\n@out\n") if $Global::DEBUG;
	if($matches > $q->{global}->{match_limit}) {
		$q->save_more(\@out);
		$matches = $q->{global}->{match_limit};
		$#out = $matches - 1;
	}

	finish_up($c,$q,\@out) or return 0;
	return($q,\@out);
}

sub finish_up {
	my($c,$q,$out) = @_;
	my($v) = $Vend::Session->{'values'};

	my $matches = $q->{global}->{matches};
	$v->{'mv_search_match_count'}	= $matches;
	$v->{'mv_searchspec'}			= $c->{'mv_searchspec'} 
						  			|| $c->{'mv_dict_look'};
	$v->{'mv_raw_searchspec'}		= $c->{'mv_raw_searchspec'};
	$v->{'mv_raw_dict_look'}		= $c->{'mv_raw_dict_look'};
	$v->{'mv_dict_look'}			= $c->{'mv_dict_look'}
									|| $q->{global}->{dict_look} || '';

	my $msg;
	if ( $matches > 0 ) {
		if (defined $Vend::Cfg->{'CollectData'}->{'matched'}) {
			$msg = join " ",
						"search matched $matches: ",
						$q->specs(),
						$q->{global}->{dict_look};
			logData($Vend::Cfg->{'LogFile'}, format_log_msg($msg));
		}
	}
	elsif (defined $matches and $matches == 0) {
		$msg = join " ",
						$q->specs(),
						$q->{global}->{dict_look};
		if (defined $Vend::Cfg->{'CollectData'}->{'nomatch'}) {
			logData($Vend::Cfg->{'LogFile'}, format_log_msg('no match: ' . $msg));
		}
	}
	else {
		# Got an error handled by search module
		return 0;
	}

	if($Vend::Cfg->{'Delimiter'} eq 'CSV') {
		for(@$out) { s/^"//; s/[",|].*$//; }
	}

	undef $v->{'mv_search_over_msg'}
    			 unless $q->global('overflow');

	return 1;
}

# Search for an item with glimpse or text engine
sub perform_search {
	my($c,$more_matches) = @_;

	my($v) = $Vend::Session->{'values'};
    my($param);
	my(@fields);
	my(@specs);
	my($out);
	my ($p, $q, $matches);

	my %options = (
			session_key => $c->{mv_cache_key} || '',
			session_id => $Vend::SessionID,
			search_mod => ++$Vend::Session->{pageCount},
			);

	if(defined %Vend::Cache) {
		$options{'save_hash'} = \%Vend::Cache;
	}
	else {
		$options{'save_dir'} = $Vend::Cfg->{'ScratchDir'};
	}

	if (defined $more_matches and $more_matches) {
		return search_page( do_more($c, \%options, $more_matches) );
	}
	elsif (defined $c->{mv_searchtype} and $c->{mv_searchtype} eq 'sql') {
		return search_page( sql_search($c, \%options) );
	}

	# A text or glimpse search from here

	foreach $param (@Order) {
		next unless defined ($c->{$param});
		$p = $Map{$param};
		$options{$p} = $c->{$param};
		$options{$p} =
			&{$Parse{$p}}(\%options, $options{$p})
				if defined $Parse{$p};
		last if $options{$p} eq '-1' and $p eq 'mv_profile';
		delete $options{$p} unless defined $options{$p};
	}

	if ( ($options{search_type} || '') eq 'sql') {
		return search_page( sql_search($c, \%options, 'second_pass') );
	}

	unless(defined $options{'search_file'}) {
		if ($Vend::Cfg->{'Delimiter'} eq 'CSV') {
			$options{'index_delim'} = ',';
		}
		elsif ($Vend::Cfg->{'Delimiter'} ne "\t") {
			$options{'index_delim'} = $Vend::Cfg->{'Delimiter'};
			$options{'return_delim'} = "\t"
				unless defined $options{return_delim};
		}
	}

    if (defined $options{'search_page'} or $options{session_key}) {
		$options{'save_context'} = [	'session_key', 'search_page',
										'search_spec', 'dict_look' ];
	}

 	$options{'search_type'} = 'text'
		unless ($Vend::Cfg->{'Glimpse'});

  SEARCH: {

		$options{'search_spec'} = $options{'dict_look'} 
			unless defined $options{'search_spec'};

		if(ref $options{'search_spec'}) {
			@specs = @{$options{'search_spec'}};
			delete $options{'search_spec'};
		}
	
		if (defined $options{search_type} and $options{search_type} eq 'glimpse'){
			 		$q = new Vend::Glimpse %options;
		}
		else	{ 	$q = new Vend::TextSearch %options }

		@specs = ($options{'search_spec'}) 
			unless defined @specs;

		if(defined $options{mv_return_spec}) {
			$q->global('matches', 1) 
				if product_code_exists_ref($specs[0]);
			$out = [$specs[0]];
			last SEARCH;
		}

		delete $options{'search_type'};

		$q->fields(@{$options{'search_field'}}) 
			if defined $options{'search_field'} ;
		$q->specs(@specs);

		$out = $q->search();
  } # last SEARCH

	if($q->{global}->{list_only}) {
		return $out;
	}

	finish_up($c,$q,$out) or return 0;

	search_page($q,$out);

}

sub _column {
	return '' unless $_[1];
	my @fields = split /\s*[,\0]\s*/, $_[1];
	my $col;
	for(@fields) {
		next if /^\d+$/;
		if (! defined $_[0]->{search_file} and defined ($col = column_exists($_)) ) {
			$_ = $col + 1;
		}
		elsif ( $col = _find_field($_[0], $_) or defined $col ) {
			$_ = $col;
		}
		else {
			logError("Bad search column '$_'");
			return undef;
		}
	}
	\@fields;
}

sub _find_field {
	my($s, $field) = @_;
	my ($file, $i, $line, @fields);

	if($s->{field_names}) {
		@fields = @{$s->{field_names}};
	}
	elsif(! defined $s->{search_file}) {
		return undef;
	}
	elsif(ref $s->{search_file}) {
		$file = $s->{search_file}->[0];
	}
	elsif($s->{search_file}) {
		$file = $s->{search_file};
	}
	else {
		return undef;
	}

	if(defined $file) {
		my $dir = $s->{base_directory} || $Vend::Cfg->{ProductDir};
		open (Vend::Scan::FIELDS, "$dir/$file")
			or return undef;
		chomp($line = <Vend::Scan::FIELDS>);
		@fields = split /$Vend::Cfg->{Delimiter}/, $line;
		close(Vend::Scan::FIELDS);
		$s->{field_names} = \@fields;
	}
	$i = 0;
	for(@fields) {
		return $i if $_ eq $field;
		$i++;
	}
	return undef;
}

sub _command {
	return undef unless defined $_[1];
	return undef unless $_[1] =~ m{^\S+$};
	return $_[1];
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
	my(@fields) = split /\s*[,\0]\s*/, $_[1], -1;
	scalar @fields > 1 ? [@fields] : (defined $fields[0] ? $fields[0] : '');
}

sub _yes_array {
	my(@fields) = split /\s*[,\0]\s*/, $_[1];
	return $#fields ? [map {_yes('',$_)} @fields] : _yes('',$fields[0]);
}

sub _dict_limit {
	my ($ref,$limit) = @_;
	return undef unless	defined $ref->{dict_look};
    $ref->{'dict_end'} = $ref->{'dict_look'};
    substr($ref->{'dict_end'},$limit,1) =~ s/(.)/chr(ord($1) + 1)/e;
	1;
}

1;
__END__
