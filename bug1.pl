#!/usr/bin/perl

# Demonstrates a bug I encounter where data is not stored in a DBM
# file when taintchecking is turned on.  This is using Perl version 5.000
# under Linux 1.0.9.
#
# You'll need to edit vend.pl and set $Config::VendRoot to this directory,
# and copy the sample files:
#         cp sample/pages/* pages
#         cp sample/products/* products
#         cp sample/report .
#
# When run, vend.pl will first display one of the catalog pages.  Then
# if the bug manifests, the last line printed will be "Data was not
# stored in DBM file".

$ENV{'SERVER_SOFTWARE'}='CERN/3.0pre3';
$ENV{'GATEWAY_INTERFACE'}='CGI/1.1';
$ENV{'REMOTE_ADDR'}='127.0.0.1';
$ENV{'REQUEST_METHOD'}='GET';
$ENV{'REMOTE_USER'}='';
$ENV{'QUERY_STRING'}='9FItsadK;;1';
$ENV{'HTTP_ACCEPT'}='www/source, text/plain, text/html, application/x-wais-source';
$ENV{'SERVER_NAME'}='amber';
$ENV{'SERVER_PORT'}='80';
$ENV{'PATH_TRANSLATED'}='/planets';
$ENV{'REMOTE_IDENT'}='amw';
$ENV{'SERVER_PROTOCOL'}='HTTP/1.0';
$ENV{'REMOTE_HOST'}='localhost';
$ENV{'HTTP_REFERER'}='http://localhost/order/';
$ENV{'HTTP_USER_AGENT'}='Lynx/2.2  libwww/2.14';
$ENV{'AUTH_TYPE'}='';
$ENV{'HTTP_FROM'}='';
$ENV{'SCRIPT_NAME'}='/amw/cgi-bin/order';
$ENV{'PATH_INFO'}='/planets';

exec("/usr/bin/perl -T vend.pl");
