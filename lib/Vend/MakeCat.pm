#!/usr/local/bin/perl
#
# MakeCat.pm - routines for catalog configurator
#
# $Id: MakeCat.pm,v 1.16 1999/02/15 08:51:05 mike Exp $
#
# Copyright 1996-1999 by Michael J. Heins <mikeh@iac.net>
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

## END CONFIGURABLE VARIABLES

package Vend::MakeCat;

use Cwd;
use File::Find;
use File::Copy;
use File::Basename;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(

add_catalog
addhistory
can_do_suid
conf_parse_http
copy_current_to_dir
description
do_msg
findexe
findfiles
get_id
get_ids
pretty
prompt
sethistory

);


use strict;

use vars qw($Force $Error $History $VERSION);
$VERSION = substr(q$Revision: 1.16 $, 10);

$Force = 0;
$History = 0;
my %Pretty = qw(

	aliases         Aliases
	basedir         BaseDir
	catuser			CatUser
	cgibase         CgiBase
	cgidir          CgiDir
	cgiurl          CgiUrl
	demotype        DemoType
	documentroot    DocumentRoot
	imagedir        ImageDir
	imageurl        ImageUrl
	mailorderto     MailOrderTo
	minivenduser	MiniVendUser
	minivendgroup	MiniVendGroup
	samplehtml      SampleHtml
	sampledir       SampleDir
	sampleurl       SampleUrl
	serverconf      ServerConf
	servername      ServerName
	catroot         CatRoot
	vendroot        VendRoot

);
 
 
my %Desc = (

	aliases    =>  <<EOF,
#
# Additional URL locations for the CGI program, as with CgiUrl.
# This is used when calling the catalog from more than one place,
# perhaps because your secure server is not the same name as the
# non-secure one.
#
# http://www.secure.domain/secure-bin/prog
#                         ^^^^^^^^^^^^^^^^
#
# We set it to the name of the catalog by default to enable the
# internal HTTTP server.
#
EOF
	basedir    =>  <<EOF,
# 
# DIRECTORY where the MiniVend catalog directories will go. These
# are the catalog files, such as the ASCII database source,
# MiniVend page files, and catalog.cfg file. Catalogs will
# be an individual subdirectory of this directory.
#
EOF
	catuser    =>  <<EOF,
#
# The user name the catalog will be owned by.
#
EOF
	cgibase    =>  <<EOF,
#
# The URL-style location of the normal CGI directory.
# Only used to set the default for the CgiUrl setting.
# 
# DO NOT PUT A TRAILING /.
#
# http://www.virtual.com/cgi-bin/prog
#                       ^^^^^^^^
#
# If you have no CGI-bin directory, (your CGI programs end
# in .cgi), leave this blank.
#
EOF
	cgidir     =>  <<EOF,
# The location of the normal CGI directory. This is a
# file path, not a script alias.
#
# If all of your CGI programs must end in .cgi, this is
# should be the same as your HTML directory.
#
EOF
	cgiurl     =>  <<EOF,
# The URL location of the CGI program, without the http://
# or server name.
#
# http://www.virtual.com/cgi-bin/prog
#                       ^^^^^^^^^^^^^
#
# http://www.virtual.com/program.cgi
#                       ^^^^^^^^^^^^
#
EOF
	demotype   =>  <<EOF,
# The type of demo catalog to use, simple or flycat.
#
#    simple -- database-based catalog
#    flycat -- on-the-fly non-database catalog
#
# If you have defined your own custom template catalog,
# you can enter it's name.
EOF
	documentroot    =>  <<EOF,
# The base directory for HTML for this (possibly virtual) domain.
# This is a directory path name, not a URL -- it is your HTML
# directory.
#
EOF
	mailorderto  =>  <<EOF,
# The email address where orders for this catalog should go.
# To have a secure catalog, either this should be a local user name and
# not go over the Internet -- or use the PGP option.
#
EOF
	permtype  =>  <<EOF,
# The type of permission structure for multiple user catalogs.
# Select M for each user in own group (with minivend user in group)
#        G for all users in group of minivend user
#        U for all catalogs owned by minivend user (must be catuser as well)
#
#        M is recommended, G works for most installations.
EOF
	minivenduser  =>  <<EOF,
# The user name the MiniVend server runs under on this machine. This
# should not be the same as the user that runs the HTTP server (i.e.
# NOT nobody).
#
EOF
	minivendgroup    =>  <<EOF,
# The group name the server-owned files should be set to.  This is
# only important if MiniVend catalogs will be owned by multiple users
# and the group to be used is not the default for the catalog user.
#
# Normally this is left blank.
# 
EOF
	imagedir   =>  <<EOF,
# Where the image files should be copied. A directory path
# name, not a URL.
#
EOF
	imageurl   =>  <<EOF,
# The URL base for the sample images. Sets the ImageDir
# directive in the catalog configuration file. This is a URL
# fragment, not a directory or file name.
#
#         <IMG SRC="/simple/images/icon.gif">
#                   ^^^^^^^^^^^^^^
#
EOF
	samplehtml =>  <<EOF,
# Where the sample HTML files (not MiniVend pages) should be
# installed. There is a difference.  Usually a subdirectory of
# your HTML directory.
#
EOF
	sampleurl  =>  <<EOF,
# Our guess as to the URL to run this catalog, used for the
# client-pull screens and an informational message, not prompted for.
#
EOF
	serverconf =>  <<EOF,
# The server configuration file, if you are running
# Apache or NCSA. Often:
#                          /usr/local/apache/conf/httpd.conf
#                          /usr/local/etc/httpd/conf/httpd.conf
#
EOF
	servername =>  <<EOF,
# The server name, something like: www.company.com
#                                  www.company.com:8000
#                                  www.company.com/~yourname
#
EOF
	catroot   =>  <<EOF,
# Where the MiniVend files for this catalog will go, pages,
# products, config and all.  This should not be in HTML document
# space! Usually a 'catalogs' directory below your home directory
# works well. Remember, you will want a test catalog and an online
# catalog.
#
EOF

	vendroot  =>  <<EOF,
# The directory where the MiniVend software is installed.
#
EOF

);
 
