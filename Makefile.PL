use ExtUtils::MakeMaker;
require ExtUtils::Install;

BEGIN {
	eval {
		require FindBin;
		chdir $FindBin::RealBin;
	};
}

use Config;

use File::Copy;
use File::Path;
use File::Basename;
use Cwd;
require 5.004;

use strict;

use vars (qw($VERSION $DOWARN));

my $TermRead;
my $Prompt_sub;
my @mods_to_get;
my $Lock_troubles;
my $Windows;

$VERSION = '3.10';

# See if we have the CPAN module
my $Cpan = 0;
my $CpanInit;
eval { 	
		die if $ =~ /win32/i;
		unless( -f ".cpan.tried") {
			open TMP, ">.cpan.tried" and close TMP;
			require CPAN::Config;
			require CPAN;
			import CPAN;
		}
		unlink ".cpan.tried";
};
unless($@) {
	$Cpan = 1;
}

my (@extra_lib_dirs);
my (@extra_lib_files);


# Now we can use the libraries
use lib './lib';


my $origdir = fastcwd();

# See if we have Term::ReadLine::Perl
eval {
		require Term::ReadLine;
		require Term::ReadLine::Perl;
		require Term::ReadKey;
		$TermRead = 1;
};
unless($@) {
	$ENV{PERL_RL} = 'Perl';
}
elsif ($Cpan) {
	push @mods_to_get, 'Term::ReadKey', 'Term::ReadLine::Perl';
}

my $term;
if($TermRead) {
	$term = new Term::ReadLine 'MakeFile';
	$Prompt_sub = sub {
		my($prompt, $default) = @_;
		$prompt .= "[$default] "
			if defined $default && !$ENV{PERL_RL};
		return $term->readline($prompt, $default);
	};
}

if($Config{osname} eq 'solaris') {
	eval { require 5.004 or require File::Lock };
	if($@) {
		push @mods_to_get, "File::Lock";
		$Lock_troubles = 1;
	}
}
elsif($Config{osname} =~ /win32/i) {
	$Windows = 1;

	eval { require 5.004; };
	if($@) {
				print <<EOF;
Sorry -- this version of MiniVend for Windows requires
Perl 5.004 -- the standard port of Perl.  The ActiveState
5.003 version will not run MiniVend.

See http://www.perl.com/ for information on how to get
the standard Perl distribution.
EOF
	}

}
elsif(	$Config{osname} =~ /linux/i		and
		$Config{d_gnulibc} eq 'define'	and
		$Config{POSIX_cflags} !~ /STRUCT_TM_HASZONE/	and
		! defined $ENV{MINIVEND_BADPOSIX})
{
	if (! -f ".linux.warned") {
		system "touch .linux.warned";
		print <<EOF;

This looks like a broken version of Perl for Linux, as often
happens with improperly built GLIBC Perls. RedHat Linux 5.0 has
this problem. If your Perl is built properly and does not dump
core when calling POSIX::strftime, then set the environment
variable MINIVEND_BADPOSIX to 0.

If it is built improperly, you will soon find out, for this
installation will stop. If it does, then you can re-run and
we will limp along as best we can, though it is recommended 
that you update your Perl.

EOF
		 print "Trying strftime, if we stop re-run configure.\n";
		 require POSIX;
		 POSIX::strftime("%c", 0,0,0,1,1,97);
		 print "\nYour perl appears to be OK. Good.\n";
	 }
	 elsif( -f 'core') {
		unlink 'core';
		system "echo REMOVE_THIS_FILE_IF_YOU_UPDATE_PERL > dist/.linux.badposix";
		print <<EOF;
Compensating for badly-built GLIBC Perl. Please update Perl as soon as 
possible. Once you do so, you can remove the file "linux.badposix".

EOF
		$ENV{MINIVEND_BADPOSIX} = 1;
	}
}

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
	my ($srcdir, $targdir, $filename) = @_;
	my $srcfile  = $srcdir . '/' . $filename;
	my $targfile = $targdir . '/' . $filename;
	my $mkdir = File::Basename::dirname($targfile);
	my $extra;
	my $perms;

	if(! -d $mkdir) {
		File::Path::mkpath($mkdir)
			or die "Couldn't make directory $mkdir: $!\n";
	}

	if ($Windows) {
		$perms = 0777;
	}
	elsif (! -f $srcfile) {
		die "Source file $srcfile missing.\n";
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
	chmod $perms, $targfile;

}

sub copyright_prompt {

	print <<EOF;

 MiniVend V$VERSION
 
 Copyright 1996-1998 by Michael J. Heins <mikeh\@minivend.com>

 MiniVend is free under the terms of the GNU General Public License.

EOF
}

