#!/usr/local/bin/perl
#
# MakeCat.pm - routines for catalog configurator
#
# $Id $
#
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

## END CONFIGURABLE VARIABLES

package Vend::MakeCat;

use Cwd;
use File::Find;
use File::Copy;
BEGIN { $SIG{"__WARN__"} = sub { warn $_[0] if $DOWARN } }
use Archive::Tar;
BEGIN { $DOWARN = 1 }

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
$VERSION = substr(q$Revision: 1.8 $, 10);

$Force = 0;
$History = 0;
my %Pretty = qw(

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
	servername      ServerConf
	servername      ServerName
	catroot         CatRoot
	vendroot        VendRoot

);
 
 
my %Desc = (

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
# The location of the normal CGI directory. This is a UNIX
# file name, not a script alias.
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
# The type of demo catalog to use, sample or simple.
#
#    sample -- frame-based high-end catalog
#    simple -- no frames, good basic catalog
#
# If you have defined your own custom template catalog,
# you can enter it's name.
EOF
	documentroot    =>  <<EOF,
# The base directory for HTML for this (possibly virtual) domain.
# This is a UNIX directory name, not a URL -- it is your HTML
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
# Where the sample images should be installed. A UNIX directory
# name, not a URL.
#
EOF
	imageurl   =>  <<EOF,
# The URL base for the sample images. Sets the ImageDir
# directive in the catalog configuration file. This is a URL
# fragment, not a directory or file name.
#
#         <IMG SRC="/sample/images/icon.gif">
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

sub copy_current_to_dir {
    my($target_dir, $exclude_pattern) = @_;
    my $orig_dir = cwd();
    my @files; 
    my $wanted = sub {  
        return unless -f $_;
        my $name = $File::Find::name;
        $name =~ s:^\./::;
        return if $exclude_pattern and $name =~ m{$exclude_pattern}o;
        push (@files, $name);
    };
    File::Find::find($wanted, '.');  

	if (-f "$::VendRoot/bad_tar_pm") {
		my $f = "/tmp/mv_bad_tar_pm";
		open(TARCAT, "> $f") or die "Can't fork: $!\n";
		for(@files) { print TARCAT "$_\n" }
		close TARCAT;
		system "cat $f | xargs tar cf - | (cd $target_dir; tar xf -)";
		unlink $f;
		die "File copy failed: $!\n" if $?;
		return 1;
	}

    my $tar = Archive::Tar->new();   
    $tar->add_files(@files);
    chdir $target_dir   or die "Can't change directory to $target_dir: $!\n";
    $tar->extract(@files);
    chdir $orig_dir     or die "Can't change directory to $orig_dir: $!\n";
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
						print "\n";
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
		print "\n";
		return $default;
	}
    my($ans);

    print $prompt;
    print "[$default] " if $default;
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
		my ($file, $directive, $configname, $value) = @_;
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
					([^>]+)
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
		@data = grep /^\s*[^#]/, @data;
		for(@data) {
			next unless /^\s*servername\s+(.*)/i;
			$servname = $1;
			if(defined $servers->{$servname}) {
				$Error = "Server $servname defined twice.";
				return undef;
			}
			$servers->{$servname} = {};
		}
		
		if($handle eq ' ') {
			chomp($servname = `hostname`) unless $servname;
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
				if (defined $Http_process{$directive}) {
					$key = &{$Http_process{$directive}}('key', $key);
					$val = &{$Http_process{$directive}}('value', $val);
				}
				$servers->{$servname}->{$directive}->{$key} = $val;
			}
			elsif(defined $Http_scalar{$directive}) {
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
