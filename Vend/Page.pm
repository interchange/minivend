# Page: stub for either Page_compiled or Page_simple
#
# $Id: Page.pm,v 1.2 1996/03/12 16:10:35 amw Exp $
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

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(define_placeholder escape_to_filename imprint_page page_code
             page_exists page_iterate strip_page);

use strict;

sub configure {
    my ($class, $config) = @_;
    my $implementation = $config->{'Implementation'};

    my $impl_module = $implementation;
    $impl_module =~ s,::,/,g;

    require "$impl_module.pm";
    # $implementation->import();
    really_configure($config);
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

    my $base = Page_directory() . "/" . join('/', @nelem);
    $base =~ s,/?$, '/' . Welcome_pagename(),e
        if -d follow_symbolic_links($base);
    return $base . Html_extension();
}


# Map from a filename back to the page name.

sub filename_to_name {
    my ($name) = @_;

    my $html = Html_extension();
    ($name =~ s/\Q$html\E$//o) or return undef;
    return join('/', map(unescape_from_filename($_), split(/\//, $name)));
}

my %Page_changed_date;

# Reads in a page from the page directory.  Returns the entire
# contents of the page, or undef if the file could not be read.

sub readin_page {
    my ($name) = @_;
    local($/, $.);

    my $fn = name_to_filename($name);
    my $contents;
    if (open(IN, $fn)) {
        $Page_changed_date{$name} = (stat(IN))[9];
	undef $/;
	$contents = <IN>;
	close(IN);
    } else {
	$contents = undef;
    }
    ($fn, $contents);
}

sub page_changed_date {
    my ($pagename) = @_;
    $Page_changed_date{$pagename};
}

sub follow_symbolic_links {
    my ($original_fn) = @_;
    my $fn = $original_fn;
    my ($m, $link, $i);

    my $i;
    while (-l $fn) {
        die "Too many symbolic links for '$original_fn'\n" if ++$i > 20;
        $link = readlink($fn);
        if (not defined $link) {
            $m = "Could not read symbolic link '$fn'";
            $m .= " (pointed to by '$original_fn')" if $fn ne $original_fn;
            die "$m: $!\n";
        }
        $fn = $link;
    }
    return $fn;
}

# sub file_type {
#     my ($original_fn) = @_;
#     my $fn = follow_symbolic_links($original_fn);
#     if    (-d $fn) { return 'd'; }
#     elsif (-f _)   { return 'f'; }
#     else           { return ''; }
# }


# List all the pages in all the subdirectories of the page directory.
# The $callback code ref is called for each page.  It is passed two
# arguments, the filename (including the complete path), and the page
# name.

sub page_iterate {
    my ($callback) = @_;
    recurse_pages(Page_directory(), $callback);
}

sub recurse_pages {
    my ($base, $callback, $dir) = @_;
    my ($fn, $name, $t, $destination);
    local (*DIR);

    my $d = (defined $dir ? "$base/$dir" : $base);
    opendir(DIR, $d) or die "Could not read directory '$d': $!\n";
    while ($fn = readdir(DIR)) {
        next if $fn =~ m/^\./;
        $destination = follow_symbolic_links("$d/$fn");
        # $t = file_type("$d/$fn");
        if (-d $destination) {
            recurse_pages($base, $callback, (defined $dir ? "$dir/$fn" : $fn));
        }
        elsif (-f _) {
            $name = filename_to_name(defined $dir ? "$dir/$fn" : $fn);
            next unless defined $name;
            &$callback("$d/$fn", $name);
            # (defined $dir ? "$base/$dir/$fn" : "$base/$fn")
        }
    }
    closedir(DIR);
}

1;
