# Startup.pm:  startup Vend program and process command line arguments
#
# $Id: Startup.pm,v 1.21 1995/12/15 21:55:28 amw Exp $
#
package Vend::Startup;

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
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

use Getopt::Long;
use strict;
use Vend::Directive
      qw(App_directory Data_directory Modules Phd_directory
         Display_errors Read_permission Database
         Session_expire Write_permission);
use Vend::Dispatch;
require Vend::Http;
use Vend::Page;
use Vend::Require;
use Vend::Server;
use Vend::Session;
use Vend::Uneval;

my $Vend_version = "0.3.3";

my $Running_as_cgi_bin;
my $Mode;
my $File_creation_mask;
my $Umask;

## COMMAND LINE OPTIONS

# my $config_file = Config_file;

sub parse_options {
    GetOptions(# "config=s",
               "version",
               "help",
               "test",
               "expire",
               "dump-sessions",
               "server",
               "debug",
               "restart")
        or exit 1;

    # if ($Vend::Startup::opt_config) {
    #     $config_file = $Vend::Startup::opt_config;
    # }

    if ($Vend::Startup::opt_version) {
	version();
	exit 0;
    } elsif ($Vend::Startup::opt_help) {
	usage();
	exit 0;
    } elsif ($Vend::Startup::opt_test) {
	$Mode = 'test';
    } elsif ($Vend::Startup::opt_expire) {
	$Mode = 'expire';
    } elsif ($Vend::Startup::opt_dump_sessions) {
	$Mode = 'dump-sessions';
    } elsif ($Vend::Startup::opt_server) {
	$Mode = 'server';
    } elsif ($Vend::Startup::opt_restart) {
        $Mode = 'restart';
    }
}


sub version {
    print "Vend version $Vend_version, Copyright 1995 Andrew M. Wilcox.\n";
}

sub usage {
    version();
    print <<'END';

Vend is free software and you are welcome to distribute copies of it
under the terms of the GNU General Public License.  There is
absolutely no warranty for Vend; see the file COPYING for details.

Command line options:

     -test            report problems
     -version         display program version
     -expire          expire old sessions
END
}

## FILE PERMISSIONS

sub set_file_permissions {
    my ($r, $w, $p, $u);

    $r = Read_permission;
    if    ($r eq 'user')  { $p = 0400;   $u = 0277; }
    elsif ($r eq 'group') { $p = 0440;   $u = 0227; }
    elsif ($r eq 'world') { $p = 0444;   $u = 0222; }
    else                  { die "Invalid value ('$r') for Read_permission\n"; }

    $w = Write_permission;
    if    ($w eq 'user')  { $p += 0200;  $u &= 0577; }
    elsif ($w eq 'group') { $p += 0220;  $u &= 0557; }
    elsif ($w eq 'world') { $p += 0222;  $u &= 0555; }
    else                  { die "Invalid value ('$w') ".
                                "Write_permission\n"; }

    $File_creation_mask = $p;
    $Umask = $u;
}

# based on longmess() from Carp.pm

sub longmess {
    my ($mess, $i) = @_;
    ++$i;
    my ($pack,$file,$line,$sub);
    while (($pack,$file,$line,$sub) = caller($i++)) {
	$mess .= "    in $sub called from $file line $line\n";
    }
    $mess;
}

sub expound_error {
    my $l = longmess($_[0], 1);
    die $l;
}

sub startup {
    my ($initialize) = @_;

    local $SIG{'__DIE__'} = \&expound_error;

    # Were we called from an HTTPD server as a cgi-bin program?
    $Running_as_cgi_bin = defined($ENV{'GATEWAY_INTERFACE'});

    $ENV{'PATH'} = '/bin:/usr/bin';
    $ENV{'SHELL'} = '/bin/sh';
    $ENV{'IFS'} = '';
    srand($$ ^ time);           # (Thanks to Mike Stok)
    umask 077;

    undef $Mode;
    if ($Running_as_cgi_bin) { $Mode = 'cgi' }
    else                     { parse_options() }

    if (not defined $Mode) {
        print
"Hmm, since I don't seem to have been invoked as a cgi-bin program,\n",
"I'll assume I'm being run from the shell command line.\n\n";
        usage();
        exit 0;
    }

    set_file_permissions();
    chdir App_directory
        or die "Could not chdir to '".App_directory()."': $!\n";
    umask $Umask;

    # my $vdb_class = "Vdb_" . Database;
    # require "$vdb_class.pm";

    my @modules = split(/\s+/, Modules);
    foreach (@modules) {
        s!::!/!g;
        print "Loading $_\n" if ($Mode eq 'test');
        Require("$_.pm");
    }

    # read_config_file($config_file);

    {
        no strict 'refs';
        foreach (@modules) {
            &{$_."::init"}() if defined &{$_."::init"};
        }
    }

    read_phds(Phd_directory);
    read_templates(Phd_directory);

    if ($Mode eq 'test') {
        test_pages();
        exit 0;
    }

    initialize_Session(Database,
                       Data_directory,
                       Session_expire,
                       $File_creation_mask);

    if ($Mode eq 'cgi') {
        my $http = new Vend::Http::CGI;
        $http->populate(\%ENV);
        dispatch($http);
    }
    elsif ($Mode eq 'server')        { run_server($Vend::Startup::opt_debug) }
    elsif ($Mode eq 'restart')       { restart_server() }
    elsif ($Mode eq 'expire')        { expire_sessions() }
    elsif ($Mode eq 'dump-sessions') { dump_sessions() }
    else {
        die "Unknown mode: $Mode\n";
    }
    exit 0;
}

1;