sub my_prompt {
    return &$Prompt_sub(@_)
        if defined $Prompt_sub;
    my($pr) = shift || '? ';
    my($def) = shift;
    my($ans);

    print $pr;
    print "[$def] " if $def;
    chomp($ans = <STDIN>);
    $ans ? $ans : $def;
}

sub cpan_get {
	my($module, $libdir, $prompt) = @_;
	
	print <<EOF unless defined $CpanInit;

Since you have the CPAN module installed and initialized,
we can go and get optional modules that help MiniVend work a
bit better and faster. At least we can if you are connected
to the Internet and have one of the following on your machine:

		Perl LWP libraries
		Perl Net::FTP library
		ncftp (a nice FTP program)
		lynx  (the text-based web browser)

In case you were wondering, CPAN is a worldwide network of
over 40 FTP sites which maintain the latest Perl software.
If you don't know a URL to use, you can try:

	ftp://ftp.cdrom.com/pub/perl/CPAN
	ftp://ftp.funet.fi/pub/languages/perl/CPAN

If you have never used CPAN before, you may want to reply NO.
MiniVend should work anyway -- it just won't be quite as easy
to build the demo catalogs.

If you have errors during the process, don't worry. Either
just continue on or stop the program and try again, replying
No when prompted for CPAN.

EOF
	$prompt = "Get $module module? [yes]" unless defined $prompt;
	my $ask = my_prompt($prompt);
	return undef if $ask =~ /^\s*n/i;
	
	return undef unless defined $CPAN::Config;
	$CPAN::Config->{makepl_arg} = "INSTALLPRIVLIB=$libdir/lib INSTALLARCHLIB=$libdir/lib INSTALLSITELIB=$libdir/lib INSTALLMAN1DIR=none INSTALLMAN3DIR=none INSTALLSITEARCH=$libdir/lib INSTALLDIRS=perl";
	return install($module);
}

