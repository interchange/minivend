use ExtUtils::MakeMaker;
require ExtUtils::Install;
use Config;
use Cwd;
require 5.003;

use strict;

use vars (qw($VERSION));

my $TermRead;
my $Prompt_sub;
my @mods_to_get;

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

sub my_prompt {
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

sub cpan_get {
	my($module, $libdir, $prompt) = @_;
	
	print <<EOF unless defined $CpanInit;
		
Since you have the CPAN module installed, we can go
and get any modules that need installation -- that is, 
if you are connected to the Internet and have one of
the following on your machine:
	
		Perl LWP libraries
		Perl Net::FTP library
		ncftp (a nice FTP program)
		lynx  (the text-based web browser)

If you have never used CPAN before, you may want to reply NO.
MiniVend should work anyway -- it just won't be quite as
easy to build the demo catalogs.

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
		my @mvdir = (
						"/usr/local/lib/minivend",
						"/home/minivend",
						"$ENV{HOME}/minivend",
					);
		my $mvdir;

		for $mvdir (@mvdir) {
			if (-f "$mvdir/minivend.cfg") {
				$realdir = $mvdir if -w $mvdir;
				last;
			}
		}
		$realdir ||= $mvdir[0];
		$realdir=my_prompt("Where is your MiniVend to be installed? ",$realdir);

		$realdir =~ s:/\s*$::;
		$X{INSTALLARCHLIB}	= "$realdir/lib";
		$X{INSTALLPRIVLIB}	= "$realdir/lib";
		$X{INSTALLMAN1DIR}	= "$realdir/doc";
		$X{INSTALLMAN3DIR}	= "$realdir/doc";
		$X{INSTALLDIRS}     = "perl";

		return \%X;
	}

	die "Shouldn't get here unless a 'make install'!?!\n"
		unless $install;


MODCHECK: {

	last MODCHECK unless $Cpan;
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

You may wish to inspect minivend.cfg.dist for new values.  The
major change that might be necessary is setting NoAbsolute to "No"
if you have directories or files with absolute pathnames
defined in tags or the catalog.cfg file.

Check the README file for changes you might have to make if
updating from an earlier version of MiniVend.
EOF

	}
}

	# Would like to use module, but changes mode to read only!
	#ExtUtils::Install::install( {'dist', $realdir }, 1);

	my (@files);
	if(-d $realdir) {
		open(MANIFILE, 'MANIFEST')
			or die "Couldn't open MANIFEST: $!\n";
		@files = <MANIFILE>;
		close MANIFILE;
		chomp(@files);
		@files = grep m:^dist/:, @files;
		@files = map { s:^dist/::; $_} @files;
	}
	else {
		mkdir $realdir, 0777
			or die "Couldn't make directory $realdir: $!\n";
	}

	for(@files) {
		next unless -f "$realdir/$_";
		unlink "$realdir/$_" or die "Couldn't unlink $realdir/$_: $!";
	}

	system "(cd dist; tar cf - *) | (cd $realdir; tar xf -)";
	die "File copy failed: $!\n" if $?;

	MODGET: {
		last MODGET unless $Cpan;
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
	system "(cd $realdir; $perl configure.pl -v $realdir $perl)";
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
			    COMPRESS => "gzip -9f" },
        VERSION_FROM => "dist/bin/minivend",
	EXE_FILES => [],
	CONFIGURE  => \&initialize,
);
