#!/usr/bin/perl
#
# MiniVend version 1.02
#
# $Id: minivend.pl,v 1.1 1996/04/04 08:28:04 mike Exp mike $
#
# This program is largely based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Enhancements made by and
# Copyright 1996 by Michael J. Heins <mikeh@iac.net>
#
# $Log: minivend.pl,v $
# Revision 1.1  1996/04/04 08:28:04  mike
# Initial revision
#
# Revision 1.2  1996/03/08 07:12:14  mike
# Fixed bug in mv_perl=on search, could crash system
#
# Revision 1.1  1996/03/07 22:54:15  mike
# Initial revision 
#
#
# See the file 'Changes' for information.
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

BEGIN {
$Config::VendRoot = '/usr/local/lib/minivend';
$Config::ConfDir = '/usr/local/lib/minivend/etc';
}
$Config::PERL = '/usr/bin/perl';
$Config::VEND = '/usr/local/lib/minivend/minivend.pl';
$Config::ConfigFile = 'minivend.cfg';
$Config::ErrorFile = 'error.log';

# Uncomment the next line if you have the Des module and the
# proper library support

#use Des;

### END CONFIGURABLE VARIABLES

use strict;
use Fcntl;

use lib $Config::VendRoot;


use Vend::Server;
use Vend::lock;
use Vend::Imagemap;
use Vend::Glimpse;
use Vend::TextSearch;

#select a DBM

BEGIN {
	eval {require GDBM_File} ||
	eval {require DB_File} ||
	eval {require NDBM_File};
	$Config::GDBM = $Config::DB_File = $Config::NDBM = 0;
	if(defined $GDBM_File::VERSION) {
		$Config::DB_Version = "GDBM V$GDBM_File::VERSION";
		require Vend::Table::GDBM;
		import GDBM_File;
		$Config::GDBM = 1;
	}
	elsif(defined $DB_File::VERSION) {
		$Config::DB_Version = "Berkeley DB V$DB_File::VERSION";
		require Vend::Table::DB_File;
		import DB_File;
		$Config::DB_File = 1;
	}
	elsif(defined $NDBM_File::VERSION) {
		$Config::DB_Version = "NDBM V$NDBM_File::VERSION";
		require Vend::Table::InMemory;
		import NDBM_File;
		$Config::NDBM = 1;
	}
	else {
		die "No DBM defined! MiniVend can't run.\n";
	}
}

use Vend::Table::Import 'import_ascii_delimited';
use Vend::Util;

my $H;
sub http {
	$H;
}

$Config::ConfigFile = "$Config::VendRoot/$Config::ConfigFile"
    if ($Config::ConfigFile !~ m.^/.);
$Config::ErrorFile = "$Config::VendRoot/$Config::ErrorFile"
    if ($Config::ErrorFile !~ m.^/.);


## CURRENCY

# Put commas in numbers
sub commify {
   local($_) = shift;
   1 while s/^(-?\d+)(\d{3})/$1,$2/;
   return $_;
}

# Return AMOUNT formatted as currency.

sub currency {
    my($amount) = @_;

	if(is_yes($Config::PriceCommas)) {
    	commify sprintf("%.2f", $amount);
	}
	else {
    	sprintf("%.2f", $amount);
	}
}


# Return shipping costs.

sub shipping {
	if($Config::CustomShipping) {
		custom_shipping();
	}
	else { $Config::Shipping; }
}

sub VerifyCreditCard {
    my $cardnumber = shift;
	my ($lengthofnumber,$numbertocheck,$checkdigit,$counter);
	my ($s,$t);

	$cardnumber =~ s/[^d]//g;

	$lengthofnumber = length($cardnumber) - 1 ;

	my $numbertocheck = substr($cardnumber,0,$lengthofnumber);

	for ($counter = 0 ; $counter < $lengthofnumber ; $counter++) {
		$t = (substr($numbertocheck,($lengthofnumber - $counter - 1),1) * (1 +
		(($counter + 1) % 2)));
		$s = $s + (($t < 10) ? $t : ($t - 9));
	}

	$checkdigit = ((10 - $s % 10) % 10);

	# Is the check digit correct?

	if (substr($cardnumber,$lengthofnumber,1) eq $checkdigit) {
		return 1;
	}
	else {
		return 0;
	}


}

sub custom_shipping {
	my($mode) = $Vend::Session->{'values'}->{'mv_shipmode'} || 'default';
	my($field) = $Config::CustomShipping;
	my($code, $i, $total);

	if(! defined $mode) {
		logError("Custom shipping called with no mode, returning 0");
		return 0;
	}
	else {
		eval {/$mode/; 1;};
		if ($@) {
			logError("Bad shipping mode '$mode', returning 0");
			return 0;
		}
	}
			
	if(! defined $Vend::Shipping_cost{'default'}) {
		if ( ! read_shipping() ) {
			logError("Custom shipping called, no shipping file, returning 0");
			return 0;
		}
	}

    $total = 0;
    foreach $i (0 .. $#$Vend::Items) {
		$total = $total + $Vend::Items->[$i]->{$field};
    }

	# We will return from this loop if a match is found
	foreach $code (sort keys %Vend::Shipping_cost) {
		next unless $code =~ /^$mode/i;
		if(	$total >= $Vend::Shipping_min{$code} and
			$total <= $Vend::Shipping_max{$code} ) {
			# unless field begins with 'x', straight cost is returned
			unless ($Vend::Shipping_cost{$code} =~ /^x\s*/i) {
				return $Vend::Shipping_cost{$code};
			}
			# - otherwise the quantity is multiplied by the cost
			else {
				my $multiplier = $Vend::Shipping_cost{$code};
				$multiplier =~ s/^x\s*//i;
				return $multiplier * $total;
			}
		}
	}

	# If we got here, the mode and quantity fit was not found
	logError("Custom shipping: no match found for\n" .
			 "mode '$mode', quantity '$total', returning 0");
	return 0;

}

# Calculate the sales tax
sub salestax {
	my($amount) = shift || subtotal();
	my($r, $code);
	my(@code) = map { $Vend::Session->{'values'}->{$_} }
					split /\s*,\s*/,$Config::SalesTax;
					

	if(! defined $Vend::SalesTax{'default'}) {
		if ( ! read_salestax() ) {
			logError("Sales tax failed, no tax file, returning 0");
			return 0;
		}
	}

	foreach $code (@code) {
		# Trim the zip+4
		$code =~ s/(\d{5})-\d+/$1/;
		# Make it upper case for state and overseas postal
		# codes, zips don't matter
		$code = uc $code;
		if(defined $Vend::SalesTax{$code}) {
			$r = $amount * $Vend::SalesTax{$code};
			last;
		}
		else {
			$r = $amount * $Vend::SalesTax{'default'};
		}
	}

	$r;
}

# Now defined in Vend::Util
#sub blank {
#	my($v) = @_;
#	!defined($v) || $v eq '';
#}

sub read_password {
	my($password,$string,$check);
	my $i = 0;

	if ($Config::Tracking) {
		open_tracking();
		$check = defined $Vend::Tracking{'encrypted_pass'}
				? $Vend::Tracking{'encrypted_pass'}
				: 0;
	}
	else {
		$check = 0;
	}

	if($Config::CreditCards) {
		while($i < 3) {
			if (-t) {
				system 'stty', '-echo';
				print "Enter the password: ";
				chop($password = <>);
				unless($check) {
					print "\nVerify: ";
					chop($string = <>);
				}
				system 'stty', 'echo';
				print "\n";
			}
			else {
				$i = 999;
				chomp($password = <>);
			}
			$i++;
			if($check) {
				if( crypt($password,$check) eq $check) {
					$Config::Password = $password;
					$check =~ s/^(........).*/$1/;
					$Config::Pw_Ivec = $check;
					return;
				}
				else {
					print "\n\nWrong password!\n\n" if -t;
					next;
				}
			}
			elsif($string eq $password) {
				$Config::Password = $password;
				if($Config::Tracking) {
					open_tracking();
					$check = crypt($password,random_string());
					$Vend::Tracking{'encrypted_pass'} = $check;
					$check =~ s/^(........).*/$1/;
					$Config::Pw_Ivec = $check;
					close_tracking();
				}
				else {
					$Config::Pw_Ivec = 'mINIvEND';
				}
				return;
			}
			else {
				undef $password;
				undef $Config::Password;
				print "\n\nThey don't match!\n\n" if -t;
				next;
			}
		}
	}

	# If we made it here, we failed to get a password
	$Config::Password = '';
	$Config::EncryptProgram = '';
	$Config::CreditCards = 0;
}


## ERROR

# Log the error MSG to the error file.

sub logError {
    my($msg) = @_;

    eval {
	open(Vend::ERROR, ">>$Config::ErrorFile") or die "open\n";
	lockfile(\*Vend::ERROR, 1, 1) or die "lock\n";
	seek(Vend::ERROR, 0, 2) or die "seek\n";
	print(Vend::ERROR `date`, "$msg\n") or die "write to\n";
	unlockfile(\*Vend::ERROR) or die "unlock\n";
	close(Vend::ERROR) or die "close\n";
    };
    if ($@) {
	chomp $@;
	print "\nCould not $@ error file '";
	print $Config::ErrorFile, "':\n$!\n";
	print "to report this error:\n", $msg;
	exit 1;
    }
}


## CONFIG

# Report an error MSG in the configuration file.

sub config_error {
    my($msg) = @_;

    die "$msg\nIn line $. of the configuration file '$Config::ConfigFile':\n" .
	"$Vend::config_line\n";
}

# Report a warning MSG about the configuration file.

sub config_warn {
    my($msg) = @_;

    logError("$msg\nIn line $. of the configuration file '" .
	     $Config::ConfigFile . "':\n" . $Vend::config_line . "\n");
}

# Each of the parse functions accepts the value of a directive from the
# configuration file as a string and either returns the parsed value or
# signals a syntax error.

# Check that an absolute pathname starts with /, and remove a final /
# if present.

sub parse_absolute_dir {
    my($var, $value) = @_;

    config_warn("The $var directive (now set to '$value') should probably\n" .
	  "start with a leading /.")
	if $value !~ m.^/.;
    $value =~ s./$..;
    $value;
}

# Prepend the VendRoot pathname to the relative directory specified,
# unless it already starts with a leading /.

sub parse_relative_dir {
    my($var, $value) = @_;

    config_error(
      "Please specify the VendRoot directive before the $var directive\n")
	unless defined $Config::VendRoot;
    $value = "$Config::VendRoot/$value" unless $value =~ m.^/.;
    $value =~ s./$..;
    $value;
}


