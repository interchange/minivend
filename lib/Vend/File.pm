# Vend::File - Interchange file functions
#
# $Id$
# 
# Copyright (C) 1996-2002 Red Hat, Inc. <interchange@redhat.com>
#
# This program was originally based on Vend 0.2 and 0.3
# Copyright 1995 by Andrew M. Wilcox <amw@wilcoxsolutions.com>
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

package Vend::File;
require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(
	absolute_or_relative
	allowed_file
	catfile
	check_security
	exists_filename
	file_allow
	file_modification_time
	file_name_is_absolute
	get_filename
	lockfile
	readfile
	readfile_db
	set_lock_type
	unlockfile
	writefile
);

use strict;
use Config;
use Fcntl;
use Errno;
use Vend::Util;
use subs qw(logError logGlobal);
use vars qw($VERSION @EXPORT @EXPORT_OK);
$VERSION = substr(q$Revision$, 10);

sub writefile {
    my($file, $data, $opt) = @_;

	$file = ">>$file" unless $file =~ /^[|>]/;
	if (ref $opt and $opt->{umask}) {
		$opt->{umask} = umask oct($opt->{umask});
	}
    eval {
		unless($file =~ s/^[|]\s*//) {
			if (ref $opt and $opt->{auto_create_dir}) {
				my $dir = $file;
				$dir =~ s/>+//;

				## Need to make this OS-independent, requires File::Spec support
				$dir =~ s:[\r\n]::g;   # Just in case
				$dir =~ s:(.*)/.*:$1: or $dir = '';
				if($dir and ! -d $dir) {
					File::Path::mkpath($dir);
				}
			}
			# We have checked for beginning > or | previously
			open(MVLOGDATA, $file) or die "open\n";
			lockfile(\*MVLOGDATA, 1, 1) or die "lock\n";
			seek(MVLOGDATA, 0, 2) or die "seek\n";
			if(ref $data) {
				print(MVLOGDATA $$data) or die "write to\n";
			}
			else {
				print(MVLOGDATA $data) or die "write to\n";
			}
			unlockfile(\*MVLOGDATA) or die "unlock\n";
		}
		else {
            my (@args) = grep /\S/, Text::ParseWords::shellwords($file);
			open(MVLOGDATA, "|-") || exec @args;
			if(ref $data) {
				print(MVLOGDATA $$data) or die "pipe to\n";
			}
			else {
				print(MVLOGDATA $data) or die "pipe to\n";
			}
		}
		close(MVLOGDATA) or die "close\n";
    };

	my $status = 1;
    if ($@) {
		::logError ("Could not %s file '%s': %s\nto write this data:\n%s",
				$@,
				$file,
				$!,
				$data,
				);
		$status = 0;
    }

    if (ref $opt and defined $opt->{umask}) {                                        
        $opt->{umask} = umask oct($opt->{umask});                                    
    }

	return $status;
}

sub file_modification_time {
    my ($fn, $tolerate) = @_;
    my @s = stat($fn) or ($tolerate and return 0) or die "Can't stat '$fn': $!\n";
    return $s[9];
}

sub readfile_db {
	my ($name) = @_;
	return unless $Vend::Cfg->{FileDatabase};
	my ($tab, $col) = split /:+/, $Vend::Cfg->{FileDatabase};
	my $db = $Vend::Interpolate::Db{$tab} || ::database_exists_ref($tab)
		or return undef;
#::logDebug("tab=$tab exists, db=$db");

	# I guess this is the best test
	if($col) {
		return undef unless $db->column_exists($col);
	}
	elsif ( $col = $Global::Variable->{LANG} and $db->column_exists($col) ) {
		#do nothing
	}
	else {
		$col = 'default';
		return undef unless $db->column_exists($col);
	}

#::logDebug("col=$col exists, db=$db");
	return undef unless $db->record_exists($name);
#::logDebug("ifile=$name exists, db=$db");
	return $db->field($name, $col);
}

# Reads in an arbitrary file.  Returns the entire contents,
# or undef if the file could not be read.
# Careful, needs the full path, or will be read relative to
# VendRoot..and will return binary. Should be tested by
# the user.

