# Vend/Scan.pm:  Prepare searches for MiniVend
#
# $Id: Scan.pm,v 1.41 1998/09/01 13:15:22 mike Exp mike $
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
			create_last_search
			check_search_cache
			find_search_params
			perform_search
			);

$VERSION = substr(q$Revision: 1.41 $, 10);

use strict;
use Vend::Util;
use Vend::Interpolate;
use Vend::Data qw(product_code_exists_ref column_index);

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
					mv_range_alpha
					mv_numeric
					mv_negate
					mv_begin_string
					mv_return_fields
					mv_coordinate
					mv_substring_match
					mv_search_field
					mv_search_page
					mv_sort_field
					mv_sort_option
					mv_unique
					mv_first_match
                    mv_more_matches
					mv_field_names
					mv_value

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
					mv_numeric
                    mv_column_op
					mv_begin_string
					mv_coordinate
					mv_delay_page
					mv_dict_end
					mv_dict_fold
					mv_dict_limit
					mv_dict_order
					mv_failpage
					mv_first_match
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
					mv_return_reference
					mv_substring_match
					mv_return_spec
					mv_spelling_errors
					mv_search_field
					mv_search_page
					mv_sort_field
					mv_sort_option
					mv_sort_command
					mv_sort_crippled
					mv_paren
					mv_searchtype
					mv_unique
					mv_more_matches
					mv_value

));

my %Map = ( qw(
					mv_base_directory	base_directory
					mv_case				case_sensitive
                    mv_column_op        column_op
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
					mv_begin_string     begin_string
					mv_all_chars		all_chars
					mv_return_all		return_all
					mv_head_skip		head_skip
					mv_index_delim		index_delim
					mv_list_only        list_only
					mv_first_match      first_match
					mv_paren			paren
					mv_matchlimit		match_limit
					mv_min_string		min_string
					mv_max_matches		max_matches
					mv_negate      		negate
					mv_numeric          numeric
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
					mv_return_reference return_reference
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
					mv_unique			unique_result
					mv_value     		mv_value
					mv_searchspec		search_spec
					mv_substring_match	substring_match

) );

my %Scan = ( qw(
                    ac  mv_all_chars
                    bd  mv_base_directory
					bs  mv_begin_string
                    co  mv_coordinate
                    cs  mv_case
                    de  mv_dict_end
                    df  mv_dict_fold
                    di  mv_dict_limit
                    dl  mv_dict_look
                    DL  mv_raw_dict_look
                    do  mv_dict_order
                    dp  mv_delay_page
                    dr  mv_record_delim
                    em  mv_exact_match
                    er  mv_spelling_errors
                    fi  mv_search_file
                    fm  mv_first_match
                    fn  mv_field_names
                    hs  mv_head_skip
                    id  mv_index_delim
					pp  mv_paren
                    ml  mv_matchlimit
                    mm  mv_max_matches
                    MM  mv_more_matches
                    sq  mv_sql_query
                    mp  mv_profile
                    ms  mv_min_string
                    ne  mv_negate
					nu  mv_numeric
                    op  mv_column_op
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
                    rr  mv_return_reference
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
					un	mv_unique
					va  mv_value

				) );

my %RevScan;
%RevScan = reverse %Scan;
delete $RevScan{mv_cache_key};

