# Dispatch.pm: dispatch URL to page or handler
#
# $Id: Dispatch.pm,v 1.11 1996/02/26 21:28:31 amw Exp $
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
@EXPORT = qw(dispatch display_page display_special_page Dump_request http
             interaction_error page_name page_url register_action report
             report_error set_last_page specify_action vend_url);

use strict;
require Vend::Http;
use Vend::Page;
use Vend::Session;
use Vend::Uneval;

my $Config;

sub Display_errors { $Config->{'Display_errors'} }
sub Dump_request   { $Config->{'Dump_request'} }
sub Page_URL       { $Config->{'Page_URL'} }

sub configure {
    my ($class, $config) = @_;
    $Config = $config;
}

=head1 NAME

Vend::Dispatch - dispatches HTTP request

=head1 DESCRIPTION

Vend::Dispatch accepts a URL and determines what to do to make a
response.  If the first component of the URL path is the name of a
declared "action", the corresponding Perl subroutine is called to
handle the request.  Otherwise the the named catalog page is
displayed.

Errors and warnings are trapped during the processing of the request.
Either will generate a report in the error log file, including a
traceback of which functions were called before the error occurred.
Errors will cause a "technical difficulties" page to be displayed if
the Display_errors configuration directive is false.  The error
message will be returned to the browser if Display_errors is true.

Dispatch makes a number of functions available to inquire about the
request, and to generate a response.

=head1 FUNCTIONS

=head2 C<die($message)>

Calling Perl's die() function will terminate processing of the current
request and return to Vend::Dispatch.  The $message is saved in the
error log file, along with information about the request, the session,
and a traceback of called functions.  If a response has not yet been
made to the browser, then Vend::Dispatch will either display a technical
difficulties page (if Display_errors is false), or the error
information (if Display_errors is true).

=head2 C<warn($message)>

Calling Perl's warn() function will save the $message in the error log
file, along with information about the request, the session, and a
traceback of called functions.

=cut

my $Http_obj;

my $Reports;

=head2 C<report($message)>

Writes $message to the error log file, along with information about
the request and the session.  Similar to calling Perl's warn()
function, but does not generate a traceback of function calls.

=cut

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

    $Http_obj = $http;

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

    my ($error_traceback, @warnings, @warning_traceback, $eval_error,
        $abort_message);

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

    if ($eval_error =~ m/^ABORT: ([\000-\377]*)/m) {
        $abort_message = $1;
        undef $eval_error;
    }

    my $problem = $Reports || $eval_error || @warnings || $abort_message;

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

        $report .= $abort_message if $abort_message;
        print $abort_message if $debug and $abort_message;
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

    print main::LOG $report . "\n" if $report;

    if ($eval_error or $abort_message) {
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

    undef $Http_obj;
    $abort;
}


=head2 C<http()>

Returns the Vend::Http object for the request.  It can be queried for
HTTP fields passed by the browser, and for a passed entity if any.

=cut

sub http { $Http_obj; }

sub cgi_host {
    my ($host);

    $host = http()->Client_Hostname;
    $host = http()->Client_IP_Address unless (defined $host && $host ne '');
    $host = '' unless defined $host;
    $host;
}

sub cgi_user {
    my ($user);

    $user = http()->Authenticated_User;
    $user = http()->Client_Ident unless (defined $user && $user ne '');
    $user = '' unless defined $user;
    $user;
}


my $Last_page;

sub set_last_page {
    my ($lp) = @_;
    $Last_page = $lp;
}


my %Action_table = ();

sub act {
    my ($path, $args) = @_;

    $path =~ s,^/?,/,;

    my ($act, $rest) = ($path =~ m!^ / ([^/]*) /? (.*) $!x);
    my $action = $Action_table{$act};
    if (defined $action) {
        $Last_page = $args->{'lp'};
        $Last_page = '/' unless defined $Last_page;
        &$action($act, $rest, $args);
    }
    else {
        $Last_page = $path;
        display_page($path);
    }
}


=head2 C<register_action($action_name, $code_ref)>

Registers $action_name so that when a URL is requested that has that
name as the first component, the $code_ref will be called to handle
the request.

=cut

sub register_action {
    my ($action_name, $action_sub) = @_;

    $Action_table{$action_name} = $action_sub;
}


sub specify_action { register_action(@_) }



my $Current_page;

sub page_name {
    $Current_page;
}


=head2 vend_url($path, $args)

Returns a URL refering to $path in the catalog, along with the session
ID.  Additional arguments to include in the URL may be passed in a
hash ref through $args.

=cut

sub vend_url {
    my ($path, $args) = @_;

    $path =~ s,^/,,;
    $path =~ s,/$,,;

    my %a = (defined $args ? %$args : ());
    $a{'se'} = session_id();
    $a{'pg'} = ++Session->{pageCount};
    $a{'lp'} = $Last_page if defined $Last_page and not defined $a{'lp'};
    my $a = join('&', map($_ . "=" . $a{$_}, keys %a));

    Page_URL() . "/" . $path . "?" . $a;
}


=head2 C<page_url($path, [$args])>

Returns the URL which references the specified catalog page.  Names
that start with a "/" are absolute names, rooted in the
C<Page_directory> as defined in the configuration.  Names that don't
start with a "/" are relative to the current page being displayed.

Using a relative page name serves the same purpose as using a relative
URL in HTML.  The difference is that the location of the page is
determined by Vend instead of by the browser.  page_url() always
returns a fully qualified URL.

=cut

sub page_url {
    my ($page, $args) = @_;
    my ($path, $base);

    if (($path) = ($page =~ m!^/(.*)!)) {
        return vend_url($path, $args);
    }
    
    ($base) = (page_name() =~ m!^(.*)/!);
    if (defined $base) {
        return vend_url($base . "/" . $page, $args);
    } else {
        return vend_url($page, $args);
    }
}


=head2 interaction_error($message)

Call interaction_error() if you did not receive the response you
expected from the browser, such as missing form fields.  The
"interact" special page is displayed.  interaction_error() calls
die(), so it does not return.

=cut

sub interaction_error {
    my ($msg) = @_;

    display_special_page("interact", $msg) unless http->response_made;
    die "Difficulty interacting with browser:\n$msg";
}

# Page

sub _display_page {
    my ($name) = @_;

    $name =~ s,^/?,/,;
    $Current_page = $name;
    http()->respond("text/html", read_page($name));
}

sub display_special_page {
    my ($name, $message) = @_;

    $Vend::Message = $message;
    _display_page($name);
}


=head2 display_page($name)

Displays the catalog page $name.  If the file is not found, displays
the special page 'missing'.

=cut

sub display_page {
    my ($name) = @_;
    my ($text);

    if (page_exists($name)) {
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
