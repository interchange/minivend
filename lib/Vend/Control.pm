# Rare.pm - MiniVend routines rarely used or not requiring much performance
# 
# $Id$
#
# Copyright 1996-2000 by Michael J. Heins <mikeh@minivend.com>
#
# This program was originally based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
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
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA.

package Vend::Control;

require Exporter;
@ISA = qw/ Exporter /;
@EXPORT = qw/
				signal_reconfig
				signal_add
				signal_remove
				control_minivend
				change_catalog_directive
				change_global_directive
				remove_catalog
				add_catalog
				change_catalog_directive
				change_global_directive
/;

use strict;
use Vend::Util;

sub signal_reconfig {
	my (@cats) = @_;
	for(@cats) {
		my $ref = $Global::Catalog{$_}
			or die ::errmsg("Unknown catalog '%s'. Stopping.\n", $_);
		Vend::Util::writefile("$Global::ConfDir/reconfig", "$ref->{script}\n");
	}
}

sub signal_remove {
	shift;
	$Vend::mode = 'reconfig';
	my $cat = shift;
	Vend::Util::writefile("$Global::ConfDir/restart", "remove catalog $cat\n");
	control_minivend('remove', 'HUP');
}

sub signal_add {
	$Vend::mode = 'reconfig';
	Vend::Util::writefile("$Global::ConfDir/restart", <>);
	control_minivend('add', 'HUP');
}

sub control_minivend {
	my ($mode, $sig, $restart) = @_;

	unless(-f $Global::PIDfile) {
		warn errmsg(
			"The Minivend server was not running (%s).\n",
			$Global::PIDfile,
			) unless $Vend::Quiet;
		exit 1 unless $restart;
		return;
	}
	Vend::Server::open_pid()
		or die errmsg(
				"Couldn't open PID file %s: %s\n",
				$Global::PIDfile,
				$!,
				);
	my $pid = Vend::Server::grab_pid();
	Vend::Server::unlink_pid();
	if(! $pid) {
		warn errmsg(<<EOF);
The previous Minivend server was not running and probably
terminated with an error.
EOF
		return if $restart;
	}
	if(! $sig) {
		$sig = $mode ne 'kill' ? 'TERM' : 'KILL';
	}
	print "Killing Minivend server $pid with $sig.\n"
		unless $Vend::Quiet;
	kill $sig, $pid
		or die errmsg("MiniVend server would not stop.\n");
	exit 0 unless $restart;
}

sub change_catalog_directive {
	my($cat, $line) = @_;
	$line =~ s/^\s+//;
	my($dir,$val) = split /\s+/, $line, 2;
	my $ref = Vend::Config::set_directive($dir,$val);
	die "Bad directive '$line'.\n" unless defined $ref;
	$cat->{$ref->[0]} = $ref->[1];
	return 1;
}

sub change_global_directive {
	my($line) = @_;
	chomp $line;
	$line =~ s/^\s+//;
	my($dir,$val) = split /\s+/, $line, 2;
	my $ref = Vend::Config::set_directive($dir,$val,1);
	die "Bad directive '$line'.\n" unless defined $ref;
	no strict 'refs';
	${"Global::" . $ref->[0]} = $ref->[1];
	$Global::Structure->{$ref->[0]} = $ref->[1]
		if $Global::DumpStructure;

	dump_structure($Global::Structure, $Global::ConfigFile)
		if $Global::DumpStructure;
	return 1;
}

sub remove_catalog {
	my($name) = @_;
	my $g = $Global::Catalog{$name};
	my @aliases;

	unless(defined $g) {
		::logGlobal( "Attempt to remove non-existant catalog %s." , $name );
		return undef;
	}

	if($g->{alias}) {
		@aliases = @{$g->{alias}};
	}

	for(@aliases) {
		delete $Global::Selector{$_};
		delete $Global::SelectorAlias{$_};
	}
	
	delete $Global::Selector{$g->{script}};
	delete $Global::Catalog{$name};
	logGlobal("Removed catalog %s (%s)", $name, $g->{script});
}


sub add_catalog {
	my($line) = @_;
	$line =~ s/^\s+//;
	my ($var, $name, $val) = split /\s+/, $line, 3;
	Vend::Config::parse_catalog($var,"$name $val")
		or die "Bad catalog line '$line'\n";

	my $g = $Global::Catalog{$name}
				or die "Catalog '$name' not parsed.\n";

	my $c = $Global::Selector{$g->{script}}			||
			$Global::SelectorAlias{$g->{script}}	||
			{};

	$c->{CatalogName} = $name;

	my $dir = $g->{'dir'};
	my $script = $g->{'script'};

	if(defined $g->{'alias'}) {
		for(@{$g->{alias}}) {
			if (exists $Global::Selector{$_}
				and $Global::SelectorAlias{$_} ne $g->{'script'})
			{
				logGlobal("Alias %s used a second time, skipping.", $_);
				next;
			}
			elsif (m![^\w-_\~:#/.]!) {
				logGlobal( "Bad alias %s, skipping.", $_,);
			}
			$Global::Selector{$_} = $c;
			$Global::SelectorAlias{$_} = $g->{'script'};
		}
	}

	Vend::Util::writefile("$Global::ConfDir/reconfig", "$script\n");
	my $msg = <<EOF;
Added/changed catalog %s:

 Directory: %s
 Script:    %s
EOF
	
	logGlobal( $msg, $name, $dir, $script);

	$Global::Selector{$g->{script}} = $c;
}

sub change_catalog_directive {
	my($cat, $line) = @_;
	$line =~ s/^\s+//;
	my($dir,$val) = split /\s+/, $line, 2;
	my $ref = Vend::Config::set_directive($dir,$val);
	die "Bad directive '$line'.\n" unless defined $ref;
	$cat->{$ref->[0]} = $ref->[1];
	return 1;
}

sub change_global_directive {
	my($line) = @_;
	chomp $line;
	$line =~ s/^\s+//;
	my($dir,$val) = split /\s+/, $line, 2;
	my $ref = Vend::Config::set_directive($dir,$val,1);
	die "Bad directive '$line'.\n" unless defined $ref;
	no strict 'refs';
	${"Global::" . $ref->[0]} = $ref->[1];
	$Global::Structure->{$ref->[0]} = $ref->[1]
		if $Global::DumpStructure;

	dump_structure($Global::Structure, $Global::ConfigFile)
		if $Global::DumpStructure;
	return 1;
}

1;