sub parse_url {
    my($var, $value) = @_;

    config_warn(
      "The $var directive (now set to '$value') should probably\n" .
      "start with 'http:' or 'https:'")
	unless $value =~ m/^https?:/i;
    $value =~ s./$..;
    $value;
}

# Parses a time specification such as "1 day" and returns the
# number of seconds in the interval, or undef if the string could
# not be parsed.

sub time_to_seconds {
    my($str) = @_;
    my($n, $dur);

    ($n, $dur) = ($str =~ m/(\d+)\s*(\w+)?/);
    return undef unless defined $n;
    if (defined $dur) {
	$_ = $dur;
	if (m/^s|sec|secs|second|seconds$/i) {
	} elsif (m/^m|min|mins|minute|minutes$/i) {
	    $n *= 60;
	} elsif (m/^h|hour|hours$/i) {
	    $n *= 60 * 60;
	} elsif (m/^d|day|days$/i) {
	    $n *= 24 * 60 * 60;
	} elsif (m/^w|week|weeks$/i) {
	    $n *= 7 * 24 * 60 * 60;
	} else {
	    return undef;
	}
    }

    $n;
}

sub parse_executable {
    my($var, $value) = @_;
    my($x);
	my $root = $value;
	$root =~ s/\s.*//;

	if( ! defined $value or $value eq '') {
		$x = '';
	}
	elsif ($root =~ m#^/# and -x $root) {
		$x = $value;
	}
	else {
		my @path = split /:/, $ENV{PATH};
		for (@path) {
			next unless -x "$_/$root";
			$x = $value;
		}
	}

    config_error("Can't find executable ('$value') for the $var directive\n")
		unless defined $x;
    $x;
}

sub parse_time {
    my($var, $value) = @_;
    my($n);

    $n = time_to_seconds($value);
    config_error("Bad time format ('$value') in the $var directive\n")
	unless defined $n;
    $n;
}

sub parse_buttonbar {
	my ($var, $value) = @_;
	return '' unless (defined $value && $value); 
	$var = lc $var;
	@Config::ButtonBar[0..15] = get_files(split /\s+/, $value);
	return $value;
}

sub parse_help {
	my ($var, $value) = @_;
	my (@files);
	my (@items);
	my ($chunk, $item, $help, $key);
	return '' unless (defined $value && $value); 
	$var = lc $var;
	@files = get_files(split /\s+/, $value);
	foreach $chunk (@files) {
		@items = split /\n\n/, $chunk;
		foreach $item (@items) {
			($key,$help) = split /\s*\n/, $item, 2;
			if(defined $Config::Help{$key}) {
				$Config::Help{$key} .= $help;
			}
			else {
				$Config::Help{$key} = $help;
			}
				
		}
	}
	return $value;
}
		

sub parse_random {
	my ($var, $value) = @_;
	return '' unless (defined $value && $value); 
	$var = lc $var;
	@Config::Random = get_files(split /\s+/, $value);
	return $value;
}
		

sub parse_color {
	my ($var, $value) = @_;
	return '' unless (defined $value && $value); 
	$var = lc $var;
	@{Config::Color->{$var}}[0..15] = split /\s+/, $value, 16;
	return $value;
}
		

# Returns 1 for Yes and 0 for No.

sub parse_yesno {
    my($var, $value) = @_;

    $_ = $value;
    if (m/^y/i || m/^t/i || m/^1/) {
	return 1;
    } elsif (m/^n/i || m/^f/i || m/^0/) {
	return 0;
    } else {
	config_error("Use 'yes' or 'no' for the $var directive\n");
    }
}

