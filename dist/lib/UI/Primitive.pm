#!/usr/bin/perl

# Copyright (C) 1998-2000 Akopia, Inc. <info@akopia.com>

# Author: Michael J. Heins <heins@akopia.com>
# Maintainer: Stefan Hornburg <racke@linuxia.de>

# This file is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any
# later version.

# This file is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this file; see the file COPYING.  If not, write to the Free
# Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

my($order, $label, %terms) = @_;

package UI::Primitive;

$VERSION = substr(q$Revision$, 10);
$DEBUG = 0;

use vars qw!
	@EXPORT @EXPORT_OK
	$VERSION $DEBUG
	$DECODE_CHARS
	!;

use File::Find;
use File::CounterFile;
use Text::ParseWords;
use Exporter;
use strict;
use Vend::Util qw/errmsg/;
$DECODE_CHARS = qq{&[<"\000-\037\177-\377};

@EXPORT = qw( ui_check_acl ui_acl_enabled ) ;

=head1 NAME

Primitive.pm -- Miniman Configuration Manager Primitives

=head1 SYNOPSIS

display_directive %options;

=head1 DESCRIPTION

The Interchange UI is an interface to configure and administer Interchange catalogs.

=cut

my $ui_safe = new Safe;
$ui_safe->untrap(@{$Global::SafeUntrap});

sub is_super {
#::logDebug("called is_super");
	return 0 if ! $Vend::Session->{logged_in};
#::logDebug("is_super: logged in");
	return 0 if ! $Vend::username;
	return 0 if $Vend::Cfg->{AdminUserDB} and ! $Vend::admin;
#::logDebug("is_super: have username");
	my $db = Vend::Data::database_exists_ref(
						$Vend::Cfg->{Variable}{UI_ACCESS_TABLE} || 'access'
						);
	return 0 if ! $db;
#::logDebug("is_super: access db exists");
	$db = $db->ref();
	my $result = $db->field($Vend::username, 'super');
#::logDebug("is_super: result=$result");
	return $result;
}

sub is_logged {
#::logDebug("is_logged check");
	return 0 if ! $Vend::Session->{logged_in};
#::logDebug("is_logged logged_in=ok");
	return 0 unless $Vend::admin or ! $Vend::Cfg->{AdminUserDB};
#::logDebug("is_logged admin=ok");
	return 1;
}

my %wrap_dest;
my $compdb;

sub ui_wrap {
	my $path = shift;
	if($CGI::values{ui_destination}) {
		my $sub = $wrap_dest{$CGI::values{ui_destination}} || return 1;
		return $sub->($path);
	}
	$Vend::Cfg->{VendURL} .= '/ui_wrap';
	$UI::Editing = \&resolve_var;
	$compdb = ::database_exists_ref($::Variable->{UI_COMPONENT_TABLE} ||= 'component');
	$path =~ s:([^/]+)::;
	$Vend::RedoAction = 1;
	my $snoop = $1;
	return $snoop;
}

sub wrap_edit {
	package Vend::Interpolate;
	my $name = shift;
::logGlobal("entering wrap_edit $name");
	my $ref;
	if ($compdb->record_exists($name)) {
		$ref = $compdb->row_hash($name);
	}
	else {
		return $::Variable->{$name} if ! $::Variable->{$name};
		$ref = { variable => $::Variable->{$name} };
	}
	if ($ref->{variable} =~ s/^(\s*\[)include(\s+)/$1 . 'file' . $2/e) {
		$ref->{variable} = ::interpolate_html($ref->{variable});
	}
	my $edit_link;
	my $url = $Vend::Cfg->{VendURL};
	$url =~ s!/ui_wrap$!$::Variable->{UI_BASE} || $Global::Variable->{UI_BASE} || 'admin'!e;
	$url .= "/";
	if(not $edit_link = $::Variable->{UI_EDIT_LINK}) {
		my $url = Vend::Interpolate::tag_area(
						"$::Variable->{UI_BASE}/compedit",
						$name,
						);
		$url =~ s:/ui_wrap/:/:;
		$edit_link = <<EOF;
<A HREF="$url" target="_blank"><u>edit</u></A>
EOF
		chop $edit_link;
	}
	my $out = <<EOF;
[calc] \$C_stack = [] unless \$C_stack;
		push \@\$C_stack, \$Scratch->{ui_component} || '';
		\$Scratch->{ui_component} = q{$name}; return; [/calc]
EOF
	chop $out;

	for( qw/preedit preamble variable postamble postedit/ ) {
		$out .= $ref->{$_};
	}
	$out .= qq{[calc] \$Scratch->{ui_component} = pop \@\$C_stack; return; [/calc]};
	$out =~ s:\[comment\]\s*\$EDIT_LINK\$\s*\[/comment\]:$edit_link:;
::logGlobal("returning wrap_edit $out");
	return $out;
}

sub resolve_var {
	my ($name, $ref) = @_;
	if ($compdb) {
		return wrap_edit($name);
	}
	return $ref->{$name} if $ref and defined $ref->{$name};
	return $::Variable->{$name};
}

sub ui_acl_enabled {
	my $try = shift;
	my $table;
	$Global::SuperUserFunction = \&is_super;
	my $default = defined $Global::Variable->{UI_ACL}
				 ? (! $Global::Variable->{UI_ACL})
				 : 1;
	$table = $::Variable->{UI_ACCESS_TABLE} || 'access';
	$Vend::WriteDatabase{$table} = 1;
	my $db = Vend::Data::database_exists_ref($table);
	return $default unless $db;
	$db = $db->ref() unless $Vend::Interpolate::Db{$table};
	my $uid = $try || $Vend::username || $CGI::remote_user;
#::logDebug("ACL enabled try uid=$uid");
	if(! $uid or ! $db->record_exists($uid) ) {
		return 0;
	}
#::logDebug("ACL enabled record exists uid=$uid");
	my $ref = $db->row_hash($uid)
		or die "Bad database record for $uid.";
#::logDebug("ACL enabled, table_control=$ref->{table_control}");
	if($ref->{table_control}) {
		$ref->{table_control_ref} = $ui_safe->reval($ref->{table_control});
	}
	return $ref if $try;
	$Vend::UI_entry = $ref;
}

sub get_ui_table_acl {
	my ($table, $user, $keys) = @_;
	$table = $::Values->{mv_data_table} unless $table;
#::logDebug("Call get_ui_table_acl: " . Vend::Util::uneval_it(\@_));
	my $acl_top;
	if($user and $user ne $Vend::username) {
		if ($Vend::UI_acl{$user}) {
			$acl_top = $Vend::UI_acl{$user};
		}
		else {
			my $ui_table = $::Variable->{UI_ACCESS_TABLE} || 'access';
			my $acl_txt = Vend::Interpolate::tag_data($ui_table, 'table_control', $user);
			return undef unless $acl_txt;
			$acl_top = $ui_safe->reval($acl_txt);
			return undef unless ref($acl_top);
		}
		$Vend::UI_acl{$user} = $acl_top;
		return keys %$acl_top if $keys;
		return $acl_top->{$table};
	}
	else {
		unless ($acl_top = $Vend::UI_entry) {
#::logDebug("Call get_ui_table_acl: acl_top=" . ::uneval($acl_top));
			return undef unless ref($acl_top = ui_acl_enabled());
		}
	}
	return undef unless defined $acl_top->{table_control_ref};
	return $acl_top->{table_control_ref}{$table};
}

sub ui_acl_grep {
	my ($acl, $name, @entries) = @_;
#::logDebug("Call ui_acl_grep: " . ::uneval(\@_));
	my $val;
	my %ok;
	@ok{@entries} = @entries;
	if($val = $acl->{owner_field} and $name eq 'keys') {
		my $u = $Vend::username;
		my $t = $acl->{table}
			or do{
				::logError("no table name with owner_field.");
				return undef;
			};
			for(@entries) {

				my $v = ::tag_data($t, $val, $_);
#::logDebug("ui_acl_grep owner: t=$t f=$val k=$_ v=$v u=$u");
				$ok{$_} = $v eq $u;
			}
	}
	else {
		if($val = $acl->{"no_$name"}) {
			for(@entries) {
				$ok{$_} = ! ui_check_acl($_, $val);
			}
		}
		if($val = $acl->{"yes_$name"}) {
			for(@entries) {
				$ok{$_} &&= ui_check_acl($_, $val);
			}
		}
	}
	return (grep $ok{$_}, @entries);
}

sub ui_acl_atom {
	my ($acl, $name, $entry) = @_;
	my $val;
	my $status = 1;
	if($val = $acl->{"no_$name"}) {
		$status = ! ui_check_acl($entry, $val);
	}
	if($val = $acl->{"yes_$name"}) {
		$status &&= ui_check_acl($entry, $val);
	}
	return $status;
}

sub ui_extended_acl {
	my ($item, $string) = @_;
	$string = " $string ";
#::logDebug("extended acl string='$string'");
	my ($name, $sub) = split /=/, $item, 2;
#::logDebug("extended acl: name=$name sub=$sub");
#::logDebug("extended acl trying /[\s,]!${name}\[,\s]/");
	return 0 if $string =~ /[\s,]!$name(?:[,\s])/;
#::logDebug("extended acl passed /[\s,]!${name}\[,\s]/");
#::logDebug("extended acl trying /[\s,]${name}\[,\s]/");
	return 1 if $string =~ /[\s,]$name(?:[,\s])/;
#::logDebug("extended acl passed /[\s,]${name}\[,\s]/");
	my (@subs) = split //, $sub;
	for(@subs) {
#::logDebug("extended acl trying /[\s,]!$name=[^,\s]*$sub/");
		return 0 if $string =~ /[\s,]!$name=[^,\s]*$sub/;
#::logDebug("extended acl passed /[\s,]!$name=[^,\s]*$sub/");
#::logDebug("extended acl trying /[\s,]$name=[^,\s]*$sub/");
		return 0 unless $string =~ /[\s,]$name=[^,\s]*$sub/;
#::logDebug("extended acl passed /[\s,]$name=[^,\s]*$sub/");
	}
	return 1;
}

sub ui_check_acl {
	my ($item, $string) = @_;
#::logDebug("checking item=$item");
	return ui_extended_acl(@_) if $item =~ /=/;
	$string = " $string ";
	return 0 if $string =~ /[\s,]!$item[=,\s]/;
	return 1 if $string =~ /[\s,]$item[=,\s]/;
	return '';
}

sub ui_acl_global {
	my $record = ui_acl_enabled();
	# First we see if we have ACL enforcement enabled
	# If you don't, then people can do anything!
	unless (ref $record) {
		$::Scratch->{mv_data_enable} = $record;
		return;
	}
	my $enable = delete $::Scratch->{mv_data_enable} || 1;
	my $CGI = \%CGI::values;
	my $Tag = new Vend::Tags;
	$CGI->{mv_todo} = $CGI->{mv_doit}
		if ! $CGI->{mv_todo};
	if( $Tag->if_mm('super')) {
		$::Scratch->{mv_data_enable} = $enable;
		return;
	}

    if( $CGI->{mv_todo} eq 'set' ) {
		undef $::Scratch->{mv_data_enable};
		my $mml_enable = $Tag->if_mm('functions', 'mml');
		my $html_enable = ! $Tag->if_mm('functions', 'no_html');
		my $target = $CGI->{mv_data_table};
		$Vend::WriteDatabase{$target} = 1;
		my $db = Vend::Data::database_exists_ref($target);
		if(! $db) {
			$::Scratch->{ui_failure} = "Table $target doesn't exist";
			return;
		}

		my $keyname = $CGI->{mv_data_key};
		if ($CGI->{mv_auto_export}
			and $Tag->if_mm('!tables', undef, { table => "$target=x" }, 1) ) {
			$::Scratch->{ui_failure} = "Unauthorized to export table $target";
			$CGI->{mv_todo} = 'return';
			return;
		}
		if ($Tag->if_mm('!tables', undef, { table => "$target=e" }, 1) ) {
			$::Scratch->{ui_failure} = "Unauthorized to edit table $target";
			$CGI->{mv_todo} = 'return';
			return;
		}

		my @codes = grep /\S/, split /\0/, $CGI->{$keyname};
		for(@codes) {
			unless( $db->record_exists($_) ) {
				next if $Tag->if_mm('tables', undef, { table => "$target=c" }, 1);
				$::Scratch->{ui_failure} = "Unauthorized to insert to table $target";
				$CGI->{mv_todo} = 'return';
				return;
			}
			next if $Tag->if_mm('keys', $_, { table => $target }, 1);
			$CGI->{mv_todo} = 'return';
			$::Scratch->{ui_failure} = errmsg("Unauthorized for key %s", $_);
 			return;
  		}

		my @fields = grep /\S/, split /[,\s\0]+/, $CGI->{mv_data_fields};
		for(@fields) {
			$CGI->{$_} =~ s/\[/&#91;/g unless $mml_enable;
			$CGI->{$_} =~ s/\</&lt;/g unless $html_enable;
			next if $Tag->if_mm('columns', $_, { table => $target }, 1);
			$CGI->{mv_todo} = 'return';
			$::Scratch->{ui_failure} = errmsg("Unauthorized for key %s", $_);
 			return;
  		}

 		$::Scratch->{mv_data_enable} = $enable;
	}
	elsif ($CGI->{mv_todo} eq 'deliver') {
		if($Tag->if_mm('files', $CGI->{mv_data_file}, {}, 1 ) ) {
			$::Scratch->{mv_deliver} = $CGI->{mv_data_file};
		}
		else {
			$::Scratch->{ui_failure} = errmsg(
										"Unauthorized for file %s",
										$CGI->{mv_data_file},
										);
		}
	}
    return;

}

sub list_keys {
	my $table = shift;
	my $opt = shift;
#::logDebug("list-keys $table");
	$table = $::Values->{mv_data_table}
		unless $table;
#::logDebug("list-keys $table");
	my @keys;
	my $record;
	if(! ($record = $Vend::UI_entry) ) {
		$record =  ui_acl_enabled();
	}

	my $acl;
	my $keys;
	if($record) {
#::logDebug("list_keys: record=$record");
		$acl = get_ui_table_acl($table);
#::logDebug("list_keys table=$table: acl=$acl");
		if($acl and $acl->{yes_keys}) {
#::logDebug("list_keys table=$table: yes.keys enabled");
			@keys = grep /\S/, split /\s+/, $acl->{yes_keys};
		}
	}
	unless (@keys) {
		my $db = Vend::Data::database_exists_ref($table);
		return '' unless $db;
		$db = $db->ref() unless $Vend::Interpolate::Db{$table};
		my $keyname = $db->config('KEY');
		if($db->config('LARGE')) {
			return ::errmsg('--not listed, too large--');
		}
		my $query = "select $keyname from $table order by $keyname";
#::logDebug("list_keys: query=$query");
		$keys = $db->query(
						{
							query => $query,
							ml => $::Variable->{UI_ACCESS_KEY_LIMIT} || 500,
							st => 'db',
						}
					);
		if(defined $keys) {
			@keys = map {$_->[0]} @$keys;
		}
		else {
			my $k;
			while (($k) = $db->each_record()) {
				push(@keys, $k);
			}
			if( $db->numeric($db->config('KEY')) ) {
				@keys = sort { $a <=> $b } @keys;
			}
			else {
				@keys = sort @keys;
			}
		}
#::logDebug("list_keys: query=returned " . ::uneval(\@keys));
	}
	if($acl) {
#::logDebug("list_keys acl: ". ::uneval($acl));
		@keys = UI::Primitive::ui_acl_grep( $acl, 'keys', @keys);
	}
	my $joiner = $opt->{joiner} || "\n";
	return join($joiner, @keys);
}

sub list_tables {
	my $opt = shift;
	my @dbs;
	my $d = $Vend::Cfg->{Database};
	@dbs = sort keys %$d;
	my @outdb;
	my $record =  ui_acl_enabled();
	undef $record
		unless ref($record)
			   and $record->{yes_tables} || $record->{no_tables};

	for(@dbs) {
		next if $::Values->{ui_tables_to_hide} =~ /\b$_\b/;
		if($record) {
			next if $record->{no_tables}
				and ui_check_acl($_, $record->{no_tables});
			next if $record->{yes_tables}
				and ! ui_check_acl($_, $record->{yes_tables});
		}
		push @outdb, $_;
	}

	@dbs = $opt->{nohide} ? (@dbs) : (@outdb);
	$opt->{joiner} = " " if ! $opt->{joiner};
	
	my $string = join $opt->{joiner}, grep /\S/, @dbs;
	if(defined $::Values->{mv_data_table}) {
		return $string unless $d->{$::Values->{mv_data_table}};
		my $size = -s $Vend::Cfg->{ProductDir} .
						"/" .  $d->{$::Values->{mv_data_table}}{'file'};
		$size = 3_000_000 if $size < 1;
		$::Values->{ui_too_large} = $size > 100_000 ? 1 : '';
		$::Values->{ui_way_too_large} = $size > 2_000_000 ? 1 : '';
		local($_) = $::Values->{mv_data_table};
		$::Values->{ui_rotate_spread} = $::Values->{ui_tables_to_rotate} =~ /\b$_\b/;
	}
	return $string;
}

sub list_images {
	my ($base) = @_;
	return undef unless -d $base;
	my $suf = '\.(GIF|gif|JPG|JPEG|jpg|jpeg|png|PNG)';
	my @names;
	my $wanted = sub {
					return undef unless -f $_;
					return undef unless /$suf$/o;
					my $n = $File::Find::name;
					$n =~ s:^$base/?::;
					push(@names, $n);
				};
	find($wanted, $base);
	return sort @names;
}

sub list_glob {
	my($spec, $prefix) = @_;
	my $globspec = $spec;
	if($prefix) {
		$globspec =~ s:^\s+::;
		$globspec =~ s:\s+$::;
		$globspec =~ s:^:$prefix:;
		$globspec =~ s:\s+: $prefix:g;
	}
	my @files = glob($globspec);
	if($prefix) {
		@files = map { s:^$prefix::; $_ } @files;
	}
	return @files;
}

sub list_pages {
	my ($keep, $suf, $base) = @_;
	$suf = $Vend::Cfg->{StaticSuffix} if ! $suf;
	$base = Vend::Util::catfile($Vend::Cfg->{VendRoot}, $base) if $base;
	$base = $Vend::Cfg->{PageDir} if ! $base;
	my @names;
	my $wanted = sub {
					if(-d $_ and $Vend::Cfg->{AdminPage}{$_}) {
						$File::Find::prune = 1;
						return;
					}
					return undef unless -f $_;
					return undef unless /$suf$/;
					my $n = $File::Find::name;
					$n =~ s:^$base/?::;
					$n =~ s/$suf$// unless $keep;
					push(@names, $n);
				};
	find($wanted, $base);
	return sort @names;
}

my %Break = (
				'variable'   => 1,
				'subroutine' => 1,

);

my %Format_routine;

sub rotate {
	my($base, $options) = @_;

	$base = 'catalog.cfg' unless $base;

	if(! $options) {
		$options = {};
	}
	elsif (! ref $options) {
		$options = {Motion => 'unsave'};
	}


	my $dir = '.';

	if( $options->{Directory} ) {
		$dir = $options->{Directory};
	}

	if ($base =~ s:(.*)/:: ) {
		$dir .= "/$1";
	}

	my $motion = $options->{Motion} || 'save';

#::logDebug( "rotate $base with options dir=$dir motion=$motion from >> " . ::uneval($options));

	$dir =~ s:/+$::;

	if("\L$motion" eq 'save' and ! -f "$dir/$base+") {
			require File::Copy;
			File::Copy::copy("$dir/$base", "$dir/$base+")
				or die "copy $dir/$base to $dir/$base+: $!\n";
	}

	opendir(forwardDIR, $dir) || die "opendir $dir: $!\n";
	my @files;
	@files = grep /^$base/, readdir forwardDIR;
	my @forward;
	my @backward;
	my $add = '-';

	if("\L$motion" eq 'save') {
		@backward = grep s:^($base\++):$dir/$1:, @files;
		@forward = grep s:^($base-+):$dir/$1:, @files;
	}
	elsif("\L$motion" eq 'unsave') {
		return 0 unless -f "$dir/$base-";
		@forward = grep s:^($base\++):$dir/$1:, @files;
		@backward = grep s:^($base-+):$dir/$1:, @files;
		$add = '+';
	}
	else { 
		die "Bad motion: $motion";
	}

	$base = "$dir/$base";

#::logDebug( "rotate $base with options dir=$dir motion=$motion from >> " . ::uneval($options));

	my $base_exists = -f $base;
	push @forward, $base if $base_exists;

	for(reverse sort @forward) {
		next unless -f $_;
		rename $_, $_ . $add or die "rename $_ => $_+: $!\n";
	}

	#return 1 unless $base_exists && @backward;

	@backward = sort @backward;

	unshift @backward, $base;
	my $i;
	for($i = 0; $i < $#backward; $i++) {
		rename $backward[$i+1], $backward[$i]
			or die "rename $backward[$i+1] => $backward[$i]: $!\n";
	}

	if($options->{Touch}) {
		my $now = time();
		utime $now, $now, $base;
	}
	return 1;
}

my @t = localtime();

my (@years) = ( $t[5] + 1899 .. $t[5] + 1910 );
my (@months);
my (@days);

for(1 .. 12) {
	$t[4] = $_ - 1;
	push @months, [sprintf("%02d", $_), POSIX::strftime("%B", @t)];
}

for(1 .. 31) {
	push @days, [sprintf("%02d", $_), $_];
}

sub date_widget {
	my($name, $val) = @_;
	if($val =~ /\D/) {
		$val = Vend::Interpolate::filter_value('date_change', $val);
	}
	@t = localtime();
	$val = POSIX::strftime("%Y%m%d", @t) if not $val;
	my $sel = 0;
	my $out = qq{<SELECT NAME="$name">};
	my $o;
	for(@months) {
		$o = qq{<OPTION VALUE="$_->[0]">$_->[1]};
		($out .= $o, next) unless ! $sel and $val;
		$o =~ s/>/ SELECTED>/ && $sel++
			if substr($val, 4, 2) eq $_->[0];
		$out .= $o;
	}
	$sel = 0;
	$out .= qq{</SELECT>};
	$out .= qq{<INPUT TYPE=hidden NAME="$name" VALUE="/">};
	$out .= qq{<SELECT NAME="$name">};
	for(@days) {
		$o = qq{<OPTION VALUE="$_->[0]">$_->[1]};
		($out .= $o, next) unless ! $sel and $val;
		$o =~ s/>/ SELECTED>/ && $sel++
			if substr($val, 6, 2) eq $_->[0];
		$out .= $o;
	}
	$sel = 0;
	$out .= qq{</SELECT>};
	$out .= qq{<INPUT TYPE=hidden NAME="$name" VALUE="/">};
	$out .= qq{<SELECT NAME="$name">};
	for(@years) {
		$o = qq{<OPTION>$_};
		($out .= $o, next) unless ! $sel and $val;
		$o =~ s/>/ SELECTED>/ && $sel++
			if substr($val, 0, 4) eq $_;
		$out .= $o;
	}
	$out .= qq{</SELECT>};
}

my $base_entry_value;

sub meta_display {
	my ($table,$column,$key,$value,$meta_db,$query,$o) = @_;

#::logDebug("metadisplay: t=$table c=$column k=$key v=$value md=$meta_db");
	my $metakey;
	$meta_db = $::Variable->{UI_META_TABLE} || 'mv_metadata' if ! $meta_db;
	$o = {} if ! $o;
#::logDebug("metadisplay: t=$table c=$column k=$key v=$value opt=" . ::uneval_it($o));
	my $meta = Vend::Data::database_exists_ref($meta_db)
		or return undef;
	$meta = $meta->ref();
	if($column eq $meta->config('KEY')) {
		$base_entry_value = $value;
	}
#::logDebug("metadisplay: got meta ref=$meta");
	my $tag = '';
	if($o->{arbitrary}) {
		$tag = "$o->{arbitrary}::";
	}
	my (@tries) = "$tag${table}::$column";
	if($key) {
		# Don't think we need table::key combo anymore....
		# unshift @tries, "$tag${table}::${column}::$key", "$tag${table}::$key";
		unshift @tries, "$tag${table}::${column}::$key";
	}
	if($tag and $o->{fallback}) {
		push @tries, "${table}::${column}::$key", "${table}::${column}";
	}

	my $sess = $Vend::Session->{mv_metadata} || {};
	for $metakey (@tries) {
#::logDebug("enter metadisplay record $metakey");
		my $record;
		unless ( $record = $sess->{$metakey} and ref $record ) {
			next unless $meta->record_exists($metakey);
			$record = $meta->row_hash($metakey);
		}
		if($query) {
			return $record->{query};
		}
#::logDebug("metadisplay record: " . Vend::Util::uneval_it($record));
		my $opt;
		if($record->{options} and $record->{options} =~ /^[\w:]+$/) {
			PASS: {
				my $passed = $record->{options};
::logDebug("passed = '$passed'");

				if($passed eq 'tables') {
					$record->{passed} = list_tables({ joiner => ',' });
				}
				elsif($passed =~ /^columns(::(\w*))?$/) {
					my $total = $1;
					my $tname = $2 || $record->{db} || $table;
					$tname = $base_entry_value if $total eq '::';
::logDebug("tname=$tname total=$total");
					my $db = $Vend::Database{$tname};
					$record->{passed} = join (',', $db->columns())
						if $db;
				}
				elsif($passed =~ /^keys(::(\w+))?$/) {
					my $tname = $2 || $record->{db} || $table;
					$record->{passed} = list_keys($tname, { joiner => ',' });
				}
			}
		}
		if($record->{pre_filter}) {
			$value = Vend::Interpolate::filter_value($record->{pre_filter}, $value);
		}
		if($record->{lookup}) {
			my $fld = $record->{field} || $record->{lookup};
			my $key = $record->{lookup};
			LOOK: {
				my $dbname = $record->{db} || $table;
				my $db = Vend::Data::database_exists_ref($dbname);
				last LOOK unless $db;
				my $query = "select DISTINCT $key, $fld FROM $dbname ORDER BY $fld";
				my $ary = $db->query($query);
				last LOOK unless ref($ary);
				if(! scalar @$ary) {
					push @$ary, ["=--no current values--"];
				}
				undef $record->{type} unless $record->{type} =~ /multi|combo/;
				my $sub;
				if($record->{lookup_exclude}) {
					eval {
						$sub = sub { $_[0] !~ m{$record->{lookup_exclude}}o };
					};
					if ($@) {
						::logError(errmsg(
										"Bad lookup pattern m{%s}: %s",
										$record->{exclude},
										$@,
									));
						$sub = \&CORE::length;
					}
				}
				$sub = sub { length(@_) } if ! $sub;
				$record->{passed} = join ",", grep $sub->($_),
									map
										{ $_->[1] =~ s/,/&#44;/g; $_->[0] . "=" . $_->[1]}
									@$ary;
				$record->{passed} = "=--no current values--"
					if ! $record->{passed};
			}
		}
		elsif ($record->{type} eq 'date') {
			my $w = date_widget($column, $value);
			$w .= qq{<INPUT TYPE=hidden NAME="ui_filter:$column" VALUE="date_change">};
			return $w unless $o->{template};
			return ($w, $record->{label}, $record->{help}, $record->{help_url});
		}
		elsif ($record->{type} eq 'imagedir') {
			my $dir = $record->{'outboard'} || $column;
			my @files = list_images($dir);
			$record->{type} = 'combo';
			$record->{passed} = join ",",
									map { s/,/&#44;/g; $_} @files;
			$record->{append} = Vend::Util::resolve_links($record->{append})
				and $record->{append} =~ s/_UI_VALUE_/$value/g
				and $record->{append} =~ s/_UI_TABLE_/$table/g
				and $record->{append} =~ s/_UI_COLUMN_/$column/g
				and $record->{append} =~ s/_UI_KEY_/$key/g
				if $record->{append};
			
			$record->{prepend} = Vend::Util::resolve_links($record->{prepend})
				and $record->{append} =~ s/_UI_VALUE_/$value/g
				and $record->{append} =~ s/_UI_TABLE_/$table/g
				and $record->{append} =~ s/_UI_COLUMN_/$column/g
				and $record->{append} =~ s/_UI_KEY_/$key/g
				if $record->{prepend};
		}

		if($record->{height}) {
			if($record->{type} =~ /multi/i) {
				$record->{type} = "MULTIPLE SIZE=$record->{height}";
			}
			elsif ($record->{type} =~ /textarea/i) {
				my $width = $record->{width} || 80;
				$record->{type} = "textarea_" . $record->{height} . '_' . $width;
			}
		}
		elsif ($record->{width}) {
			if($record->{type} =~ /textarea/) {
				$record->{type} = "textarea_2_" . $record->{width};
			}
			elsif($record->{type} =~ /text/) {
				$record->{type} = "text_$record->{width}";
			}
			elsif($record->{type} =~ /radio|check/) {
				$record->{type} =~ s/(left|right)[\s_]*\d*/$1 $record->{width}/;
			}
		}

		$opt = {
			attribute	=> ($record->{'attribute'}	|| $column),
			table		=> ($record->{'db'}			|| $meta_db),
			column		=> ($record->{'field'}		|| 'options'),
			name		=> ($o->{'name'} || $record->{'name'} || $column),
			outboard	=> ($record->{'outboard'}	|| $metakey),
			passed		=> ($record->{'passed'}		|| undef),
			type		=> ($record->{'type'}		|| undef),
			prepend		=> ($record->{'prepend'}	|| undef),
			append		=> ($record->{'append'}		|| undef),
		};
#::logDebug("going to display");
		my $w = Vend::Interpolate::tag_accessories(
				undef, undef, $opt, { $column => $value } );
		if($record->{filter}) {
			$w .= qq{<INPUT TYPE=hidden NAME="ui_filter:$column" VALUE="};
			$w .= $record->{filter};
			$w .= '">';
		}
#::logDebug("template=$o->{template}");
		return $w unless $o->{template};
#::logDebug("supposed to return template: " . ::uneval_it($record));
		return ($w, $record->{label}, $record->{help}, $record->{help_url});
	}
	return undef;
}

1;

__END__

