#!/usr/bin/perl
#
# configure.pl - Configure the MiniVend program
#
# Version 1.0
# Copyright 1996 by Mike Heins <mikeh@iac.net>
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

if ($< == 0) {
	die <<EOF ;

Sorry.

MiniVend should not be installed as root.  It should not be
run as root.  Nothing really _need_ be done as root, except
possibly copy the executables and HTML pages to appropriate
directories.

If you need root access later in the configuration, you will
be given an opportunity to 'su' and do so.

Please make all the files owned by another user, and re-run
the configuration as that user.  You might define one called
"minivend" if you like.

EOF

}

$Rerun = 0;

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
	else {
		warn "Unrecognized parameter $param, ignoring.\a\n"
			if $param;
	}
	last PARAM unless $param;
	redo PARAM;
} # PARAM

	
############### Configurable Variables ######################
#
# Where the initial configuration is stored
$CONFIGFILE   =   'etc/mvconf.cfg';

%Initial = (
				HelpFile  =>	'etc/mvconf.cmt'
			);
chop($Initial{'VendRoot'} = `pwd`);

#
############## END CONFIGURABLE VARIABLES ###################

sub is_yes {
	return( defined($_[0]) && ($_[0] =~ /^[yt1]/i));
}

sub is_no {
	return( !defined($_[0]) || ($_[0] =~ /^[nf0]/i));
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

sub adjustmodules {
	my ($file,@modules) = @_;
	my($mod);
	my $bak = 'mytemp.fil';
	return undef unless $file and @modules;

	my $check;
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
					warn "\nCouldn't use $mod module, darn! " .
						($found ? 'It was found but: ' : 'It was not found: ') . 
						"\n$@\n";
					warn join "\n", '@INC was:', @INC, "";
					warn "\nThis is not normally fatal. Don't worry.\n";
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
			next if -d $target;
			mkdir $target, $Perms{$file}
				|| die "Couldn't make directory $target: $!\n";
		}
		else {
			if(-f $target && !-w _) {
				next unless
					is_yes(prompt "Overwrite read-only file $target? ", 'no');
				chmod 0644, $target;
			}
			unless(defined $Funcs{$file} and $Funcs{$file} =~ /text:(.*)/) {
				cp($source,$target) ||
					die "Couldn't copy $source to $target: $!\n";
			}
			else {
				my $text = $1;
				my @text = split /:/, $text;
				adjusttext($source,$target,@text) ||
					die "Couldn't copy $source to $target (adjusted): $!\n";
			}
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
		delete $types{'placeholder'};
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

	print "Default: $Default{$param}\n";
	unless (defined $Initial{$param}) {
		$Initial{$param} = ($Default{$param} =~ /BLANK_DEFAULT|UNDEFINED/)
							? ''
							: $Default{$param};
	}
	print "Current: $Initial{$param}\n\n";

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

# Initialize for an upgrade or rerun;
initconfig($CONFIGFILE);

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
		print "\nIt looks like you are installing in the current directory\n";
		print "and have a full package.  Good.\n";
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
			push(@types, qw(odir simphtml simppage samphtml samppage image));
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
	copyfiles('.', $Initial{$param}, @types);

	for (@Errors) { print "$_\n" }
	@Errors = ();

	print "done.\n";

} # last COPYFILES

print "\nEntering $Initial{'VendRoot'}.\n"
	unless $Samedir;
chdir $Initial{'VendRoot'}
	|| die "Couldn't change directory to $Initial{'VendRoot'}: $!\n";

use Config;


if ($PERL) {
	$Initial{'PERL'} = $PERL;
}

HOSTNAME: {
	my $host;
	my $domain;
	# Have to skip this for NT
	last HOSTNAME if $Config{'osname'} =~ /(win32|mswin)/;
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

LOCKING: {
	$Initial{'BadLocking'} = 0;
	last LOCKING unless
		$Config{'osname'} =~ /(irix|solaris)/;
	$GCCFLAG = ' -lsocket -DSVR4';
	last LOCKING if $Config{'osname'} =~ /sunos\b.*4\S/;
	$Initial{'BadLocking'} = 1;
	print <<EOF;

Your operating system ($Config{'osname'}) doesn't fully support
flock(), no MultiServer mode or forked searches are possible.
This might work on Solaris 2 if you have the File::Lock module,
and on IRIX if you install patch 596.  If you have either of these,
set the BadLocking variable to 0 in the minivend.pl program.

EOF

} # last LOCKING

my @params = qw(PERL HostName RunType);

for(@params) {
	$save = $Initial{$_};
	$Done{$_} = 1;
	next if $Rerun;
	unless (
		($Initial{$_} = get_detailed_param($_))
			eq $save) {
		$Changed{$_} = 1;
	}
}

CHECKPERL: {

	last CHECKPERL if $Rerun;

	if($]  ne `$PERL -e 'print $]'`) {
		print <<EOP;

	We will now re-run this configure with the Perl you specified,
	it will just take a moment...

EOP
		writeconfig($CONFIGFILE, qw(PERL BadLocking HostName RunType VendRoot));
		exec $PERL, $0, $PERL, '-rerun', $DEBUG ? '-D' : '';
	}
}

NEWPERL: {
	$Initial{'ConfDir'} = $Initial{'VendRoot'} . '/' . 'etc'
		unless defined $Initial{'ConfDir'};
	$Initial{'VEND'} = $Initial{'VendRoot'} . '/' . 'minivend.pl'
		unless defined $Initial{'VEND'};
	$Initial{'MAT'} = $Initial{'VendRoot'} . '/' . 'bin/mat'
		unless defined $Initial{'MAT'};
	$Initial{'CGIUSER'} = finduid('http','nobody','httpd','www')
		unless defined $Initial{'CGIUSER'};
	if ($Initial{'RunType'} =~ /^st/i) {
		$vendprog = 'svend';
	}
	else {
		$Initial{'RunType'} = 'server';
		$vendprog = 'vlink';
	}
}

# Ugly dependency for 5.001
FILE_COUNTER: {
	eval {require 5.002};
	if($@) {
		print "\nSorry, can't configure in the order counter,\n" .
				"you don't have Perl 5.002. Ignore the permission message\n" .
				"for File/CounterFile.pm.\n\n";
		system 'mv', 'File/CounterFile.pm',
			'File/CounterFile.no.you.dont.have.5.002.pm';
	}
}

$Initial{'LINK_FILE'} = $Initial{'VendRoot'} . '/' . 'etc/socket'
	unless defined $Initial{'LINK_FILE'};
$Initial{'VendURL'} = "http://$Initial{'HostName'}/cgi-bin/$vendprog"
	unless defined $Initial{'VendURL'};
$Initial{'SecureURL'} = "https://$Initial{'HostName'}/cgi-bin/$vendprog"
	unless defined $Initial{'SecureURL'};
$Initial{'MailOrderTo'} = $ENV{'LOGNAME'} . '@' . $Initial{'HostName'}
	unless defined $Initial{'MailOrderTo'};

@params = qw( CGIUSER HtmlDir CgiBin
				ProtBin VendURL SecureURL MailOrderTo NET_START);

unless (-x '/usr/lib/sendmail') {
	$Initial{SendMailLocation} = findexe('sendmail');
	push @params, 'SendMailLocation';
}

for(@params) {
	$save = $Initial{$_};
	unless (
		($Initial{$_} = get_detailed_param($_))
			eq $save) {
		$Changed{$_} = 1;
	}
	$Done{$_} = 1;
}

$prompt = <<EOF ;

There are a lot more parameters you might not be interested
in.  They mostly are for setting running systems, and
can be changed by MAT.

EOF
$ans = prompt $prompt . "Set them? ", 'no';
if (is_yes($ans)) {
	for (sort keys %Default) {
		next if $Done{$_};
		$save = $Initial{$_};
		unless (
			($Initial{$_} = get_detailed_param($_))
				eq $save) {
			$Changed{$_} = 1;
		}
		$Done{$_} = 1;
	}
}
else {
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
}

WRITECONFIG: {

	if(defined (keys %Changed)) {
		print "\nWriting the configuration file for this program...";
		writeconfig($CONFIGFILE, keys %Default);
		print "done.\n";
		$param = 'ConfigFile';

		if (-f $Initial{$param}) {
			$prompt = <<EOP ;

You already had a $Initial{$param} file.  Writing will overwrite
that configuration.

But wait -- maybe this is an upgrade.

EOP
			$Upgrade = 0;
			$ans = prompt $prompt . "Is it? ", 'yes';
			($Upgrade = 1,last WRITECONFIG) if is_yes($ans);
			print "OK, I thought it might be.\n\n";
			$prompt = <<EOP ;

You already had a $Initial{$param} file.  Writing will overwrite
that configuration.

EOP
			$ans = prompt $prompt . "Write this configuration? ", 'yes';
			last WRITECONFIG if is_no($ans);
		}
		my %settings = getvendsettings('etc/minivend.def');
		writeconfig($Initial{$param}, keys %settings);
	}
	else {
		print "You didn't change anything, no need to write configuration.";
	}
} # end WRITECONFIG


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
print "\nYou only need to re-make vlink and mat if you have changed directories.\n\n"
	if $Upgrade;
$ans = prompt "\nMake the dispatch programs vlink, svend, and mat? ", $default;
if (is_yes($ans)) {
	my $CC = findexe('cc') || findexe('gcc');
	warn "No C compiler found, this phase will not be successful, I bet...\n"
		unless $CC;
	$CC = 'cc' unless $CC;
	$CC .= $GCCFLAG if (defined $GCCFLAG and $CC =~ /gcc$/);
	$? = 1;
	chdir 'src' || die "Couldn't change to source directory: $!\n";
	system "./configure";
	print "Compiling, this may take a sec...";
	unless($?) {
		$? = 1;
              print "Compiling with $CC -o vlink vlink.c'\n"
                      if $DEBUG;
		system "$CC -o vlink vlink.c";
		if($?) {
			warn "\nCompiliation of vlink.c FAILED.\n";
		}
	}
	else {
		warn "\nConfiguration of vlink.c FAILED.\n";
	}
	$? = 1;
      print "Compiling with $CC -o svend svend.c'\n"
                      if $DEBUG;
	system "$CC -o svend svend.c";
	if($?) {
		warn "\nCompiliation of svend.c FAILED.\n";
	}
	$? = 1;
      print "Compiling with $CC -o mat mat.c'\n"
                      if $DEBUG;
	system "$CC -o mat mat.c";
	if($?) {
		warn "\nCompiliation of mat.c FAILED.\n";
	}
	print "done.\n";
	chdir '..' || die "Couldn't change back to $Initial{'VendRoot'}: $!\n";
}

sub newer {
	my $compfile = shift;
	my $basefile = shift;
	return undef unless -f $basefile && -f $compfile;
	my($btime,$ctime);
	
	$btime = (stat($basefile))[9];
	$ctime = (stat($compfile))[9];

	($ctime > $btime) ? 1 : 0;
}
	



INSTALLPROGS: {

	$MatMade = (-x 'src/mat' && newer('src/mat', 'src/mat.c'));
	$VlinkMade = (-x 'src/vlink' && newer('src/vlink', 'src/vlink.c'));
	$SvendMade = (-x 'src/svend' && newer('src/svend', 'src/svend.c'));

CHECKPERMS: {
	last CHECKPERMS if $Upgrade;
	last CHECKPERMS if $< == 0;
	print <<EOP ;

You must have write permission on some directories
for all of the following steps to work.  I will check.

EOP
	my(@params) = qw(CgiBin ProtBin HtmlDir);
	foreach $param (@params) {
		print "$Initial{$param}: ";
		if (-d $Initial{$param}) {
			print "exists";
		}
		else {
			print "does not exist, skipping.\n";
			next;
		}
		if(-w $Initial{$param}) {
			print " and you have write permission.\n";
			$Copydirs{$param} = 1;
		}
		else {
			print " but is not writeable, skipping.\n";
			next;
		}
	}

	if (scalar(@params) == scalar(keys %Copydirs)) {
		$CanWrite = 1;
	}

} # END CHECKPERMS

MAKESU: {

	last MAKESU if $Upgrade;
	last MAKESU if $< == 0;
	if ($CanWrite && can_do_suid) {
		print "\nGoody, you can do everything! No need to be superuser.";
		last MAKESU;
	}
	elsif (can_do_suid) {

	$prompt = <<EOP ;

You are missing some write permissions. If you don't become superuser,
you won't be able to copy files to the directories you don't have write
permission to.

EOP
	}
	elsif ($CanWrite) {
	$prompt = <<EOP;

You won't be able to make the dispatch programs SUID unless you become
superuser.

EOP
	}
	else {
	$prompt = <<EOP ;

The next steps will be possible only if you are the
superuser.  If you don't become superuser, you won't be able to:

    1. Copy files to the directories you don't have write permission to.
    2. Make the dispatch programs SUID.

EOP
	}

	$default = $Upgrade ? 'no' : 'yes';
	$ans = prompt $prompt . "Become superuser? ", $default;

	if(is_yes($ans)) {
		! defined $SamplesPresent and $SamplesPresent = '';
		system "su -c '$Initial{'PERL'} $0 -install $SamplesPresent'";
		unless ($?) {
			exit;
		}
		else {
			print "\nAlas, something went awry. We will try and muddle along.\n";
		}
	}
	else {
		print <<EOP unless $Upgrade;
OK, you can pick this up later by doing this as superuser:

	perl $Initial{'VendRoot'}/configure.pl -install

EOP
	}

} # MAKESU

SAMPLE: {
	$param = 'HtmlDir';
	last SAMPLE unless $SamplesPresent;
	last SAMPLE if $Upgrade;
	unless($< == 0 or defined $Copydirs{$param} && $Copydirs{$param}) {
		print "\nCan't copy samples, directory not writeable.\n";
		last SAMPLE;
	}
	$prompt = <<EOP ;


We can install a demonstration MiniVend system in your HTML
directory if you wish. It will be copied to the  following
directory:

    $Initial{$param}/sample

Any custom parameters you entered will be saved in
the file "mv_cfg.bak".

EOP
	$prompt .= "You defined static mode, it will be much slower.\n"
		if ($Initial{'RunType'} !~ /^server$/);
	$prompt .= <<EOF;
	
There are two demos. One is a simple no-frills demo (simple)
that uses only the basic MiniVend features.  One is a no-holds barred
demo (sample) that tries to demonstrate the advanced features of MiniVend,
including SSL and frames.

EOF

sub sample_exists {
	my $file = shift;
	my $answer;
  	print "Couldn't make directory $file\n";
    print "It might exist...";
    if (-d $file) {
		print "it does.\n";
		$answer = prompt "Want to overwrite files? ", 'no';
	}
	elsif (-e $file) {
		print "it does, but it is something besides a directory.\n\n";
		$answer = prompt "Want to remove it? ", 'no';
		unlink $file
			if is_yes($answer);
		print "OK, it's history. Making new directory $file.\n\n";
		mkdir $file, 0755;

	}
	else {
		print "nope.  Something is wrong.\n\n";
		$answer = 'no';
	}

	$answer;
}

	$ans = prompt $prompt . "Install a demo? ", 'yes';
	if(is_no($ans)) { last SAMPLE; }
	$ans = prompt "Install which demo, sample or simple? ",
				$Initial{RunType} eq 'static' ? 'simple' : 'sample';
	if ($ans =~ /^\s*si/i) {
		print "copying files...";
		if(mkdir "$Initial{HtmlDir}/sample", 0755) {
			mkdir "$Initial{HtmlDir}/sample/images", 0755
				or die "mkdir: $!, died";
		}
		else {
			last SAMPLE
				unless( is_yes sample_exists("$Initial{HtmlDir}/sample") );
			mkdir "$Initial{HtmlDir}/sample/images", 0755
				unless -e "$Initial{HtmlDir}/sample/images";
		}
		copyfiles($Initial{VendRoot}, "$Initial{HtmlDir}/sample/", 'simphtml');
		copyfiles($Initial{VendRoot}, "$Initial{HtmlDir}/sample/images/", 'image');
		cp 'demo/products.simple', "demo/products.asc";
		print "writing config....";
		rename $Initial{ConfigFile}, 'mv_cfg.bak';
		open(WRITEIT,">$Initial{ConfigFile}")
			or die "Couldn't write $Initial{ConfigFile}: $!\n";
		foreach $what (qw ( MailOrderTo VendURL SecureURL) ) {
			printf WRITEIT "%-23s %s\n", $what, $Initial{$what};
		}
		$what = `cat sample.cfg`;
		print WRITEIT $what;
		close WRITEIT;
		print "done.\n";
	}
	elsif ($ans =~ /^\s*sa/i) {
		print "copying files...";
		if(mkdir "$Initial{HtmlDir}/sample", 0755) {
			mkdir "$Initial{HtmlDir}/sample/images", 0755
				or die "mkdir: $!, died";
		}
		else {
			last SAMPLE
				unless( is_yes sample_exists("$Initial{HtmlDir}/sample") );
			mkdir "$Initial{HtmlDir}/sample/images", 0755
				unless -e "$Initial{HtmlDir}/sample/images";
		}
		copyfiles($Initial{VendRoot}, "$Initial{HtmlDir}/sample/", 'samphtml');
		copyfiles($Initial{VendRoot}, "$Initial{HtmlDir}/sample/images/", 'image');
		cp 'demo/products.sample', "demo/products.asc";
		print "writing config...";
		rename $Initial{ConfigFile}, 'mv_cfg.bak';
		open(WRITEIT,">$Initial{ConfigFile}")
			or die "Couldn't write $Initial{ConfigFile}: $!\n";
		foreach $what (qw ( MailOrderTo VendURL SecureURL) ) {
			printf WRITEIT "%-23s %s\n", $what, $Initial{$what};
		}
		$what = `cat sample.cfg`;
		print WRITEIT $what;
		close WRITEIT;
		print "done.\n";
	}


} # end SAMPLE


CGI: {
	$param = 'CgiBin';
	last CGI unless ($SvendMade || $VlinkMade);
	my $where = $Initial{'VendURL'};
	$where =~ s:.*/::;
	$Svend_loc =  "$Initial{$param}/$where";
	$Vlink_loc =  "$Initial{$param}/$where";
	unless($< == 0 or defined $Copydirs{$param} && $Copydirs{$param}) {
		print "Can't copy svend, directory not writeable.\n";
		last CGI;
	}
	$ans = prompt "\nInstall the vlink dispatch program as $Vlink_loc? ",
			$Initial{'RunType'} =~ /^server$/i ? 'yes' : 'no';
	if (is_yes($ans)) {
		cp 'src/vlink', $Vlink_loc;
	}
	$ans = prompt "Install the svend dispatch program as $Svend_loc? ",
			$Initial{RunType} =~ /^server$/i ? 'no' : 'yes';
	if (is_yes($ans)) {
		cp 'src/svend', $Svend_loc;
	}

} # end CGI


PROT: {
	$param = 'ProtBin';
	last PROT unless $MatMade;
	unless($< == 0 or defined $Copydirs{$param} && $Copydirs{$param}) {
		print "Can't copy mat, directory not writeable.\n";
		last PROT;
	}
	$ans = prompt "Install the mat dispatch program? ", 'yes';
	if (is_yes($ans)) {
		cp 'src/mat', "$Initial{$param}/mat";
	}

} # end PROT

SETUID: {
	last SETUID if $Upgrade;
	unless ($< == 0 || can_do_suid) {
		print <<EOP;

You aren't the superuser, so you can't make the vlink, mat
and svend programs setuid. You will have to have the
superuser do that later with the commands:

	chmod 4755 $Vlink_loc
	chmod 4755 $Svend_loc
	chmod 4755 $Initial{'ProtBin'}/mat

EOP
		last SETUID;
}

	my($uid,$gid,$who);
	$ans = prompt "Make the svend, vlink, and mat programs SUID (not to root)? ", 'yes';
	if (is_yes($ans)) {
		$who = ($< != 0)
				? $ENV{'LOGNAME'}
				: prompt "Make it owned by who? ", $ENV{'LOGNAME'};
		unless ($uid = finduid($who)) {
			print "UhUhnh.  No way that guy is going to own it. Skipping.\n";
			last SETUID;
		}
		else {
			$gid = (getpwnam($who))[3];
		}
		chown $uid, $gid, "$Initial{'CgiBin'}/svend", "$Initial{'ProtBin'}/mat"
			unless $< != 0;
		(! -f $Vlink_loc or
			chmod 04755, $Vlink_loc)
			or print "Didn't SUID  $Vlink_loc, something was wrong.\n";
		(! -f $Svend_loc or
			chmod 04755, $Svend_loc)
			or print "Didn't SUID  $Svend_loc, something was wrong.\n";
		(! -f "$Initial{'ProtBin'}/mat" or
			chmod 04755, "$Initial{'ProtBin'}/mat")
			or print "Didn't SUID  $Initial{'ProtBin'}/mat, something was wrong.\n";
	}
} # end SETUID

} # end INSTALLPROGS

STARTSERVER: {
	last STARTSERVER if $Upgrade;
	last STARTSERVER unless $Initial{'RunType'} =~ /^server$/i;
	$ans = prompt "\nStart the MiniVend server now? ", 'yes';
	if (is_yes($ans)) {
		system $Initial{'PERL'}, $Initial{'VEND'}, '-serve';
		sleep 2;
	}
}

INITDB: {
	last INITDB if $Upgrade;
	last INITDB unless $Initial{'RunType'} =~ /^static$/i;
	system $Initial{'PERL'}, $Initial{'VEND'}, '-init';
}

print <<EOU if $Upgrade;

Completed upgrade to MiniVend 1.03.

Try out your catalog, but be sure to type:

        cd $Initial{'VendRoot'}
        ./makedocs

to make the documentation, many new features have been added.

EOU

print <<EOP unless $Upgrade;

If you installed the demo, you can open the following URL to
test it:

        http://$Initial{'HostName'}/sample

EOP
print "\nDone with the MiniVend installation.\n" unless $Upgrade;

print " You can remove this directory\nand its files."
	unless ($Samedir || $Upgrade);
print <<EOP unless $Upgrade;

Type:

        cd $Initial{'VendRoot'}
        ./makedocs

to make the documentation.

EOP