my %Parse = (

	case_sensitive		=>	\&_yes_array,
	negate         		=>	\&_yes_array,
	numeric        		=>	\&_yes_array,
	begin_string        =>	\&_yes_array,
	coordinate          =>	\&_yes,
	head_skip           =>	\&_number,
	match_limit         =>	sub { $_[1] =~ /(\d+)/ ? $1 : 50 },
	max_matches         =>	sub { $_[1] =~ /(\d+)/ ? $1 : 2000 },
	min_string          =>	sub { $_[1] =~ /(\d+)/ ? $1 : 1 },
	dict_limit			=>	\&_dict_limit,
	exact_match			=>	\&_yes,
	mv_profile          =>	\&parse_profile,
	mv_value            =>	\&_value,
	or_search           =>  \&_yes,
	return_fields       =>	\&_column,
	range_look	        =>	\&_column,
	range_min	        =>	\&_array,
	range_max	        =>	\&_array,
	range_alpha	        =>	\&_array,
	column_op           =>	\&_array,
	search_spec       	=>	\&_scalar_or_array,
	return_file_name    =>	\&_yes,
	all_chars		    =>	\&_yes,
	return_all		    =>	\&_yes,
	unique_result	    =>	\&_yes,
	paren			    =>	\&_left_right,
	save_context        =>	\&_array,
	search_field		=>	\&_column,
	sort_command		=>	\&_command,
	sort_field			=>	\&_column_opt,
	sort_option			=>	\&_opt,
	sort_crippled		=>	\&_yes,
	search_file         => 	\&_scalar_or_array,
	field_names         =>	\&_array,
	spelling_errors     => 	sub { my $n = int($_[1]); $n < 8 ? $n : 1; },
	substring_match		=>	\&_yes_array,

);

sub check_search_cache {
	my($path, $key) = @_;
	$key = generate_key($path) unless $key;
	
	my $page = readfile ($Vend::Cfg->{ScratchDir}.'/SearchCache/'.$key.'.html');

	return($key,undef) unless defined $page;
	return(undef,\$page);
}

sub create_last_search {
	my ($ref) = @_;
	my @out;
	my $val;
	for (keys %$ref) {
		next unless defined $RevScan{$_};
		$val = $ref->{$_};
		$val =~ s!/!__SLASH__!g;
		$val =~ s!\0!__NULL__!g;
		$val =~ s!(\W)!'%' . sprintf '%02x', ord($1)!eg;
		$val =~ s!__SLASH__!::!g;
		push @out, ( $RevScan{$_} . '=' . $val );
	}
	$Vend::Session->{last_search} = join "/", 'scan', @out;
}

sub find_search_params {
	my($c,$param) = @_;
	my(@args);
	$param =~ s/__NULL__/\0/g;
	@args = split m:/:, $param;
	
	my($var,$val);

	for(@args) {
		($var,$val) = split /=/, $_, 2;
		next unless defined $Scan{$var};
		$val =~ s/%([A-Fa-f0-9][A-Fa-f0-9])/chr(hex($1))/ge;
		$val =~ s!::!/!g;
		if ($var eq 'dl' || $var eq 'se') {
			$val =~ s/\.(..)/chr(hex($1))/ge unless $Vend::Cfg->{NewEscape};
			defined $c->{$Scan{uc $var}}
				? ( $c->{$Scan{uc $var}} .= "__NULL__$val" )
				: ( $c->{$Scan{uc $var}}  =  $val          );
		}
		defined $c->{$Scan{$var}} ? ($c->{$Scan{$var}} .= "\0$val" )
								  : ($c->{$Scan{$var}}  =  $val    );
	}
	1;
}

my %Save;

sub parse_map {
	my($ref,$map) = @_;
	$map = $ref->{mv_search_map} unless $map;
	use strict;
	return undef unless defined $map;
	my($params);
	if(index($map, "\n") != -1) {
		$params = $map;
	}
    elsif(defined $Vend::Cfg->{'SearchProfileName'}->{$map}) {
        $map = $Vend::Cfg->{'SearchProfileName'}->{$map};
        $params = $Vend::Cfg->{'SearchProfile'}->[$map];
    }
    elsif($map =~ /^\d+$/) {
        $params = $Vend::Cfg->{'SearchProfile'}->[$map];
    }
    elsif(defined $::Scratch->{$map}) {
        $params = $::Scratch->{$map};
    }
	
	return undef unless $params;

	if ( index($params, '[') != -1 or index($params, '__') != -1) {
		$params = interpolate_html($params);
	}

	my($ary, $var,$source, $i);

	$params =~ s/^\s+//mg;
	$params =~ s/\s+$//mg;
	my %out;
	my(@param) = grep $_, split /[\r\n]+/, $params;
	for(@param) {
#::logGlobal("parm=$_");
		($var,$source) = split /[\s=]+/, $_, 2;
		$out{$var} = [] unless defined $out{$var};
		push @{$out{$var}}, ($ref->{$source} || '');
	}
	while( ($var, $ary) = each %out ) {
#::logGlobal("ary: $var=" . Data::Dumper::Dumper($ary));
		unshift @$ary, $ref->{$var}
			if defined $ref->{$var};
		$ref->{$var} = join "\0", @$ary;
	}
	return 1;
}

