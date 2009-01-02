# SessionFile.pm:  stores session information in files
#
# $Id: SessionFile.pm,v 1.2 2000/03/28 04:27:22 mike Exp $
#
# Copyright 1996-2000 by Michael J. Heins <mikeh@minivend.com>
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
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA.


# $Id: SessionFile.pm,v 1.2 2000/03/28 04:27:22 mike Exp $

package Vend::SessionFile;
require Tie::Hash;
@ISA = qw(Tie::Hash);

use strict;
use Vend::Util;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.2 $, 10);

my $SessionDir;
my $SessionFile;
my $SessionLock;
my %HaveLock;
my $Last;
my @Each;

sub TIEHASH {
	my($self, $dir) = @_;
	die "Vend::SessionFile: directory name\n"
		unless $dir;
	$SessionDir = $dir;
	bless {}, $self;
}

sub keyname {
	return Vend::Util::get_filename(shift, 2, 1, $SessionDir);
}

sub FETCH {
	my($self, $key) = @_;
    $SessionFile = keyname($key);
    $SessionLock = $SessionFile . ".lock";
	return undef unless -f $SessionFile;
	my $str;
	unless ($HaveLock{$SessionFile} || $Global::Windows) {
		open(SESSIONLOCK, "+>>$SessionLock")
			or die "Can't open '$SessionLock': $!\n";
		lockfile(\*SESSIONLOCK, 1, 1)
			and $HaveLock{$SessionFile} = 1;
	}
	my $ref = Vend::Util::eval_file($SessionFile);
#::logDebug("retrieving from $SessionFile: " . ::uneval($ref));
	return $ref;
}

sub FIRSTKEY {
	my ($self) = @_;
	require File::Find
		or die "No standard Perl library File::Find!\n";
	@Each = ();
	File::Find::find( sub {
						return if ! -f $File::Find::name;
						return if $File::Find::name =~ /\.lock$/;
						push @Each, $File::Find::name;
					},
					$SessionDir,
	);
	&NEXTKEY;
}

sub NEXTKEY {
	my $key = shift @Each;
	my $last = $Last;
	$Last = $key;
	return $key;
}

sub EXISTS {
	return Vend::Util::exists_filename($_[1], 2, 1, $SessionDir);
}

sub DELETE {
	my($self,$key) = @_;
    my $filename = keyname($key);
	unlink $filename;
	return 1 if $Global::Windows;
    my $lockname = $filename . ".lock";
	unlink $lockname;
}

sub STORE {
	my($self, $key, $ref) = @_;
    $SessionFile = keyname($key);
    $SessionLock = $SessionFile . ".lock";
    unlink $SessionFile;
	unless ($HaveLock{$SessionFile} || $Global::Windows) {
		open(SESSIONLOCK, "+>>$SessionLock")
			or die "Can't open '$SessionLock': $!\n";
		lockfile(\*SESSIONLOCK, 1, 1)
			and $HaveLock{$SessionFile} = 1;
	}
#::logDebug("storing in $SessionFile: " . ::uneval($ref));
	Vend::Util::uneval_file($ref,$SessionFile);
}
	
sub DESTROY {
	my($self) = @_;
	close(SESSION);
	unlockfile(\*SESSIONLOCK);
	close(SESSIONLOCK);
	undef $self;
}

1;
__END__
