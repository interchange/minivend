# Http.pm:  interface to cgi protocol
#
# $Id: Http.pm,v 1.9 1997/11/03 11:31:17 mike Exp $
#
package Vend::Http;

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

package Vend::Http::Base;
# abstract class

use strict;
use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.9 $, 10);

#sub Server                    { $_[0]->{'Server'} }
sub Content_Encoding          { $_[0]->{'Content_Encoding'} }
#sub Content_Language          { $_[0]->{'Content_Language'} }
sub Content_Transfer_Encoding { $_[0]->{'Content_Transfer_Encoding'} }
#sub Server_Software           { $_[0]->{'Server_Software'} }
#sub URI                      { $_[0]->{'URI'} }
sub Accept                    { $_[0]->{'Accept'} }
sub Accept_Charset            { $_[0]->{'Accept_Charset'} }
sub Accept_Encoding           { $_[0]->{'Accept_Encoding'} }
sub Accept_Language           { $_[0]->{'Accept_Language'} }
sub Allow                     { $_[0]->{'Allow'} }
sub Authenticated_User        { $_[0]->{'Authenticated_User'} }
sub Authorization             { $_[0]->{'Authorization'} }
sub Authorization_Type        { $_[0]->{'Authorization_Type'} }
sub Client_Hostname           { $_[0]->{'Client_Hostname'} }
sub Client_IP_Address         { $_[0]->{'Client_IP_Address'} }
sub Client_Ident              { $_[0]->{'Client_Ident'} }
sub Content_Length            { $_[0]->{'Content_Length'} }
sub Content_Type              { $_[0]->{'Content_Type'} }
sub Cookie                    { $_[0]->{'Cookie'} }
sub Date                      { $_[0]->{'Date'} }
sub Derived_From              { $_[0]->{'Derived_From'} }
sub Expires                   { $_[0]->{'Expires'} }
sub Forwarded                 { $_[0]->{'Forwarded'} }
sub From                      { $_[0]->{'From'} }
sub HTTP_Version              { $_[0]->{'HTTP_Version'} }
sub Https_on              	  { $_[0]->{'Https_on'} }
sub If_Modified_Since         { $_[0]->{'If_Modified_Since'} }
sub Last_Modified             { $_[0]->{'Last_Modified'} }
sub Link                      { $_[0]->{'Link'} }
sub Location                  { $_[0]->{'Location'} }
sub MIME_Version              { $_[0]->{'MIME_Version'} }
sub Message_ID                { $_[0]->{'Message_ID'} }
sub Method                    { $_[0]->{'Method'} }
sub Path_Info                 { $_[0]->{'Path_Info'} }
sub Path_Translated           { $_[0]->{'Path_Translated'} }
sub Pragma                    { $_[0]->{'Pragma'} }
sub Public                    { $_[0]->{'Public'} }
sub Query                     { $_[0]->{'Query'} }
sub Reason_Phrase             { $_[0]->{'Reason_Phrase'} }
sub Reconfigure               { $_[0]->{'Reconfigure'} }
sub Referer                   { $_[0]->{'Referer'} }
sub Request_URI               { $_[0]->{'Request_URI'} }
sub Retry_After               { $_[0]->{'Retry_After'} }
sub Script                	  { $_[0]->{'Script'} }
sub Server_Host               { $_[0]->{'Server_Host'} }
sub Server_Port               { $_[0]->{'Server_Port'} }
sub Status_Code               { $_[0]->{'Status_Code'} }
sub Title                     { $_[0]->{'Title'} }
sub URI				 		  { $_[0]->{'Server_Host'} . $_[0]->{'Script'} }
sub User_Agent                { $_[0]->{'User_Agent'} }
sub Version                   { $_[0]->{'Version'} }
sub WWW_Authenticate          { $_[0]->{'WWW_Authenticate'} }
sub no_cache                  { $_[0]->{'no_cache'} }

sub new {
    my ($class) = @_;
    bless {}, $class;
}

sub field {
    my ($s, $name) = @_;
    $s->{$name};
}

sub has_Entity {
    my ($s) = @_;

    $s->Content_Length > 0;
}

sub response_made {
    my ($s) = @_;
    $s->{'response_made'};
}


######################################################################
package Vend::Http::CGI;
@Vend::Http::CGI::ISA = qw(Vend::Http::Base);

use strict;

sub new {
    my ($class) = @_;
    my $http = new Vend::Http::Base;
    bless $http, $class;
}

