#!/usr/bin/perl

# Copyright (C) 1998 Michael J. Heins <mikeh@minivend.com>

# Author: Michael J. Heins <mikeh@minivend.com>
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

Primitive.pm -- MiniMate Configuration Manager

=head1 SYNOPSIS

display_directive %options;

=head1 DESCRIPTION

The Minivend UI is an interface to configure and administer Minivend catalogs.

=cut

my $ui_safe = new Safe;
$ui_safe->untrap(@{$Global::SafeUntrap});

sub ui_acl_enabled {
	my $table;
	my $default = defined $Global::Variable->{MINIMATE_ACL}
				 ? (! $Global::Variable->{MINIMATE_ACL})
				 : 1;
	$table = $::Variable->{MINIMATE_TABLE} || 'minimate';
	$Vend::WriteDatabase{$table} = 1;
	my $db = Vend::Data::database_exists_ref($table);
	return $default unless $db;
	$db = $db->ref() unless $Vend::Interpolate::Db{$table};
	my $uid = $Vend::Session->{username} || $CGI::remote_user;
	if(! $db->record_exists($uid) ) {
		return 0;
	}
	$Vend::Session->{ui_username} = $uid;
	my $ref = $db->row_hash($uid)
		or die "Bad database record for $uid.";
#::logDebug("ACL enabled, table_control=$ref->{table_control}");
	if($ref->{table_control}) {
		$ref->{table_control_ref} = $ui_safe->reval($ref->{table_control});
	}
	$Vend::Minimate_entry = $ref;
}