sub parse_permission {
    my($var, $value) = @_;

    $_ = $value;
    tr/A-Z/a-z/;
    if ($_ ne 'user' and $_ ne 'group' and $_ ne 'world') {
	config_error(
"Permission must be one of 'user', 'group', or 'world' for
the $var directive\n");
    }
    $_;
}


# Parse the configuration file for directives.  Each directive sets
# the corresponding variable in the Config:: package.  E.g.
# "DisplayErrors No" in the config file sets Config::DisplayErrors to 0.
# Directives which have no default value ("undef") must be specified
# in the config file.

sub config {
    my($directives, $d, %name, %parse, $var, $value, $lvar, $parse);
    my($directive);
    no strict 'refs';

    $directives = [
#        Directive name      Parsing function    Default value

	['PageDir',          'relative_dir',     'pages'],
	['ProductDir',       'relative_dir',     'products'],
	['VendURL',          'url',              undef],
	['SecureURL',        'url',              undef],
	['OrderReport',      'relative_dir',     'report'],
	['ScratchDir',       'relative_dir',     'etc'],
    ['DisplayErrors',    'yesno',            'Yes'],
	['SessionDatabase',  'relative_dir',     'session'],
	['WritePermission',  'permission',       'user'],
	['ReadPermission',   'permission',       'user'],
	['SessionExpire',    'time',             '1 day'],
	['MailOrderTo',      undef,              undef],
	['SendMailProgram',  undef,              '/usr/lib/sendmail'],
    ['Glimpse',          'executable',       ''],
    ['RequiredFields',   undef,              ''],
    ['ReportIgnore',     undef, 			 'credit_card_no,credit_card_exp'],
    ['UseCode',		 	 undef,     	     'yes'],
    ['CreditCards',		 'yesno',     	     'No'],
    ['EncryptProgram',	 undef,     	     ''],
    ['Tracking',		 undef,     	     ''],
    ['BackendOrder',	 undef,     	     ''],
    ['SalesTax',		 undef,     	     ''],
    ['CustomShipping',	 undef,     	     ''],
    ['DefaultShipping',	 undef,     	     'default'],
    ['DebugMode',		 undef,     	     '0'],
    ['PriceCommas',		 undef,     	     'yes'],
    ['ItemLinkDir',	 	 undef,     	     ''],
    ['SearchOverMsg',	 undef,           	 ''],
	['SecureOrderMsg',   undef,              'Use Order Security'],
    ['SearchFrame',	 	 undef,     	     'main'],
    ['OrderFrame',	     undef,              '_top'],
    ['FrameOrderPage',	 undef,     	     ''],
    ['FrameSearchPage',	 undef,     	     ''],
    ['DescriptionTrim',  undef,              ''],
    ['ItemLinkValue',    undef,              'More Details'],
	['FinishOrder',      undef,              'Finish Incomplete Order'],
	['Shipping',         undef,               0],
	['Help',            'help',              ''],
	['Random',          'random',            ''],
	['Mv_Background',   'color',             ''],
	['Mv_BgColor',      'color',             ''],
	['Mv_TextColor',    'color',             ''],
	['Mv_LinkColor',    'color',             ''],
	['Mv_VlinkColor',   'color',             ''],
	['ButtonBars',       'buttonbar',         ''],
    ];

    foreach $d (@$directives) {
	($directive = $d->[0]) =~ tr/A-Z/a-z/;
	$name{$directive} = $d->[0];
	if (defined $d->[1]) {
	    $parse = 'parse_' . $d->[1];
	} else {
	    $parse = undef;
	}
	$parse{$directive} = $parse;
	$value = $d->[2];
	if (defined $parse and defined $value) {
	    $value = &$parse($d->[0], $value);
	}
	${'Config::' . $name{$directive}} = $value;
    }

    open(Vend::CONFIG, $Config::ConfigFile)
	|| die "Could not open configuration file '" .
                $Config::ConfigFile . "':\n$!\n";
    while(<Vend::CONFIG>) {
	chomp;			# zap trailing newline,
	s/^\s*#.*//;            # comments,
				# mh 2/10/96 changed comment behavior
				# to avoid zapping RGB values
				#
	s/\s+$//;		#  trailing spaces
	next if $_ eq '';
	$Vend::config_line = $_;
	# lines read from the config file become untainted
	m/^(\w+)\s+(.*)/ or config_error("Syntax error");
	$var = $1;
	$value = $2;
	($lvar = $var) =~ tr/A-Z/a-z/;
	config_error("Unknown directive '$var'") unless defined $name{$lvar};
	$parse = $parse{$lvar};
				# call the parsing function for this directive
	$value = &$parse($name{$lvar}, $value) if defined $parse;
				# and set the Config::directive variable
	${'Config::' . $name{$lvar}} = $value;
    }
    close Vend::CONFIG;

    # check for unspecified directives that don't have default values
    foreach $var (keys %name) {
        if (!defined ${'Config::' . $name{$var}}) {
            die "Please specify the $name{$var} directive in the\n" .
            "configuration file '$Config::ConfigFile'\n";
        }
    }
}


## ESCAPE_CHARS

$ESCAPE_CHARS::ok_in_filename = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' .
    'abcdefghijklmnopqrstuvwxyz' .
    '0123456789' .
    '-_.$/';

sub setup_escape_chars {
    my($ok, $i, $a, $t);

    foreach $i (0..255) {
        $a = chr($i);
        if (index($ESCAPE_CHARS::ok_in_filename,$a) == -1) {
	    $t = '%' . sprintf( "%02X", $i );
        } else {
	    $t = $a;
        }
        $ESCAPE_CHARS::translate[$i] = $t;
    }
}

# Replace any characters that might not be safe in a filename (especially
# shell metacharacters) with the %HH notation.

sub escape_chars {
    my($in) = @_;
    my($c, $r);

    $r = '';
    foreach $c (split(//, $in)) {
	$r .= $ESCAPE_CHARS::translate[ord($c)];
    }

    # safe now
    $r =~ m/(.*)/;
    $r = $1;
    #print Vend::DEBUG "escape_chars tainted: ", tainted($r), "\n";
    $1;
}

# Replace the escape notation %HH with the actual characters.

sub unescape_chars {
    my($in) = @_;

    $in =~ s/%(..)/chr(hex($1))/ge;
    $in;
}

# Encrypts a credit card number with DES or the like
# Prefers internal Des module, if was included
sub encrypt_cc {
	my($enclair) = @_;
	my($password) = $Config::Password || return undef;
	my($encrypted, $status, $cmd);
	my $firstline = 0;

	$cmd = $Config::EncryptProgram;

	# This is the internal function, will return the value
	# if it was found. Takes the IVEC from the first
	# 8 characters of the encrypted password
	if (defined @Des::EXPORT) {
		my $key = string_to_key($Config::Password);
		my $sched = set_key($key);
		$encrypted = pcbc_encrypt($enclair,undef,$sched,$Config::Pw_Ivec);
		open(CAT, ">test.out");
		print CAT $encrypted;
		close CAT;
		return $encrypted;
	}

	#Substitute the password
	unless ($cmd =~ s/%p/$Config::Password/) {
		$firstline = 1;
	}

	my $tempfile = $Vend::SessionID . '.cry';

	#Substitute the filename, else concatenate
	unless ($cmd =~ s/%f/$tempfile/) {
		$cmd .= " $tempfile";
	}

	# Send the CC to a tempfile
	open(CARD, ">$tempfile") ||
		die "Couldn't write $tempfile: $!\n";

	# Put the cardnumber there, and maybe password first
	print CARD "$Config::Password\n" if $firstline;
	print CARD $enclair;
	#close CARD;

	# Encrypt the string, but key on arg line will be exposed
	# to ps(1) for systems that allow it
	open(CRYPT, "$cmd |") || die "Couldn't fork: $!\n";
	chomp($encrypted = <CRYPT>);
	close CRYPT;
	$status = $?;

	if($status) {
		logError("Encryption didn't work, status $status: $!\n"
					. "Command: $cmd\n");
		return undef;
	}

	$encrypted;
}


## RANDOM_STRING

# leaving out 0, O and 1, l
$RANDOM_STRING::chars =
    "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

# Return a string of random characters.

sub random_string {
    my($len) = @_;
    $len = 8 unless $len;
    my($r, $i);

    $r = '';
    for ($i = 0;  $i < $len;  ++$i) {
	$r .= substr($RANDOM_STRING::chars,
		     int(rand(length($RANDOM_STRING::chars))), 1);
    }
    $r;
}


## UNEVAL

# Returns a string representation of an anonymous array, hash, or scaler
# that can be eval'ed to produce the same value.
# uneval([1, 2, 3, [4, 5]]) -> '[1,2,3,[4,5,],]'

sub uneval {
    my($o) = @_;		# recursive
    my($r, $s, $i, $key, $value);

    $r = ref $o;
    if (!$r) {
	$o =~ s/[\\"\$@]/\\$&/g;
	$s = '"' . $o . '"';
    } elsif ($r eq 'ARRAY') {
	$s = "[";
	foreach $i (0 .. $#$o) {
	    $s .= uneval($o->[$i]) . ",";
	}
	$s .= "]";
    } elsif ($r eq 'HASH') {
	$s = "{";
	while (($key, $value) = each %$o) {
	    $s .= "'$key' => " . uneval($value) . ",";
	}
	$s .= "}";
    } else {
	$s = "'something else'";
    }

    $s;
}


## READIN

# Reads in a page from the page directory with the name FILE and ".html"
# appended.  Returns the entire contents of the page, or undef if the
# file could not be read.

sub readin {
    my($file) = @_;
    my($fn, $contents);
    local($/);

    $fn = "$Config::PageDir/" . escape_chars($file) . ".html";
    if (open(Vend::IN, $fn)) {
		undef $/;
		$contents = <Vend::IN>;
		close(Vend::IN);
    } else {
		$contents = undef;
    }
    $contents;
}

# Calls readin to get files, then returns an array of values
# with the file contents in each entry. Returns a single newline
# if not found or empty. For getting buttonbars, helps,
# and randoms.
sub get_files {
	my(@files) = @_;
	my(@out);
	my($file, $contents);

	foreach $file (@files) {
		push(@out,"\n") unless
			push(@out,readin($file));
	}
	
	@out;
}


## SESSIONS implemented using DBM

sub get_session {
	open_session();
	read_session();
	close_session();
}

sub put_session {
	open_session();
	write_session();
	close_session();
}

sub open_session {

    open(Vend::SessionLock, "+>>$Config::ConfDir/session.lock")
	or die "Could not open 'session.lock': $!\n";
    lockfile(\*Vend::SessionLock, 1, 1)
	or die "Could not lock 'session.lock': $!\n";
    
    # Selects based on initial config
	if($Config::GDBM) {
    	tie(%Vend::SessionDBM, 'GDBM_File', $Config::SessionDatabase . ".gdbm",
		&GDBM_WRCREAT, $Config::FileCreationMask)
		or die "Could not tie to $Config::SessionDatabase: $!\n";
	}
	elsif($Config::DB_File) {
    	tie(%Vend::SessionDBM, 'DB_File', $Config::SessionDatabase . ".db",
		&O_RDWR|&O_CREAT, $Config::FileCreationMask)
		or die "Could not tie to $Config::SessionDatabase: $!\n";
	}
	elsif($Config::NDBM) {
    	tie(%Vend::SessionDBM, 'NDBM_File', $Config::SessionDatabase,
		&O_RDWR|&O_CREAT, $Config::FileCreationMask)
		or die "Could not tie to $Config::SessionDatabase: $!\n";
	}
	else {
		die "No DBM implementation configured!\n";
	}

}

sub new_session {
    my($name);

    open_session();
    $Vend::SessionName = session_name();
    for (;;) {
		$Vend::SessionID = random_string();
		$name = session_name();
		last unless defined $Vend::SessionDBM{$name};
    }
    $Vend::SessionName = $name;
    init_session();
	write_session();
	close_session();
}

sub close_tracking {

	if ($Config::Tracking && defined %Vend::Tracking) {
	   	untie %Vend::Tracking
			or die "Could not untie $Config::ProductDir/tracking: $!\n";
	   	unlockfile(\*Vend::TrackingLock)
			or die "Could not unlock 'tracking.lock': $!\n";
	   	close(Vend::TrackingLock)
			or die "Could not close 'tracking.lock': $!\n";
	}
}

sub close_session {
    #pick one

    untie %Vend::SessionDBM
	or die "Could not close $Config::SessionDatabase: $!\n";
	
	unlockfile(\*Vend::SessionLock)
		or die "Could not unlock 'session.lock': $!\n";
    close(Vend::SessionLock)
		or die "Could not close 'session.lock': $!\n";
}

sub write_session {
    my($s);
    $Vend::Session->{'time'} = time;
    $s = uneval($Vend::Session);
    $Vend::SessionDBM{$Vend::SessionName} = $s;
    die "Data was not stored in DBM file\n"
		if $Vend::SessionDBM{$Vend::SessionName} ne $s;
}

sub unlock_session {
}

sub read_session {
    my($s);

    $s = $Vend::SessionDBM{$Vend::SessionName};
    $Vend::Session = eval($s);
    die "Could not eval '$s' from session dbm: $@\n" if $@;
    $Vend::Items = $Vend::Session->{'items'};
}

sub expire_sessions {
    my($time, $session_name, $s, $session, @delete);

    $time = time;
    open_session();
    while(($session_name, $s) = each %Vend::SessionDBM) {
		next if $session_name =~ /^lock/;
		$session = eval($s);
		die "Could not eval '$s' from session dbm: $@\n" if $@;
		if ( (! defined $session) ||
			 $time - $session->{'time'} > $Config::SessionExpire) {
			push @delete, $session_name;
			push @delete, "lock$session_name"
				if $Vend::SessionDBM{"lock$session_name"};
		}
    }
    foreach $session_name (@delete) {
		delete $Vend::SessionDBM{$session_name};
		my $file = $session_name;
		$file =~ s/:.*//;
		opendir(Vend::DELDIR, $Config::ScratchDir) ||
			die "Could not open configuration directory $Config::ScratchDir: $!\n";
		my @files = grep /^$file/, readdir(Vend::DELDIR);
		for(@files) {
			unlink "$Config::ScratchDir/$_";
		}
		closedir(Vend::DELDIR);
    }
    close_session();
}

sub dump_sessions {
    my($session_name, $s);

    open_session();
    while(($session_name, $s) = each %Vend::SessionDBM) {
	print "$session_name $s\n\n";
    }
    close_session();
}


## SESSIONS

sub session_name {
    my($host, $user, $fn);

    $fn = escape_chars($Vend::SessionID) . ':'
	. escape_chars($CGI::host) . ':' . escape_chars($CGI::user);
    #escape_chars($CGI::gateway_interface);
    $fn;
}


sub init_session {
    $Vend::Session = {
	'version' => 1,
	'frames' => 0,
	'secure' => 0,
	'browser' => $CGI::useragent,
	'items' => [],
    };
    $Vend::Items = $Vend::Session->{'items'};
	$Vend::Session->{'values'}->{'mv_shipmode'} = $Config::DefaultShipping;
}

## PRODUCTS

# Read in the shipping file.

sub read_shipping {
    my($code, $desc, $min, $criterion, $max, $cost);

    open(Vend::SHIPPING,"$Config::ProductDir/shipping.asc")
	|| do {
		logError("Could not open shipping: $!");
		return undef;
		};
    while(<Vend::SHIPPING>) {
		chomp;
		($code, $desc, $criterion, $min, $max, $cost) = split(/\t/);
		$Vend::Shipping_desc{$code} = $desc;
		$Vend::Shipping_criterion{$code} = $criterion;
		$Vend::Shipping_min{$code} = $min;
		$Vend::Shipping_max{$code} = $max;
		$Vend::Shipping_cost{$code} = $cost;
    }
    close Vend::SHIPPING;
	1;
}

# Read in the sales tax file.

sub read_salestax {
    my($code, $percent);

    open(Vend::SALESTAX,"$Config::ProductDir/salestax.asc")
	|| do {
		logError("Could not open salestax.asc: $!");
		return undef;
		};
    while(<Vend::SALESTAX>) {
		chomp;
		($code, $percent) = split(/\s+/);
		$Vend::SalesTax{$code} = $percent;
    }
    close Vend::SALESTAX;
	1;
}

sub open_tracking {
	
	my($page, $desc, $price);

    open(Vend::TrackingLock, "+>>$Config::ConfDir/tracking.lock")
    	or die "Could not open '$Config::ConfDir/tracking.lock': $!\n";
    lockfile(\*Vend::TrackingLock, 0, 1)
    	or die "Could not lock '$Config::ConfDir/tracking.lock': $!\n";

    if($Config::GDBM) {
 		tie(%Vend::Tracking, 'GDBM_File',
				"$Config::ProductDir/tracking.gdbm",
				&GDBM_WRCREAT, $Config::FileCreationMask)
    		or die "Could not tie to $Config::ProductDir/tracking.gdbm: $!\n";

	}
	elsif ($Config::DB_File) {
		tie(%Vend::Tracking, 'DB_File',
				"$Config::ProductDir/tracking.db",
				&O_RDWR|&O_CREAT, $Config::FileCreationMask)
			or die "Could not tie to $Config::ProductDir/tracking: $!\n";
	}
	elsif ($Config::NDBM) {
		tie(%Vend::Tracking, 'NDBM_File',
				"$Config::ProductDir/tracking",
				&O_RDWR|&O_CREAT, $Config::FileCreationMask)
			or die "Could not tie to $Config::ProductDir/tracking: $!\n";
	}
	else {
		die "No DBM configuration defined!\n";
	}

}

my $New_product_dbm; 
my ($Products, $Product_desc, $Product_price);

sub product_code_exists {
    my ($product_code) = @_;
    return $Products->record_exists($product_code);
}

sub product_price {
    my ($product_code) = @_;
    return "NA" unless product_code_exists($product_code);
    return &$Product_price($product_code);
}

sub product_description {
    my ($product_code) = @_;
    return "NA" unless product_code_exists($product_code);
    return &$Product_desc($product_code);
}

sub product_field {
    my ($product_code, $field_name) = @_;
    return "NA" unless product_code_exists($product_code);
    return $Products->field($product_code, $field_name);
}


sub create_product_mem {
    my (@columns) = @_;
    return Vend::Table::InMemory->create_table( {}, $New_product_dbm,
                                           [@columns]);
}

sub create_product_dbfile {
    my (@columns) = @_;
    return Vend::Table::DB_File->create_table( {}, $New_product_dbm,
                                           [@columns]);
}

sub create_product_gdbm {
    my (@columns) = @_;
    return Vend::Table::GDBM->create_table({Fast_write => 1},
                                           $New_product_dbm,
                                           [@columns]);
}

sub import_products {
    my ($config) = @_;

    my $data = $Config::ProductDir;

    my $product_txt = "$data/products.asc";
	my $product_dbm;
	my $create_sub;
	my $restart_necessary = 0;
	my $restart = 0;

    if($Config::GDBM) {
		$New_product_dbm = "$data/new.product.gdbm";
    	$product_dbm = "$data/product.gdbm";
    	$create_sub = \&create_product_gdbm;
	}
    elsif($Config::DB_File) {
		$New_product_dbm = "$data/new.product.db";
    	$product_dbm = "$data/product.db";
    	$create_sub = \&create_product_dbfile;
		$restart_necessary = 1;
	}
    else {
    	$create_sub = \&create_product_mem;
	}

    if (! defined $product_dbm
		or ! -e $product_dbm
        or file_modification_time($product_txt) >
            file_modification_time($product_dbm)) {

        print "Importing product table\n";
        $Products = import_ascii_delimited($product_txt, "\t", $create_sub);
		$restart = 1 if $restart_necessary;
		if(defined $product_dbm) {
        	rename($New_product_dbm, $product_dbm)
            	or die "Couldn't move '$New_product_dbm' to '$product_dbm': $!\n";
		}
    }


    if($Config::GDBM) {
    	$Products = Vend::Table::GDBM->open_table({Read_only => 1},
                                              "$data/product.gdbm");
	}
    elsif($Config::DB_File) {
		if($restart) {
			warn "Need to restart after Berkeley DB import...\n";
			exit 2;
		}
    	$Products = Vend::Table::DB_File->open_table({Read_only => 1},
                                              "$data/product.db");
	}
    $Product_desc = $Products->field_accessor("description");
    $Product_price = $Products->field_accessor("price");
}   

sub close_products {
    	$Products->close_table()
			or die "Could not untie products database.\n";
}

## PAGE GENERATION

sub plain_header {
    print "Content-type: text/plain\n\n";
    $Vend::content_type = 'plain';
}

sub response {
	my ($type,$output,$debug) = @_;
	$Vend::content_type = $type;
	if(defined $Vend::ServerMode) {
		http()->respond("text/$type",$output,$debug);
	}
	else {
		print "Content-type: text/$type\n\n";
		print $output;
	}
}

sub html_header {
    print "Content-type: text/html\n\n";
    $Vend::content_type = 'html';
}

# Returns a URL which will run the ordering system again.  Each URL
# contains the session ID as well as a unique integer to avoid caching
# of pages by the browser.

sub vendUrl
{
    my($path, $arguments) = @_;
    my($r);

    $r = $Config::VendURL . '/' . $path . '?' . $Vend::SessionID .
	';' . $arguments . ';' . ++$Vend::Session->{'pageCount'};
    $r;
}    

sub secure_vendUrl
{
    my($path, $arguments) = @_;
    my($r);

	return undef unless $Config::SecureURL;

    $r = $Config::SecureURL . '/' . $path . '?' . $Vend::SessionID .
	';' . $arguments . ';' . ++$Vend::Session->{'pageCount'};
    $r;
}    

# Returns 'CHECKED' when a value is present on the form
# Must match exactly, but NOT case-sensitive
# Defaults to 'on' for checkboxes
# Silently returns null string if illegal regex

sub tag_checked {
	my $field = shift;
	my $value = shift || 'on';
	my $r;

	#eval {/^$value$/} ;
	#return '' if $@;

	if($Vend::Session->{'values'}->{"\L$field"} =~ /^$value$/i) {
		$r = 'CHECKED';
	}
	else {$r = ''}
	$r;
}

# Returns 'SELECTED' when a value is present on the form
# Must match exactly, but NOT case-sensitive
# Silently returns null string if illegal regex

sub tag_selected {
	my $field = shift;
	my $value = shift || '';
	my $r;

	#eval {/^$value$/} ;
	#return '' if ( $@ or ! $value);

	if($Vend::Session->{'values'}->{$field} =~ /^$value$/i) {
		$r = 'SELECTED';
	}
	else {$r = ''}
	$r;
}


# Returns either a href to finish the ordering process (if at least
# one item has been ordered), or an empty string.
# If a secure order has been started (with a forms submission)
# then it will be given the secure URL

sub tag_finish_order {
    my($finish_order);

    if (@$Vend::Items > 0) {
		if ($Vend::Session->{'secure'}) {
			$finish_order = '<a href="' . secure_vendUrl("finish");
		}
		else {
			$finish_order = '<a href="' . vendUrl("finish");
		}
		$finish_order .= '" TARGET="' . $Config::OrderFrame
			if $Vend::Session->{'frames'};
		$finish_order .= '">' . $Config::FinishOrder . "</a><p>";
    }
	else {
		$finish_order = '';
    }
    $finish_order;
}


# Returns an href to place an order for the product PRODUCT_CODE.
# If a secure order has been started (with a call to at least
# one secure_vendUrl), then it will be given the secure URL

sub tag_order {
    my($product_code) = @_;
	my($r);

	if ($Vend::Session->{'secure'}) {
    	$r  = '<a href="' . secure_vendUrl('order', $product_code);
	}
	else {
    	$r  = '<a href="' . vendUrl('order', $product_code);
	}
	$r .= '" TARGET="' . $Config::OrderFrame
		if $Vend::Session->{'frames'};
	$r .= '">';
}

# Returns a body tag with a user-entered, a set color scheme, or the default
sub tag_body {
    my($scheme) = @_;
	my $r = '<BODY';
	my ($var,$tag);
	#return '<BODY>' unless (int($scheme) < 16 and int($scheme) > 1);

	my %color = qw( mv_bgcolor BGCOLOR mv_textcolor TEXT
					mv_linkcolor LINK mv_vlinkcolor VLINK
					mv_background BACKGROUND );
	if (defined $Vend::Session->{'values'}->{mv_resetcolors}
			and $Vend::Session->{'values'}->{mv_resetcolors}) {
		delete $Vend::Session->{'values'}->{mv_customcolors};
		undef $Vend::Session->{'values'}->{mv_resetcolors};
	}
	if (defined $Vend::Session->{'values'}->{mv_customcolors}) {
		foreach $var (keys %color) {
			$r .= qq| $color{$var}="| . $Vend::Session->{'values'}->{$var} . '"'
				if $Vend::Session->{'values'}->{$var};
		}
	}
	else {
		foreach $var (keys %color) {
			$r .= qq| $color{$var}="| . ${Config::Color->{$var}}[$scheme] . '"'
				if defined ${Config::Color->{$var}}[$scheme]
					&&  ${Config::Color->{$var}}[$scheme] !~ /\bnone\b/;
		}
	}
	$r .= '>';
}

# Returns the text of a user entered field named VAR.
sub tag_value {
    my($var) = @_;
    my($value);

    if (defined ($value = $Vend::Session->{'values'}->{$var})) {
	return $value;
    } else {
	return "";
    }
}

# Returns an href which will call up the specified PAGE.

sub tag_page {
    my($page) = @_;

    '<a href="' . vendUrl($page) . '">';
}

# Returns an href which will call up the specified PAGE with TARGET reference.
# If target ends with '__secure', will call the SecureURL

sub tag_pagetarget {
    my($page,$target) = @_;
    my($r);
	unless ($target =~ s/__secure$//i) {
    	$r  = '<a href="' . vendUrl($page);
	}
	else {
    	$r  = '<a href="' . secure_vendUrl($page);
	}
    $r .= '" TARGET="' . $target
        if $Vend::Session->{'frames'};
    $r .= '">';
}

# Returns an href which will call up the specified PAGE.

sub tag_area {
    my($area) = @_;

    vendUrl($area);
}

# Returns an href which will call up the specified PAGE with TARGET reference.

sub tag_areatarget {
    my($area,$target) = @_;
	my($r);
    $r  = vendUrl($area);
	$r .= '" TARGET="' . $target
		if $Vend::Session->{'frames'};
	$r;
}

# Sets the frames feature to on, returns empty string
sub tag_frames_on {
    $Vend::Session->{'frames'} = 1;
	return '';
}

# Sets the frames feature to on, returns empty string
sub tag_frames_off {
    $Vend::Session->{'frames'} = 0;
	return '';
}

# Sets the frame base, can't coexist with other base tags
sub tag_frame_base {
	my($baseframe) = shift;
    if ($Vend::Session->{'frames'}) {
		'<BASE TARGET="' . $baseframe .'">';
	}
	else {
		return '';
	}
}

# Returns a random message or image
sub tag_random {
	my $random = int rand(scalar(@Config::Random));
    if (defined $Config::Random[$random]) {
		return $Config::Random[$random];
	}
	else {
		return '';
	}
}

# Returns a help item by name, if it exists
sub tag_help {
	my($help) = shift;
	# Move this to control section?
	if (defined $Vend::Session->{'values'}->{mv_helpon}
			and $Vend::Session->{'values'}->{mv_helpon}) {
		delete $Vend::Session->{'values'}->{mv_helpoff};
		undef $Vend::Session->{'values'}->{mv_helpon};
	}
	return '' if defined $Vend::Session->{'values'}->{'mv_helpoff'};
    if (defined $Config::Help{$help}) {
		return $Config::Help{$help};
	}
	else {
		return '';
	}
}

# Returns a buttonbar by number
sub tag_buttonbar {
	my($buttonbar) = shift;
    if (defined $Config::ButtonBar[$buttonbar]) {
		return $Config::ButtonBar[$buttonbar];
	}
	else {
		return '';
	}
}

# Returns an href to call up the last page visited.

sub tag_last_page {
    tag_page($Vend::Session->{'page'});
}

# Returns the total number of items ordered.

sub tag_nitems {
    my($total, $i);

    $total = 0;
    foreach $i (0 .. $#$Vend::Items) {
	$total += $Vend::Items->[$i]->{'quantity'};
    }
    $total;
}

# Returns the shipping charges.

sub tag_shipping {
	my $mode = @_;
    currency(shipping($mode));
}

# Returns the total cost of items ordered.

sub tag_total_cost {
    my($total, $i);

    $total = subtotal();

    $total += salestax($total);

    $total += shipping();

    currency($total);

}


# Returns just subtotal of items ordered
sub subtotal {
    my($subtotal, $i);

    $subtotal = 0;
    foreach $i (0 .. $#$Vend::Items) {
	$subtotal += $Vend::Items->[$i]->{'quantity'} *
	    product_price($Vend::Items->[$i]->{'code'});
    }

	$subtotal;
}

# Returns the href to process the completed order form or do the search.

sub tag_process_target {
	my($frame,$security) = @_;
	my $frametag = '';

	if($Vend::Session->{'frames'}) {
    	$frametag = '" TARGET="'. $frame;
	}

	if ("\L$security" eq 'secure') {
    	secure_vendUrl('process') . $frametag;
	}
	else {
    	vendUrl('process') . $frametag;
	}
}

sub tag_process_search {
	if($Vend::Session->{'frames'}) {
    	vendUrl('process') . '" TARGET="'. $Config::SearchFrame;
	}
	else {
    	vendUrl('process');
	}
}

sub tag_process_order {
	my $frametag = '';

	if($Vend::Session->{'frames'}) {
    	$frametag = '" TARGET="_self' ;
	}

	if ($Vend::Session->{'secure'}) {
    	secure_vendUrl('process') . $frametag;
	}
	else {
    	vendUrl('process') . $frametag;
	}
}

sub tag_secure_order {
	my $r = '';
	my $message = $Config::SecureOrderMsg;
	my $target = '';

	$target = '" TARGET="' . $Config::OrderFrame
		if $Vend::Session->{'frames'};

	unless($Vend::Session->{'secure'}) {
		$r = 	'<A HREF="' .
				secure_vendUrl('account') . $target .
				'">' . $message . '</A>';
	}

	$r;

}

# Evaluates the [...] tags.

sub interpolate_html {
    my($html) = @_;
    my($codere) = '[\w-_#/.]+';

    $html =~ s:\[finish[-_]order\]:tag_finish_order():ige;

    $html =~ s:\[frames[-_]on\]:tag_frames_on():ige;
    $html =~ s:\[frames[-_]off\]:tag_frames_off():ige;

    $html =~ s:\[secure[-_]order\]:tag_secure_order():ige;
    $html =~ s:\[framebase\s+($codere)\]:tag_frame_base($1):ige;
    $html =~ s:\[body\s+($codere)\]:tag_body($1):igoe;
    $html =~ s:\[help\s+($codere)\]:tag_help($1):igoe;
    $html =~ s:\[buttonbar\s+($codere)\]:tag_buttonbar($1):igoe;
    $html =~ s:\[random\]:tag_random():ige;

    $html =~ s:\[pagetarget\s+($codere)\s+($codere)\]:tag_pagetarget($1,$2):igeo;
    $html =~ s:\[/pagetarget\]:</a>:ig;

    $html =~ s:\[area\s+($codere)\]:tag_area($1):igeo;

    $html =~ s:\[areatarget\s+($codere)\s+($codere)\]:tag_areatarget($1,$2):igeo;

	$html =~ s:\[checked\s+($codere)(\s+)?($codere)?\]:tag_checked($1,$3):igeo;
	$html =~ s:\[selected\s+($codere)\s+($codere)\]:tag_selected($1,$2):igeo;

    $html =~ s:\[page\s+($codere)\]:tag_page($1):igeo;
    $html =~ s:\[/page\]:</a>:ig;

    $html =~ s:\[last[-_]page\]:tag_last_page():ige;
    $html =~ s:\[/last[-_]page\]:</a>:ig;

    $html =~ s:\[order\s+($codere)\]:tag_order($1):igeo;
    $html =~ s:\[/order\]:</a>:ig;

    $html =~ s:\[field\s+($codere)\s+($codere)\]:product_field($2,$1):igeo;
    $html =~ s:\[value\s+($codere)\]:tag_value($1):igeo;

    $html =~ s:\[nitems\]:tag_nitems():ige;
    $html =~ s#\[subtotal\]#currency(subtotal())#ige;
    $html =~ s#\[shipping\]#currency(shipping())#ige;
    $html =~ s#\[salestax\]#currency(salestax())#ige;
    $html =~ s#\[total[-_]cost\]#tag_total_cost()#ige;
    $html =~ s#\[price\s+($codere)\]#currency(product_price($1))#igoe;
    $html =~ s#\[description\s+($codere)\]#
               product_description($1)#igoe;

    $html =~ s#\[process[-_]order\]#tag_process_order()#ige;
    $html =~ s#\[process[-_]search\]#tag_process_search()#ige;
    $html =~ s#\[process[-_]target\s+($codere)(\s+)?($codere)?\]#
				tag_process_target($1,$3)#igoe;
    $html;
}

# Trims the description output for the order and search pages
# Trims from $Config::DescriptionTrim onward
sub trim_desc {
	my($desc) = @_;
	if($Config::DescriptionTrim) {
		$desc =~ s/$Config::DescriptionTrim(.*)//;
	}
	$desc;
}
	

## ORDER PAGE

sub tag_search_list {
    my($text,$obj,$q) = @_;
    my($r, $i, $item, $code, $link);
	my($linkvalue, $run, $count);
    my($codere) = '[\w-_#/.]+';

	# get the number to start the increment from
	$count = $q->global('first_match');

    $r = "";
	$linkvalue = $Config::ItemLinkValue;

    foreach $item (@$obj) {
		($code, $link) = split(/\s+/,$item, 2);
		$link = $code if is_yes($Config::UseCode);

		# Uncomment next line to ignore non-database items
		# next unless product_code_exists($code);

		$count++;

	    $run = $text;
	    $run =~ s#\[if[-_]field\s+($codere)\]([\s\S]*?)\[/if\]#
				  product_field($code,$1) ? $2 : ''#ige;
	    $run =~ s:\[item[-_]increment\]:$count:ig;
	    $run =~ s:\[item[-_]code\]:$code:ig;
	    $run =~ s:\[item[-_]field\s+($codere)\]:product_field($code,$1):ige;
	    $run =~ s:\[item[-_]description\]:trim_desc(product_description($code)):ige;
	    $run =~ s#\[item[-_]link\]#"[page $Config::ItemLinkDir$link]"
	  			. $linkvalue . '[/page]'#ige;
	    $run =~ s:\[item[-_]price\]:currency(product_price($code)):ige;

	  $r .= $run;
    }
    $r;
}

sub tag_more_list {
	my($r,$q) = @_;
	my ($list, $inc, $next, $last);

	my $first = $q->global('first_match') + 1;
	my $mod   = $q->global('search_mod');
	my $chunk = $q->global('match_limit');
	my $total = $q->global('matches');

	if($chunk >= $total) {
		return '';
	}

	my $next = $q->global('next_pointer');
	my $last = $next + $chunk - 1;
	my $adder = ($total % $chunk) ? 1 : 0;
	my $pages = int($total / $chunk) + $adder;
	my $current = int($next / $chunk) || $pages;

	if($next) {
		$list = '<A HREF="' .
			vendUrl('search', "$next:$last:$mod") .
			'" TARGET="_self">Next</A> ';
	}
	
	foreach $inc (1..$pages) {
		$next = ($inc-1) * $chunk;
		$last = ($last+1) < $total ? ($next + $chunk - 1) : ($total - 1);
		if($inc == $current) {
			$list .= qq|<STRONG>$inc</STRONG> |;
		}
		else {
			$list .= '<A HREF="';
			$list .= vendUrl('search',"$next:$last:$mod");
			$list .= '" TARGET="_self">';
			$list .= qq|$inc</A> |;
		}
	}

	unless( $first < $chunk ) {
		$next = $first - $chunk - 1;
		$last = $first - 2;
		$list .= '<A HREF="' .
			vendUrl('search', "$next:$last:$mod") .
			'" TARGET="_self">Previous</A> ';
	}
	$last = $first + $chunk - 1;
	$last = $last > $total ? $total : $last;
	my $m = $first . '-' . $last; 
	$r =~ s/\[more\]/$list/ige;
	$r =~ s/\[matches\]/$m/ige;

	$r;

}

sub tag_item_list {
    my($text) = @_;
    my($r, $i, $item, $link, $code, $quantity, $linkvalue, $run);
    my($codere) = '[\w-_#/.]+';

    $r = "";
	$linkvalue = $Config::ItemLinkValue;
    foreach $i (0 .. $#$Vend::Items) {
		$item = $Vend::Items->[$i];
		$code = $item->{'code'};
		$quantity = $item->{'quantity'};

	    $run = $text;
		$run =~ s#\[if[-_]field\s+($codere)\]([\s\S]*?)\[/if\]#
				  product_field($code,$1) ? $2 : ''#ige;
	    $run =~ s:\[item[-_]increment\]:$i + 1:ige;
		$run =~ s:\[item[-_]quantity\]:$quantity:ig;
		$run =~ s:\[quantity[-_]name\]:quantity$i:ig;
	    $run =~ s:\[item[-_]code\]:$code:ig;
	    $run =~ s:\[item[-_]field\s+($codere)\]:product_field($code,$1):ige;
	    $run =~ s:\[item[-_]description\]:trim_desc(product_description($code)):ige;
	    $run =~ s#\[item[-_]link\]#"[page $Config::ItemLinkDir$code]"
	  			  . $linkvalue . '[/page]'#ige;
	    $run =~ s:\[item[-_]price\]:currency(product_price($code)):ige;

	    $r .= $run;
    }
    $r;
}

# Displays the order page with the special [item-list] tag evaluated.

sub search_page
{
	my($q,$o) = @_;
    my($page);

	if($Config::FrameSearchPage && $Vend::Session->{'frames'}) {
    	$page = readin($Config::FrameSearchPage);
	}
    else {
    	$page = readin("search");
	}

    die "Missing special page: search\n" unless defined $page;
	# passing the list reference here
    $page =~ s:\[search[-_]list\]([\000-\377]*?)\[/search[-_]list\]:
              tag_search_list($1,$o,$q):ige;
    $page =~ s:\[more[-_]list\]([\000-\377]*?)\[/more[-_]list\]:
              tag_more_list($1,$q):ige;
    response('html',interpolate_html($page));
}


# Tries to display the on-the-fly page if page is missing
sub fly_page
{
	my($code) = @_;
	$code =~ s:.*/::;
    my($page);
    my($codere) = '[\w-_#/.]+';

	if(is_yes($Config::UseCode) && product_code_exists($code)) {
    	$page = readin('flypage');
	}

    return undef unless defined $page;
	$page =~ s#\[if[-_]field\s+($codere)\]([\s\S]*?)\[/if\]#
				  product_field($code,$1) ? $2 : ''#ige;
    $page =~ s!\[item[-_]code\]!$code!ig;
    $page =~ s!\[item[-_]description\]!product_description($code)!ige;
    $page =~ s!\[item[-_]price\]!product_price($code)!ige;
	$page =~ s:\[item[-_]field\s+($codere)\]:product_field($code,$1):ige;

    interpolate_html($page);
}

sub order_page
{
    my($page);

	if($Config::FrameOrderPage && $Vend::Session->{'frames'}) {
    	$page = readin($Config::FrameOrderPage);
	}
    else {
    	$page = readin("order");
	}

    die "Missing special page: order\n" unless defined $page;
    $page =~ s:\[item[-_]list\]([\000-\377]*?)\[/item[-_]list\]:
              tag_item_list($1):ige;
    response('html',interpolate_html($page));
}


## INTERFACE ERROR

# An incorrect response was returned from the browser, either because of a
# browser bug or bad html pages.

sub interaction_error {
    my($msg) = @_;
    my($page);

    logError ("Difficulty interacting with browser: $msg\n");

    $page = readin("interact");
    if (defined $page) {
	$page =~ s#\[message\]#$msg#ig;
    response('html',interpolate_html($page));
    } else {
	logError("Missing special page: interact\n");
    response('plain',"$msg\n");
    }
}


## EXPECT FORM

# Check that a form is being submitted.

sub expect_form {
    if ($CGI::request_method ne 'POST') {
	interaction_error("Request method for form submission is not POST\n");
	return 0;
    }

    if ($CGI::content_type ne 'application/x-www-form-urlencoded') {
	interaction_error("Content type for form submission is not\n" .
			  "application/x-www-form-urlencoded\n");
	return 0;
    }

    return 1;
}

# Places the order report in the Tracking file
sub track_order {

	# We don't do anything unless tracking is enabled
	return undef unless $Config::Tracking;

	open_tracking();

	my $order_report = shift;
	my $i;
	my $order_no = $Vend::Tracking{'mv_next_order'};
	my (@backend) = split /\s*,\s*/, $Config::BackendOrder;
	

	# See if we have an order number already
	unless (defined $order_no) {
		$order_no = $Config::Tracking;
		$order_no =~ s/[^A-Za-z0-9]//g &&
			logError("Removed non-letter/non-digit chars from Order number");
	}

	# Put the text of the order in tracking
	$Vend::Tracking{$order_no} = $order_report;

	# Put in the backend order values if enabled
	if(@backend) {
		my(@ary);
		for(@backend) {
			push @ary, $Vend::Session->{'values'}->{$_};
		}
		my $order_info = join "\0", @ary;
		foreach $i (0 .. $#$Vend::Items) {
			$order_info .=  "\0" . $Vend::Items->[$i]->{'code'} .
							"\0" . $Vend::Items->[$i]->{'quantity'};
		}
		$Vend::Tracking{"Backend$order_no"} = $order_info;
		if($Config::CreditCards) {
			$Vend::Tracking{"Cc$order_no"} = 
				$Vend::Session->{'values'}->{'credit_card_no'};
			$Vend::Tracking{"Exp$order_no"} = 
				$Vend::Session->{'values'}->{'credit_card_exp'};
		}
	}

	my $this_order = $order_no;
	$order_no++;
	$Vend::Tracking{'mv_next_order'} = $order_no;
	close_tracking();
	$this_order;
}

# Logs page hits in tracking file
sub track_page {
    return unless $Config::Tracking;
	open_tracking();
	my $page = shift;
	$Vend::Tracking{$page} = $Vend::Tracking{$page} + 1;
	close_tracking();
}


## ACTIONS SPECIFIED BY THE INVOKING URL

## DO CATALOG

# Display the initial catalog page.

sub do_catalog {
    do_page('catalog');
}


## DO PAGE

sub display_special_page {
    my($name, $subject) = @_;
    my($page);

    $page = readin($name);
    die "Missing special page: $name\n" unless defined $page;
    $page =~ s#\[subject\]#$subject#ig;
    response('html',interpolate_html($page));
}

# Displays the catalog page NAME.  If the file is not found, displays
# the special page 'missing'. If it any of the special pages 'order',
# 'fr_order', or 'account', it will return the special page 'violation'
# instead

sub display_page {
    my($name) = @_;
    my($page);

	if($name =~ /^(order\b|fr_order\b|account\b)/
		and !$CGI::secure) {
		$name = 'violation';
	}
    $page = readin($name);
	# Try for on-the-fly if not there
	if(! defined $page) {
		$page = fly_page($name);
	}

    if (defined $page) {
    	response('html',interpolate_html($page));
		return 1;
    } else {
		$page = readin('missing');
		die "Special page not found: 'missing'\n" unless defined $page;
		$page =~ s#\[subject\]#$name#ig;
    	response('html',interpolate_html($page));
		return 0;
    }
}

# Display the catalog page NAME.

sub do_page {
    my($name) = @_;

	track_page($name);
    display_page($name) and $Vend::Session->{'page'} = $name;
    put_session();
}


## DO ORDER

# Order an item with product code CODE.

sub do_order
{
    my($code) = @_;
    my($i, $found);

    if (!product_code_exists($code)) {
		logError("Attempt to order missing product code: $code\n");
		display_special_page('noproduct', $code);
		return;
    }

    # Check that the item has not been already ordered.
    $found = -1;
    foreach $i (0 .. $#$Vend::Items) {
	if ($Vend::Items->[$i]->{'code'} eq $code) {
	    $found = $i;
	}
    }

    # An if not, start of with a single quantity.
    if ($found == -1) {
		push @$Vend::Items, {'code' => $code, 'quantity' => 1};
    }

    order_page();		# display the order page
    put_session();
}


sub untaint {
	my $tainted = $_[0];
	$tainted =~ /(.*)/;
	$tainted = $1;
}	

## DO SEARCH

# Search for an item with glimpse 

sub do_search {
	my($more_matches) = @_;
    my($matchlimit) = $CGI::values{'mv_matchlimit'} || 50;
    my($spelling_errors) = defined $CGI::values{'mv_spelling_errors'}
				?  $CGI::values{'mv_spelling_errors'} 
				: '0';
    my($orsearch) = is_yes($CGI::values{'mv_orsearch'});
    my($type) =  defined $CGI::values{'mv_searchtype'}
				?  $CGI::values{'mv_searchtype'} 
				: '';
    my($case) = is_yes($CGI::values{'mv_case'});
	my(@out);
	my $q;
	my $matches;

	unless (defined $Vend::Session->{'values'}->{'mv_search_over_msg'}) {
		$Vend::Session->{'values'}->{'mv_search_over_msg'} =
			$Config::SearchOverMsg;
	}

	if($Config::Glimpse) { $type = 'glimpse' unless $type }
	else 				 { $type = 'text' }


	my %options = (
			session_id => $Vend::SessionID,
			search_mod => ++$Vend::Session->{pageCount},
			match_limit => $matchlimit,
			);
	$options{'spelling_errors'} = $spelling_errors
			if $spelling_errors;
	
	if(defined %Vend::Cache) {
		$options{'save_hash'} = \%Vend::Cache;
	}
	else {
		$options{'save_dir'} = $Config::ScratchDir;
	}

	if ($type =~ /glimpse/)		{ $q = new Vend::Glimpse %options }
	else				 		{ $q = new Vend::TextSearch %options }

	unless($more_matches) {
		$q->rowpush(
			undef,
			$CGI::values{'mv_searchspec'},
			$case,
			$orsearch );
		@out = $q->search();
	}
	else {
		my ($next,$last,$mod) = split(/:/,$more_matches);
		@out = $q->more_matches($next,$last,$mod);
	}

	$matches = $q->global('matches');

	if ( $matches > 0 )
	{
	 $Vend::Session->{'values'}->{'mv_search_match_count'} = $matches;
	}
	elsif ($matches == 0) {
		display_special_page 'nomatch', $CGI::values{'mv_searchspec'};
		return;
	}
	else {
		# Got an error handled by search module
		return;
	}

	undef $Vend::Session->{'values'}->{'mv_search_over_msg'}
    			 unless $q->global('overflow');

	search_page($q,\@out);

}


sub is_yes {
	return( defined($_[$[]) && ($_[$[] =~ /^[yYtT1]/));
}

sub is_no {
	return( !defined($_[$[]) || ($_[$[] =~ /^[nNfF0]/));
}

# Returns undef if interaction error
sub update_quantity {
	my($i, $quantity);

	foreach $i (0 .. $#$Vend::Items) {
    	$quantity = $CGI::values{"quantity$i"};
    	if (defined($quantity) && $quantity =~ m/^\d+$/) {
        	$Vend::Items->[$i]->{'quantity'} = $quantity;
    	}
		elsif (defined $quantity) {
			my $item = $Vend::Items->[$i]->{'code'};
        	interaction_error("'$quantity' for item $item is not numeric\n");
        	return undef;
    	}
		else {
        	interaction_error("Variable '$quantity' not passed from form\n");
        	return undef;
    	}
    }
	# If the user has put in "0" for any quantity, delete that item
    # from the order list.
    DELETE: for (;;) {
        foreach $i (0 .. $#$Vend::Items) {
            if ($Vend::Items->[$i]->{'quantity'} == 0) {
                splice(@$Vend::Items, $i, 1);
                next DELETE;
            }
        }
        last DELETE;
    }

	1;

}

	
## DO FINISH

# Finish an incomplete order.

sub do_finish {
    order_page();
    put_session();
}

# Update the user-entered fields.
sub update_user {
	my($key,$value);
    # Update the user-entered fields.
    while (($key, $value) = each %CGI::values) {
        next if ($key =~ m/^quantity\d+/);
        next if ($key =~ /^mv_(todo|nextpage|doit)/);
        #next if ($key eq 'mv_nextpage');
        #next if ($key eq 'mv_doit');
        $Vend::Session->{'values'}->{$key} = $value;
		next unless $key =~ /credit_card/i;
		if(	defined $Config::Password &&
			$Config::CreditCards			)
		{
			$value = encrypt_cc($value);
			! defined $value &&
				logError("Encryption didn't work, session $Vend::SessionID");
        	$Vend::Session->{'values'}->{$key} = $value;
			undef $CGI::values{$key};
		}
		else {
			# No writing of real credit card numbers without 
			# encryption
        	$Vend::Session->{'values'}->{$key} = 'xxxxxxxxxxxxxxxxxxxxxx';
		}
			
    }
}

## DO PROCESS

# Process the completed order or search page.

sub do_process {
    my($i, $doit, $nextpage, $quantity, $todo, $page, $key, $value);

    expect_form() || return;

    $doit = $CGI::values{'mv_doit'};
    $todo = $CGI::values{'mv_todo'};
    $nextpage = $CGI::values{'mv_nextpage'} || $Vend::Session->{'page'};

	# Maybe we have an imagemap input, if not, use $doit
    if (!defined $todo) {
		if (defined $CGI::values{'mv_todo.x'}) {
				my $x = $CGI::values{'mv_todo.x'};
				my $y = $CGI::values{'mv_todo.y'};
				my $map = $CGI::values{'mv_todo.map'};
				$todo = action_map($x,$y,$map);
				# logError("map action: $todo  ($x,$y)");  #DEBUG
		}
		else {
			$todo = $doit if defined $doit;
		}
	}

	#Check again, see if we have a todo
    if (!defined $todo) {
			interaction_error("No action passed from form\n");
			return;
    }

	if ($doit =~ /\baccount\b/i) {
		if ($CGI::secure) {
			$Vend::Session->{'secure'} = 1;
			update_user();
			do_page($nextpage);
		}
		else {
			do_page('violation');
		}
    }
	elsif ($doit =~ /\bcontrol\b/i) {
		update_user();
		do_page($nextpage);
	}
	elsif ($todo =~ /submit/i) {
		update_user();
		update_quantity() || return; #Return on error
		my($ok);
		my($missing);
		my($values) = $Vend::Session->{'values'};
		($ok, $missing) = check_required($values);
		if (!$ok) {
			$missing =~ s/(\w+)/ucfirst($1)/ge;
	    	display_special_page("needfield", $missing);
    		put_session();
			return;
		}

		# This function (followed down) now does the backend ordering
		$ok = mail_order();

		# Remove the items
		@$Vend::Items = ();

		if ($ok) {
	    	display_special_page("confirmation");
		} else {
	    	display_special_page("failed");
		}
    }
	elsif ($todo =~ /return/i) {
		update_user();
		display_page($nextpage);
    }
	elsif ($todo =~ /finish|refresh|recalc/i) {
		update_user();
		update_quantity() || return; #Return on error
		order_page();
    }
	elsif ($todo =~ /search/i or $doit =~ /search/i) {
		update_user();
		do_search();
    } elsif ($todo =~ /cancel/i) {
		$Vend::Session->{'values'}->{'credit_card_no'} = 'xxxxxxxxxxxxxxxxxxxxxx';
		$Vend::Session->{'values'}->{'credit_card_exp'} = 'xxxxxxxx';
		my $frames = $Vend::Session->{'frames'};
		put_session();
		get_session();
		init_session();
		$Vend::Session->{'frames'} = $frames;
		display_page('canceled');
    }
	else {
		interaction_error(
          "Form variable 'mv_todo or mv_doit' value '$todo' not recognized\n");
		return;
    }
    put_session();
}


## SEND_MAIL

# Send a mail message to the email address TO, with subject SUBJECT, and
# message BODY.  Returns true on success.

sub send_mail {
    my($to, $subject, $body) = @_;
    my($ok);

    $ok = 0;
    SEND: {
		open(Vend::MAIL,"|$Config::SendMailProgram $to") or last SEND;
		print Vend::MAIL "To: $to\n", "Subject: $subject\n\n", $body
	    	or last SEND;
		close Vend::MAIL or last SEND;
		$ok = ($? == 0);
    }
    
    if (!$ok) {
		logError("Unable to send mail using $Config::SendMailProgram\n" .
		 	"To '$to'\n" .
		 	"With subject '$subject'\n" .
		 	"And body:\n$body");
    }

    $ok;
}
    
sub report_field {
    my($field_name, $seen) = @_;
    my($field_value, $r);

    $field_value = $Vend::Session->{'values'}->{$field_name};
    if (defined $field_value) {
		$$seen{$field_name} = 1;
		$r = $field_value;
    }
	else {
		$r = "<no input box>";
    }
    $r;
}

sub order_report {
    my($seen) = @_;
    my($fn, $report, $values, $date);
    $values = $Vend::Session->{'values'};

    $fn = $Config::OrderReport;
    if (!open(Vend::IN, $fn)) {
		logError("Could not open report file '$fn': $!\n");
		return undef;
    }

    {
		local($/);
		undef $/;
		$report = <Vend::IN>;
    }
    close(Vend::IN);

    $date = localtime();
    $report =~ s#\$date#$date#ige;

    $report =~ s#\$(\w+)#report_field($1, $seen)#ge;

    $report;
}

sub order_list {
    my($body, $i, $item, $code, $quantity, $desc, $price);

    $body = <<'END';
Qty     Item                 Description                     Price      Total
---  ------------  --------------------------------------  --------  ---------
END

    foreach $i (0 .. $#$Vend::Items) {
	$item = $Vend::Items->[$i];
	$code = $item->{'code'};
	$quantity = $item->{'quantity'};
	$price = product_price($code);
	$desc  = product_description($code);
	$desc =~ s/<.*?>/ /g;
	$body .= sprintf( "%3s  %-12s  %-38s  %8s  %9s\n",
			 $quantity,
			 $code,
			 substr($desc,0,38),
			 currency($price),
			 currency($quantity * $price) );
    }
	$body .= sprintf "%3s  %-12s  %-38s  %8s  %9s\n",
			'','','SUBTOTAL','', currency(subtotal());
	$body .= sprintf "%3s  %-12s  %-38s  %8s  %9s\n",
			'','','SALES TAX','', currency(salestax());
	$body .= sprintf "%3s  %-12s  %-38s  %8s  %9s\n",
			'','','SHIPPING',
			$Vend::Session->{'values'}->{'mv_shipmode'},
			currency(shipping());
	$body .= sprintf "%3s  %-12s  %-38s  %8s  %9s\n",
			'','','','TOTAL', tag_total_cost();
    $body;
}

sub check_required {
	my $val = shift;
	my $item;
	my @missing;
	my @req = split(/\s*,\s*/, $Config::RequiredFields);
	foreach $item (@req) {
	   push(@missing,$item)
	   		unless $val->{$item};
	}
	if(!@missing) {
		return(1);
	} else{
		return(0,join(' ', @missing));
	}
}

# Get fields to ignore for report, returns anon_hash ref
sub get_ignored {
	my @ignore;
	my $ignore = {};
	my $field;

	@ignore = split(/\s*,\s*/, $Config::ReportIgnore);
	foreach $field (@ignore) {
		$ignore->{$field} = 1;
	}
	$ignore;
}

# Email the processed order.

sub mail_order {
    my($body, $i, $code, $ok, $seen, $blankline);
    my($values, $key, $value, $order_no);

    $seen = get_ignored();
    $body = order_report($seen);
    return undef unless defined $body;

    $values = $Vend::Session->{'values'};

    $blankline = 0;
    while (($key, $value) = each %$values) {
	next if $key =~ /^mv_/i;
	if (!$$seen{$key}) {
	    if (!$blankline) {
		$body .= "\n";
		$blankline = 1;
	    }
	    $body .= "$key: $value\n";
	}
    }

    $body .= "\n" . order_list();
	$order_no = track_order($body);
	if(defined $order_no) {
    	$body .= "\n\nORDER NUMBER: $order_no\n";
	}
	else { $order_no = 'ORDER'; }
    $ok = send_mail($Config::MailOrderTo, $order_no, $body);
    $ok;
}


sub map_cgi {

    my($cgi, $major, $minor, $host, $user, $secure, $length);

    $CGI::request_method = ::http()->Method;
    die "REQUEST_METHOD is not defined" unless defined $CGI::request_method;

    $CGI::path_info = ::http()->Path_Info;

    $host = http()->Client_Hostname;
    $host = http()->Client_IP_Address
		unless (defined $host && $host ne '');
    $host = '' unless defined $host;
    $CGI::host = $host;

    $CGI::secure = 1
		if http()->Https_on;

    $user = http()->Authenticated_User;
    $user = http()->Client_Ident
		unless (defined $user && $user ne '');
    $user = '' unless defined $user;
    $CGI::user = $user;
    $CGI::useragent = http()->User_Agent;

    $CGI::content_length = http()->Content_Length;
    $CGI::content_type = http()->Content_Type;
    $CGI::query_string = http()->Query;

	$CGI::post_input = http()->read_entity_body(http());
	parse_post();
}

## DISPATCH

# Parse the invoking URL and dispatch to the handling subroutine.

sub dispatch {
	my($http, $debug) = @_;
	$H = $http;
	if( defined $Vend::ServerMode) {
		map_cgi($H);
	}
    my($query_string, $sessionid, $argument, $path, @path, $action);

    $query_string = $CGI::query_string;
    if (defined $query_string && $query_string ne '') {
	($sessionid, $argument) = split(/;/, $query_string);
    }

    if (defined $sessionid && $sessionid ne '') {
	$Vend::SessionID = $sessionid;
    $Vend::SessionName = session_name();
	get_session();
	if (time - $Vend::Session->{'time'} > $Config::SessionExpire) {
	    init_session();
	}
    } else {
	new_session();
    }

    $path = $CGI::path_info;

	# If this is left at 0, then we will try the on-the-fly page
	$Vend::RegularPage = 0;

    # If the cgi-bin program was invoked with no extra path info,
    # just display the catalog page.
    if (!defined $path || $path eq '' || $path eq '/') {
		do_catalog();
		unlock_session();
		return;
    }

    @path = split('/', $path);
    shift @path if $path[0] eq '';
    $action = shift @path;
    #print Vend::DEBUG "action is $action\n";
    if    ($action eq 'order')    { do_order($argument);  }
    elsif ($action eq 'finish')   { do_finish();          }
    elsif ($action eq 'search')   { do_search($argument); }
    elsif ($action eq 'process')  { do_process();         }
    else {
		# try the on-the-fly page if it fails
		$Vend::RegularPage = 1;
		do_page(join('/', $action, @path));
    }
	unlock_session();
	0;
}

## DEBUG

sub dontwarn {
    $Config::SearchFrame +
	$Config::VendURL +
	$Config::SecureURL +
	$Config::SecureOrderMsg +
    $Config::PageDir +
    $Config::MailOrderTo +
    $Config::FinishOrder +
    $Config::RequiredFields +
    $Config::ReportIgnore +
    $Config::OrderReport +
    $Config::UseCode +
    $Config::ScratchDir +
    $Config::CreditCards +
    $Config::DefaultShipping +
    $Config::PriceCommas +
    $Config::DebugMode +
    $Config::BackendOrder +
    $Config::ItemLinkDir +
    $Config::SearchOverMsg +
    $Config::Shipping +
    $Config::SalesTax +
    $Config::ReadPermission +
    $Config::ItemLinkValue +
	$Config::WritePermission +
	$Vend::Shipping_desc +
	$Vend::Shipping_criterion +
    $Config::ProductDir;
}


sub tainted {
    my($v) = @_;
    my($r);
    local($@);

    eval { open(Vend::FOO, ">" . "FOO" . substr($v,0,0)); };
    close Vend::FOO;
    ($@ ? 1 : 0);
}


sub dump_env {
    my($var, $value);

    open(Vend::E, ">$Config::VendRoot/env");
    while(($var, $value) = each %ENV) {
	print Vend::E "export $var='$value'\n";
    }
    close Vend::E;
}

## CGI-BIN INTERFACE PROCESSING

sub unhexify {
    my($s) = @_;

	# Following gets around Perl 5.001m bug
    #$s =~ s/%24/\$/ig;
    #$s =~ s/%5c/\\/ig;

    $s =~ s/%(..)/chr(hex($1))/ge;
    $s;
}

sub parse_post {
	my(@pairs, $pair, $key, $value);

	undef %CGI::values;
	@pairs = split(/&/, $CGI::post_input);
	foreach $pair (@pairs) {
		($key, $value) = ($pair =~ m/([^=]+)=(.*)/)
			or die "Syntax error in post input:\n$pair\n";
		$key = unhexify($key);
		$value =~ s/\+/ /g;
		$value = unhexify($value);
		# Handle multiple keys
		unless (defined $CGI::values{$key}) {
	 		$CGI::values{$key} = $value;
		}
		else {
			$CGI::values{$key} .= "\0" . $value;
		}
	 }
}


# Pull CGI variables from the environment.

sub cgi_environment {
	my($cgi, $major, $minor, $host, $user, $length);

	($cgi, $major, $minor) =
		($ENV{'GATEWAY_INTERFACE'} =~ m#^(\w+)/(\d+)\.(\d+)$#);
	if (!defined $cgi || $cgi ne 'CGI' ||
		!defined $major || $major < 1 ||
		!defined $minor || $minor < 0) {
		die "Need a cgi-bin interface version of at least 1.0\n";
	}

	$CGI::useragent = $ENV{'HTTP_USER_AGENT'};
	$CGI::request_method = $ENV{'REQUEST_METHOD'};
	die "REQUEST_METHOD is not defined" unless defined $CGI::request_method;

	$CGI::path_info = $ENV{'PATH_INFO'};
	# Commented out by Mike Heins, no need for this trap
	# die "PATH_INFO is not defined" unless defined $CGI::path_info;

	$host = $ENV{'REMOTE_HOST'};
	$host = $ENV{'REMOTE_ADDR'} unless (defined $host && $host ne '');
	$host = '' unless defined $host;
	$CGI::host = $host;

	$user = $ENV{'REMOTE_USER'};
	$user = $ENV{'REMOTE_IDENT'} unless (defined $user && $user ne '');
	$user = '' unless defined $user;
	$CGI::user = $user;

	$CGI::content_length = $ENV{'CONTENT_LENGTH'};
	$CGI::content_type = $ENV{'CONTENT_TYPE'};
	$CGI::query_string = $ENV{'QUERY_STRING'};

	if ($CGI::request_method eq 'POST') {
		die "CONTENT_LENGTH is not specified with POST method"
			unless defined $CGI::content_length;
		$length = read(STDIN, $CGI::post_input, $CGI::content_length);
		die "Could not read " . $CGI::content_length .
			" bytes from cgi-bin server: $!\n" 
				unless $length == $CGI::content_length;
	#&dump_post();
		parse_post();
	}
}
									

sub dump_post {
	open(Vend::P, ">$Config::VendRoot/post") || die;
	print Vend::P $CGI::post_input;
	close Vend::P;
}


## COMMAND LINE OPTIONS

sub parse_options {
	while ($_ = shift @ARGV) {
		if (m/^-c(onfig)?$/i) {
			$Config::ConfigFile = shift @ARGV;
			die "Missing file argument for -config option\n"
				if blank($Config::ConfigFile);
		} elsif (m/^-v(ersion)?$/i) {
			version();
			exit 0;
		} elsif (m/^-h(elp)?$/i) {
			usage();
			exit 0;
		} elsif (m/^-i(nit)?$/i) {
			$Vend::mode = 'init';
		} elsif (m/^-t(est)?$/i) {
			$Vend::mode = 'test';
		} elsif (m/^-e(xpire)?$/i) {
			$Vend::mode = 'expire';
		} elsif (m/^-n(etstart)?$/i) {
			$Vend::mode = 'netstart';
		} elsif (m/^-n(otify)?$/i) {
			$Vend::mode = 'notify';
		} elsif (m/^-s(erve)?$/i) {
			$Vend::mode = 'serve';
		} elsif (m/^-r(estart)?$/i) {
			$Vend::mode = 'restart';
		} elsif (m/^-dump-sessions$/i) {
			$Vend::mode = 'dump-sessions';
		} else {
			die "Unknown command line option: $_\n" .
				"(Use -help for a list).\n";
		}
	}
}

sub version {
	print "MiniVend version 1.02 Copyright 1995 Andrew M. Wilcox\n";
	print "                      Copyright 1996 Michael J. Heins\n";
}

sub usage {
	version();
	print <<'END';

MiniVend comes with ABSOLUTELY NO WARRANTY.  This is free software, and
you are welcome to redistribute and modify it under the terms of the
GNU General Public License.

Command line options:

	 -config <file>   specify configuration file
	 -test            report problems with config file
	 -version         display program version
	 -expire          expire old sessions
	 -serve           start server
	 -netstart        start server from the net
	 -restart         restart server (re-read config file)
END
}

sub scrub_sockets {

	my (@sockets);
	my $dir = $Config::ConfDir;

	opendir(Vend::SCRUBSOCK,$dir) ||
		die "Couldn't read $dir: $!\n";
	@sockets =  grep -S "$dir/$_", readdir(Vend::SCRUBSOCK);
	closedir(Vend::SCRUBSOCK);

	for(@sockets) {
		unlink "$dir/$_";
	}

}

## FILE PERMISSIONS

sub set_file_permissions {
	my($r, $w, $p, $u);

	$r = $Config::ReadPermission;
	if    ($r eq 'user')  { $p = 0400;   $u = 0277; }
	elsif ($r eq 'group') { $p = 0440;   $u = 0227; }
	elsif ($r eq 'world') { $p = 0444;   $u = 0222; }
	else                  { die "Invalid value for ReadPermission\n"; }

	$w = $Config::WritePermission;
	if    ($w eq 'user')  { $p += 0200;  $u &= 0577; }
	elsif ($w eq 'group') { $p += 0220;  $u &= 0557; }
	elsif ($w eq 'world') { $p += 0222;  $u &= 0555; }
	else                  { die "Invalid value for WritePermission\n"; }

	$Config::FileCreationMask = $p;
	$Config::Umask = $u;
}

sub read_socket {
}

## MAIN

sub main {
	# Setup
	$ENV{'PATH'} = '/bin:/usr/bin';
	$ENV{'SHELL'} = '/bin/sh';
	$ENV{'IFS'} = '';
	srand;
	setup_escape_chars();

	#dump_env();

	# Were we called from an HTTPD server as a cgi-bin program?
	if (defined $ENV{'GATEWAY_INTERFACE'} && $ENV{'GATEWAY_INTERFACE'}) {
		$Vend::mode = 'cgi';
		eval { cgi_environment() };
		if ($@) {
			plain_header();
			print "$@\n";
			print "while being executed as a cgi-bin program by ";
			print $ENV{'SERVER_SOFTWARE'}, "\n";
			exit 1;
		}
	} else {
		# Only parse command line arguments if not being run as a cgi-bin
		# program.
		undef $Vend::mode;      # mode will be set by options
		parse_options();
		if (!defined $Vend::mode) {
			print
"Hmm, since I don't seem to have been invoked as a cgi-bin program,\n",
"I'll assume I'm being run from the shell command line.\n\n";
			usage();
			exit 0;
		}
	}

	umask 077;
	config();
	set_file_permissions();
	chdir $Config::VendRoot;
	umask $Config::Umask;

	if ($Vend::mode eq 'cgi') {
		import_products();
		undef $Vend::ServerMode;
		dispatch();
		close_products();
	} elsif ($Vend::mode eq 'serve' or $Vend::mode eq 'netstart') {
		# This should never return unless killed or an error
		# We set debug mode to -1 to communicate with the server
		# that no output is desired
		scrub_sockets();
		import_products();
		if($Vend::mode eq 'netstart') {
			$Config::DebugMode = -1;
		}
		else {
			read_password();
		}
		$Vend::ServerMode = 1;
		Vend::Server::run_server($Config::DebugMode);
		undef $Vend::ServerMode;
		close_products();
	} elsif ($Vend::mode eq 'init') {
		import_products();
		close_products();
	} elsif ($Vend::mode eq 'restart') {
		# This should never return unless killed or an error
		undef $Vend::ServerMode;
		import_products();
		read_password();
		$Vend::ServerMode = 1;
		Vend::Server::restart_server();
		undef $Vend::ServerMode;
		close_products();
	} elsif ($Vend::mode eq 'expire') {
		expire_sessions();
	} elsif ($Vend::mode eq 'dump-sessions') {
		dump_sessions();
	} elsif ($Vend::mode eq 'notify') {
	    my $to = $Config::MailOrderTo;
	    my $subject = "MiniVend not running";
		my $msg = <<EOM;
A user tried to access MiniVend with the URL
"$Config::VendURL" and the server
was not running.
EOM
		send_mail($to, $subject, $msg) or die "Couldn't send mail: $!\n";
	} elsif ($Vend::mode eq 'test') {
		;
	} else {
		die "Unknown mode: $Vend::mode\n";
	}
}

#open(Vend::DEBUG,">>$Config::VendRoot/debug");
eval { main(); };
if ($@) {
	my($msg) = ($@);
	logError( $msg );
	if (!defined $Config::DisplayError || $Config::DisplayError) {
		if ($Vend::mode eq 'cgi') {
			if ($Vend::content_type eq 'plain') {
				print "\n";
			} elsif ($Vend::content_type eq 'html') {
				print "\n<p><pre>\n";
			} else {
				print "Content-type: text/plain\n\n";
			}
		}
		print "$msg\n";
	}
}