my @Map =
    (
     'Authenticated_User' => 'REMOTE_USER',
     'Authorization_Type' => 'AUTH_TYPE',
     'Client_Hostname' => 'REMOTE_HOST',
     'Client_IP_Address' => 'REMOTE_ADDR',
     'Client_Ident' => 'REMOTE_IDENT',
     'Content_Length' => 'CONTENT_LENGTH',
     'Content_Type' => 'CONTENT_TYPE',
     'Cookie' => 'HTTP_COOKIE',
     'From' => 'HTTP_FROM',
     'Https_on' => 'HTTPS',
     'Method', => 'REQUEST_METHOD',
     'Path_Info' => 'PATH_INFO',
     'Path_Translated' => 'PATH_TRANSLATED',
     'Query' => 'QUERY_STRING',
     'Reconfigure' => 'RECONFIGURE_MINIVEND',
     'Referer' => 'HTTP_REFERER',
     'Script' => 'SCRIPT_NAME',
     'Server_Host' => 'SERVER_NAME',
     'Server_Port' => 'SERVER_PORT',
     'User_Agent' => 'HTTP_USER_AGENT',
     'Content_Encoding' => 'HTTP_CONTENT_ENCODING',
#     'Content_Language' => 'HTTP_CONTENT_LANGUAGE',
     'Content_Transfer_Encoding' => 'HTTP_CONTENT_TRANSFER_ENCODING',
#     'Server_Software' => 'SERVER_SOFTWARE',
# Accept
# Accept_Charset
# Accept_Encoding
# Accept_Language
# Allow
# Authorization
# Date
# Derived_From
# Expires
# Forwarded
# HTTP_Version
# If_Modified_Since
# Last_Modified
# Link
# Location
# MIME_Version
# Message_ID
# Pragma
# Reason_Phrase
# Referer
# Request_URI
# Status_Code
# Title
# URI
# Version
# no_cache

     );

sub populate {
    my ($s, $cgivar) = @_;

	if($Global::Environment) {
		for(@{$Global::Environment}) {
			$ENV{$_} = $cgivar->{$_} if defined $cgivar->{$_};
		}
	}   

    my @map = @Map;
    my ($field, $cgi);
    while (($field, $cgi) = splice(@map, 0, 2)) {
        $s->{$field} = $cgivar->{$cgi} if defined $cgivar->{$cgi};
    }
}

sub read_entity_body {
    my ($s) = @_;

    my $len = $s->Content_Length;
    die "The content length of the request entity is not specified\n"
        unless defined $len;
    my $entity = '';
    my $b = read(STDIN, $entity, $len);
    die "Could not read $len bytes from the HTTP server: $!\n"
        unless $b == $len;
    $entity;
}

#sub respond {
#   my ($s, $content_type, $body) = @_;
#
#	if (1 or $CGI::script_name =~ m:/nph-[^/]+$:) {
#		print "HTTP/1.1 200 OK\r\n";
#	}
#	print STDOUT
#		"Set-Cookie: MV_SESSION_ID=" . $Vend::SessionName . "; path=/\r\n"
#		if (! $CGI::cookie and $Vend::Cfg->{'Cookies'});
#    print STDOUT "Content-type: $content_type\r\n\r\n";
#    print STDOUT $body;
#    $s->{'response_made'} = 1;
#}

######################################################################
package Vend::form;

use strict;

sub unhexify {
    my($s) = @_;

    $s =~ s/%(..)/chr(hex($1))/ge;
    $s;
}

sub parse_form_input {
    my ($input) = @_;
    my ($pair, $key, $value, $aref);

    # From Tim Bunce's Base.pm read_entity_body():
    # Convert posted query string back into canonical form.
    # We have to deal with browsers which use CRLF, CR or LF.
    $input =~ s/\r?[\n\r]/&/mg;

    my $values = {};
    foreach $pair (split(/&/, $input)) {
	($key, $value) = ($pair =~ m/([^=]+)=(.*)/)
	    or die "Syntax error in post input:\n$pair\n";
	$key = unhexify($key);
	$value =~ s/\+/ /g;
	$value = unhexify($value);
        # from Tim Bunce's Request.pm
        $aref = $values->{$key} || ($values->{$key} = []);
	push @$aref, $value;
    }
    $values;
}

sub read_form_input {
    my ($s) = @_;

    if ($s->Method eq 'GET') {
        my $query = $s->Query;
        if (defined $query and $query ne '') {
            return $query;
        }
        else {
            die "No form input available\n";
        }
    }
    elsif ($s->Method eq 'POST') {
        if ($s->has_Entity) {
            return $s->read_entity_body();
        }
        else {
            die "No entity data for form input included with POST request\n";
        }
    }
    return undef;
}

1;
__END__