sub get_ui_table_acl {
	my ($table, $user, $keys) = @_;
	$table = $::Values->{mv_data_table} unless $table;
#::logDebug("Call get_ui_table_acl: " . Vend::Util::uneval_it(\@_));
	my $acl_top;
	if($user and $user ne $Vend::Session->{ui_username}) {
		if ($Vend::Minimate_acl{$user}) {
			$acl_top = $Vend::Minimate_acl{$user};
		}
		else {
			my $ui_table = $::Variable->{MINIMATE_TABLE} || 'minimate';
			my $acl_txt = Vend::Interpolate::tag_data($ui_table, 'table_control', $user);
			return undef unless $acl_txt;
			$acl_top = $ui_safe->reval($acl_txt);
			return undef unless ref($acl_top);
		}
		$Vend::Minimate_acl{$user} = $acl_top;
		return keys %$acl_top if $keys;
		return $acl_top->{$table};
	}
	else {
		unless ($acl_top = $Vend::Minimate_entry) {
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
		my $u = $Vend::Session->{ui_username};
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

sub ui_check_acl {
	my ($item, $string) = @_;
	$string = " $string ";
	return 0 if $string =~ /[\s,]!$item[,\s]/;
	return 1 if $string =~ /[\s,]$item[,\s]/;
	return '';
}

sub ui_acl_global {
	my $record = ui_acl_enabled('write');
	# First we see if we have ACL enforcement enabled
	# If you don't, then people can do anything!
	unless (ref $record) {
		$::Scratch->{mv_data_enable} = $record;
		return;
	}
	my $CGI = \%CGI::values;
	my $Tag = new Vend::Tags;
	$CGI->{mv_todo} = $CGI->{mv_doit}
		if ! $CGI->{mv_todo};
    if( $CGI->{mv_todo} eq 'set' ) {
		undef $::Scratch->{mv_data_enable};
		my $mml_enable = $Tag->if_mm('functions', 'mml');
		my $html_enable = ! $Tag->if_mm('functions', 'no_html');
		my $target = $CGI->{mv_data_table};
		$Vend::WriteDatabase{$target} = 1;
		my $keyname = $CGI->{mv_data_key};
		my @codes = grep /\S/, split /\0/, $CGI->{$keyname};
		my @fields = grep /\S/, split /[,\s\0]+/, $CGI->{mv_data_fields};
		if ($Tag->if_mm('!edit', undef, { table => $target }, 1) ) {
			$::Scratch->{ui_failure} = "Unauthorized to edit table $target";
			$CGI->{mv_todo} = 'return';
			return;
		}
		for(@codes) {
			next if $Tag->if_mm('keys', $_, { table => $target }, 1);
			$CGI->{mv_todo} = 'return';
			$::Scratch->{ui_failure} = errmsg("Unauthorized for key %s", $_);
 			return;
  		}
		for(@fields) {
			$CGI->{$_} =~ s/\[/&#91;/g unless $mml_enable;
			$CGI->{$_} =~ s/\</&lt;/g unless $html_enable;
			next if $Tag->if_mm('columns', $_, { table => $target }, 1);
			$CGI->{mv_todo} = 'return';
			$::Scratch->{ui_failure} = errmsg("Unauthorized for key %s", $_);
 			return;
  		}
 		$::Scratch->{mv_data_enable} = 1;
	}
    return;

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

	my $dir = $options->{Directory} || '.';
	my $motion = $options->{Motion} || 'save';

	$dir =~ s:/+$::;

	opendir(forwardDIR, $dir) || die "opendir $dir: $!\n";
	my @files;
	@files = grep /^$base/, readdir forwardDIR;
	my @forward;
	my @backward;
	my $add = '-';

	if("\L$motion" eq 'save') {
		return 0 unless -f "$dir/$base+";
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

#::logGlobal( "rotate $base with options dir=$dir motion=$motion from >> " . Data::Dumper::Dumper($options));

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

sub meta_display {
	my ($table,$column,$key,$value,$meta_db) = @_;

#::logDebug("metadisplay: t=$table c=$column k=$key v=$value md=$meta_db");
	return undef if $key =~ /::/;

	my $metakey;
	$meta_db = $::Variable->{MINIMATE_META} || 'mv_metadata' if ! $meta_db;
#::logDebug("metadisplay: t=$table c=$column k=$key v=$value md=$meta_db");
	my $meta = Vend::Data::database_exists_ref($meta_db)
		or return undef;
#::logDebug("metadisplay: got meta ref=$meta");
	my (@tries) = "${table}::$column";
	if($key) {
		unshift @tries, "${table}::${column}::$key", "${table}::$key";
	}
	for $metakey (@tries) {
#::logDebug("enter metadisplay record $metakey");
		next unless $meta->record_exists($metakey);
		$meta = $meta->ref();
		my $record = $meta->row_hash($metakey);
#::logDebug("metadisplay record: " . Vend::Util::uneval_it($record));
		my $opt;
		if($record->{lookup}) {
			my $fld = $record->{field} || $record->{lookup};
#::logDebug("metadisplay lookup");
			LOOK: {
				my $dbname = $record->{db} || $table;
				my $db = Vend::Data::database_exists_ref($dbname);
				last LOOK unless $db;
				my $query = "select DISTINCT $fld FROM $dbname ORDER BY $fld";
#::logDebug("metadisplay lookup, query=$query");
				my $ary = $db->query($query);
				last LOOK unless ref($ary) && @{$ary};
#::logDebug("metadisplay lookup, query succeeded");
				undef $record->{type} unless $record->{type} =~ /multi|combo/;
				$record->{passed} = join ",",
									map
										{ $_->[0] =~ s/,/&#44;/g; $_->[0]}
									@$ary;
#::logDebug("metadisplay lookup, passed=$record->{passed}");
			}
		}
		elsif ($record->{type} eq 'imagedir') {
			my $dir = $record->{'db'} || 'images';
			my @files = list_images($dir);
			$record->{type} = 'combo';
			$record->{passed} = join ",",
									map { s/,/&#44;/g; $_} @files;
		}
		$opt = {
			attribute	=> ($record->{'attribute'}	|| $column),
			table		=> ($record->{'db'}			|| $meta_db),
			column		=> ($record->{'field'}		|| 'options'),
			name		=> ($record->{'name'}		|| $column),
			outboard	=> ($record->{'outboard'}	|| $metakey),
			passed		=> ($record->{'passed'}		|| undef),
			type		=> ($record->{'type'}		|| undef),
		};
		my $o = Vend::Interpolate::tag_accessories(
				undef, undef, $opt, { $column => $value } );
		if($record->{filter}) {
			$o .= qq{<INPUT TYPE=hidden NAME="ui_filter:$column" VALUE="};
			$o .= $record->{filter};
			$o .= '">';
		}
		return $o;
	}
	return undef;
}

1;

__END__

