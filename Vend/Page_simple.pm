# Page_simple.pm: simple substitution of placeholders in pages
#
# $Id: Page_simple.pm,v 1.1 1996/02/26 21:41:18 amw Exp $
#
package Vend::Page;

# Copyright 1996 by Andrew M. Wilcox <awilcox@world.std.com>
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

#another possibility
#
# require Exporter;
# @ISA = qw(Exporter);
# @EXPORT = qw(page_code read_code define_placeholder);
# fool require into thinking we've actually loaded Vend::Page.
# $main::INC{'Vend/Page.pm'} = __FILE__;

use strict;
use Vend::Dispatch;

my $Config;

sub Html_extension   { $Config->{'Html_extension'} }
sub Page_directory   { $Config->{'Page_directory'} }
sub Welcome_pagename { $Config->{'Welcome_pagename'} }

sub really_configure {
    # my ($class, $config) = @_;
    my ($config) = @_;
    $Config = $config;
}

my $Ok_in_filename = 
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:-_.$';
my (@Translate_to_filename);

{
    my ($i);
    foreach $i (0..255) {
        $Translate_to_filename[$i] = '%' . sprintf("%02X", $i);
    }
}

sub escape_to_filename {
    my ($str) = @_;

    $str =~ s/([^\Q$Ok_in_filename\E])/$Translate_to_filename[ord($1)]/geo;
    # untaint since safe now
    $str =~ m/(.*)/;
    $1;
}

sub unescape_from_filename {
    my ($filename) = @_;

    $filename =~ s/%(..)/chr(hex($1))/ge;
    $filename;
}

# Map a page name to a filename.  Handle '..' by dropping the previous
# element of the pathname.  (A '..' that would reference something outside
# the page directory is silently ignored.)  Dangerous characters in the
# page name are escaped.

sub name_to_filename {
    my ($name) = @_;

    my ($elem, @nelem);
    foreach $elem (split(/\//, $name)) {
        if ($elem eq '..') {
            pop @nelem;
        }
        elsif ($elem eq '') {}
        else {
            push @nelem, escape_to_filename($elem);
        }
    }

    # return undef unless @nelem;

    my $base = Page_directory . "/" . join('/', @nelem);
    $base .= '/' . Welcome_pagename if -d $base;
    return $base . Html_extension;
}


# Reads in a page from the page directory.  Returns the entire
# contents of the page, or undef if the file could not be read.

sub readin_page {
    my ($name) = @_;
    local($/, $.);

    my $fn = name_to_filename($name);
    my $contents;
    if (open(IN, $fn)) {
        # $Page_changed_date{$name} = (stat(Vend::Page::IN))[9];
	undef $/;
	$contents = <IN>;
	close(IN);
    } else {
	$contents = undef;
    }
    ($fn, $contents);
}


my %Placeholders;

sub define_placeholder {
    my ($template, $coderef) = @_;
    my ($ph_name) = ($template =~ m#^ \[ ([/\w\-]+) #x);
    die "Couldn't parse placeholder name out of '$template'"
        unless defined $ph_name;
    $Placeholders{$ph_name} = $coderef;
}

sub page_exists {
    my ($page_name) = @_;
    return -f name_to_filename($page_name);
}

sub page_code {
    my ($pagename) = @_;

    return undef unless -f name_to_filename($pagename);
    return sub { read_page($pagename) };
}


# sub read_page {
#     my ($pagename) = @_;
#     local $_;
#     my $fn;
# 
#     ($fn, $_) = readin_page($pagename);
#     die "Couldn't read page '$pagename'\n" unless defined $fn;
# 
#     s! \[ \s* (/?[\w\.\-\_]+) \s* ([^\n\]]*) \] ! ph($1, $2, $fn) !egimx;
# 
#     return $_;
# }


my ($Filename, $Text);

sub read_page {
    my ($page_name) = @_;

    ($Filename, $Text) = readin_page($page_name);
    die "Couldn't read page '$page_name'\n" unless defined $Filename;

    my $p;
    my $value = '';

    for (;;) {
        $p = pos($Text);
        # pick up everything until next \ or [
        if ($Text =~ m/\G ([^\\\[]+) /gmx) {
            $value .= $1;
            next;
        }

        pos($Text) = $p;         # reset search, since last match failed
        # is it a "\" ?
        if ($Text =~ m/\G (\\[.\n]?) /gmx) {
            $value .= $1;
            next;
        }

        pos($Text) = $p;
        # is it a "[" ?
        if ($Text =~ m/\G \[ /gmx) {
            # ok, we want the closing ] on the same line
            # $1 will be the placeholder name, $2 all the arguments
            $p = pos($Text);
            if ($Text =~ m!\G [ \t]* (/?[\w\.\-\_]+) [ \t]* ([^\n\]]*) \] !gmx) {
                # whew
                $value .= ph($1, $2, $p - 1);
                next;
            }
            else {
                parse_error("Syntax error in placeholder", $p);
            }
        }
        
        last;
    }
    return $value;
}


sub ph {
    my ($name, $arguments, $pos) = @_;

    my $coderef = $Placeholders{$name};
    parse_error("Undefined placeholder '$name'", $pos)
        unless defined $coderef;

    return &$coderef(split(/\s+/, $arguments));
}


sub parse_error {
    my ($msg, $pos) = @_;
    $pos = 0 unless defined $pos;

    my $before = substr($Text, 0, $pos);
    my $linecnt = ($before =~ tr/\n//);
    my $linestart = rindex($before, "\n") + 1;
    my $lineend = index($Text, "\n", $linestart + 1);
    if ($lineend == -1) { $lineend = length($Text); }
    my $line = substr($Text, $linestart, $lineend - $linestart);
    my $posinline = $pos - $linestart;

    die "ABORT: $msg in line ". ($linecnt + 1) . " of '$Filename':\n" .
        "$line\n" . (" " x $posinline) . "^\n";
}

1;
