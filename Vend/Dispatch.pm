# Dispatch.pm: dispatch URL to page or handler
#
# $Id: Dispatch.pm,v 1.9 1995/10/30 19:52:20 amw Exp $
#
package Vend::Dispatch;

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

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(http dispatch specify_action vend_url interaction_error
             page_name display_page display_special_page
             report_error);

use strict;
use Vend::Directive qw(Dump_request Dump_session Default_page Page_URL
                       Display_errors);
require Vend::Http;
use Vend::Log;
use Vend::Page;
use Vend::Session;
use Vend::Uneval;

my $H;
sub http { $H; }

sub cgi_host {
    my ($host);

    $host = $H->Client_Hostname;
    $host = $H->Client_IP_Address unless (defined $host && $host ne '');
    $host = '' unless defined $host;
    $host;
}

sub cgi_user {
    my ($user);

    $user = $H->Authenticated_User;
    $user = $H->Client_Ident unless (defined $user && $user ne '');
    $user = '' unless defined $user;
    $user;
}


##

my $Debug;
my $date_logged;

sub dump_date {
    unless ($date_logged) {
        lock_log();
        log_error(localtime() . "\n");
        $date_logged = 1;
    }
}

my $request_logged;
my $request_path;
my $request_session_id;

sub dump_request {
    unless ($request_logged) {
        dump_date();
        log_error("Request: Path = '$request_path'; ".
                  "Session ID = ".
                  (defined($request_session_id) ? "'$request_session_id'"
                                                : "<not specified>").
                  "\n");
        $request_logged = 1;
    }
}

my $initial_session_logged;
my $initial_session;

sub dump_initial_session {
    unless ($initial_session_logged) {
        dump_date();
        log_error('Session '.session_id().': '.
                  uneval($initial_session)."\n");
        $initial_session_logged = 1;
    }
}

sub report_error {
    my ($msg) = @_;

    dump_request();
    dump_initial_session();
    log_error($msg);
}


##

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

sub log_warning {
    my $l = longmess($_[0], 1);
    print $l if $Debug;
    report_error($l);
}

sub expound_error {
    my $l = longmess($_[0], 1);
    print $l if $Debug;
    die $l;
}


## DISPATCH

# Parse the invoking URL and dispatch to the handling subroutine.

sub dispatch {
    my ($http, $debug) = @_;
    my ($query_string, $sessionid, @path, $action);
    my $abort = 0;

    $H = $http;

    $Debug = $debug;
    $date_logged = 0;
    $request_logged = 0;
    $initial_session_logged = 0;
    $Vend::Message = '';

    # @path = ();

    my $args = {};
    my $q = http()->Query;
    if (defined $q and $q ne '') {
        foreach (split(/&/, $q)) {
            if (m/^ (.*?) = (.*) $/x) {
                $args->{$1} = $2;
            }
        }
    }

    $request_path = http()->Path_Info;
    $request_path = '' unless defined $request_path;
    $request_session_id = $sessionid = $args->{se};

    dump_request if Dump_request;

    if (defined $sessionid && $sessionid ne '') {
        open_session($sessionid, cgi_host(), cgi_user());
    } else {
        new_session(cgi_host(), cgi_user());
    }

    my $initial_session = Session;

    my $eval_error;
    {
        local $SIG{'__DIE__'} = \&expound_error;
        local $SIG{'__WARN__'} = \&log_warning;
        my $saved_eval_error = $@;
        eval {
            act($request_path, $args);
        };
        $eval_error = $@;
        $@ = $saved_eval_error;
    }

    if ($eval_error) {
        close_session(0);
        report_error($eval_error);
        if (not http()->response_made) {
            if (Display_errors) {
                http()->respond("text/plain", "$eval_error\n");
            }
            else {
                technical_difficulties();
            }
        }
        $abort = 1;
    }
    else {
        close_session(1);
        log_error('Session '.session_id().': '.
                  uneval($initial_session)."\n")
            if Dump_session;
    }

    log_error("\n") if $date_logged;
    unlock_log();
    undef $H;
    $abort;
}


my %Action_table = ();

sub act {
    my ($path, $args) = @_;

    $path =~ s!^/!!;

    if ($path eq '') {
        display_page(Default_page);
    }

    else {
        my ($act, $rest) = ($path =~ m!^ ([^\/]*) /? (.*) $!x);
        my $action = $Action_table{$act};
        if (defined $action) {
            &$action($act, $rest, $args);
        }
        else {
            display_page($path);
        }
    }
}

# # depreciated
# sub do_page {
#     my ($name) = @_;
# 
#     display_page($name)
#         and Session->{page} = $name;
# }

#     # If the cgi-bin program was invoked with no extra path info,
#     # just display the catalog page.
#     if (!@path) {
#         display_page(Default_page);
#     } else {
#         $action = shift @path;
#         run_action($action, $args, [@path])
#             or display_page(join('/', $action, @path));
#     }


## ACTIONS

sub specify_action {
    my ($action_name, $action_sub) = @_;

    $Action_table{$action_name} = $action_sub;
}

# sub run_action {
#     my $action = shift;
#     my $argument = shift;
#     my @path = @_;
# 
#     my $sub = $Action_table{$action};
#     if (defined $sub) {
# 	&$sub($action, $argument, @path);
# 	return 1;
#     } else {
# 	return 0;
#     }
# }


my $Current_page;

sub page_name {
    $Current_page;
}

## vend_url()

# Returns a URL which will run the ordering system again.  Each URL
# contains the session ID as well as a unique integer to avoid caching
# of pages by the browser.

sub vend_url {
    my ($path, $args) = @_;

    my %a = (defined $args ? %$args : ());
    $a{se} = session_id();
    $a{pg} = ++Session->{pageCount};
    my $a = join('&', map($_ . "=" . $a{$_}, keys %a));

    Page_URL() . "/" . $path . "?" . $a;
}


## INTERACTION ERROR

# An incorrect response was returned from the browser, either because of a
# browser bug or bad html pages.

sub interaction_error {
    my ($msg) = @_;

    report_error("Difficulty interacting with browser:\n$msg");
    display_special_page("interact", $msg);
}

# Page

sub _display_page {
    my ($name) = @_;

    my $code = page_code($name, $Debug);
    die "Missing page: $name\n" unless defined $code;
    $Current_page = $name;
    http()->respond("text/html", &$code());
}

sub display_special_page {
    my ($name, $message) = @_;

    $Vend::Message = $message;
    _display_page($name);
}

# Displays the catalog page NAME.  If the file is not found, displays
# the special page 'missing'.

sub display_page {
    my ($name) = @_;
    my ($text);

    if (defined page_code($name, $Debug)) {
        _display_page($name);
        return 1;
    }
    else {
        display_special_page('missing', $name);
        return 0;
    }
}

sub technical_difficulties {
    http->respond("text/html", <<'END');
<html><head><title>Technical Difficulties</title></head>

<body><h1>Technical Difficulties</h1>

We are sorry, but we are currently experiencing technical difficulties
and were unable to complete your request.

</body></html>
END
}

1;
