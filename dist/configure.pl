#!/usr/local/bin/perl
#
# configure.pl - Configure the MiniVend program
#
# Version 1.1
# Copyright 1996,1997 by Michael J. Heins <mikeh@minivend.com>
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

# This script should be passed the Perl location as an argument,
# but there will be a chance to recover
#$DEBUG = 1;

# Set STDOUT to autoflush
$| = 1;

use Config;
use File::Path;
use ExtUtils::Install;
use lib "./lib";

# Find external commands

my $param;
PARAM: {
	my $param = shift || '';
	unless($param =~ /^-/) {
		if ($param) {
			$Initial{PERL} = $PERL = $param and
			$NoAsk{PERL} = 1;
		}
	}
	elsif ($param eq '-v') {
		$Initial{VendRoot} = shift and
		$NoAsk{VendRoot} = 1;
	}
	elsif  ($param eq '-D') {
		warn "****  Setting DEBUG to on   ****\n";
		$DEBUG = 1;
	}
	elsif  ($param eq '--' or $param eq '') {
		# Do nothing
	}
	else {
		warn "Unrecognized parameter $param, ignoring.\a\n"
			if $param;
	}
	last PARAM unless $param;
	redo PARAM;
} # PARAM

	
############### Configurable Variables ######################
#

use Cwd;

$Initial{'VendRoot'} = cwd();
$Initial{'HelpFile'} = 'etc/mvconf.cmt';

#
############## END CONFIGURABLE VARIABLES ###################

sub dontwarn {

}

sub prompt {
	return &$Prompt_sub(@_)
		if defined $Prompt_sub;
    my($pr) = shift || '? ';
    my($def) = shift;
    my($ans);

    print $pr;
    print "[$def] " if $def;
    chop($ans = <STDIN>);
    $ans ? $ans : $def;
}

sub install_perl_module {
	my ($mod, $dir) = @_;
	$dir = $dir || $mod;
    mkdir('lib/auto', 0755);
    chdir 'src' or die "Source directory src/ not found: $!\n";
    system "tar xf $mod.tar";
    chdir $dir or die "chdir: $!\n";
    my $makemake = <<EOF;
$PERL Makefile.PL INSTALLPRIVLIB=$Initial{VendRoot}/lib \
                  INSTALLARCHLIB=$Initial{VendRoot}/lib \
                  INSTALLSITELIB=$Initial{VendRoot}/lib \
                  INSTALLMAN1DIR=none \
                  INSTALLMAN3DIR=none \
                  INSTALLSITEARCH=$Initial{VendRoot}/lib \
                  INSTALLDIRS=perl
EOF
    for ($makemake, 'make', 'make test', 'make pure_perl_install') {
        system $_;
        if($?) {
			chdir '../..' or die "chdir: $!\n";
            my $msg = $_;
            $msg =~ s/ I.*//s;
            die "\nModule install FAILED on '$msg'.\n";
        }
    }
    chdir '../..' or die "chdir: $!\n";
    1;
}


sub adjustvars {
	my ($file,%vars) = @_;

	my $bak = 'mytemp.fil';
	return undef unless $file && defined %vars;

	my $check;
	my $changed = 0;
	my $save = $;
	$ = 0;
	for(keys %vars) {
		$vars{$_} = qq|'$vars{$_}'|
			unless int($vars{$_}) eq $vars{$_};
	}
	$ = $save;
	rename $file, $bak;
	open(ADJUST_IN,$bak)
		|| die "Couldn't open $bak: $!\n";
	open(ADJUST_OUT,">$file")
		|| die "Couldn't create $file: $!\n";

	while(<ADJUST_IN>) {
		unless (/^\s*(my\s+)?\$/) {
			print ADJUST_OUT $_;
			last if /^\s*#+\s+end\s+config/i;	# prevent parsing whole file
			next;
		}
		$line = $_;
		foreach $var (keys %vars) {
			if ($line =~ /^
							\s*(my\s+)?
							\$(\w+::)?
							$var\s*=\s*
							(\$(?:\w+::)?$var\s*\|\|\s*)?('?[^']+'?)\s*;/x) {
				my $my = $1 || '';
				my $pkg = $2 || '';
				my $or = $3 || '';
				$check = $4 || '';
				print "Found $var in $file\n" if $DEBUG;
				unless ($check eq $vars{$var}) {
					$changed++;
					$line = $my . '$' . $pkg . $var . ' = ' . $or . $vars{$var} . ";\n";
					print "Adjusted $var in $file\n" if $DEBUG;
				}
				delete $vars{$var};
			}
		}
		print ADJUST_OUT $line;
		unless (scalar keys %vars) {
			last;
		}
	}

	if ($changed) {
		while(<ADJUST_IN>) {print ADJUST_OUT $_}
		close ADJUST_IN;
		close ADJUST_OUT;
		unlink $bak;
	}
	else {
		close ADJUST_IN;
		close ADJUST_OUT;
		unlink $file;
		rename $bak, $file;
	}

	! scalar keys %vars;

}