sub findexe {
    my($exe) = @_;
    my($dir,$path) = ('', $ENV{PATH});
    $path =~ s/\(\)//g;
    $path =~ s/\s+/\s/g;
    my(@dirs) = split /[\s:]+/, $path;
    foreach $dir (@dirs) {
        return "$dir/$exe" if -x "$dir/$exe";
    }
    return '';
}
 
sub findfiles {
    my($file) = @_;
	return undef if $ =~ /win32/i;
	my $cmd;
	my @files;
    if($cmd = findexe('locate')) {
		@files = `locate \\*/$file`;
	}
	else {
		@files = `find / -name $file -print 2>/dev/null`;
	}
	return undef unless @files;
	chomp @files;
	return @files;
}

sub pretty {
	my($parm) = @_;
	return defined $Pretty{lc $parm} ? $Pretty{lc $parm} : $parm;
}

sub description {
	my($parm) = @_;
	return defined $Desc{lc $parm} ? $Desc{lc $parm} : '';
}

sub can_do_suid {
	return 0 if $ =~ /win32/i;
	my $file = "tmp$$.fil";
	my $status;

	open(TEMPFILE,">$file");
	close TEMPFILE;
	eval { chmod 04755, $file; $@ = ''};
	$status = $@ ? 0 : 1;
	unlink $file;
	return $status;
}

sub get_id {
	return 'everybody' if $ =~ /win32/i;
    my $file = -f "$::VendRoot/error.log"
                ? "$::VendRoot/error.log" : '';
    return '' unless $file;
    my ($name);

    my($uid) = (stat($file))[4];
    $name = (getpwuid($uid))[0];
    return $name;
}

sub get_ids {
	return ('everybody', 'nogroup') if $ =~ /win32/i;
	my $file = "tmp$$.fil";
	my ($name, $group);

	open(TEMPFILE,">$file");
	close TEMPFILE;
	my($uid,$gid) = (stat($file))[4,5];
	unlink $file;
	$name = (getpwuid($uid))[0];
	$group = (getgrgid($gid))[0];
	return ($name,$group);
}

