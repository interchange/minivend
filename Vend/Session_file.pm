# Session_file.pm:  stores session information in files
#
# $Id: Session_file.pm,v 1.2 1996/02/26 22:15:27 amw Exp $
#
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

package Vend::Session;

#alternative method.
#
# require Exporter;
# @ISA = qw(Exporter);
# @EXPORT = qw(close_session dump_sessions expire_sessions new_session
#              open_session Session session_id Value);
#$main::INC{'Vend/Session.pm'} = __FILE__;

use Carp;
use strict;
use Vend::Escape;
use Vend::lock;
use Vend::Uneval;
use Vend::Util qw(random_string);

sub config_value {
    my ($config, $directive) = @_;
    croak "The '$directive' directive is not present in the configuration hash"
        unless defined $config->{$directive};
    return $config->{$directive};
}

my ($Session_directory, $Session_expire);

sub really_configure {
    my ($class, $config) = @_;
    # my ($config) = @_;
    $Session_directory = config_value($config, 'Session_directory');
    $Session_expire = config_value($config, 'Session_expire');
}

sub setup {
    require Vend::Expire_file;
    Vend::Expire_file->setup();
}

sub initialize {
    if (! -e $Session_directory) {
        mkdir $Session_directory, 0777
            or die "Can't create directory '$Session_directory': $!\n";
    }
    elsif (! -d $Session_directory) {
        die "'$Session_directory' is not a directory\n";
    }
}

my ($ID, $Full_ID, $Filename);

sub set_filename {
    my ($session_id, $host, $user) = @_;

    $ID = $session_id;
    $Full_ID = $ID . ':' . $host . ':' . $user;
    $Filename = $Session_directory . '/' . escape_filename($Full_ID);
}
    
sub open_session {
    my ($session_id, $host, $user) = @_;

    set_filename($session_id, $host, $user);
    my $last_modtime = open_and_lock(\*SESSION, $Filename);

    if ($last_modtime == 0) {   # new file
        init_session();
    }
    else {
        read_session();
    }
}


sub new_session {
    my ($host, $user) = @_;
    my ($session_id);

    SESSION: {
        $session_id = random_string();
        set_filename($session_id, $host, $user);
        redo SESSION if -e $Filename;

        my $already_existing = open_and_lock(\*SESSION, $Filename);
        if ($already_existing) {
            close(SESSION);
            redo SESSION;
        }
    }

    init_session();
}

sub close_session {
    my ($write_session) = @_;

    write_session() if $write_session;
    close(SESSION);
}


my $Session = {};

sub init_session {
    $Session = {version => 1};
}

sub Session {
    return $Session;
}

sub set_session {
    my ($value) = @_;
    $Session = $value;
}

sub session_id {
    return $ID;
}


sub read_session {
    local ($/, $., $_);

    seek(SESSION, 0, 0) or die "Can't seek session: $!\n";
    $/ = undef;
    my $str = <SESSION>;
    $str =~ m/([\000-\377]*)/m;

    my $saved_eval_error = $@;
    my $value = eval($1);
    my $eval_error = $@;
    $@ = $saved_eval_error;

    die "Couldn't eval session string '$str': $eval_error\n"
        if $eval_error;

    $Session = $value;
}


sub write_session {
    no strict 'subs';
    truncate(SESSION, 0) or die "Can't truncate session: $!\n";
    seek(SESSION, 0, 0) or die "Can't seek session: $!\n";
    print SESSION uneval($Session), "\n";
}


sub expire_sessions {
    my ($fn, $path, $mod_time);

    opendir(DIR, $Session_directory)
        or die "Can't open directory '$Session_directory': $!\n";
    my $now = time;
    while ($fn = readdir(DIR)) {
        next if $fn eq '.' or $fn eq '..';
        $path = "$Session_directory/$fn";
        $mod_time = (stat($path))[9];
        next if not defined $mod_time or $now - $mod_time <= $Session_expire;

        $mod_time = open_and_lock(\*SESSION, $path);
        if ($mod_time == 0 or $now - $mod_time > $Session_expire) {
            unlink($path) or die "Can't delete '$path': $!\n";
        }
        close(SESSION);
    }
    closedir(DIR);
}


sub dump_sessions {
    local ($/, $.);
    undef $/;
    my ($fn, $id, $path, $string);

    opendir(DIR, $Session_directory)
        or die "Can't open directory '$Session_directory': $!\n";
    while ($fn = readdir(DIR)) {
        next if $fn eq '.' or $fn eq '..';
        $id = unescape_filename($fn);
        $path = "$Session_directory/$fn";
        open_and_lock(\*SESSION, $path);
        $string = <SESSION>;
        close(SESSION);
        print "$id: $string";
    }
    close(DIR);
}

# Opens and exclusively locks $filename on the passed file $handle.
# Returns the file modification time of when the file was last updated
# if it already exists.  Assume that if the file is empty we just created
# it, and return 0.

sub open_and_lock {
    my ($handle, $filename) = @_;

    open($handle, "+>>$filename")
        or die "Can't open '$filename': $!\n";
    lockfile($handle, 1, 1);
    my @s = stat($handle);
    my $size = $s[7];
    return 0 if $size == 0;
    my $mod_time = $s[9];
    return $mod_time;
}


sub Value {
    my ($name) = @_;

    Session()->{'values'} = {}
        unless defined Session()->{'values'};

    if (defined $name) {
        return Session()->{'values'}{$name};
    }
    else {
        return Session()->{'values'};
    }
}

# *Vend::Session::close_session   = \&close_session;
# *Vend::Session::dump_sessions   = \&dump_sessions;
# *Vend::Session::expire_sessions = \&expire_sessions;
# *Vend::Session::open_session    = \&open_session;
# *Vend::Session::new_session     = \&new_session;
# *Vend::Session::Session         = \&Session;
# *Vend::Session::session_id      = \&session_id;

1;