# Will also look in the *global* TemplateDir. (No need for the
# extra overhead of local TemplateDir, probably also insecure.)
#
# To ensure security in multiple catalog setups, leading /
# is not allowed if $Global::NoAbsolute) is true and the file
# is not part of the TemplateDir, VendRoot, or is owned by the
# defined CatalogUser.

# If catalog FileDatabase is enabled and there are no contents, we can retrieve
# the file from the database.

sub readfile {
    my($ifile, $no, $loc) = @_;
    my($contents);
    local($/);

	unless(allowed_file($ifile)) {
		::logError("Can't read file '%s' with NoAbsolute set" , $ifile);
		::logGlobal({ level => 'auth'}, "Can't read file '%s' with NoAbsolute set" , $ifile );
		return undef;
	}

	my $file;

	if (file_name_is_absolute($ifile) and -f $ifile) {
		$file = $ifile;
	}
	else {
		for( ".", @{$Global::TemplateDir} ) {
			next if ! -f "$_/$ifile";
			$file = "$_/$ifile";
			last;
		}
	}

	if(! $file) {
		$contents = readfile_db($ifile);
		return undef unless defined $contents;
	}
	else {
		return undef unless open(READIN, "< $file");
		$Global::Variable->{MV_FILE} = $file;

		binmode(READIN) if $Global::Windows;
		undef $/;
		$contents = <READIN>;
		close(READIN);
	}

	if (
		$Vend::Cfg->{Locale}
			and
		(defined $loc ? $loc : $Vend::Cfg->{Locale}->{readfile} )
		)
	{
		Vend::Util::parse_locale(\$contents);
	}
    return $contents;
}

### flock locking

# sys/file.h:
my $flock_LOCK_SH = 1;          # Shared lock
my $flock_LOCK_EX = 2;          # Exclusive lock
my $flock_LOCK_NB = 4;          # Don't block when locking
my $flock_LOCK_UN = 8;          # Unlock

sub flock_lock {
    my ($fh, $excl, $wait) = @_;
    my $flag = $excl ? $flock_LOCK_EX : $flock_LOCK_SH;

    if ($wait) {
        flock($fh, $flag) or die "Could not lock file: $!\n";
        return 1;
    }
    else {
        if (! flock($fh, $flag | $flock_LOCK_NB)) {
            if ($!{EAGAIN} or $!{EWOULDBLOCK}) {
				return 0;
            }
            else {
                die "Could not lock file: $!\n";
            }
        }
        return 1;
    }
}

sub flock_unlock {
    my ($fh) = @_;
    flock($fh, $flock_LOCK_UN) or die "Could not unlock file: $!\n";
}

sub fcntl_lock {
    my ($fh, $excl, $wait) = @_;
    my $flag = $excl ? F_WRLCK : F_RDLCK;
    my $op = $wait ? F_SETLKW : F_SETLK;

	my $struct = pack('sslli', $flag, 0, 0, 0, $$);

    if ($wait) {
        fcntl($fh, $op, $struct) or die "Could not fcntl_lock file: $!\n";
        return 1;
    }
    else {
        if (fcntl($fh, $op, $struct) < 0) {
            if ($!{EAGAIN} or $!{EWOULDBLOCK}) {
                return 0;
            }
            else {
                die "Could not lock file: $!\n";
            }
        }
        return 1;
    }
}

sub fcntl_unlock {
    my ($fh) = @_;
	my $struct = pack('sslli', F_UNLCK, 0, 0, 0, $$);
	if (fcntl($fh, F_SETLK, $struct) < 0) {
		if ($!{EAGAIN} or $!{EWOULDBLOCK}) {
			return 0;
		}
		else {
			die "Could not un-fcntl_lock file: $!\n";
		}
	}
	return 1;
}

my $lock_function = \&flock_lock;
my $unlock_function = \&flock_unlock;

