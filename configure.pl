#!/usr/local/bin/perl
#
# configure.pl - Configure the MiniVend program
#
# Version 1.1
# Copyright 1996,1997 by Michael J. Heins <mikeh@iac.net>
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

$Rerun = 0;

use lib "./lib";
my $param;
PARAM: {
	my $param = shift || '';
	unless($param =~ /^-/) {
		$PERL = $param if $param;
	}
	elsif ($param eq '-i') {
		$InstallOnly = 1;
	}
	elsif  ($param eq '-rerun') {
		warn "****  Re-running with specified Perl  ****\n";
		$Rerun = 1;
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

chop($Initial{'VendRoot'} = `pwd`);
$Initial{'HelpFile'} = 'etc/mvconf.cmt';

#
############## END CONFIGURABLE VARIABLES ###################

sub is_yes {
	return( defined($_[0]) && ($_[0] =~ /^[yt1]/i));
}

sub is_no {
	return( !defined($_[0]) || ($_[0] =~ /^[nf0]/i));
}

sub do_msg {
	my ($msg, $size) = @_;
	$size = 60 unless defined $size;
	my $len = length $msg;
	
	return "$msg.." if ($len + 2) >= $size;
	$msg .= '.' x ($size - $len);
	return $msg;
}
	

sub cp {
    my ($srcFile, $dstFile) = @_;
    my ($buf,$len);
    open (IN,"<$srcFile") or die "Can't open input $srcFile: $!\n";
    open (OUT,">$dstFile") or die "Can't open output $dstFile: $!\n";
    my ($access,$mod) = (stat IN)[8,9];
	$ = 0;
    syswrite(OUT, $buf, $len) while $len = sysread(IN, $buf, 8192);
	$ = 1;
    close IN;
    close OUT;
    utime $access, $mod, $dstFile;
}

sub regularize {
	for (@_) {
			s/[\\]\n//g;
			s/\n\s+/ /g;
			s/\s+$//g;
	}
	wantarray ? @_ : $_[0];
}

sub dontwarn {
	
}

sub initconfig {
	my $file = shift;
	my($status,$key,$val);
	open(INITIAL, $file)
		|| return undef;

	while(<INITIAL>) {
		next if /^\s*#/;	# Ignore comments
		next unless /\S/;	# Ignore blanks
		chomp;
		($key, $value) = split(/[\t =]+/, $_, 2);
		$Initial{$key} = $value;
	}
	close INITIAL;
	1;
}

sub can_do_suid {
	my $file = 'mytemp.fil';
	my $status;

	open(TEMPFILE,">$file");
	close TEMPFILE;
	eval { chmod 04755, $file; $@ = ''};
	$status = $@ ? 0 : 1;
	unlink $file;
	return $status;
}

sub prompt {
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
            return 0;
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
			if ($line =~ /^\s*(my\s+)?\$(\w+::)?$var\s*=\s*('?[^']+'?)\s*;/) {
				my $my = $1 || '';
				my $pkg = $2 || '';
				$check = $3 || '';
				print "Found $var in $file\n" if $DEBUG;
				unless ($check eq $vars{$var}) {
					$changed++;
					$line = $my . '$' . $pkg . $var . ' = ' . $vars{$var} . ";\n";
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

my %ModuleMessage = (
	
	File::Basename => sub {
							$msg = <<EOF;

You don't have the File::Basename module, why not?  It is included
with every Perl 5 distribution. You should contact your system
administrator and ask them to install Perl properly. It is
included with MiniVend, so it may not be fatal.  But don't e 
surprised if you can't start the server.

This is a strong warning.

EOF
							$msg;
					},
	Search::Dict => sub {
							my $msg = <<EOF;

You don't have the Search::Dict module, why not?  It is included
with every Perl 5 distribution. You should contact your system
administrator and ask them to install Perl properly.

It won't cause a problem except you cannot use the dictionary-ordered
fast binary search. MiniVend will crash if you do.  An outside person
could even crash it if they knew the right URL to submit.

EOF
							$msg;
					},
	File::CounterFile => sub {
							my $msg = <<EOF;

You don't have the File::CounterFile module for some reason. It may
be because you are installing with Perl 5.001, naughty you! You 
might want to upgrade.

It won't cause a problem except you cannot use the OrderNumber
directive.  Please comment it out of any catalog.cfg file.

EOF
							$msg;
					},
	File::Lock => sub {
						if ($Config{'osname'} eq 'solaris') {
							warn <<EOF . "\n";

You are running Solaris 2, and you don't have the File::Lock module
installed. This is a show-stopper with less than Perl 5.004, as Solaris
doesn't support flock().  and you need this module. The good news is that
it is included with MiniVend. It is also available at any CPAN site --
you can download it from http://www.perl.com at any time.

MiniVend's attempt to install it apparently failed, so try and install
it manually.  If you have Perl 5.004, MiniVend may work without this
module.

EOF
						}
						"";
					},
	Des			=> sub {
							"You have no Des.pm module, no biggie.\n"
					},
	generic     => sub {
							my $msg = <<EOF;
You don't have the $_[0] module, this is normally not fatal.
EOF
							$msg;
					},
			
          );

sub adjustmodules {
	my ($file,@modules) = @_;
	my($mod);
	my $bak = 'mytemp.fil';
	return undef unless $file and @modules;

	my $check = '';
	my $changed = 0;

	rename $file, $bak;
	open(ADJUST_IN,$bak)
		|| die "Couldn't open $bak: $!\n";
	open(ADJUST_OUT,">$file")
		|| die "Couldn't create $file: $!\n";

	while(<ADJUST_IN>) {
		unless (/^\s*#*\s*use\s+/) {
			print ADJUST_OUT $_;
			last if /^\s*#+\s+end\s+config/i;	# prevent parsing whole file
			next;
		}
		$line = $_;
		foreach $mod (@modules) {
			$found = 0;
			if ($line =~ /^\s*#*use\s+$mod\s?;?/ ) {
				eval { eval "require $mod" and $found = 1};
				print "Found reference to module $mod in $file\n" if $DEBUG;
				if (!$found or $@) {
					$changed++ if $line =~ s/^(\s*)use/$1#use/;
					warn &{$ModuleMessage{$mod}}() . "\n"
							if defined $ModuleMessage{$mod};
					warn &{$ModuleMessage{'generic'}}($mod) . "\n"
							if ! defined $ModuleMessage{$mod};
					warn $found ? 'It was found but: ' : 'It was not found: ' . 
						"\n$@\n" if $DEBUG;
					warn join "\n", '@INC was:', @INC, "" if $DEBUG; 
				}
				else {
					$changed++ if $line =~ s/^(\s*)#(\s*)(use\s+)/$1$2$3/;
				}
				$check = $mod;
				last;
			}
		}
		@modules = grep ! ($_ eq $check), @modules;
		print ADJUST_OUT $line;
		unless (@modules) {
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

	! scalar @modules;

}



sub adjusttext {
	my ($file,$newfile,%text) = @_;
	my ($done,$origtext,$newtext);
	return undef unless
		(defined $file) && (defined %text) &&
		(defined $newfile);
	
	open(ADJUST_IN,$file)
		|| die "Couldn't open $file: $!\n";
	open(ADJUST_OUT,">$newfile")
		|| die "Couldn't create $newfile: $!\n";

	while(<ADJUST_IN>) {
		while( ($origtext,$newtext) = each %text) {
			if (/$origtext/) {
				s/$origtext/$Initial{$newtext}/g;
				print "Adjusted '$origtext' to '$Initial{$newtext}' in $file\n"
					if $DEBUG;
			}
		}
		print ADJUST_OUT $_;
	}

	close ADJUST_IN;
	close ADJUST_OUT;
	1;
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

sub getvendsettings {
	my $file = shift;
	my($status,$key,$val);
	my(%settings);
    open(VENDSET, $file)
        || die "Couldn't open $file: $!\n";

    while(<VENDSET>) {
        next if /^\s*#/;    # Ignore comments
        next unless /\S/;   # Ignore blanks
        chomp;
        ($key, $value) = split(/[\t =]+/, $_, 2);
		next unless $key =~ /\S/;
        $settings{$key} = $value;
    }
    close VENDSET;
	%settings;
}

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

sub writeconfig {
	my($file) = shift;
	my(@keys) = @_;
	my($status,$key,$val);
	open(WRITECONFIG, ">$file")
		|| die "Couldn't write $file: $!, died";
	if(grep /^PageDir/, @keys) {
		@keys = grep !/^PageDir/, @keys;
		unshift @keys, 'PageDir';
	}
	for(sort @keys) {
		warn "Doing $_: Initial=$Initial{$_} Default=$Default{$_}\n" if $DEBUG;
		next if $Initial{$_} eq $Default{$_};
		next unless $Initial{$_};
		printf WRITECONFIG "%-20s %s\n", $_, $Initial{$_};
	}
	close WRITECONFIG;
	return 1;
}


sub copyfiles {
	my ($srcdir,$targdir,@types) = @_;
	my (%types);
	my ($file, $tempfile, $source, $target);
	my $dirmode = $targdir =~ m#/$# ? 1 : 0;

	unless (scalar(@types)) {
		@types = grep !$types{$_}++, values %Type;
	}
	else {
		for(@types) { $types{$_} = 1 }
	}

	foreach $file (@Files) {
		next unless $types{$Type{$file}};
		$source = "$srcdir/$file";
		if($dirmode) {
			$tempfile = $file;
			$tempfile =~ s:.*/::;
			$target = $targdir . $tempfile;
		}
		else {
			$target = "$targdir/$file";
		}
		if ($Type{$file} =~ /dir$/) {
			unless (-d $target) {
				mkdir $target, $Perms{$file}
					or die "Couldn't make directory $target: $!\n";
			}
			if($Type{$file} =~ /odir/) {
				system "(cd $file; tar -cf - *) | (cd $target; tar -xf -)";
			}
		}
		else {
			if(-f $target ) {
				if (defined $Funcs{$file} and $Funcs{$file} =~ /\bbackup\b/) {
					my $n = 0;
					my $backup;
					$backup = "$target~";
					while (-f $backup) {
						$backup .= '~';
						$n++;
						die "Too many backups of $target."
							if $n > 9;
					}
					warn "Saving old $target to $backup.\n";
					cp($target, $backup) or
						die "Couldn't copy $target to $backup: $!\n";
				}
				elsif ( !-w _ ) {
					next unless
						is_yes(prompt "Overwrite read-only file $target? ", 'no');
					chmod 0644, $target;
				}
			}
			cp($source,$target) or
				die "Couldn't copy $source to $target: $!\n";
		}
		if (defined $Funcs{$file} and $Funcs{$file} =~ /\bchown\b/) {
			chown ($UserID, $GroupID, $target)
				if defined $UserID;
		}
		chmod $Perms{$file}, $target ||
			die "Couldn't change mode of $target to $Perms{$file}: $!\n";
	}
	1;
}

sub checkmanifest {
	my ($targdir,@types) = @_;
	my (%types);
	my (@errors);
	my ($file, $target);

	unless (scalar(@types)) {
		@types = grep !$types{$_}++, values %Type;
		delete $types{'link'};
	}
	else {
		for(@types) { $types{$_} = 1 }
	}

	foreach $file (@Files) {
		next unless $types{$Type{$file}};
		$target = "$targdir/$file";
		push(@errors, "$target doesn't exist!") unless -e $target;
	}

	if (@errors) {
		push (@Errors, @errors);
		return undef;
	}
	1;
}

sub finduid {
	my(@users) = @_;
	my  ($user, $login,$pass,$uid,$gid);
	foreach $user (@users) {
		($login,$pass,$uid,$gid) = getpwnam($user);
		last if defined $uid;
	}
	defined $uid ? $uid : '';
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
then you _might_ know enough to get it running with 5.001m).

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
	$Nomove = 1;
	warn "\nCouldn't open manifest: $!\n" .
		  "We won't be moving or changing any program files.\n";
}

if($InstallOnly) {
	goto INSTALLPROGS;
}

if (checkmanifest('.')) {
	$Fullpackage = 1;
	$SamplesPresent = 1;
	print "\nYou seem to have a complete package here.\n";
}

goto COPYFILES if $Rerun;

$param = 'VendRoot';

my $save = $Initial{$param};
unless (
	($Initial{$param} = get_detailed_param($param))
		eq $save) {
	chop($Initial{$param} = `pwd`)
		if $Initial{$param} eq '.';
	$Changed{$param} = 1;
}
$Done{$param} = 1;

CHECKMANIFEST: {

	last CHECKMANIFEST if $Nomove || $Fullpackage || $Rerun;

	unless (checkmanifest('.', 'dir', 'static', 'script', 'csrc', 'conf')) {
		$Nomove = 1;
		for (@Errors) { print "$_\n" }
		print "Not all the important files are here. I won't be copying files.\n";
		@Errors = ();
	}
	else {
		print "You have the important files.\n";
	}

} # CHECKMANIFEST

chop($curdir = `pwd`);
$Samedir = 1 if $curdir eq $Initial{'VendRoot'};

COPYFILES: {
	my(@types);
	my($ans);
	last COPYFILES if $Nomove || $Rerun;
	if ($Fullpackage && $Samedir) {
		print <<EOF;
It looks like you are installing in the current directory
and have a full package.  Good.
EOF
		last COPYFILES;
	}
	elsif ($Samedir) {
		print "\nIt looks like you are installing in the current directory\n";
		print "but don't have a full package.\n";
		if ( -f $Initial{'ConfigFile'}) {
			print "\nOh, just a reconfiguration. You have a configuration file.\n";
		}
		last COPYFILES;
	}
	
	if (checkmanifest($Initial{$param},
				'dir', 'static', 'script', 'csrc')) {
		print "All important files seem to be in $Initial{$param}.\n";
		last COPYFILES if $Samedir;
		$ans = prompt "Want to copy these over them? ", 'yes';
		if(is_yes($ans)) {
			push(@types, 'dir', 'static', 'script', 'csrc', 'conf');
		}
		else {
			print "\nOK, continuing with the files already there.\n";
			last COPYFILES;
		}
		$ans = prompt "Want to copy the sample files? ", 'yes';
		if(is_yes($ans)) {
			$SamplesPresent = 1;
			push(@types, qw(odir demo html image));
		}
		else {
			undef $SamplesPresent;
			print "\nOK, continuing with the files already there.\n";
		}
	}
	else {
		if($Samedir) {
			print "There is not a complete package here, I hope you\n";
			print "know what you are doing.\n";
			last COPYFILES;
		}
		unless (-d $Initial{$param}) {
			$ans = prompt 
				"\nThe directory $Initial{$param} is not there.\nMake it? ",
				'yes';
			mkdir $Initial{$param}, 0755
				or die "Couldn't make $Initial{$param}: $!\n";
		}
		else {
			undef $SamplesPresent;
			$ans = prompt 
				"The directory $Initial{$param} already exists.\nUse it? ",
				'no';
			exit if is_no($ans);
		}
	}
	@Errors = ();
	print "Copying files to $Initial{$param}...";
	$::InitialCopy = 1;
	copyfiles('.', $Initial{$param}, @types);
	$::InitialCopy = 0;

	for (@Errors) { print "$_\n" }
	@Errors = ();

	print "done.\n";

} # last COPYFILES

print "\nEntering $Initial{'VendRoot'}.\n"
	unless $Samedir;
chdir $Initial{'VendRoot'}
	|| die "Couldn't change directory to $Initial{'VendRoot'}: $!\n";

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
else {
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


use Config;

if ($PERL) {
	$Initial{'PERL'} = $PERL;
}

HOSTNAME: {
	my $host;
	my $domain;
	# Have to skip this for NT
	unless (defined $Initial{'HostName'}) {
		$Initial{'HostName'} = '';
		chop($host = `hostname`);
		last HOSTNAME if $?;
		chop($domain = `domainname`);
		last HOSTNAME if $?;
		$host .= ".$domain"
			if ($host =~ s/\.?\(?none\)?$//i or $host !~ /\./);
		$Initial{'HostName'} = $host;
	}
}

LOCK: {
	last LOCK unless
		$Config{'osname'} =~ /solaris/i;
	eval {require File::Lock and last LOCK }; 

		print <<EOF;

Your operating system ($Config{'osname'}) doesn't fully support
flock(), so you will need the File::Lock module in order for
MiniVend to operate.  It is included with MiniVend, but the
latest version can be obtained from http://www.perl.com
in the CPAN area.  Expect a ***fatal*** error if you don't have
it and MiniVend is not able to install it..

MiniVend will try and install the module now.

EOF
		if(install_perl_module('File-Lock-0.9')) {
			print "\nInstall successful, apparently.\n";
			system	$PERL,
				'-npi', '-e',
				"'s!^\s*#\s*(use\s+File::Lock)!$1!'",
				'lib/Vend/Util.pm';
		}
		else {
			warn "\nInstall FAILED.\n";
			require 5.00393;
		}

} # last LOCK

MDMODULE: {
	eval {require MD5};
	if ($@) {

		print <<EOF;

You don't have the MD5 module installed.  MiniVend uses it
to advantage in quite a few ways -- you can operate without it
but we will try to install it anyway.  It is included with MiniVend,
but the latest version can be obtained from http://www.perl.com
in the CPAN area.  It will be no problem if MiniVend is not able
to install it.

MiniVend will try and install the module now.

EOF
	(install_perl_module("MD5-1.6") and
		print "\nInstall successful, apparently.\n")
		or warn <<EOF . "\n";
Install FAILED. This is not fatal -- but you might want
to obtain MD5 and install it later.
EOF

	}
}

my @params = qw(PERL);

for(@params) {
	$ = 0;
	$save = $Initial{$_};
	$Done{$_} = 1;
	next if $Rerun;
	unless (
		($Initial{$_} = get_detailed_param($_))
			eq $save) {
		$Changed{$_} = 1;
	}
	$ = 1;
}

CHECKPERL: {

	last CHECKPERL if $Rerun;

	if($]  ne `$PERL -e 'print $]'`) {
		print <<EOP;

	We will now re-run this configure with the Perl you specified,
	it will just take a moment...

EOP
		exec $PERL, $0, $PERL, '-rerun', $DEBUG ? '-D' : '';
	}
}

NEWPERL: {
	$Initial{'ConfDir'} = $Initial{'VendRoot'} . '/' . 'etc'
		unless defined $Initial{'ConfDir'};
	$Initial{'VEND'} = $Initial{'VendRoot'} . '/' . 'minivend.pl'
		unless defined $Initial{'VEND'};
}

# Ugly dependency for 5.001
FILE_COUNTER: {
	eval {require 5.002};
	if($@) {
		system 'mv', 'File/CounterFile.pm',
			'File/CounterFile.no.you.dont.have.5.002.pm';
	}
}

$Initial{'LINK_FILE'} = $Initial{'VendRoot'} . '/' . 'etc/socket'
	unless defined $Initial{'LINK_FILE'};

@params = ();

unless (-x '/usr/lib/sendmail') {
	$Initial{SendMailLocation} = findexe('sendmail');
	push @params, 'SendMailLocation';
}

for(@params) {
	$ = 0;
	$save = $Initial{$_};
	unless (
		($Initial{$_} = get_detailed_param($_))
			eq $save) {
		$Changed{$_} = 1;
	}
	$ = 1;
	$Done{$_} = 1;
}

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
			elsif($func =~ /^modules/i) {
				($junk, @params) = split /\s*;\s*/, $func;
				print "Calling adjustmodules with " . join(' ',@params) . "\n"
					if $DEBUG;
				adjustmodules($file,@params)
					|| die "Something was wrong with $file, didn't adjust modules.\n";
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

$default = $Upgrade ? 'no' : 'yes';
print "\nYou only need to re-make vlink if you have changed directories.\n\n"
	if $Upgrade;
$ans = prompt "\nMake the dispatch programs vlink and tlink? ", $default;
if (is_yes($ans)) {
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
		system "$CC $CFLAGS $LIBS -o vlink vlink.c";
		if($?) {
			warn "\nCompiliation of vlink.c FAILED.\n";
			$vfail = 1;
		}
		system "$CC $CFLAGS $LIBS -o tlink tlink.c";
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


chdir 'bin' || die "Couldn't cd to $Initial{'VendRoot'}/bin: $!\n";

##  UGLY
if(! -f 'start') {
	eval { symlink 'start_unix', 'start' };
	link ('start_unix', 'start') if $@;
}
if(! -f 'restart') {
	eval { symlink 'restart_unix', 'restart' };
	link ('restart_unix', 'restart') if $@;
}

chdir '..' || die "Couldn't change back to $Initial{'VendRoot'}: $!\n";

print <<EOF;

That takes care of the program configuration.

EOF

if (defined $Compile_failed and $Compile_failed) {
print <<EOF;

The compilation of one or both link programs (tlink and/or
vlink) failed.  You may be able to use the Perl-based tlink.pl
program along with starting the server in INET mode (start_inet)
to make MiniVend work.

Using vlink.pl requires either that your installation use
CGIWRAP or that you compile it with a wrapper such as the Perl
example 'wrapsuid' program.

EOF
}

print <<EOF;

To configure the demo catalogs, run the following commands:

EOF

	# If they have copied files -- they will not
	# stay in the new directory

	print "	cd $Initial{VendRoot}\n" unless $Samedir;

print <<EOF;
	bin/makecat sample
	bin/makecat simple

You will be prompted for some information -- refer to the 
README file if you have questions.

After you have done that, you will start the MiniVend server
and the demo catalogs should be operating.

Welcome to MiniVend!

EOF