my $Windows = ($ =~ /win32/i ? 1 : 0);

sub compare_file {
    my($first,$second) = @_;
    return 0 unless -s $first == -s $second;
    local $/;
    open(FIRST, $first) or return undef;
    open(SECOND, $second) or (close FIRST and return undef);
    binmode(FIRST);
    binmode(SECOND);
    $first = '';
    $second = '';
    while($first eq $second) {
        read(FIRST, $first, 1024);
        read(SECOND, $second, 1024);
        last if length($first) < 1024;
    }
    close FIRST;
    close SECOND;
    $first eq $second;
}

sub install_file {
    my ($srcdir, $targdir, $filename, $opt) = @_;
	$opt = {} unless $opt;
	if (ref $srcdir) {
		$opt = $srcdir;
		$srcdir  = $opt->{Source} || die "Source dir for install_file not set.\n";
		$targdir = $opt->{Target} || die "Target dir for install_file not set.\n";
		$filename = $opt->{Filename} || die "File name for install_file not set.\n";
	}
    my $srcfile  = $srcdir . '/' . $filename;
    my $targfile = $targdir . '/' . $filename;
    my $mkdir = File::Basename::dirname($targfile);
    my $extra;
    my $perms;

    if(! -d $mkdir) {
        File::Path::mkpath($mkdir)
            or die "Couldn't make directory $mkdir: $!\n";
    }

    if (! -f $srcfile) {
        die "Source file $srcfile missing.\n";
    }
    elsif (
		$opt->{Perm_hash}
			and $opt->{Perm_hash}->{$filename}
		)
	{
        $perms = $opt->{Perm_hash}->{$filename};
	}
    elsif ( $opt->{Perms} =~ /^(m|g)/i ) {
        $perms = (stat(_))[2] | 0660;
	}
    elsif ( $opt->{Perms} =~ /^u/i ) {
        $perms = (stat(_))[2] | 0600;
	}
    else {
        $perms = (stat(_))[2] & 0777;
    }

    if( ! $Windows and -f $targfile and ! compare_file($srcfile, $targfile) ) {
        open (GETVER, $targfile)
            or die "Couldn't read $targfile for version update: $!\n";
        while(<GETVER>) {
            /VERSION\s+=.*?\s+([\d.]+)/ or next;
            $extra = $1;
            $extra =~ tr/0-9//cd;
            last;
        }
        $extra = 'old' unless $extra;
        while (-f "$targfile.$extra") {
            $extra .= '~';
        }
        rename $targfile, "$targfile.$extra"
            or die "Couldn't rename $targfile to $targfile.$extra: $!\n";
    }

    File::Copy::copy($srcfile, $targfile)
        or die "Copy of $srcfile to $targfile failed: $!\n";
	if($opt->{Substitute}) {
			my $bak = "$targfile.mv";
			rename $targfile, $bak;
			open(SOURCE, "$bak")			or die "open $bak: $!\n";
			open(TARGET, ">$targfile")		or die "create $targfile: $!\n";
			local($/) = undef;
			my $page = <SOURCE>; close SOURCE;
			$page =~ s/__MVC_(\w+)__/$opt->{Substitute}{lc $1}/g;
			print TARGET $page				or die "print $targfile: $!\n";
			close TARGET					or die "close $targfile: $!\n";
			unlink $bak						or die "unlink $bak: $!\n";
	}
    chmod $perms, $targfile;
}

sub copy_current_to_dir {
    my($target_dir, $exclude_pattern) = @_;
	return copy_dir('.', $target_dir, $exclude_pattern);
}

