# Swish_search: search catalog pages using Swish program
#
# $Id: Swish_search.pm,v 1.2 1996/03/14 20:40:13 amw Exp $
#
package Vend::Swish_search;

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
@EXPORT = qw(swish_search);

use strict;
use Vend::Option_1 qw(combine defaults);
use Vend::Strip;

my $Options;

sub configure {
    my ($class, $config) = @_;

    $Options = combine($config,
                      qw(Data_directory Html_extension Stripped_directory Swish_index_file
                         Swish_conf_file Swish_program
                         Bin_directory Perl_program Vend_lib App_directory
                         Config_file));

    my $app = $Options->{App_directory} || '';
    my $data = $Options->{Data_directory} || '';

    defaults($Options,
             Html_extension => '.html',
             Stripped_directory => "$data/stripped",
             Swish_index_file => "$data/index.swish",
             Swish_conf_file => "$app/swish.conf",
             );
}

sub setup {
    make_index_program();
}

sub make_index_program {
    my $fn = $Options->{'Bin_directory'} . "/make_index";
    print "Creating $fn\n";
    open(OUT, ">$fn") or die "Can't create '$fn': $!\n";
    print OUT <<"END";
#!$Options->{'Perl_program'} -w

use lib '$Options->{'Vend_lib'}';
use Vend::Setup;

\$ENV{'PATH'} = '/bin:/usr/bin';
\$ENV{'SHELL'} = '/bin/sh';
\$ENV{'IFS'} = '';
srand(\$\$ ^ time());
umask 077;
chdir '$Options->{'App_directory'}';

require '$Options->{'Config_file'}';
initialize_modules();

Vend::Swish_search::create_swish_index();
exit 0;
END

    close(OUT);
    chmod 0700, $fn or die "Can't chmod '$fn': $!\n";
}


sub create_swish_index {
    write_stripped_pages($Options->{'Stripped_directory'},
                         $Options->{'Html_extension'});

    my $cmd = $Options->{'Swish_program'};
    $cmd .= " -c $Options->{'Swish_conf_file'}";
    $cmd .= " -i $Options->{'Stripped_directory'}";
    $cmd .= " -f $Options->{'Swish_index_file'}";
    xsystem($cmd);
}
    
sub xsystem {
    my ($cmd) = @_;

    print "$cmd\n";
    my $r = system($cmd);
}

sub swish_search {
    my ($words, $options, $callback) = @_;

    $options =
        combine($options,
                $Options,
                qw(Swish_tags Swish_index_file Swish_max_hits Swish_program
                   Stripped_directory Html_extension));

    my $args = "-w";
    while ($words =~ m/(\w+)/g) {
        $args .= " $1";
    }

    $args .= " -t " . $options->{'Swish_tags'} if defined $options->{'Swish_tags'};
    $args .= " -f " . $options->{'Swish_index_file'} if defined $options->{'Swish_index_file'};
    $args .= " -m " . $options->{'Swish_max_hits'} if defined $options->{'Swish_max_hits'};

    # my $result = [];
    die "Swish program '$options->{'Swish_program'}' is not executable\n"
        unless -x $options->{'Swish_program'};
    my $cmd = "$options->{'Swish_program'} $args";
    open(SWISH, "$cmd |")
        or die "Can't create pipe from swish: $!\n";
    local ($_, $.);
    my ($rank, $fn, $title, $size);
    while(<SWISH>) {
        if (m/^err: (.*)/) {
            return $1;
        }
        if (($rank, $fn, $title, $size) = m/^(\d+) (\S+) \"([^\"]+)\" (\d+)/) {
            $fn =~ s,^$options->{'Stripped_directory'}/,,;
            $fn =~ s,\Q$options->{'Html_extension'}\E$,,;
            &$callback($rank, $fn, $title, $size);
        }
    }
    close (SWISH);
    return '';
}

1;
