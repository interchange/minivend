# SessionFile.pm:  stores session information in files
#
# $Id: SessionFile.pm,v 1.3 1997/01/07 01:16:56 mike Exp $
#
# Copyright 1996 by Andrew M. Wilcox <awilcox@world.std.com>
# Copyright 1996 by Michael J. Heins <mikeh@iac.net>
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


# $Id: SessionFile.pm,v 1.3 1997/01/07 01:16:56 mike Exp $

package Vend::SessionFile;
require Tie::Hash;
@ISA = qw(Tie::Hash);

use strict;
use Vend::Util;

my $SessionDir;
my $SessionFile;
my $SessionLock;

sub TIEHASH {
	my($self, $dir) = @_;
	die "Vend::SessionFile: directory name\n"
		unless $dir;
	$SessionDir = $dir;
	bless {}, $self;
}

sub FETCH {
	my($self, $key) = @_;
    $SessionFile = $SessionDir . "/$key";
    $SessionLock = $SessionDir . "/LOCK_$key";
	my $str;
    open(SESSIONLOCK, "+>>$SessionLock")
        or die "Can't open '$SessionLock': $!\n";
    open(SESSION, "+>>$SessionFile")
        or die "Can't open '$SessionFile': $!\n";
    lockfile(\*SESSION, 1, 1);

    seek(SESSION, 0, 0) or die "Can't seek session: $!\n";
    while(<SESSION>) {
		$str .= $_;
	}
	#$self->{LEN} = length $str;
	return $str;
}

sub EXISTS {
	return -f "$SessionDir/$_[1]";
}

sub DELETE {
	my($self,$key);
    my $filename = $SessionDir . "/$key";
	unlink $filename;
}

sub STORE {
	my($self, $key, $val) = @_;
	close(SESSION);
    unlink $SessionFile;
    open(SESSION, "+>$SessionFile")
        or die "Can't open '$SessionFile': $!\n";
    #seek(SESSION, 0, 0) or die "Can't seek session: $!\n";
    #lockfile(\*SESSION, 1, 1);
	print SESSION $val;
}
	
sub DESTROY {
	my($self) = @_;
	unlockfile(\*SESSIONLOCK);
	close(SESSIONLOCK);
	close(SESSION);
	undef $self;
}

1;