sub adjustdefs {
	my ($file,%defs) = @_;
	my $changed = 0;

	my $bak = 'mytemp.fil';
	return undef unless $file && defined %defs;
	my $save = $;
	$ = 0;
	for(keys %defs) {
		$defs{$_} = qq|"$defs{$_}"|
			unless int($defs{$_}) eq $defs{$_};
	}
	$ = $save;

	rename $file, $bak;
	open(ADJUST_IN,$bak)
		|| die "Couldn't open $bak: $!\n";
	open(ADJUST_OUT,">$file")
		|| die "Couldn't create $file: $!\n";

	while(<ADJUST_IN>) {
		unless (/^#define/) {
			print ADJUST_OUT $_;
			next;
		}
		$line = $_;
		foreach $def (keys %defs) {
			my $val;
			if ($line =~ /^#define(\s+)$def(\s+)(.*)/) {
				my $sp1 = $1;
				my $sp2 = $2;
				my $val = $3;
				unless ( $val eq $defs{$def} ) {
					$changed++;
					$line = '#define' . $sp1 . $def . $sp2 . $defs{$def} . "\n";
					print "Adjusted $def in $file\n" if $DEBUG;
				}
				delete $defs{$def};
			}
		}
		print ADJUST_OUT $line;
		unless (scalar keys %defs) {
			last;
		}
	}

	if ($changed) {
		while(<ADJUST_IN>) {print ADJUST_OUT $_}
		close ADJUST_IN;
		close ADJUST_OUT;
		unlink $bak;
	}
	else {
		close ADJUST_IN;
		close ADJUST_OUT;
		unlink $file;
		rename $bak, $file;
	}

	! scalar keys %defs;
}


