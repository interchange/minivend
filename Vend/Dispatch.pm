# Dispatch.pm: dispatch URL to page or handler
#
# $Id: Dispatch.pm,v 1.10 1996/01/30 23:22:41 amw Exp $
#
package Vend::Dispatch;

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

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(http dispatch specify_action vend_url interaction_error
             page_name display_page display_special_page
             report_error);

use strict;
use Vend::Directive qw(Dump_request Default_page Page_URL
                       Display_errors);
require Vend::Http;
use Vend::Log;
use Vend::Page;
use Vend::Session;
use Vend::Uneval;

=head1 NAME

Vend::Dispatch - dispatches HTTP request

=head1 DESCRIPTION

The dispatch() function accepts a URL and dispatches to an action
function or displays the indicated catalog page.  

=cut

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

my ($Reports);

sub report {
    my ($message) = @_;
    $Reports .= $message;
}
sub report_error { report(@_) }


sub show_date {
    return localtime() . "\n";
}

sub show_initial_session {
    my ($initial_session) = @_;
    return 'Initial session ' . session_id() . ': '
           . uneval($initial_session) . "\n";
}

sub show_request {
    my ($request_path, $request_session_id) = @_;
    return "Request: Path = '$request_path'; "
           . "Session ID = "
           . (defined($request_session_id) ? "'$request_session_id'"
                                           : "undef")
           . "\n";
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


## DISPATCH

# Parse the invoking URL and dispatch to the handling subroutine.

sub dispatch {
    my ($http, $debug) = @_;
    my ($query_string, $sessionid, @path, $action);
    my $abort = 0;

    $H = $http;

    $Vend::Message = '';

    my $args = {};
    my $q = http()->Query;
    if (defined $q and $q ne '') {
        foreach (split(/&/, $q)) {
            if (m/^ (.*?) = (.*) $/x) {
                $args->{$1} = $2;
            }
        }
    }

    my $request_path = http()->Path_Info;
    $request_path = '' unless defined $request_path;
    my $request_session_id = $sessionid = $args->{se};

    if (defined $sessionid && $sessionid ne '') {
        open_session($sessionid, cgi_host(), cgi_user());
    } else {
        new_session(cgi_host(), cgi_user());
    }

    my $initial_session = Session;

    my ($error_traceback, @warnings, @warning_traceback, $eval_error);

    my $trace_error = sub {
        my ($msg) = @_;
        $error_traceback = longmess($msg, 1)
            unless $msg =~ m/^ABORT:/;
        die $msg;
    };

    my $trace_warning = sub {
        my ($msg) = @_;
        push @warnings, $msg;
        push @warning_traceback, longmess($msg, 1);
    };

    $Reports = '';

    {
        local $SIG{'__DIE__'} = $trace_error;
        local $SIG{'__WARN__'} = $trace_warning;
        my $saved_eval_error = $@;
        eval { act($request_path, $args) };
        $eval_error = $@;
        $@ = $saved_eval_error;
    }

    undef $eval_error if $eval_error =~ m/^ABORT:/;

    my $problem = $Reports || $eval_error || @warnings;

    my $report = '';
    if ($problem or Dump_request) {
        $report = show_date() . show_initial_session($initial_session)
                  . show_request($request_path, $request_session_id);
    }

    if ($problem) {
        $report .= $Reports if $Reports;
        print $Reports if $debug and $Reports;

        $report .= join('', @warnings) if @warnings;
        print join('', @warnings) if $debug and @warnings;

        $report .= $eval_error if $eval_error;
        print $eval_error if $debug and $eval_error;

    }

    if (Dump_request and not $eval_error) {
        $report .= "Final session " . session_id() . ": "
                   . uneval(Session) . "\n";
    }

    if ($eval_error or @warnings) {
        $report .= "\nTraceback information:\n";
        $report .= $error_traceback if $eval_error;
        $report .= join("\n", @warning_traceback) if @warnings;
    }

    log_error $report . "\n" if $report;

    if ($eval_error) {
        close_session(0);
        if (not http()->response_made) {
            if (Display_errors) {
                http()->respond("text/plain", $report);
            }
            else {
                technical_difficulties();
            }
        }
        $abort = 1;
    }
    else {
        close_session(1);
    }

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

    display_special_page("interact", $msg) unless http->response_made;
    die "Difficulty interacting with browser:\n$msg";
}

# Page

sub _display_page {
    my ($name) = @_;

    my $code = page_code($name);
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

    if (defined page_code($name)) {
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