sub set_lock_type {
	if ($Global::LockType eq 'none') {
		logDebug("using NO locking");
		$lock_function = sub {1};
		$unlock_function = sub {1};
	}
	elsif ($Global::LockType =~ /fcntl/i) {
		logDebug("using fcntl(2) locking");
		$lock_function = \&fcntl_lock;
		$unlock_function = \&fcntl_unlock;
	}
	else {
		$lock_function = \&flock_lock;
		$unlock_function = \&flock_unlock;
	}
	return; # VOID
}
 
sub lockfile {
    &$lock_function(@_);
}

sub unlockfile {
    &$unlock_function(@_);
}

### Still necessary, sad to say.....
if($Global::Windows) {
	set_lock_type('none');
}
elsif($^O =~ /hpux/) {
	set_lock_type('fcntl');
}

# Return a quasi-hashed directory/file combo, creating if necessary
sub exists_filename {
    my ($file,$levels,$chars, $dir) = @_;
	my $i;
	$levels = 1 unless defined $levels;
	$chars = 1 unless defined $chars;
	$dir = $Vend::Cfg->{ScratchDir} unless $dir;
    for($i = 0; $i < $levels; $i++) {
		$dir .= "/";
		$dir .= substr($file, $i * $chars, $chars);
		return 0 unless -d $dir;
	}
	return -f "$dir/$file" ? 1 : 0;
}

# Return a quasi-hashed directory/file combo, creating if necessary
sub get_filename {
    my ($file,$levels,$chars, $dir) = @_;
	my $i;
	$levels = 1 unless defined $levels;
	$chars = 1 unless defined $chars;
	$dir = $Vend::Cfg->{ScratchDir} unless $dir;
    for($i = 0; $i < $levels; $i++) {
		$dir .= "/";
		$dir .= substr($file, $i * $chars, $chars);
		mkdir $dir, 0777 unless -d $dir;
	}
    die "Couldn't make directory $dir (or parents): $!\n"
		unless -d $dir;
    return "$dir/$file";
}

# These were stolen from File::Spec
# Can't use that because it INSISTS on object
# calls without returning a blessed object

my $abspat = $^O =~ /win32/i ? qr{^([a-zA-Z]:)?[\\/]} : qr{^/};
my $relpat = qr{\.\.[\\/]};

sub file_name_is_absolute {
    my($file) = @_;
    $file =~ $abspat;
}

sub absolute_or_relative {
    my($file) = @_;
    $file =~ $abspat or $file =~ $relpat;
}

sub win_catfile {
    my $file = pop @_;
    return $file unless @_;
    my $dir = catdir(@_);
    $dir =~ s/(\\\.)$//;
    $dir .= "\\" unless substr($dir,length($dir)-1,1) eq "\\";
    return $dir.$file;
}

sub unix_catfile {
    my $file = pop @_;
    return $file unless @_;
    my $dir = catdir(@_);
    for ($dir) {
	$_ .= "/" unless substr($_,length($_)-1,1) eq "/";
    }
    return $dir.$file;
}

sub unix_path {
    my $path_sep = ":";
    my $path = $ENV{PATH};
    my @path = split $path_sep, $path;
    foreach(@path) { $_ = '.' if $_ eq '' }
    @path;
}

sub win_path {
    local $^W = 1;
    my $path = $ENV{PATH} || $ENV{Path} || $ENV{'path'};
    my @path = split(';',$path);
    foreach(@path) { $_ = '.' if $_ eq '' }
    @path;
}

sub win_catdir {
    my @args = @_;
    for (@args) {
	# append a slash to each argument unless it has one there
	$_ .= "\\" if $_ eq '' or substr($_,-1) ne "\\";
    }
    my $result = canonpath(join('', @args));
    $result;
}

sub win_canonpath {
    my($path) = @_;
    $path =~ s/^([a-z]:)/\u$1/;
    $path =~ s|/|\\|g;
    $path =~ s|\\+|\\|g ;                          # xx////xx  -> xx/xx
    $path =~ s|(\\\.)+\\|\\|g ;                    # xx/././xx -> xx/xx
    $path =~ s|^(\.\\)+|| unless $path eq ".\\";   # ./xx      -> xx
    $path =~ s|\\$|| 
             unless $path =~ m#^([a-z]:)?\\#;      # xx/       -> xx
    $path .= '.' if $path =~ m#\\$#;
    $path;
}