sub parse_profile {
	my($ref,$profile) = @_;
	return undef unless defined $profile;
	my($params);
    if(defined $Vend::Cfg->{'SearchProfileName'}->{$profile}) {
        $profile = $Vend::Cfg->{'SearchProfileName'}->{$profile};
        $params = $Vend::Cfg->{'SearchProfile'}->[$profile];
    }
    elsif($profile =~ /^\d+$/) {
        $params = $Vend::Cfg->{'SearchProfile'}->[$profile];
    }
    elsif(defined $::Scratch->{$profile}) {
        $params = $::Scratch->{$profile};
    }
	
	return undef unless $params;

	if ( index($params, '[') != -1 or index($params, '__') != -1) {
		$params = interpolate_html($params);
	}

	my($p, $var,$val);
	my $status = $profile;
	undef %Save;
	$params =~ s/^\s+//mg;
	$params =~ s/\s+$//mg;
	my(@param) = grep $_, split /[\r\n]+/, $params;
	for(@param) {
		($p,$val) = split /[\s=]+/, $_, 2;
		$status = -1 if $p eq 'mv_last';
		next unless defined $Map{$p} or $p = $Scan{$p};
		$var = $Map{$p} or next;
		$val =~ s/&#(\d+);/chr($1)/ge;
		$Save{$p} = $val;
		$val = &{$Parse{$var}}($ref,$val,$ref->{$var} || undef)
				if defined $Parse{$var};
		$ref->{$var} = $val if defined $val;
	}

	return $status;
}

sub do_more {
	my($c,$opt,$more,$delay) = @_;
	my($session,$next,$last,$chunk,$mod) = split(/:/,$more);
	$opt->{'match_limit'} = $chunk;
	$opt->{'cache_key'} = $Vend::Cfg->{SearchCache};
	my $q = new Vend::Search %{$opt};
	my $out = $q->more_matches($session,$next,$last,$mod);
	finish_up($c,$q,$out);
   	return($q,$out) if $delay;
   	return search_page($q,$out);
}