sub shbang {
	my $file = shift;
	my $perl = shift;
	my $changed = 0;
	my $bak = 'mytemp.fil';
	return undef unless $file && $perl;
	rename $file, $bak;
	open(ADJUST_IN,$bak)
		|| die "Couldn't open $bak: $!\n";
	open(ADJUST_OUT,">$file")
		|| die "Couldn't create $file: $!\n";
	while(<ADJUST_IN>) {
		if (/^(#\!\s*)(\S+)/) {
			my $precursor = $1;
			my $current = $2;
			unless ($perl eq $current) {
				$changed++;
				s/$current/$perl/;
			}
		}
		else {
			s/^/'#!' . $perl . "\n"/e;
		}
		print ADJUST_OUT $_;
		last;
	}
	if ($changed) {
		while(<ADJUST_IN>) {print ADJUST_OUT $_}
		close ADJUST_IN;
		close ADJUST_OUT;
		print "Adjusted SHBANG in $file to $perl\n" if $DEBUG;
		unlink $bak;
	}
	else {
		close ADJUST_IN;
		close ADJUST_OUT;
		unlink $file;
		rename $bak, $file;
	}

	1;
}

sub findexe {
	my($exe) = @_;
	my($dir,$path) = ('', $ENV{PATH});
	if($Config{osname} =~ /bsd/i and $path !~ /sbin/) {
		$path .= ":/usr/sbin:/sbin";
	}
	$path =~ s/\(\)//g;
	$path =~ s/\s+/\s/g;
	my(@dirs) = split /[\s:]+/, $path;
	foreach $dir (@dirs) {
		return "$dir/$exe" if -x "$dir/$exe";
	}
	return '';
}

sub get_detailed_param {
	my $param = shift;
	my $result;
	if($Help{$param}) {
		print "\n\n", $Help{$param};
	}

	unless (defined $Initial{$param}) {
		$Initial{$param} = ($Default{$param} =~ /BLANK_DEFAULT|UNDEFINED/)
							? ''
							: $Default{$param};
	}

	$result = prompt("$param? ", $Initial{$param});
}

### Start main configuration

if (open(HELP, $Initial{'HelpFile'})) {
	$/ = '';
	while(<HELP>) {
		my ($thing, $comment) = split /\n/, $_, 2;
		my ($var, $default) =  split /\s+/, $thing, 2;
		$Help{$var} = $comment;
		$Default{$var} = $default;
	}
	close HELP;
	$/ = "\n";
}
else {
	die "Ooops! No helpfile. Can't continue.\n";
}

require 5.002 || die <<EOF;

Sorry, MiniVend requires at least Perl 5.002 to be assured of running
properly. (If you know enough about UNIX and Perl to defeat this check,
then you might know enough to get it running with 5.002).

Please upgrade your Perl before installing MiniVend 2.0.

EOF

if (open(MANIFEST, 'manifest')) {
	while(<MANIFEST>) {
		next if /^#/;
		next unless /\S/;
		chomp;
		($file,$type,$perms,$funcs) = split /\s+/, $_, 4;
		push(@Files,$file);
		$Type{$file} = $type;
		$Perms{$file} = oct($perms);
		$Funcs{$file} = $funcs;
	}
	close MANIFEST;
}
else {
	die "\nCouldn't open manifest: $!\n";
}

my @params = qw(PERL);

unless (-x '/usr/lib/sendmail') {
	$Initial{SendMailLocation} = findexe('sendmail');
	push @params, 'SendMailLocation';
}

for(@params) {
	$ = 0;
	$save = $Initial{$_};
	$Done{$_} = 1;
	unless ($NoAsk{$_} or ($Initial{$_} = get_detailed_param($_)) eq $save )
	{
		$Changed{$_} = 1;
	}
	$ = 1;
}

print "\nEntering $Initial{'VendRoot'}.\n";
chdir $Initial{'VendRoot'}
	|| die "Couldn't change directory to $Initial{'VendRoot'}: $!\n";

$Upgrade = -f 'minivend.cfg' ? 1 : 0;

	@Keyfiles = (
					"$Initial{VendRoot}",
					"$Initial{VendRoot}/error.log",
					"$Initial{VendRoot}/etc",
				);
	# Change ownership of key files if we are root.
if($< == 0) {
	print <<EOF;

The root user cannot run the MiniVend server for security reasons.

Since you are the superuser, you must change the ownership of the
MiniVend directory to that of the user ID that will run MiniVend.
You may also if you wish set the group -- it will default to the
default group of the user.

EOF
	for(;;) {
			$UserName = prompt("User who will run MiniVend? ", '');
			($UserID,$GroupID) = (getpwnam($UserName))[2,3];
			last if defined $UserID;
			print "Error -- that is not a valid user name on this machine.\n\n";
		}
		$GroupName = (getgrgid($GroupID))[0];
		for(;;) {
			$GroupName = prompt("Group to own MiniVend? ", $GroupName);
			$GroupID = (getgrnam($GroupName))[2];
			last if defined $GroupID;
			print "Error -- that is not a valid group name on this machine.\n\n";
		}
		for(@Keyfiles) {
			chown ($UserID, $GroupID, $_)
				or die "Couldn't change ownership of $Initial{VendRoot}: $!\n";
		}
		print "\n";
	}
elsif (! $NoAsk{VendRoot}) {
	print <<EOF;

-------------------------------------------------------------------
FYI, if you are installing this software as another user name than
the one which will ultimately run MiniVend, you will need to change
ownership of two directories to that user name before it will
work properly.  That includes the main MiniVend directory 
$Initial{VendRoot}, and the configuration directory
$Initial{VendRoot}/etc.  The command to accomplish that
(as root) is:

EOF
    for(@Keyfiles) { print "chown <username> $_\n"; }

	print <<EOF;
	
Substitute the proper user name for <username>.
-------------------------------------------------------------------

EOF
}

LOCK: {
	last LOCK unless
		$Config{'osname'} =~ /solaris/i;
	if($ENV{PATH} !~ m:/usr/ccs/bin:) {
		$ENV{PATH} = "$ENV{PATH}:/usr/ccs/bin";
	}
	eval {require 5.004};
	last LOCK unless $@;
	eval {require File::Lock} and last LOCK; 

		print <<EOF;

Your operating system ($Config{'osname'}) doesn't fully support
flock(), so you will need the File::Lock module in order for
MiniVend to operate.  the latest version can be obtained from
http://www.perl.com in the CPAN area.  Expect a ***fatal*** error
if you don't have it when you start MiniVend.

MiniVend will try and make a last ditch attempt to install this
module now.

EOF
	eval {install_perl_module('File-Lock-0.9') };
	if($@) {
		print "$@\n\nMiniVend has to give up on File::Lock.\n";
	}
	else {
		print "Module apparently installed correctly.\n";
	}

} # last LOCK

$Initial{'LINK_FILE'} = $Initial{'VendRoot'} . '/' . 'etc/socket'
	unless defined $Initial{'LINK_FILE'};

for (sort keys %Default) {
	next if $Done{$_};
	$Done{$_} = 1;
	unless ($Initial{$_}) {
		$Initial{$_} = $Default{$_};
	}
	else {
		$Changed{$_} = 1;
	}
}

ADJUST: {

print "\nAdjusting program variables and defines...";

my(@funcs);
my(@vars);
my(@params);
my($func, $file);

foreach $file (@Files) {
	next unless defined $Funcs{$file};
	if($Type{$file} eq 'csrc') {
		@funcs = split /\s*,\s*/, $Funcs{$file};
		foreach $func (@funcs) {
			@params = ();
			next unless $func =~ /^defs/i;	
			($junk, @vars) = split /\s*:\s*/, $func;
			for(@vars) { push(@params, $_, $Initial{$_}); }
			print "Calling adjustdefs with " . join(':',@params) . "\n"
					if $DEBUG;
			adjustdefs($file,@params)
				|| die "Something was wrong with $file, couldn't adjust defs.\n";
		}
	}
	elsif($Type{$file} eq 'script') {
		@funcs = split /\s*,\s*/, $Funcs{$file};
		foreach $func (@funcs) {
			@params = ();
			if($func =~ /^vars/i) {
				($junk, @vars) = split /\s*:\s*/, $func;
				for(@vars) { push(@params, $_, $Initial{$_}); }
				print "Calling adjustvars with " . join(':',@params) . "\n"
					if $DEBUG;
				adjustvars($file,@params)
					|| die "Something was wrong with $file, couldn't adjust vars.\n";
			}
			elsif("\L$func" eq 'shbang') {
				shbang($file,$PERL);
			}
		}
		chmod $Perms{$file}, $file
			|| warn "Couldn't set permissions for $file: $!\n";
	}
}

print "done.\n";

} # end ADJUST

$default = $ans = 'yes';
if($Upgrade) {
	$default = 'no';
	print <<EOF;
You only need to re-make vlink if you have changed directories.

EOF
	$ans = prompt "Make the dispatch programs vlink and tlink? ", $default;
}
if ($ans =~ /^\s*y/i) {
	my($vfail, $tfail);
	my $CC = findexe('cc') || findexe('gcc');
	warn "No C compiler found, this phase will not be successful, I bet...\n"
		unless $CC;
	$? = 1;
	chdir 'src' || die "Couldn't change to source directory: $!\n";
	system "./configure";
	eval `cat syscfg`;
	print "Compiling, this may take a sec...";
	unless($?) {
		$? = 1;
        print "Compiling with $CC $CFLAGS $LIBS -o vlink vlink.c'\n"
                      if $DEBUG;
		system "$CC $CFLAGS $LIBS -o ../bin/vlink vlink.c";
		if($?) {
			warn "\nCompiliation of vlink.c FAILED.\n";
			$vfail = 1;
		}
		system "$CC $CFLAGS $LIBS -o ../bin/tlink tlink.c";
		if($?) {
			warn "\nCompiliation of tlink.c FAILED.\n";
			$tfail = 1;
		}
	}
	else {
		$vfail = 1; 
		$tfail = 1; 
		warn "\nConfiguration of link programs FAILED.\n";
	}
	print "done.\n";
	chdir '..' || die "Couldn't change back to $Initial{'VendRoot'}: $!\n";
	$Compile_failed = 1 if (defined $vfail or defined $tfail);
}

print <<EOF;

That takes care of the program configuration.

EOF

if ($Compile_failed) {
	print <<EOF;

The compilation of one or both link programs (tlink and/or
vlink) failed.  You may be able to use the Perl-based tlink.pl
program along with starting the server in INET mode (start_inet)
to make MiniVend work.

Using vlink.pl requires either that your installation use
CGIWRAP or that you compile it with a wrapper such as the Perl
example 'wrapsuid' program.

EOF
	exit 1;
}

print <<EOF;

If you are updating from a previous version of MiniVend, you
will want to look at the README file for possible small changes
you must make to your catalog configuration.

If this is your first time using MiniVend, you will want to make
a sample catalog.  If you decide not to do it now, then you will
need to run:

	cd $Initial{VendRoot}
	bin/makecat

At that point, MiniVend will be ready to run. Start the daemon
with:

	$Initial{VendRoot}/bin/start

Welcome to MiniVend!

EOF