sub unix_canonpath {
    my($path) = @_;
    $path =~ s|/+|/|g ;                            # xx////xx  -> xx/xx
    $path =~ s|(/\.)+/|/|g ;                       # xx/././xx -> xx/xx
    $path =~ s|^(\./)+|| unless $path eq "./";     # ./xx      -> xx
    $path =~ s|/$|| unless $path eq "/";           # xx/       -> xx
    $path;
}

sub unix_catdir {
    my @args = @_;
    for (@args) {
	# append a slash to each argument unless it has one there
	$_ .= "/" if $_ eq '' or substr($_,-1) ne "/";
    }
    my $result = join('', @args);
    # remove a trailing slash unless we are root
    substr($result,-1) = ""
	if length($result) > 1 && substr($result,-1) eq "/";
    $result;
}

my $catdir_routine;
my $canonpath_routine;
my $catfile_routine;
my $path_routine;

if($^O =~ /win32/i) {
	$catdir_routine = \&win_catdir;
	$catfile_routine = \&win_catfile;
	$path_routine = \&win_path;
	$canonpath_routine = \&win_canonpath;
}
else {
	$catdir_routine = \&unix_catdir;
	$catfile_routine = \&unix_catfile;
	$path_routine = \&unix_path;
	$canonpath_routine = \&unix_canonpath;
}

sub path {
	return &{$path_routine}(@_);
}

sub catfile {
	return &{$catfile_routine}(@_);
}

sub catdir {
	return &{$catdir_routine}(@_);
}

sub canonpath {
	return &{$canonpath_routine}(@_);
}

#print "catfile a b c --> " . catfile('a', 'b', 'c') . "\n";
#print "catdir a b c --> " . catdir('a', 'b', 'c') . "\n";
#print "canonpath a/b//../../c --> " . canonpath('a/b/../../c') . "\n";
#print "file_name_is_absolute a/b/c --> " . file_name_is_absolute('a/b/c') . "\n";
#print "file_name_is_absolute a:b/c --> " . file_name_is_absolute('a:b/c') . "\n";
#print "file_name_is_absolute /a/b/c --> " . file_name_is_absolute('/a/b/c') . "\n";

sub check_user_read {
	my $fn = shift;
	my $un = $Global::CatalogUser->{$Vend::Cat}
		or return undef;
	my ($own, $grown) = (stat($fn))[4,5];
	return 0 unless defined $own;
	my $uid = getpwnam($un);
	return 1 if $uid eq $own;
	my @members = split /\s+/, (getgrgid($grown))[3];
	for(@members) {
		return 1 if $un eq $_;
	}
	return 0;
}

sub check_user_write {
	my $fn = shift;
	my $un = $Global::CatalogUser->{$Vend::Cat}
		or return undef;
	my ($mode,$own, $grown) = (stat($fn))[2,4,5];
	return 0 unless defined $own;
	my $uid = getpwnam($un);
	return 1 if $uid eq $own and $mode & 0200;
	return 0 unless $mode & 020;
	my @members = split /\s+/, (getgrgid($grown))[3];
	for(@members) {
		return 1 if $un eq $_;
	}
	return 0;
}

sub check_user_read {
	my $fn = shift;
	my $un = $Global::CatalogUser->{$Vend::Cat}
		or return undef;
	my ($mode,$own, $grown) = (stat($fn))[2,4,5];
	return 0 unless defined $own;
	my $uid = getpwnam($un);
	return 1 if $uid eq $own and $mode & 0400;
	return 0 unless $mode & 040;
	my @members = split /\s+/, (getgrgid($grown))[3];
	for(@members) {
		return 1 if $un eq $_;
	}
	return 0;
}

sub allowed_file {
	my $fn = shift;
	my $write = shift;
	my $status = 1;
	if(	$Global::NoAbsolute
			and
		$fn !~ $Vend::Cfg->{AllowedFileRegex}
			and
		absolute_or_relative($fn)
		)
	{
		$status = $write ? check_user_write($fn) : check_user_read($fn);
	}
#::logDebug("allowed_file check for $fn: $status");
	return $status;
}

1;
__END__