sub sql_search {
	my($c,$options,$second, $delay) = @_;
	my ($out, $table, @fields);
	my ($i, $op, @out);
	my (@range);
	my (@range_min);
	my (@range_max);
	my (@range_alpha);
	my ($numeric,$substring,$negate,$begin_string);

	unless(defined $second) {
		for( grep defined $c->{$_}, @Sql ) {
			$options->{$Map{$_}} = $c->{$_}
				if defined $c->{$_};
		}
	}
	else {
		for( grep defined $Save{$_}, @Sql ) {
			$options->{$Map{$_}} = $Save{$_};
		}
	}

	my @specs = split /\000/, $options->{search_spec};

    if (defined $options->{'search_page'} or $options->{session_key}) {
		$options->{'save_context'} = [	'session_key', 'search_page',
										'search_spec', 'dict_look',
										'field_names', 'return_fields' ];
	}

	$substring = _yes_array('', $options->{substring_match});
	$substring = [($substring) x scalar @specs] unless ref $substring;

	$begin_string = _yes_array('', $options->{begin_string});
	$begin_string = [($begin_string) x scalar @specs] unless ref $begin_string;

	$negate = _yes_array('', $options->{'negate'});
	$negate = [($negate) x scalar @specs] unless ref $negate;

	$numeric = _yes_array('', $options->{'numeric'});
	$numeric = [($numeric) x scalar @specs] unless ref $numeric;

	my(@tables) = split /[\s,\000]+/, ($options->{search_file} || 'products');

	my $db = Vend::Data::database_exists_ref($tables[0])
				or do {
#					logError("non-existent database '$tables[0]'");
					logError( errmsg('Scan.pm:1', "non-existent database '%s'" , $tables[0]) );
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

	if($options->{return_fields}) {
		$options->{return_fields} =~ s/[\0,\s]+/,/g;
	}
	else {
		$options->{return_fields} = $db->[$Vend::Table::DBI::KEY];
	}

	if($options->{sort_field}) {
		$options->{sort_field} =~ s/[\0,\s]+$//;
		$options->{sort_field} =~ s/[\0,\s]+desc\b/\001DESC/ig;
		$options->{sort_field} =~ s/[\0,\s]+asc\b/\001ASC/ig;
		$options->{sort_field} =~ s/[\0,\s]+/,/g;
		$options->{sort_field} =~ tr/\001/ /;
	}

	my $joiner = ' AND ';

	$joiner = ' OR ' if _yes($options->{or_search});

	if($options->{sql_query}) {
		$options->{sql_query} =~ s/\0+$//g;
		$options->{sql_query} =~ s/[\0\s]*(where|order\s+by)[\s\0]+/ $1 /ig;
		$options->{sql_query} =~ s/\bfrom\s+%t/'FROM ' . join(", ", @tables)/ei;
		$options->{sql_query} =~ s/[\0\s]+order\s+by\s+%f\b/
			$options->{sort_field}
				?  " ORDER BY $options->{sort_field}"
				: ''/ie;
		$options->{sql_query} =~ /(select(\s+distinct)?)
									\s+(.*?)
									\s+from\s+/ix;
		if ($3 eq '%f') {
			$options->{sql_query} =~ s/\s+%f\s+/ $options->{return_fields} /i;
		}
		else {
			$options->{return_fields} = $3;
		}
		$options->{sql_query} =~ s/order\s+by[\s\0]*$//ig;
		$options->{sql_query} =~ s/where[\s\0]*$//ig;
		$options->{sql_query} =~ s/\0+\s*([!=<>][=<>]?|like)\s*\0+$/ $1 /ig;
		$options->{sql_query} =~ s/\0+\s*([!=<>][=<>]?|like)\s*$//i;
		$options->{sql_query} =~ s/\0+/$joiner/g;
		$options->{sql_query} =~ s/(\s)\?([\s]|$)/%s/;
# DEBUG
#Vend::Util::logDebug
#("mv_sql_query: $options->{sql_query} specs: '" . join("','", @specs) . "'\n")
#	if ::debug(0x10);
# END DEBUG
		my $cfg = {PERL => 1, BOTH => 1};
		$out = $db->array_query(
					$options->{sql_query},$tables[0], $cfg, @specs
				) or return 0;
		last FORMULATE;
	}
	elsif($options->{range_look}) {
		@range			= split /[,\000]/, $options->{range_look};
		@range_min		= split /[,\000]/, $options->{range_min};
		@range_max		= split /[,\000]/, $options->{range_max};
		@range_alpha	= split /[,\000]/, $options->{range_alpha};
	}


	if($options->{return_fields} eq '*') {
		@{$options->{field_names}} = $db->columns();
		unshift @{$options->{field_names}}, $db->[$Vend::Table::DBI::KEY];
	}
	$options->{return_fields} =~ s/\b0\b/code/;

	if (defined $options->{search_field}) {
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

	if(! @specs) {
		# do nothing here
	}
	elsif($coord == 0) {
		$i = 0;
		for (@specs) {
			$op = $negate->[$i] ? '!=' : '=';
			$qb = $qe = "";
			if( $substring->[$i] and ! $db->numeric($fields[$i]) ) {
					$op  = 'like';
					$qe = "%";
					$qb = "%" unless $begin_string->[$i];
			}
			if(! $db->numeric($fields[$i]) ) {
# DEBUG
#Vend::Util::logDebug
#("quoting field $i=$specs[$i]\n")
#	if ::debug(0x10);
# END DEBUG
				$specs[$i] = $db->quote("$qb$specs[$i]$qe");
# DEBUG
#Vend::Util::logDebug
#("quoted field $i=$specs[$i]\n")
#	if ::debug(0x10);
# END DEBUG
			}

			push(@query, "$fields[$i] $op $specs[$i]");
			$i++;
		}
	}
	elsif ($coord == -1) {
		$joiner = ' OR ';
		$i = 0;
		my $spec;
		$op = '=';
		$qb = $qe = "";
		if( $substring->[$i] and ! $db->numeric($fields[$i]) ) {
				$op  = 'like';
				$qb = $qe = "%";
		}
		if(! $db->numeric($fields[$i]) ) {
			$specs[$i] = $db->quote("$qb$specs[$i]$qe");
		}
		for(@fields) {
			push(@query, "$fields[$i] $op $specs[0]");
			$i++;
		}
	}
	else {
		$joiner = ' OR ';
		$i = 0;
		if( $substring->[$i] and ! $db->numeric($fields[0]) ) {
				$op  = 'like';
				$qb = $qe = "%";
		}
		for(@specs) {
			$op = '=';
			$qb = $qe = "";
			if( $substring->[$i] and ! $db->numeric($fields[0]) ) {
					$op  = 'like';
					$qb = $qe = "%";
			}
			if(! $db->numeric($fields[0]) ) {
				$specs[$i] = $db->quote("$qb$specs[$i]$qe");
			}
			push(@query, "$fields[0] $op $specs[$i]");
			$i++;
		}
	}



	$query .= join ($joiner, @query) if @query;

	$joiner = ' AND ' unless _yes($options->{or_search});

	@query = ();

	$i = 0;
	foreach $range (@range) {
		if(length $range_min[$i]) {
			$op = '>=';
			$range_min[$i] = $db->quote($range_min[$i]) if $range_alpha[$i];
			push @query, "$range $op $range_min[$i]";
		}
		if(length $range_max[$i]) {
			$op = '<=';
			$range_max[$i] = $db->quote($range_max[$i]) if $range_alpha[$i];
			push @query, "$range $op $range_max[$i]";
		}
		$i++;
	}

	if(@query) {
		$query .= ' AND ' unless $query =~ /where\s+$/i;
		$query .= join ' AND ', @query;
	}

	$query .= '1 = 1 ' if $query =~ /where\s+$/i;

	if ($options->{sort_field}) {
		$query .= " ORDER by $options->{sort_field}";
		if($options->{sort_option} =~ /r/i) {
			$query .= ' DESC';
		}
	}

# DEBUG
#Vend::Util::logDebug
#("complex query: $query\n")
#	if ::debug(0x10);
# END DEBUG
	$out = $db->array_query ($query,$tables[0])
			or return 0;

  } # last FORMULATE

	unless (defined $options->{field_names}) {
		$options->{field_names}		= ref $options->{return_fields}
								?	$options->{return_fields} 
								: _array('', $options->{return_fields});
	}
	else {
		$options->{field_names}	= _array('', $options->{field_names});
	}

	for(@$out) {
		push @out, join "\t", @{$_};
	}
	my $q = new Vend::Search %{$options};
	my $matches = $q->{'global'}->{'matches'} = scalar @$out;
	$q->{'specs'} = \@specs;
# DEBUG
#Vend::Util::logDebug
#("matches: $matches\n@out\n")
#	if ::debug(0x10);
# END DEBUG
	if($matches > $q->{'global'}->{match_limit}) {
		$q->save_more(\@out);
		$matches = $q->{'global'}->{match_limit};
		$#out = $matches - 1;
	}

	finish_up($c,$q,\@out);
	return($q,\@out) if $delay;
	search_page($q, \@out);
}

sub finish_up {
	my($c,$q,$out) = @_;
	my($v) = $::Values;
	my $matches = $q->{'global'}->{'matches'};
	$v->{'mv_search_match_count'}	= $matches;
	$v->{'mv_matchlimit'}			= $q->{'global'}{match_limit};
	$v->{'mv_first_match'}			= $q->{'global'}{first_match};
	$v->{'mv_searchspec'}			= $c->{mv_searchspec} 
						  			|| $c->{mv_dict_look};
	$v->{'mv_raw_searchspec'}		= $c->{mv_raw_searchspec};
	$v->{'mv_raw_dict_look'}		= $c->{mv_raw_dict_look};
	$v->{'mv_dict_look'}			= $c->{mv_dict_look}
									|| $q->{'global'}->{dict_look} || '';
	my $msg;
	if ( $matches > 0 ) {
		if (defined $Vend::Cfg->{'CollectData'}->{'matched'}) {
			$msg = join " ",
						"search matched $matches: ",
						@{$q->{'specs'}},
						$q->{'global'}->{dict_look};
			logData($Vend::Cfg->{'LogFile'}, format_log_msg($msg));
		}
	}
	elsif (defined $matches and $matches == 0) {
		$msg = join " ",
						@{$q->{specs}},
						$q->{'global'}->{dict_look};
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

	my $delay;

	if (!$c) {
		return undef unless $Vend::Session->{search_params};
		($c, $more_matches) = @{$Vend::Session->{search_params}};
		unless($c->{mv_cache_key}) {
			Vend::Scan::create_last_search($c);
			$c->{mv_cache_key} = generate_key($Vend::Session->{last_search});
		}
		$delay = 1;
	}
	elsif ($c->{mv_search_immediate}) {
		unless($c->{mv_cache_key}) {
			Vend::Scan::create_last_search($c);
			$c->{mv_cache_key} = generate_key($Vend::Session->{last_search});
		}
		$delay = 1;
	}
	# Here we redirect back to the main page delivery mechanism
	# We will come back with the above when [search-region] is called
	elsif ($c->{mv_delay_page}) {
		$Vend::Session->{search_params} = [$c, $more_matches];
		return main::cache_page($c->{mv_delay_page}, 1);
	}

	my($v) = $::Values;
    my($param);
	my(@fields);
	my(@specs);
	my($out);
	my ($p, $q, $matches);

	$more_matches = $c->{mv_more_matches} if defined $c->{mv_more_matches};

	my %options = (
			session_key => $c->{mv_cache_key} || '',
			session_id => $Vend::SessionID,
			);

	$options{search_mod} = ++$Vend::Session->{pageCount}
		unless $options{session_key};

	$options{'save_dir'} = $Vend::Cfg->{'ScratchDir'};

	if (defined $more_matches and $more_matches) {
		return do_more($c, \%options, $more_matches, $delay );
	}
	elsif (defined $c->{mv_searchtype} and $c->{mv_searchtype} eq 'sql') {
		return sql_search($c, \%options, undef, $delay);
	}

	# A text or glimpse search from here

	parse_map($c) if defined $c->{mv_search_map};

	if(defined $c->{mv_sql_query}) {
		my $params = Vend::Interpolate::escape_scan($c->{mv_sql_query}, $c);
		find_search_params($c, $params);
	}

	$c->{mv_sort_option} = $c->{mv_sort_field}
		if ! $c->{mv_sort_option} and $c->{mv_sort_field};

	foreach $param ( grep defined $c->{$_}, @Order) {
		$p = $Map{$param};
		$options{$p} = $c->{$param};
		$options{$p} =
			&{$Parse{$p}}(\%options, $options{$p})
				if defined $Parse{$p};
		last if $options{$p} eq '-1' and $p eq 'mv_profile';
		delete $options{$p} unless defined $options{$p};
	}

	if ( $options{search_type} and
		 $options{search_type} eq 'sql') {
		return sql_search($c, \%options, 'second_pass', $delay);
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
										'search_spec', 'dict_look',
										'field_names', 'return_fields' ];
	}

 	if (defined $options{search_type} && $options{search_type} eq 'glimpse') {
		undef $options{'search_type'} if ! $Vend::Cfg->{'Glimpse'};
	}

  SEARCH: {

		$options{'search_spec'} = $options{'dict_look'} 
			unless defined $options{'search_spec'};

		if(ref $options{'search_spec'}) {
			@specs = @{$options{'search_spec'}};
			delete $options{'search_spec'};
		}
	
		if (! defined $options{search_type} or $options{search_type} eq 'text') {
			$q = new Vend::TextSearch %options;
		}
		elsif ( $options{search_type} eq 'glimpse'){
			$q = new Vend::Glimpse %options;
		}
		else  {
			eval {
				no strict 'refs';
				$q = "$Global::Variable->{$options{search_type}}"->new(%options);
			};
			if ($@) {
				::display_special_page(
					find_special_page('badsearch'),
					errmsg('Scan.pm:2', "Bad search type %s: %s",
							$options{search_type}, $@ )
					);
				return 0;
			}
		}

		@specs = ($options{'search_spec'}) 
			unless defined @specs;

		if(defined $options{mv_return_spec}) {
			$q->global('matches', 1) 
				if product_code_exists_ref($specs[0]);
			$out = [$specs[0]];
			last SEARCH;
		}

		delete $options{'search_type'};

		$q->{'fields'} = $options{'search_field'} 
			if defined $options{'search_field'} ;
		$q->{'specs'} = \@specs;

		if($q->{'global'}->{list_only}) {
			$q->{'global'}->{error_routine} = \&Vend::Util::logError;
			$q->{'global'}->{error_page} = 'Bad search, probably bad search string:';
		}

		$out = $q->search();
  } # last SEARCH

	if($q->{'global'}->{list_only}) {
		return $out;
	}

	finish_up($c,$q,$out);

	return($q,$out) if $delay;

	search_page($q,$out);

}

BEGIN {
	eval { require SQL::Statement; };
}

sub sql_statement {
	my($text, $ref, $table) = @_;

# DEBUG
#Vend::Util::logDebug
#("array_query: $text\n")
#	if ::debug(0x4);
# END DEBUG

	my @ss;

	if ($table) {
		push(@ss, "fi=$table");
	}

	die "SQL is not enabled for MiniVend. Get the SQL::Statement module.\n"
		unless $INC{'SQL/Statement.pm'};

	my $parser = SQL::Parser->new('Ansi');

	my $stmt;
	eval {
		$stmt = SQL::Statement->new($text, $parser);
	};
	if($@) {
		die "Bad SQL statement: $@\nQuery was: $text.\n";
	}

	if ($stmt->command() ne 'SELECT') {
		die "Only selects supported for the array_query function.";
	}

	for($stmt->tables()) {
		my $t = $_->name();
#::logGlobal("t=$t obj=$_");
		if( defined $Vend::Cfg->{Database}{$t}) {
			push @ss, "fi=" . $Vend::Cfg->{Database}{$t}{'file'} ;
		}
		else {
			push @ss, "fi=$t";
		}
	}

	$text =~ /\bselect\s+distinct\s+/i and push @ss, 'un=yes';

	for($stmt->columns()) {
		my $name = $_->name();
		last if $name eq '*';
		push @ss, "rf=$name";
#::logGlobal("column name=" . $_->name() . " table=" . $_->table());
	}

	my @order;

	@order = $stmt->order();
	for(@order) {
		my $c = $_->column();
		push(@ss, "tf=$c");
		my $d = $_->desc() ? 'fr' : 'f';
		push(@ss, "tf=$d");
	}

	my $where;
	my @where;
	@where = $stmt->where();
	if(@where) {
	  my $or;
	  push @ss,"co=yes";
	  do {
	  	my $where = shift @where;
		my $op = $where->op();
		my $col = $where->arg1();
		my $spec = $where->arg2();
#::logGlobal("where=$where op=$op arg1=$col arg2=$spec");
		OP: {
			if($op eq 'OR') {
				push(@ss, 'os=yes') unless $or++;
				push(@where, $where->arg1() , $where->arg2());
			}
			elsif($op eq 'AND') {
				push(@where, $where->arg1() , $where->arg2());
			}
			else {

				my ($col, $spec);

				# Search spec is a variable if a ref
				$spec = $where->arg2();
				$spec = $ref->{$spec->name()}		if ref $spec;

				# Column name is a variable if a string
				$col = $where->arg1();
				$col = ref $col ? $col->name() : $ref->{$col};

#::logGlobal("where col=$col spec=$spec");
				# If both are not supplied, we ignore it
				last OP unless $col and $spec;

				push @ss, "se=$spec";
				push @ss, "op=$op";
				push @ss, "sf=$col";
				push @ss, "ne=" . ($where->neg() || 0);

				
			}
		}
	  } while @where;

	}
	
	my $string = join "\n", @ss;
#::logGlobal("sql_statement output=$string");
	return $string;
}

sub _value {
	my($ref, $in) = @_;
	return unless $in;
	my (@in) = split /\0/, $in;
	for(@in) {
		my($var,$val) = split /=/, $_, 2;
		$::Values->{$var} = $val;
	}
	return;
}

sub _opt {
	return ($_[2] || '') unless $_[1];
	my @fields = grep $_, split /\s*[,\0]\s*/, $_[1];
	unshift(@fields, @{$_[2]}) if $_[2];
	my $col;
	for(@fields) {
		s/.*://;
		$_ = 'none' unless $_;
	}
	\@fields;
}

sub _column_opt {
	return ($_[2] || '') unless length($_[1]);
	my @fields = grep $_, split /\s*[,\0]\s*/, $_[1];
	unshift(@fields, @{$_[2]}) if $_[2];
	my $col;
	for(@fields) {
		s/:.*//;
		next if /^\d+$/;
		if (! defined $_[0]->{search_file} and defined ($col = column_index($_)) ) {
			$_ = $col + 1;
		}
		elsif ( $col = _find_field($_[0], $_) or defined $col ) {
			$_ = $col;
		}
		else {
#			logError("Bad search column '$_'");
			logError( errmsg('Scan.pm:3', "Bad search column '%s'" , $_) );
			return undef;
		}
	}
	\@fields;
}

sub _column {
	return ($_[2] || '') unless length $_[1];
	my @fields = split /\s*[,\0]\s*/, $_[1];
	unshift(@fields, @{$_[2]}) if $_[2];
	my $col;
	for(@fields) {
		next if /^\d+$/;
		next if /:/;
		if (! defined $_[0]->{search_file} and defined ($col = column_index($_)) ) {
			$_ = $col + 1;
		}
		elsif ( $col = _find_field($_[0], $_) or defined $col ) {
			$_ = $col;
		}
		else {
#			logError("Bad search column '$_'");
			logError( errmsg('Scan.pm:4', "Bad search column '%s'" , $_) );
			return undef;
		}
	}
#::logGlobal("fields=", @fields);
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
	return ($_[2] || undef) unless defined $_[1];
	my (@fields) = split /\s*[,\0]\s*/, $_[1];
	unshift(@fields, @{$_[2]}) if $_[2];
	return \@fields;
}

sub _left_right {
	return 0 unless defined($_[1]);
	$_[1] =~ /^[Rr1]/ and return 1;
	$_[1] =~ /^[Ll-]/ and return -1;
	return 0;
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
	my $arg;
	if($arg = $_[2]) {
		$arg = [ $arg ] unless ref $arg;
		unshift(@fields, @{$arg});
	}
	scalar @fields > 1 ? \@fields : (defined $fields[0] ? $fields[0] : '');
}

sub _yes_array {
	my(@fields) = split /\s*[,\0]\s*/, $_[1];
	if(defined $_[2]) {
		unshift(@fields, ref $_[2] ? @{$_[2]} : $_[2]);
	}
#::logGlobal("fields=", @fields);
	map { $_ = _yes('',$_) } @fields;
	return \@fields if @fields > 1;
	return @fields;
}

sub _dict_limit {
	my ($ref,$limit) = @_;
	return undef unless	defined $ref->{dict_look};
	$limit = -1 if $limit =~ /[^-0-9]/;
    $ref->{'dict_end'} = $ref->{'dict_look'};
    substr($ref->{'dict_end'},$limit,1) =~ s/(.)/chr(ord($1) + 1)/e;
	return $_[1];
}

1;
__END__
