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
use Data::Dumper;
use Cwd;
require 5.005;

use strict;

use vars (qw($VERSION $DOWARN));

my $TermRead;
my $Prompt_sub;
my @mods_to_get;
my $Lock_troubles;

$VERSION = '4.00';

# See if we have the CPAN module
my $Cpan = 0;
my $CpanInit;
eval { 	
		die if $^O =~ /win32/i;
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

my @extra_lib_dirs;
my @extra_lib_files;
my @chown_files = qw/
						error.log
						etc
						minivend.cfg
					/;

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

if($^O =~ /win32/i) {
	die "Windows is only supported for a binary distribution.\n";
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

	if (! -f $srcfile) {
		die "Source file $srcfile missing.\n";
	}
	else {
		$perms = (stat(_))[2] & 0777;
	}

	if( -f $targfile and ! compare_file($srcfile, $targfile) ) {
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
 
 Copyright 1996-2000 by Michael J. Heins <mikeh\@minivend.com>

 MiniVend is free under the terms of the GNU General Public License.

EOF
}

sub my_prompt {
    return $_[1] if $MV::Default{force};
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
	$CPAN::Config->{keep_source_where} = "$libdir/src"
		unless -w $CPAN::Config->{keep_source_where};
	$CPAN::Config->{cpan_home} = "$libdir/src"
		unless -w $CPAN::Config->{cpan_home};
	$CPAN::Config->{build_dir} = "$libdir/src"
		unless -w $CPAN::Config->{build_dir};
	return CPAN::install($module);
}

sub initialize {
    my %X;
    $X{INSTALLDIRS}     = "perl";
	$X{EXE_FILES}  = [qw(
							scripts/compile_link
							scripts/config_prog
							scripts/configdump
							scripts/dump
							scripts/expire
							scripts/expireall
							scripts/localize
							scripts/makecat
							scripts/minivend
							scripts/offline
							scripts/restart
							scripts/update
						)];
	$X{PL_FILES}  = {qw(
							scripts/compile_link.PL scripts/compile_link
							scripts/config_prog.PL scripts/config_prog
							scripts/configdump.PL  scripts/configdump
							scripts/dump.PL        scripts/dump
							scripts/expire.PL      scripts/expire
							scripts/expireall.PL   scripts/expireall
							scripts/localize.PL    scripts/localize
							scripts/makecat.PL     scripts/makecat
							scripts/minivend.PL    scripts/minivend
							scripts/offline.PL     scripts/offline
							scripts/restart.PL     scripts/restart
							scripts/update.PL      scripts/update
						)};

	if(! $MV::Default{force} and ! $MV::Default{PREFIX}) {
		if($> == 0) {
			$MV::Default{PREFIX} = '/usr/local/minivend';
		}
		else {
			$MV::Default{PREFIX} = "$ENV{HOME}/mvend";
		}
	}
	my $uid;
	if($> == 0 and ! $MV::Default{MINIVEND_USER}) {
		$uid = my_prompt(
			qq{MiniVend cannot be run as root. Which user should run MiniVend? },
			'minivend',
		);
		open(UID, ">_uid")
			or die "Can't write uid file: $!\n";
		print UID "$uid";
		close UID;
	}
	else {
		eval {
			$uid = scalar getpwuid($>);
		};
	}
	return %X if $MV::Default{nocopy};
	if($uid) {
		open(UID, ">_uid")
			or die "Can't write uid file: $!\n";
		print UID "$uid";
		close UID;
	}
	for(@Config{
				  qw/
					  archlib
					  archlibexp
					  privlib
					  privlibexp
					  sitearch
					  sitearchexp
					  sitelib
					  sitelibexp
				  /
		})
	{
		die "Can't install in Perl library!\n" if $MV::Default{PREFIX} eq $_;
	}

	my $realdir;

	if(! $MV::Default{final}) {
		&copyright_prompt();

		$realdir = my_prompt(
								"Where is your MiniVend to be installed? ",
								$MV::Default{PREFIX},
								);
		print "\n";
		$realdir =~ s:[\\/]\s*$::;
	}
	else {
		$realdir = $MV::Default{final};
	}

	$X{INSTALLSCRIPT}	= "$realdir/bin";
	$X{INSTALLBIN}		= "$realdir/bin";
	$X{INSTALLARCHLIB}	= "$realdir";
	$X{INSTALLPRIVLIB}	= "$realdir/lib";
	$X{INSTALLMAN1DIR}	= "$realdir/doc";
	$X{INSTALLMAN3DIR}	= "$realdir/doc";

	my @re_dir  = qw( simple/download );
	my @re_copy = qw(	
						../pod/mvdocs.pod simple/download/mvdocs.pod
						../pod/mvfaq.pod simple/download/mvfaq.pod
						);

	if($MV::Default{final}) {
		$ = 0;
		for(glob "_*") {
			File::Copy::copy($_, $realdir);
		}
		open(MANI, "MANIFEST")
			or die "No MANIFEST?\n";
		my (@files) = <MANI>;
		close MANI;
		@files = grep m:^dist/:, @files;
		chomp(@files);
		@files = map { s:^dist/::; $_} @files;

		# New install_file routine
		chdir 'dist';
		for (@re_dir) {
			mkdir $_, 0777;
		}
		while ($_ = shift @re_copy ) {
			my $from = $_;
			my $to = shift @re_copy;
			push @files, $to;
			File::Copy::copy($from, $to);
		}
		for (@files) {
			install_file('.', $realdir, $_);
		}
		if(-f "$realdir/_uid" and $> == 0) {
			open(UID, "$realdir/_uid")
				or die "Can't open uid file: $!\n";
			my $uid = <UID>;
			close UID;
			$MV::Default{MINIVEND_UID} = getpwnam($uid);
			$MV::Default{MINIVEND_GID} = getgrnam($uid);
			for(@chown_files) {
				chown	$MV::Default{MINIVEND_UID},
						$MV::Default{MINIVEND_GID},
						"$realdir/$_";
			}
		}
		exit;
	}


	# Do the extra library checks

	# We will use our own version of File::CounterFile always
	push @extra_lib_dirs, 'File';
	push @extra_lib_files, 'File/CounterFile.pm';

	eval {
		require IniConf;
	};
	if ($@) {
		push @extra_lib_files, 'IniConf.pm';
	}


	eval {
		require HTML::Entities;
	};
	if ($@) {
		push @extra_lib_dirs, 'HTML';
		push @extra_lib_files, 'HTML/Entities.pm';
	}

	eval {
		require Business::UPS;
	};
	if ($@) {
		push @extra_lib_dirs, 'Business';
		push @extra_lib_files, 'Business/UPS.pm';
	}

	eval {
		require Storable;
	};
	unless ($@) {
				my $def = 'y';
		        print <<EOF;

You appear to have Raphael Manfredi's Storable module installed.

This module will significantly improve your DBM storage and
fetch times.

You can reply one of:

		n -- Don't use Storable
		s -- Use for sessions only, won't break existing databases
		y -- Use for both sessions and databases

It is recommended that new installations reply YES, and that
existing installations reply S unless there is a need for
improved performance. Replying S will mean you have to delete all
of your session files.

If you reply YES and you use any GDBM or DB_File databases
they will NEED TO BE REMADE for ALL CATALOGS using this
MiniVend server instance.
EOF

		if($ENV{MINIVEND_STORABLE_DB} || -f "$realdir/_db_storable" || -f "_db_storable") {
			$def = 'y';
		}
		elsif($ENV{MINIVEND_STORABLE} || -f "$realdir/_session_storable" || -f "_session_storable") {
			$def = 's';
		}
		my $ask = my_prompt("Use Storable module? (y/n/s) ", $def);
		if ($ask =~ /^\s*(y|d)/i) {
			open(TSTORABLE, ">_db_storable")
				or die "creat _db_storable: $!\n";
			print TSTORABLE "REMOVE THIS FILE TO STOP USING Storable\n";
			close TSTORABLE;
		}
		if ($ask =~ /^\s*(y|s)/i) {
			open(TSTORABLE, ">_session_storable")
				or die "creat _session_storable: $!\n";
			print TSTORABLE "REMOVE THIS FILE TO STOP USING Storable\n";
			close TSTORABLE;
		}
	}

	MODCHECK: {

		last MODCHECK unless $Cpan;
		eval {
				require MD5;
			};
		push(@mods_to_get, 'MD5') if $@ and $Cpan;
		eval {
				require SQL::Statement;
			};
		push(@mods_to_get, 'SQL::Statement') if $@ and $Cpan;
		eval {
				require MIME::Base64;
			};
		push(@mods_to_get, 'MIME::Base64') if $@ and $Cpan;
		eval {
				require URI::URL;
			};
		push(@mods_to_get, 'URI::URL') if $@ and $Cpan;

	}

	COPYEXTRA: {
		my $cpdir = '.';
		mkdir $cpdir, 0777 unless -d $cpdir;
		mkdir "$cpdir/lib", 0777 unless -d "$cpdir/lib";
		for(@extra_lib_dirs) {
			next if -d "$cpdir/lib/$_";
			mkdir "$cpdir/lib/$_", 0777 or die "mkdir $cpdir/lib/$_: $!\n";
		}
		for(@extra_lib_files) {
			File::Copy::copy ("extra/$_", "lib/$_")
				or die "Couldn't copy $_: $!\n";
		}
	}

	$ = 0;

	MODGET: {
		last MODGET unless $Cpan;
		unless (-d 'build') {
			mkdir('build', 0777)
				or die "Couldn't make build directory for CPAN: $!\n";
		}
		chdir 'build'
			or die "Couldn't chdir to build directory for CPAN: $!\n";
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
		chdir '..';
	}

	$Data::Dumper::Terse = 1;
	open (INITP, ">scripts/initp.pl")
		or die "Can't write initp.pl: $!\n";
	print INITP '$MV::Self = ';
	print INITP Dumper(\%X);
	print INITP ";\n1;";
	close INITP;
    return \%X;
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
	sub dont_warn {
		\*install;
	}

	my $new = <<'EOF';
mv_install ::
			$(PERL) Makefile.PL force=1 final=$(INSTALLARCHLIB)

install :: all pure_install doc_install mv_install

EOF
	$_ = $self->MM::install;
	s/\ninstall :.*/$new/;
	$_;
}

	use Getopt::Long;
	my @saveargs = @ARGV;
	my %optctl = (
		'junk'			=> sub { 1 },
		'<>'			=> sub {
							my ($arg) = @_;
#warn "checking option $arg\n";
							my ($opt, $val);
							if($arg !~ /=/) {
								$opt = $arg;
								$val = 1;
							}
							else {
								($opt, $val) = split /=/, $arg, 2;
							}
							$MV::Default{$opt} = $val;
							return;
							},
	);

	my @options = ( qw/
		junk
		<>
	/ );

	Getopt::Long::config(qw/permute/);
	GetOptions(\%optctl, @options)
		or die "Bad option get\n";
#	use Data::Dumper;
#	$Data::Dumper::Terse = $Data::Dumper::Indent = 2;
#	print "ARGV: " . Dumper(\@ARGV);
#	print "OPT: " . Dumper(\%MV::Default);
#	@ARGV = @saveargs;

WriteMakefile(
	NAME       => "MiniVend",
	MAN3PODS => { 'pod/mvdocs.pod' => 'blib/man3/mvdocs.8' },
	DISTNAME => "minivend",
	clean    => {
	            FILES=> "lib/IniConf.pm _db_storable _session_storable lib/File/CounterFile.pm scripts/initp.pl scripts/compile_link scripts/config_prog scripts/configdump scripts/dump scripts/expire scripts/localize scripts/expireall scripts/makecat scripts/minivend scripts/offline scripts/restart scripts/update",
	           },

	dist     => {
					CI => "ci -l -t-Initial",
					SUFFIX   => ".gz",
					DIST_DEFAULT => 'all tardist',
					COMPRESS => "gzip -9f",
					ZIP_FLAGS => '-pr9',
				},
	VERSION_FROM => "scripts/minivend.PL",
	EXE_FILES  => [],
	CONFIGURE  => \&initialize,
);
