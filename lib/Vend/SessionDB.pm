# SessionFile.pm:  stores session information in files
#
# $Id: SessionDB.pm,v 1.2 1998/05/02 03:05:20 mike Exp $
#
# Copyright 1996 by Andrew M. Wilcox <awilcox@world.std.com>
# Copyright 1996-1998 by Michael J. Heins <mikeh@iac.net>
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


# $Id: SessionDB.pm,v 1.2 1998/05/02 03:05:20 mike Exp $

package Vend::SessionDB;
require Tie::Hash;
@ISA = qw(Tie::Hash);

use strict;
use Vend::Util;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.2 $, 10);

my $SessionDB;
my $SessionLock;
my $Last;
my @Each;

sub TIEHASH {
	my($self, $db) = @_;
	$db = Vend::Data::database_exists_ref($db);
	$db = $db->ref();
#::logGlobal("$self: tied");
	die "Vend::SessionDB: bad database\n"
		unless $db;
	
	bless { DB => $db }, $self;
}

sub FETCH {
	my($self, $key) = @_;
#::logGlobal("$self fetch: $key");
	return undef unless $self->{DB}->record_exists($key);
#::logGlobal("$self exists: $key");
	return $self->{DB}->field($key, 'sessionlock') if $key =~ s/^LOCK_//;
#::logGlobal("$self complex fetch: $key");
	my $data = $self->{DB}->field($key, 'session');
	return undef unless $data;
	return $data;
}

sub FIRSTKEY {
	my $self = shift;
	my $tmp = pop @{$self->{DB}};
	eval {
		$self->{DB}->config('DELIMITER');
	};
	push @{$self->{DB}}, $tmp if $@;
	return $self->{DB}->each_record();
}

sub NEXTKEY {
	return $_[0]->{DB}->each_record();
}

sub EXISTS {
	my($self,$key) = @_;
#::logGlobal("$self EXISTS check: $key");
	if ($key =~ s/^LOCK_//) {
		return undef unless $self->{DB}->record_exists($key);
		return undef unless $self->{DB}->field($key, 'sessionlock');
		return 1;
	}
	return undef unless $self->{DB}->record_exists($key);
	1;
}

sub DELETE {
	my($self,$key) = @_;
#::logGlobal("$self delete: $key");
	if($key =~ s/^LOCK_// ) {
		return undef unless $self->{DB}->record_exists($key);
		$self->{DB}->set_field($key,'sessionlock','');
		return 1;
	}
	$self->{DB}->delete_record($key);
}

sub STORE {
	my($self, $key, $val) = @_;
	my $locking = $key =~ s/^LOCK_//;
	$self->{DB}->set_row($key) unless $self->{DB}->record_exists($key);
	return $self->{DB}->set_field($key, 'sessionlock', $val) if $locking;
	$self->{DB}->set_field( $key, 'session', $val);
    return 1;
}
	
1;
__END__