sub copy_dir {
    my($source_dir, $target_dir, $exclude_pattern) = @_;
	return undef unless -d $source_dir;
	my $orig_dir;
	if($source_dir ne '.') {
		$orig_dir = cwd();
		chdir $source_dir or die "chdir: $!\n";
	}
    my @files; 
    my $wanted = sub {  
        return unless -f $_;
        my $name = $File::Find::name;
        $name =~ s:^\./::;
        return if $exclude_pattern and $name =~ m{$exclude_pattern}o;
        push (@files, $name);
    };
    File::Find::find($wanted, '.');  

	eval {
		for(@files) {
			install_file('.', $target_dir, $_);
		}
	};
	my $msg = $@;
	chdir $orig_dir if $orig_dir;
	die "$msg" if $msg;
	return 1;
}

use vars q!$Prompt_sub!;
my $History_add;
my $History_set;
my $term;
eval {
    require Term::ReadLine;
    import Term::ReadLine;
    $term = new Term::ReadLine::Perl 'MiniVend Configuration';
	die "No Term::ReadLine::Perl" unless defined $term;
	$term->MinLine(4);
    $Prompt_sub = sub {
                    my ($prompt, $default) = @_;
					if($Force) {
						print "$prompt SET TO --> $default\n";
						return $default;
					}
                    $prompt =~ s/^\s*(\n+)/print $1/ge;
                    $prompt =~ s/\n+//g;
                    return $term->readline($prompt, $default);
                    };
    $History_add = sub {
                    my ($line) = @_;
                    $term->addhistory($line)
                        if $line =~ /\S/;
                    };
    $History_set = sub {
						$term->SetHistory(@_);
					};
	$History = 1;

};


sub prompt {
    return &$Prompt_sub(@_)
        if defined $Prompt_sub;
    my($prompt) = shift || '? ';
    my($default) = shift;
	if($Force) {
		print "$prompt SET TO --> $default\n";
		return $default;
	}
    my($ans);

    print $prompt;
    print "[$default] " if $default;
	local ($/) = "\n";
    chomp($ans = <STDIN>);
    $ans ? $ans : $default;
}

sub addhistory {
	return '' unless defined $History_add;
	&{$History_add}(@_);
}

sub sethistory {
	return '' unless defined $History_set;
	&{$History_set}(@_);
}

sub do_msg {
	my ($msg, $size) = @_;
	$size = 60 unless defined $size;
	my $len = length $msg;
	
	return "$msg.." if ($len + 2) >= $size;
	$msg .= '.' x ($size - $len);
	return $msg;
}


