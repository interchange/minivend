# Startup.pm:  startup Vend program and process command line arguments
#
# $Id: Startup.pm,v 1.23 1996/01/30 23:34:55 amw Exp $
#
package Vend::Startup;

# Copyright 1995, 1996 by Andrew M. Wilcox <awilcox@maine.com>
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

use Fcntl;
use FileHandle;
use Getopt::Long;
use POSIX;
use strict;
use Vend::Directive
      qw(App App_directory App_program Data_directory Modules Phd_directory
         Perl_program Display_errors Read_permission Database
         Session_expire Write_permission);
use Vend::Dispatch;
require Vend::Http;
use Vend::lock;
use Vend::Log;
use Vend::Page;
use Vend::Require;
use Vend::Server;
use Vend::Session;
use Vend::Uneval;

my $Vend_version = "0.3.4";

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
               "debug")
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
    }
}


sub version {
    print "Vend version $Vend_version, Copyright 1995, 1996 Andrew M. Wilcox.\n";
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

my @Modules;

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

    @Modules = split(/\s+/, Modules);
    foreach (@Modules) {
        s!::!/!g;
        print "Loading $_\n" if ($Mode eq 'test');
        Require("$_.pm");
    }

    # read_config_file($config_file);

    run_module_setup_functions();

    read_phds(Phd_directory);
    read_templates(Phd_directory);

    if ($Mode eq 'test') {
        test_pages();
        exit 0;
    }

    if ($Mode eq 'cgi') {
        die;
        my $http = new Vend::Http::CGI;
        $http->populate(\%ENV);
        dispatch($http);
    }
    elsif ($Mode eq 'server')        { run_server($Vend::Startup::opt_debug) }
    elsif ($Mode eq 'expire')        { expire_sessions() }
    elsif ($Mode eq 'dump-sessions') { dump_sessions() }
    else {
        die "Unknown mode: $Mode\n";
    }
    exit 0;
}

sub run_module_setup_functions {
    no strict 'refs';
    my ($module, $function);
    foreach $module (@Modules) {
        $function = $module . "::setup";
        &$function() if defined &$function;
    }
}

sub run_module_init_functions {
    no strict 'refs';
    my ($module, $function);
    foreach $module (@Modules) {
        $function = $module . "::init";
        &$function() if defined &$function;
    }
}

my $Pid_file;

sub aquire_server_lock {
    $Pid_file = Data_directory . "/" . App . ".pid";
    open(PID, "+>>$Pid_file") or die "Couldn't open '$Pid_file': $!\n";
    autoflush PID 1;

    # server already running?
    unless (lockfile(\*PID, 1, 0)) {
        seek(PID, 0, 0) or die "Can't seek '$Pid_file': $!\n";
        my $pid = <PID> or die "Couldn't read '$Pid_file': $!\n";
        chomp $pid;
        kill('TERM', $pid)
            or die "Couldn't send signal to terminate process $pid: $!\n";
        print "Shutting down current Vend " . App . " server...\n";
        lockfile(\*PID, 1, 1);
    }

    {
        no strict 'subs';       # avoid Perl truncate bug
        truncate(PID, 0) or die "Can't truncate '$Pid_file': $!\n";
    }
    print PID "$$\n";
}


# sub grab_pid {
#     my $ok = lockfile(\*Vend::Server::Pid, 1, 0);
#     if (not $ok) {
#         chomp(my $pid = <Vend::Server::Pid>);
#         return $pid;
#     }
#     {
#         no strict 'subs';
#         truncate(Vend::Server::Pid, 0) or die "Couldn't truncate pid file: $!\n";
#     }
#     print Vend::Server::Pid $$, "\n";
#     return 0;
# }

# sub open_pid {
#     $Pid_file = Data_directory . "/" . App . ".pid";
#     open(Vend::Server::Pid, "+>>$Pid_file")
#         or die "Couldn't open '$Pid_file': $!\n";
#     seek(Vend::Server::Pid, 0, 0);
#     my $o = select(Vend::Server::Pid);
#     $| = 1;
#     {
#         no strict 'refs';
#         select($o);
#     }
# }

sub become_daemon {
    my ($pid1, $pid2);

    if ($pid1 = fork) {
        # parent
        wait;
        exit 0;
    }
    elsif (not defined $pid1) {
        # fork error
        print "Can't fork: $!\n";
        exit 1;
    }

    # child 1
    if ($pid2 = fork) {
        # child 1
        exit 0;
    }
    elsif (not defined $pid2) {
        print "child 1 can't fork: $!\n";
        exit 1;
    }

    # child 2
    sleep 1 until getppid == 1;
    setsid();
}


sub run_server {
    my ($debug) = @_;
    my $next;
    my $pid;

    if ($debug) {
        run_server_in_foreground();
    }
    else {
        run_daemon_server();
    }

    initialize_Session(Database,
                       Data_directory,
                       Session_expire,
                       $File_creation_mask);
    run_module_init_functions();

    my $next = server(Data_directory . "/socket", $debug);

    if (not $debug and $next eq 'reload') {
        log_error(localtime().
                  "\nServer restarting on signal HUP\n\n");
        system(Perl_program() . " " . App_program . " -server &");
    }
    exit 0;
}

sub run_server_in_foreground {
    aquire_server_lock();
    print "Vend ", App(), " server started (process id $$)\n";
}

sub run_daemon_server {
    # locks are not held across fork(), so we'll wait to shutdown the
    # old running server and lock the pid file after the fork.

    become_daemon();
    aquire_server_lock();

    print "Vend ", App(), " server started (process id $$)\n";

    open(STDOUT, ">&Vend::Log::ERROR");
    $| = 1;
    open(STDERR, ">&Vend::Log::ERROR");
    select(STDERR); $| = 1; select(STDOUT);
    close(STDIN);

    log_error(localtime()."\nServer running on pid $$\n\n");

    # fcntl(PID, F_SETFD, 1)
    #    or die "Can't fcntl close-on-exec flag for '$Pid_file': $!\n";
}

# sub restart_server {
#     open_pid();
#     my $pid = grab_pid();
#     if ($pid) {
#         log_error("Can't restart: another Vend server has already been started\n");
#         exit 1;
#     }
# 
#     log_error(localtime()."\nServer restarted with pid $$\n\n");
#     server($Socket_file);
# }


1;
