# Cgi: creates the "cgi" program that runs Vend as a cgi-bin program
#
# $Id: Cgi.pm,v 1.3 1996/03/14 22:35:57 amw Exp $
#
package Vend::Cgi;

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

use strict;
use Vend::Application;

my $Use_setuid_wrapper;

sub configure {
    my ($class, $config) = @_;
    $Use_setuid_wrapper = $config->{'Use_setuid_wrapper'};
}

sub setup {
    my $C = app_config();

    my $fn = $C->{'Bin_directory'} . "/cgi";
    print "Creating $fn\n";
    open(OUT, ">$fn") or die "Can't create '$fn': $!\n";

    print OUT <<"END";
#!$C->{'Perl_program'} -w

BEGIN {
   open(LOG, '>>$C->{'Error_log_file'}');
   print LOG '';
   open(STDERR, '>&LOG');
}

use lib '$C->{'Vend_lib'}';
use Vend::Setup;

\$ENV{'PATH'} = '/bin:/usr/bin';
\$ENV{'SHELL'} = '/bin/sh';
\$ENV{'IFS'} = '';
srand(\$\$ ^ time());
umask 077;
chdir '$C->{'App_directory'}';

require '$C->{'Config_file'}';
initialize_modules();

require Vend::Http;
my \$http = new Vend::Http::CGI;
\$http->populate(\\%ENV);
Vend::Dispatch::dispatch(\$http);
END

    close(OUT);
    chmod ($Use_setuid_wrapper ? 0755 : 04755), $fn
        or die "Can't chmod '$fn': $!\n";
}

1;
