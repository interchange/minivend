# Page_simple.pm: simple substitution of placeholders in pages
#
# $Id: Page_simple.pm,v 1.2 1996/03/12 16:13:24 amw Exp $
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


my (%Placeholders, %N_args);

sub define_placeholder {
    my ($template, $coderef) = @_;
    my ($ph_name, @args) = ($template =~ m,([/\w\-]+),g);
    die "Couldn't parse placeholder name out of '$template'"
        unless defined $ph_name;
    $Placeholders{$ph_name} = $coderef;
    $N_args{$ph_name} = @args;
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

sub imprint_page {
    my ($page_name) = @_;

    return substitute_placeholders($page_name, \&fill_in_placeholder);
}


sub strip_page {
    my ($page_name) = @_;

    return substitute_placeholders($page_name, \&empty_string);
}

sub empty_string {
    return '';
}


sub substitute_placeholders {
    my ($page_name, $process_placeholder) = @_;

    ($Filename, $Text) = readin_page($page_name);
    die "Couldn't read page '$page_name'\n" unless defined $Text;

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
        if ($Text =~ m/\G \\ ([\000-\377]?) /gmx) {
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
                $value .= &$process_placeholder($1, $2, $p - 1);
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


sub fill_in_placeholder {
    my ($name, $arguments, $pos) = @_;

    my $coderef = $Placeholders{$name};
    parse_error("Undefined placeholder '$name'", $pos)
        unless defined $coderef;

    my $n = $N_args{$name};
    my @args = split(/\s+/, $arguments);
    parse_error("The '$name' placeholder takes $n argument" .
                  ($n == 1 ? '' : 's'),
                $pos)
        unless @args == $n;
    return &$coderef(@args);
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
