# Session.pm:  tracks session information between requests
#
# $Id: Session.pm,v 1.9 1996/02/01 23:08:07 amw Exp $
#
package Vend::Session;

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
@EXPORT = qw(Session Value
             initialize_Session session_id
             open_session new_session close_session
             dump_sessions);

use Carp;
use strict;
use Vend::Directive qw(Data_directory);
use Vend::Uneval;


sub last_rollover_time {
    my $fn = Data_directory . "/rollover";
    my @s = stat($fn);
    return 0 unless @s;
    return $s[9];
}

sub mark_rollover {
    my $now = time;
    my $fn = Data_directory . "/rollover";
    if (-e $fn) {
        utime($now, $now, $fn)
            or die "Couldn't set modification time for '$fn': $!\n";
    }
    else {
        open(ROLLOVER, ">$fn") or die "Couldn't create '$fn': $!\n";
        close(ROLLOVER);
    }
}


my ($Session, $Name, $ID, $Db_type, $Old, $New, $Expire_time);
my ($Expire_time, $File_creation_mask);
my ($Old_path, $New_path);

sub open_db {
    if ($Db_type eq 'gdbm') {
        $Old = new Vend::SessionDB::gdbm $Old_path, $File_creation_mask;
        $New = new Vend::SessionDB::gdbm $New_path, $File_creation_mask;
    }
    elsif ($Db_type eq 'file') {
        $Old = new Vend::SessionDB::file $Old_path, $File_creation_mask;
        $New = new Vend::SessionDB::file $New_path, $File_creation_mask;
    }
    else { die "Can't happen" }

    $Old->open_db();
    $New->open_db();
}

sub close_db {
    if (defined $New) {
        $New->close_db();
        undef $New;
    }

    if (defined $Old) {
        $Old->close_db();
        undef $Old;
    }
}

sub initialize_Session {
    my ($db_type,
        $path,
        $expire_time,
        $file_creation_mask) = @_;
    croak "Unknown session database type: '$db_type'"
        unless $db_type eq 'gdbm' or $db_type eq 'file';
    $Db_type = $db_type;
    $Expire_time = $expire_time;
    $File_creation_mask = $file_creation_mask;
    $Old_path = "$path/oldsession";
    $New_path = "$path/newsession";

    if ($Db_type eq 'gdbm') {
        require Vend::SessionDB::gdbm;
    }
    elsif ($Db_type eq 'file') {
        require Vend::SessionDB::file;
    }

    open_db();
}

sub set_session {
    my ($session) = @_;

    $Session = $session;
}

sub init_session {
    set_session( {version => 1} );
}

sub gen_session_name {
    my ($session_id, $host, $user) = @_;
    $session_id .':'. $host .':'. $user;
}

sub session_name {
    $Name;
}

sub session_id {
    $ID;
}

# sub session_expired {
#    my ($session, $time) = @_;
#
#    $time - $session->{'time'} > $Expire_time;
# }

sub stuff {
    my ($value) = @_;
    return uneval($value);
}

sub unstuff {
    my ($string) = @_;
    my $saved_eval_error = $@;
    my $value = eval($string);
    my $eval_error = $@;
    $@ = $saved_eval_error;
    die "Couldn't eval '$string': $eval_error\n" if $eval_error;
    return $value;
}

sub open_session {
    my ($session_id, $host, $user) = @_;

    $Name = gen_session_name($session_id, $host, $user);
    $ID = $session_id;

    $Old->lock_key($Name);
    $New->lock_key($Name);

    my $session_string = $New->get();
    if (not defined $session_string) {
        $session_string = $Old->get();
    }

    if (not defined $session_string) {
        init_session();
    }
    else {
        set_session(unstuff($session_string));
    }
}


#     vdb_lock $Vdb $Name;
#     my $session = vdb_get $Vdb;
# 
#     if (not defined($session) or session_expired($session, time)) {
#         init_session();
#     }
#     else {
#         set_session($session);
#     }

## random_string

# leaving out 0, O and 1, l
my $chars = "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

# Return a string of random characters.

sub random_string {
    my ($len) = @_;
    $len = 8 unless $len;
    my ($r, $i);

    $r = '';
    for ($i = 0;  $i < $len;  ++$i) {
	$r .= substr($chars, int(rand(length($chars))), 1);
    }
    $r;
}

sub new_session {
    my ($host, $user) = @_;
    my ($name, $v, $session_id);

    SESSION: {
	$session_id = random_string();
	$name = gen_session_name($session_id, $host, $user);

        $Old->lock_key($name);
        $New->lock_key($name);
        if ($New->defined() or $Old->defined()) {
            $New->unlock_key();
            $Old->unlock_key();
            redo SESSION;
        }
    }

    init_session();
    $Name = $name;
    $ID = $session_id;
}

sub close_session {
    my ($write_session) = @_;

    if (not $write_session) {
        # abnormal exit
        $New->unlock_key();
        $Old->unlock_key();
        return;
    }

    $Session->{'time'} = time;
    $New->put(stuff($Session));
    $New->unlock_key();
    $Old->unlock_key();

    maybe_rollover();
}

sub maybe_rollover {
    my $last = last_rollover_time();

    if ($last == 0) {
        mark_rollover();
        return;
    }

    if (time - $last > $Expire_time) {
        rollover();
    }
}

sub rollover {
    if ($Db_type eq 'gdbm') {
        close_db();
        Vend::SessionDB::gdbm->rename_db($New_path, $Old_path);
        open_db();
        mark_rollover();
    }
}

# sub expire_sessions {
#     my $time = time;
#     my ($name, $session, @todelete);
# 
#     vdb_open $Vdb;
#     @todelete = ();
#     while (($name, $session) = vdb_each $Vdb) {
#         push @todelete, $name if ($time - $session->{'time'} > $Expire_time);
#     }
# 
#     foreach $name (@todelete) {
# 	vdb_lock $Vdb $name;
# 	$session = vdb_get $Vdb;
#         $Vdb->vdb_put(undef) if ($time - $session->{'time'} > $Expire_time);
# 	vdb_unlock $Vdb;
#     }
#     vdb_close $Vdb;
# }

sub dump_sessions {
    my ($name, $session);

    print "New:\n";
    while (($name, $session) = $New->each_record()) {
	print " $name: $session\n\n" if defined $session;
    }

    print "Old:\n";
    while (($name, $session) = $Old->each_record()) {
	print " $name: $session\n\n" if defined $session;
    }
}

## Access functions

sub Session {
    $Session = {} unless defined $Session;
    $Session;
}

sub Value {
    my ($name) = @_;

    $Session->{'values'} = {}
        unless defined $Session->{'values'};

    if (defined $name) {
        return $Session->{'values'}{$name};
    }
    else {
        return $Session->{'values'};
    }
}

# sub Lists {
#     my ($name) = @_;
# 
#     $Session->{lists} = {} unless defined $Session->{lists};
# 
#     if (defined $name) {
#         my $list = $Session->{lists}{$name};
#         $Session->{lists}{$name} = $list = new List
#             unless defined $list;
#         return $list;
#     }
#     else {
#         return $Session->{lists};
#     }
# }

1;
