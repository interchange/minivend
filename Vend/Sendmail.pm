# Sendmail.pm:  sends an email message
#
# $Id: Sendmail.pm,v 1.7 1996/02/26 21:42:10 amw Exp $
#
package Vend::Sendmail;

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
@EXPORT = qw(send_mail);

use strict;

my $Config;
sub Sendmail_program { $Config->{'Sendmail_program'} }

sub configure {
    $Config = $_[1];
}

# Send a mail message to the email address TO, with subject SUBJECT, and
# message BODY.

sub send_mail {
    my($to, $subject, $body) = @_;
    my($ok);
    my $program = Sendmail_program;
    local ($!, $?);

    my $saved_eval_error = $@;
    eval {
	open(Sendmail::MAIL, "|$program $to")
            or die "Could not open pipe to $program: $!\n";
	print(Sendmail::MAIL "To: $to\n",
                             "Subject: $subject\n\n",
                             $body)
            or die "Could not write to pipe: $!\n";
	close(Sendmail::MAIL) or die "Could not close pipe: $!\n";
        if ($? != 0) {
            my $exit_value = $? >> 8;
            my $signal = $? & 255;
            die ($signal ? "$program died with signal $signal\n"
                         : "$program failed with error value $exit_value");
        }
    };
    my $eval_error = $@;
    $@ = $saved_eval_error;

    if ($eval_error) {
        warn "Unable to send mail using '$program' to '$to' with\n" .
             "subject '$subject':\n$eval_error";
        return 0;
    }
    return 1;
}

1;