sub initialize {
    my %X=();
    $X{INSTALLARCHLIB}	= "/home/minivend/lib";
    $X{INSTALLPRIVLIB}	= "/home/minivend/lib";
    $X{INSTALLMAN1DIR}	= "/home/minivend/doc";
    $X{INSTALLMAN3DIR}	= "/home/minivend/doc";
    $X{INSTALLDIRS}     = "perl";

	my $install = 0;
	my $realdir;

	for(@ARGV) {
		return \%X  if /^nocopy$/;
		($install = 1, next) if /^install$/;
		next unless $install;
		$realdir = $_;
		$realdir =~ s:/lib$::;
	}

	unless ($install) {

		#exec("perl install.pl") if $Windows;
		&copyright_prompt();

		my @mvdir = (
						"$ENV{HOME}/mvend",
						"/home/minivend",
						"/usr/local/lib/minivend",
						"$ENV{HOME}/minivend",
					);
		if(defined $Lock_troubles) {
				print <<EOF;
Since you are on Solaris, you need to update to Perl 5.004.
Sorry.
EOF
		}
		my $mvdir;

		for $mvdir (@mvdir) {
			if (-f "$mvdir/minivend.cfg") {
				$realdir = $mvdir if -w $mvdir;
				last;
			}
		}
		$realdir ||= $mvdir[0];
		$realdir=my_prompt("Where is your MiniVend to be installed? ",$realdir);

		$realdir =~ s:[\\/]\s*$::;
		$X{INSTALLARCHLIB}	= "$realdir/lib";
		$X{INSTALLPRIVLIB}	= "$realdir/lib";
		$X{INSTALLMAN1DIR}	= "$realdir/doc";
		$X{INSTALLMAN3DIR}	= "$realdir/doc";
		$X{INSTALLDIRS}     = "perl";

		if($Windows) {
			open(WINBAT, ">configure2.bat")
				or die "create configure2.bat: $!\n";
			print WINBAT <<EOF;
CALL $Config{perlpath} Makefile.PL install $realdir\r
pause\r
EOF
			close WINBAT;
			exit;
		}

		return \%X;
	}

	die "Shouldn't get here unless a 'make install'!?!\n"
		unless $install;

	# Do the extra library checks
	eval {
		require File::Spec;
	};
	if ($@) {
		push @extra_lib_dirs, 'File', 'File/Spec';
		my (@f) = glob 'extra/File/Spec/*';
		for (@f) { s:extra/:: }
		push @extra_lib_files, 'File/Spec.pm', @f;
	}

	# We will use our own version of File::CounterFile always
	push @extra_lib_dirs, 'File';
	push @extra_lib_files, 'File/CounterFile.pm';

	eval {
		require IniConf;
	};
	if ($Windows or $@) {
		push @extra_lib_files, 'IniConf.pm';
	}

	eval {
		require HTML::Entities;
	};
	if ($@) {
		push @extra_lib_dirs, 'HTML';
		push @extra_lib_files, 'HTML/Entities.pm';
	}


MODCHECK: {

	last MODCHECK unless $Cpan;
	last MODCHECK if $Windows;
	eval {
			require MD5;
		};
	push(@mods_to_get, 'MD5') if $@ and $Cpan;
	eval {
			require SQL::Statement;
		};
	push(@mods_to_get, 'SQL::Statement') if $@ and $Cpan;

}


my $Upgrade;
UPGRADE: {
	if(	-f "$realdir/minivend.cfg" and
		(-f "$realdir/minivend.pl" or -f "$realdir/bin/minivend"))
	{
		my $msg;
		print <<EOF unless defined $Upgrade;
This looks like an upgrade.

If you are upgrading from MiniVend 2.03 (or MiniVend 3.0 
beta 6 or less) than the directory structure is changed
quite a bit.

Your minivend.cfg file will be saved, but other files will
be overwritten and MAY BE REMOVED WITHOUT WARNING.
Any custom templates that are not in the 'simple'
or 'sample' directories will be saved.

If you wish to escape to the shell and save some files
first, enter ! or 'sh' at the prompt. (Of course when
you 'exit' from the shell, you will return to this
configuration.)

If you reply 'quit', or 'no' at the prompt, this
installation will stop.

EOF
		$Upgrade = 1;
		$msg = "Continue? ";
		my $ask = my_prompt($msg);
		exit 1 if $ask =~ /^\s*[qn]/i;
		if($ask =~ /^\s*sh/ or $ask =~/^\s*!\s*$/) {
			system "$ENV{SHELL}";
			if($?) {
				die "\nShell escape failed.\n";
			}
			redo UPGRADE;
		}
		elsif($ask =~ s/^\s*!(.*)/$1/s) {
			system "$ask";
			redo UPGRADE;
		}

		print <<EOF;

You may wish to inspect minivend.cfg.dist for new values.

If you have used static page building, you must now 
define "Static Yes" in all of your catalog.cfg files
or the catalog will not run with static pages.

Check the README file for changes you might have to make if
updating from an earlier version of MiniVend.
EOF

	}
}

	COPYEXTRA: {
		my $cpdir = $Windows ? '.' : $realdir;
		mkdir $cpdir, 0777 unless -d $cpdir;
		mkdir "$cpdir/lib", 0777 unless -d "$cpdir/lib";
		for(@extra_lib_dirs) {
			next if -d "$cpdir/lib/$_";
			mkdir "$cpdir/lib/$_", 0777 or die "mkdir $cpdir/lib/$_: $!\n";
		}

		for(@extra_lib_files) {
			File::Copy::copy ("extra/$_", "$cpdir/lib/$_")
				or die "Couldn't copy $_: $!\n";
		}
	}

	my @files;
	my @winfiles;
	my $tar;

	my $origdir = cwd();
	open(MANIFILE, 'MANIFEST')
		or die "Couldn't open MANIFEST: $!\n";
	@files = <MANIFILE>;
	close MANIFILE;
	chomp(@files);
	for(@extra_lib_files) {
		push @files, "lib/$_";
	}
	$ = 0;
	if($Windows) {
		my $dll_source 	 = "win/cygwin.dll";
		my $dll_dir;
		for( $ENV{SYSTEMROOT}, qw! c:/windows d:/windows e:/windows f:/windows !) {
			-d $_ and $dll_dir = $_;
		}
		$dll_dir      .= '/system';
		$dll_dir =~ s:\\:/:g;
		my $dll_location = $dll_dir . "/cygwin.dll";
	DLL: {
		unless(-f $dll_location) {
			if (-f $dll_source and -d $dll_dir) {
				File::Copy::copy( $dll_source, $dll_location);
			}
			elsif (-f $dll_source) {
				print <<EOF;
ERROR: The directory $dll_dir
was not found. Enter the path to your Windows
DLL directory, or enter nothing to skip the DLL
installation.

(MiniVend installation will continue,
but you may need to consult the README.win32 file
to find out how to install the CGI program.)
EOF
				$dll_dir = my_prompt("DLL directory: ");
				redo DLL if $dll_dir;
			}
			else {
				print <<EOF;
MiniVend requires the CYGWIN.dll module for the .EXE version of
its CGI program to run. We did not find it in the normal c:/windows/system
location, and it is not included in this version of the ZIP file.

You will either need to get it, or you will need to use the tlink.pl program.
(Many Windows web servers require some additional setup to run Perl CGI
programs.)

The CYGWIN.DLL file is available at:

		ftp://ftp.minivend.com/pub/cygwin.dll

Enter nothing at the following prompt to put off getting this file.

EOF
				$dll_source = my_prompt("Enter another path to CYGWIN.DLL: ");
				redo DLL if $dll_source;
			}
		
		}
	}
		umask 0;
		require Win32::Shortcut;
		import Win32::Shortcut;
		my $short = new Win32::Shortcut;
		# Apparently Win32::Shortcut won't reliably work when starting
		# from here
		#$short->Load("win/minivend.pif");
		open(WINBAT, ">minivend.bat") 
			or die "create minivend.bat: $!\n";
		print WINBAT "set PGPPATH=$ENV{PGPPATH}\n" if $ENV{PGPPATH};
		print WINBAT <<EOF;
set MINIVEND_ROOT=$realdir
$Config{perlpath} $realdir/bin/minivend -serve
EOF
		close(WINBAT);
		$short->{Path}				= "$realdir/minivend.bat";
		$short->{WorkingDirectory}	= "$realdir";
		$short->{Path} 				=~ s:/:\\:g;
		$short->{WorkingDirectory}	=~ s:/:\\:g;
		$short->{File}              = "Start MiniVend Server";
		$short->Save();
		undef $short;
		open(WINBAT, ">makecat.bat") 
			or die "create makecat.bat: $!\n";
		print WINBAT <<EOF;
$Config{perlpath} $realdir/bin/makecat
EOF
		close(WINBAT);
		$short = new Win32::Shortcut;
		# Apparently Win32::Shortcut won't reliably work when starting
		# from here
		#$short->Load("win/minivend.pif");
		$short->{Path}				= "$realdir/makecat.bat";
		$short->{WorkingDirectory}	= "$realdir";
		$short->{Path} 				=~ s:/:\\:g;
		$short->{WorkingDirectory}	=~ s:/:\\:g;
		$short->{File}              = "Make MiniVend Catalog";
		$short->Save();

		File::Copy::copy('win/POSIX.pm', 'lib/POSIX.pm')
			or die "File::Copy::copy error 'win/POSIX.pm': $!\n";
		File::Copy::copy('Start MiniVend Server.pif', 'dist')
			or die "File::Copy::copy error 'Start MiniVend Server.pif': $!\n";
		File::Copy::copy('Make MiniVend Catalog.pif', 'dist')
			or die "File::Copy::copy error 'Make MiniVend Catalog.pif': $!\n";
		@winfiles = grep m:^lib/:, @files;
		push @winfiles, 'makecat.bat', 'minivend.bat';
		push @winfiles, 'lib/POSIX.pm';
		push @winfiles, 'Start MiniVend Server.pif';
		push @winfiles, 'Make MiniVend Catalog.pif';
		for (@winfiles) {
			install_file('.', $realdir, $_);
		}
	}

	@files = grep m:^dist/:, @files;
	@files = map { s:^dist/::; $_} @files;

	# New install_file routine
	chdir 'dist';
	for (@files) {
		install_file('.', $realdir, $_);
	}

	$ = 0;

	MODGET: {
		last MODGET unless $Cpan;
		last MODGET if $Windows;
		my $mod;
		foreach $mod (@mods_to_get) {
			my $ok = eval { cpan_get($mod, $realdir)};
			if (! $@) {
				$CpanInit = 1;
				print "\n\n";
			}
			else {
				print "\a\n$mod get failed.\n\n";
			}
		}
		chdir $origdir;
	}

	my $perl = $Windows ? 'perl' : $Config{perlpath};
	chdir $realdir;
	system "$perl configure.pl -v $realdir $perl";
    exit;
}

sub regularize {
	for (@_) {
			s/[\\]\n//g;
			s/\n\s+/ /g;
			s/\s+$//g;
	}
	wantarray ? @_ : $_[0];
}

sub MY::install {

	my $self = shift;
	local *install;

	my $new = <<'EOF';
mv_install ::
			$(PERL) Makefile.PL install $(INSTALLARCHLIB)

install :: all pure_install doc_install mv_install

EOF
	$_ = $self->MM::install;
	s/\ninstall :.*/$new/;
	$_;
}

WriteMakefile(
	NAME       => "MiniVend",
	"DISTNAME" => "minivend",
	"MAN1PODS" => {},
	"dist"     => { SUFFIX   => ".gz", DIST_DEFAULT => 'all tardist',
			    COMPRESS => "gzip -9f", ZIP_FLAGS => '-pr9' },
	VERSION_FROM => "dist/bin/minivend",
	EXE_FILES => [],
	CONFIGURE  => \&initialize,
);
