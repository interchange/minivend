use ExtUtils::MakeMaker;
require ExtUtils::Install;

BEGIN {
	eval {
		require FindBin;
		chdir $FindBin::RealBin;
	};

}

use lib './lib';
use Config;

# Turn off compression warning, provide facility for future
# warning suppression
BEGIN { $SIG{"__WARN__"} = sub { warn $_[0] if $DOWARN } }
use Archive::Tar;
BEGIN { $DOWARN = 1 }

use File::Copy;
use Cwd;
require 5.003;

use strict;

use vars (qw($VERSION));

my $TermRead;
my $Prompt_sub;
my @mods_to_get;
my $Lock_troubles;
my $Windows;

# See if we have the CPAN module
my $Cpan = 0;
my $CpanInit;
eval { 	require CPAN;
		import CPAN;
};
unless($@) {
	$Cpan = 1;
}

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

sub copyright_prompt {

	print <<'EOF';

 MiniVend V3.05
 
 Copyright 1996,1997 by Michael J. Heins <mikeh@minivend.com>

 MiniVend is free as long as the organization or individual
 using it does not employ uninvited commercial email
 solicitations, commonly known as SPAM. Any organization
 sending SPAM (or causing it to be sent) may not use MiniVend
 for a period of one year after any SPAM incident. If use
 is not discontinued immediately upon written notice to the
 organization, a $1,000 per day license fee will be charged
 until such time as MiniVend use is discontinued. The author
 of MiniVend, Michael J. Heins, shall be the sole judge of
 what constitutes a SPAM incident.

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

Since you have the CPAN module installed, we can go and
get optional modules that help MiniVend work a bit better
and faster. At least we can if you are connected to the
Internet and have one of the following on your machine:

		Perl LWP libraries
		Perl Net::FTP library
		ncftp (a nice FTP program)
		lynx  (the text-based web browser)

In case you were wondering, CPAN is a worldwide network
of over 40 FTP sites which maintain the latest Perl software.
If you don't know a URL to use, you can try:

	ftp://uiarchive.uiuc.edu/pub/lang/perl/CPAN
	ftp://ftp.funet.fi/pub/languages/perl/CPAN

If you have never used CPAN before, you may want to reply NO.
MiniVend should work anyway -- it just won't be quite as
easy to build the demo catalogs.

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
Since you are on Solaris, you need either to update to Perl 5.004
or obtain the File::Lock module from CPAN. "make test" will fail if
you don't have one of the above.

If you have the CPAN module installed, MiniVend will try to get and
install File::Lock for you. If that succeeds, quit and re-run the
install.

If that fails, expect to fail the test. Try a 'make install' anyway. We
will then make one more attempt to install the module from a local copy.

If the last-ditch try  fails, you will have to get File::Lock and install
it before you can go further.

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
$Config{perlpath} Makefile.PL install $realdir\r
EOF
			close WINBAT;
			exit;
		}

		return \%X;
	}

	die "Shouldn't get here unless a 'make install'!?!\n"
		unless $install;


MODCHECK: {

	last MODCHECK unless $Cpan;
	last MODCHECK if $Windows;
	eval {
			require MD5;
		};
	push(@mods_to_get, 'MD5') if $@ and $Cpan;

	eval {require 5.004};
	if($@ and $Config{osname} =~ /solaris/i) {
		eval {
				require File::Lock;
			};
		push(@mods_to_get, 'File::Lock') if $@ and $Cpan;
	}
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

	# Would like to use module, but changes mode to read only!
	#ExtUtils::Install::install( {'dist', $realdir }, 1);

	my @files;
	my @winfiles;
	my $tar = Archive::Tar->new();
	my $origdir = cwd();
	open(MANIFILE, 'MANIFEST')
		or die "Couldn't open MANIFEST: $!\n";
	@files = <MANIFILE>;
	close MANIFILE;
	chomp(@files);
	if($Windows) {

		my $dll_source 	 = "win/cygwin.dll";
		my $dll_dir      = "c:/windows/system";
		my $dll_location = "c:/windows/system/cygwin.dll";
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

		require Win32::Shortcut;
		import Win32::Shortcut;
		my $short = new Win32::Shortcut;
		$short->Load("win/minivend.pif");
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
		open(WINBAT, ">makecat.bat") 
			or die "create makecat.bat: $!\n";
		print WINBAT <<EOF;
$Config{perlpath} $realdir/bin/makecat
EOF
		close(WINBAT);
		$short->{Path}				= "$realdir/makecat.bat";
		$short->{WorkingDirectory}	= "$realdir";
		$short->{Path} 				=~ s:/:\\:g;
		$short->{WorkingDirectory}	=~ s:/:\\:g;
		$short->{ShowCmd}			= 3;
		$short->{File}              = "Make MiniVend Catalog";
		$short->Save();

		File::Copy::copy('win/POSIX.pm', 'lib/POSIX.pm');
		@winfiles = grep m:^lib/:, @files;
		push @winfiles, 'makecat.bat', 'minivend.bat';
		push @winfiles, 'lib/POSIX.pm';
		push @winfiles, 'Start MiniVend Server.pif';
		push @winfiles, 'Make MiniVend Catalog.pif';
		$tar->add_files(@winfiles);
	}

	@files = grep m:^dist/:, @files;
	@files = map { s:^dist/::; $_} @files;

	if (-d $realdir) {
		for(@files) {
			next unless -f "$realdir/$_";
			unlink "$realdir/$_" or die "Couldn't unlink $realdir/$_: $!";
		}
	}
	else {
		mkdir $realdir, 0777 or die "mkdir $realdir: $!\n";
	}

	chdir 'dist';
	$tar->add_files(@files);
	chdir $realdir;
	$tar->extract(@files,@winfiles);
	chdir $origdir;
	# Before Archive::Tar
	#system "(cd dist; tar cf - *) | (cd $realdir; tar xf -)";
	#die "File copy failed: $!\n" if $?;

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

	my $perl = $Config{perlpath};
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