sub add_catalog {
		my ($file, $directive, $configname, $value, $dynamic) = @_;
		my ($newcfgline, $mark, @out);
		my ($tmpfile) = "$file.$$";
		if (-f $file) {
			rename ($file, $tmpfile)
				or die "Couldn't rename $file: $!\n";
		}
		else {
			File::Copy::copy("$file.dist", $tmpfile);
		}
		open(CFG, $tmpfile)
			or die "Couldn't open $tmpfile: $!\n";
		$newcfgline = sprintf "%-19s %s\n", $directive, $value;
		while(<CFG>) {
			$mark = $. if /^#?\s*catalog\s+/i;
			warn "\nDeleting old configuration $configname.\n"
				if s/^(\s*$directive\s+$configname\s+)/#$1/io;
			push @out, $_;
		}
		close CFG;
		open(NEWCFG, ">$file")
			or die "\nCouldn't write $file: $!\n";
		if (defined $mark) {
			print NEWCFG @out[0..$mark-1];
			print NEWCFG $newcfgline;
			print NEWCFG @out[$mark..$#out];
		}
		else { 
			warn "\nNo $directive previously defined. Adding $configname at top.\n";
			print NEWCFG $newcfgline;
			print NEWCFG @out;
		}
		close NEWCFG || die "close: $!\n";
		unlink $tmpfile;

		if($dynamic and ! $Windows) {
			my $pidfile = $dynamic;
			$pidfile =~ s:/[^/]+$::;
			$pidfile .= '/minivend.pid';
			my $pid;
			PID: {
				local ($/);
				open(PID,$pidfile) or die "open $pidfile: $!\n";
				$pid = <PID>;
				$pid =~ /(\d+)/;
				$pid = $1;
			}

			open(RESTART, "<+$dynamic") or
				open(RESTART, ">>$dynamic") or
					die "Couldn't write $dynamic to add catalog: $!\n";
			Vend::Util::lockfile(\*RESTART, 1, 1) 	or die "lock $dynamic: $!\n";
			printf RESTART "%-19s %s\n", $directive, $value;
			Vend::Util::unlockfile(\*RESTART) 		or die "unlock $dynamic: $!\n";
			close RESTART;
			kill 'HUP', $pid;
		}
		1;
}

my %Http_hash = (
					qw(
						scriptalias		1
						addhandler		1
						alias			1
					)
				);

my %Http_process = (
						scriptalias		=> sub {
												my ($junk, $val) = @_;
												$val =~ s!/+$!!;
												return $val;
											},
				);

my %Http_scalar = (
					qw(
						user			1
						group			1
						serveradmin		1
						resourceconfig	1
						documentroot	1
					)
				);


sub conf_parse_http {
	my ($file) = @_;

	my $virtual = {};
	my $servers = {};
	my $newfile;

	open(HTTPDCONF, $file)
		or do { $Error = "Can't open $file: $!"; return undef};
	local($/) = undef;
	my $data = <HTTPDCONF>;
	close(HTTPDCONF);

	
	$data =~ s!
				<virtualhost
				\s+
					([^>\n]+)
				\s*>\s+
					([\000-\377]*?)
				</virtualhost>!
				$virtual->{$1} = $2; ''!xieg;

	if($data =~ s/^\s*resourceconfig\s+(.*)//) {
		$newfile = $1;
	}

	unless(defined $newfile) {
		$newfile = $file;
		$newfile =~ s:[^/]+$::;
		$newfile .= 'srm.conf';
	}

	SRMCONF: {
		if (-f $newfile) {
			open(HTTPDCONF, $newfile)
				or last SRMCONF;
			$data .= <HTTPDCONF>;
			close(HTTPDCONF);
		}
	}

	$virtual->{' '} = $data;

	my @data;
	my $servname;
	my $handle;
	my $main;
	foreach $handle (sort keys %$virtual) {

		undef $servname;
		@data = split /[\r\n]+/, $virtual->{$handle};
		my $port = $handle;
		$port =~ s/.*:(\d+).*/$1/ or $port = '';
		@data = grep /^\s*[^#]/, @data;
		for(@data) {
			next unless /^\s*servername\s+(.*)/i;
			$servname = $1;
			$servname =~ s/\s+$//;
			if(defined $servers->{$servname} and $port) {
				$servname .= ":$port";
			}
			elsif(defined $servers->{$servname} and $port) {
				$Error = "Server $servname defined twice.";
				return undef;
			}
			$servers->{$servname} = {};
		}
		
		if($handle eq ' ') {
			$servname = `hostname` unless $servname;
			$servname =~ s/\s+$//;
			$main = $servname;
		}
		next unless $servname;

		my ($line, $directive, $param, $key, $val);
		foreach $line (@data) {
			$line =~ s/^\s+//;
			$line =~ s/\s+$//;
			($directive,$param) = split /\s+/, $line, 2;
			$directive = lc $directive;
			if(defined $Http_hash{$directive}) {
				$servers->{$servname}->{$directive} = {}
					unless defined $servers->{$servname}->{$directive};
				($key,$val) = split /\s+/, $param, 2;
				$val =~ s/^"// and $val =~ s/"$//;
				if (defined $Http_process{$directive}) {
					$key = &{$Http_process{$directive}}('key', $key);
					$val = &{$Http_process{$directive}}('value', $val);
				}
				$servers->{$servname}->{$directive}->{$key} = $val;
			}
			elsif(defined $Http_scalar{$directive}) {
				$param =~ s/^"// and $param =~ s/"$//;
				if (defined $servers->{$servname}->{$directive}) {
					undef $servers->{$servname};
					$Error = "$directive defined twice in $servname, only allowed once.";
					return undef;
				}
				if (defined $Http_process{$directive}) {
					$param = &{$Http_process{$directive}}($param);
				}
				$servers->{$servname}->{$directive} = $param;
			}
		}
	}
			
	return $servers;
}

__END__
