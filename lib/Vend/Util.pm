# Util.pm - Minivend utility functions
#
# $Id: Util.pm,v 1.52 1999/08/05 03:51:52 mike Exp $
# 
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
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

package Vend::Util;
require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(

copyref
currency
check_security
dump_structure
errmsg
evalr
find_special_page
file_modification_time
format_log_msg
is_no
is_yes
find_close_square
generate_key
international_number
logtime
logData
logDebug
logError
logGlobal
lockfile
unlockfile
readfile
readin
random_string
quoted_comma_string
setup_escape_chars
strftime
escape_chars
send_mail
secure_vendUrl
tag_nitems
uneval
uneval_fast
vendUrl

);
@EXPORT_OK = qw(append_field_data append_to_file csv field_line);

use strict;
use Config;
use Fcntl;
use subs qw(logError logGlobal);
use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.52 $, 10);

BEGIN {
	eval {
		require 5.004;
	};
	if($@) {
		if($Config{osname} =~ /solaris/) {
			require File::Lock;
			import File::Lock;
		}
	}
}

my $Eval_routine;
my $Pretty_uneval;
my $Fast_uneval;

### END CONFIGURABLE MODULES

my @wday = ( qw! Sun Mon Tue Wed Thu Fri Sat Sun !);
my @weekday = ( qw! Sunday Monday Tuesday Wednesday
					Thursday Friday Saturday Sunday !);
my @mon = ( qw! Jan Feb Mar Apr May Jun
				Jul Aug Sep Oct Nov Dec !);
my @month = ( qw! January February March April May June
				July August September October November December !);

my $Use_posix_strftime;

CHECKSTRF: {
	print "Checking strftime.\n" if $ENV{MINIVEND_DEBUG};
	eval {
		die if $ENV{MINIVEND_BADPOSIX};
		require POSIX;
		local $ = 0;
		my $test = POSIX::strftime("%Y", localtime(1));
		$test = POSIX::strftime("%Y", localtime(1));
		if (length($test) == 4) {
			$Use_posix_strftime = 1;
		}
		print "use strftime test=$test " if $ENV{MINIVEND_DEBUG};
		print $Use_posix_strftime ? 'yes' : 'no' if $ENV{MINIVEND_DEBUG};
		print ".\n" if $ENV{MINIVEND_DEBUG};
	};
	if ($@) {
		undef $Use_posix_strftime;
	}
}

sub strftime {
	return POSIX::strftime(@_) if $Use_posix_strftime;
	my ($fmt,$sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= @_;
	my %strf = (
			'%'	=> sub { "%" },
			'a'	=> sub { $wday[$wday] },
			'A'	=> sub { $weekday[$wday] },
			'b'	=> sub { $mon[$mon] },
			'B'	=> sub { $month[$mon] },
			'c'	=> sub { printf "%s %s %2s %02d:%02d:%02d %04d",
			       		 $wday[$wday], $mon[$mon], $mday,
			       		 $hour, $min, $sec, $year+1900 },
			'd'	=> sub { sprintf "%02d", $mday },
			'H'	=> sub { sprintf "%02d", $hour},
			'I'	=> sub { my $h;
			       		if ($hour == 0) {
			       			$h = 12;
			       		} elsif ( $hour > 12 ) {
			       			$h = $hour - 12;
			       		} else {
			       			$h = $hour;
			       		}
			       		sprintf "%02d", $h; },
			'j'	=> sub { sprintf "%03d", $yday + 1 },
			'm'	=> sub { sprintf "%02d", $mday },
			'M'	=> sub { sprintf "%02d", $min },
			'p'	=> sub { $hour > 11 ? "pm" : "am" },
			'S'	=> sub { sprintf "%02d", $sec },
			'w'	=> sub { $wday },
			'x'	=> sub { sprintf "%02d %s %04d",
			       			$mday, $mon[$mon], $year + 1900 },
			'X'	=> sub { sprintf "%02d:%02d:%02d", $hour, $min, $sec },
			'y'	=> sub { substr($year,-2) },
			'Y'	=> sub { sprintf "%04d", $year + 1900 },
	);
	$fmt =~ s/%(.)/&{$strf{$1}}() || "%$1"/eg;
	return $fmt;
}

sub find_close_square {
    my $chunk = shift;
    my $first = index($chunk, ']');
    return undef if $first < 0;
    my $int = index($chunk, '[');
    my $pos = 0;
    while( $int > -1 and $int < $first) {
        $pos   = $int + 1;
        $first = index($chunk, ']', $first + 1);
        $int   = index($chunk, '[', $pos);
    }
    return substr($chunk, 0, $first);
}

## ESCAPE_CHARS

$ESCAPE_CHARS::ok_in_filename = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' .
    'abcdefghijklmnopqrstuvwxyz' .
    '0123456789' .
    '-:_.$/';

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
    $r;
}

# Returns its arguments as a string of tab-separated fields.  Tabs in the
# argument values are converted to spaces.

sub tabbed {        
    return join("\t", map { $_ = '' unless defined $_;
                            s/\t/ /g;
                            $_;
                          } @_);
}

# Finds common-log-style offset
# Unproven, authoratative code welcome
my $Offset;
FINDOFFSET: {
    my $now = time;
    my ($gm,$gh,$gd,$gy) = (gmtime($now))[1,2,5,7];
    my ($lm,$lh,$ld,$ly) = (localtime($now))[1,2,5,7];
    if($gy != $ly) {
        $gy < $ly ? $lh += 24 : $gh += 24;
    }
    elsif($gd != $ld) {
        $gd < $ld ? $lh += 24 : $gh += 24;
    }
    $gh *= 100;
    $lh *= 100;
    $gh += $gm;
    $lh += $lm;
    $Offset = sprintf("%05d", $lh - $gh);
    $Offset =~ s/0(\d\d\d\d)/+$1/;
}

# Returns time in HTTP common log format
sub logtime {
    return strftime("[%d/%B/%Y:%H:%M:%S $Offset]", localtime());
}

sub format_log_msg {
	my($msg) = @_;
	my(@params);

	# IP, Session, REMOTE_USER (if any) and time
    push @params, ($CGI::remote_host || $CGI::remote_addr || '-');
	push @params, ($Vend::SessionName || '-');
	push @params, ($CGI::user || '-');
	push @params, logtime();

	# Catalog name
	my $string = ! defined $Vend::Cfg ? '-' : ($Vend::Cfg->{CatalogName} || '-');
	push @params, $string;

	# Path info and script
	$string = $CGI::script_name || '-';
	$string .= $CGI::path_info || '';
	push @params, $string;

	# Message, quote newlined area
	$msg =~ s/\n/\n> /g;
	push @params, $msg;
	return join " ", @params;
}

# Return AMOUNT formatted as currency.

sub commify {
    local($_) = shift;
	my $sep = shift || ',';
    1 while s/^(-?\d+)(\d{3})/$1$sep$2/;
    return $_;
}

sub picture_format {
	my($amount, $pic, $sep, $point) = @_;
    $pic	= reverse $pic;
	$point	= '.' unless defined $point;
	$sep	= ',' unless defined $sep;
	$pic =~ /(#+)\Q$point/;
	my $len = length($1);
	$amount = sprintf('%.' . $len . 'f', $amount);
	$amount =~ tr/0-9//cd;
	my (@dig) = split //, $amount;
	$pic =~ s/#/pop(@dig)/eg;
	$pic =~ s/\Q$sep\E+(?!\d)//;
	$pic =~ s/\d/*/g if @dig;
	$amount = reverse $pic;
	return $amount;
}

sub setlocale {
    my ($locale, $currency, $persist) = @_;
    $locale = $::Scratch->{mv_locale} unless defined $locale;

    if ( $locale and not defined $Vend::Cfg->{Locale_repository}{$locale}) {
        Vend::Util::logError( errmsg('Util.pm:1', "attempt to set non-existant locale '%s'" , $locale) );
        return '';
    }

    if ( $currency and not defined $Vend::Cfg->{Locale_repository}{$currency}) {
        Vend::Util::logError( errmsg('Util.pm:2', "attempt to set non-existant currency '%s'" , $currency) );
        return '';
    }

    if($locale) {
        my $loc = $Vend::Cfg->{Locale} = $Vend::Cfg->{Locale_repository}{$locale};

        for(@Vend::Config::Locale_directives_scalar) {
            $Vend::Cfg->{$_} = $loc->{$_}
                if defined $loc->{$_};
        }

        for(@Vend::Config::Locale_directives_ary) {
            @{$Vend::Cfg->{$_}} = split (/\s+/, $loc->{$_})
                if $loc->{$_};
        }
    }

    if ($currency) {
        my $curr = $Vend::Cfg->{Locale_repository}{$currency};

        for(@Vend::Config::Locale_directives_currency) {
            $Vend::Cfg->{$_} = $curr->{$_}
                if defined $curr->{$_};
        }
        @{$Vend::Cfg->{Locale}}{@Vend::Config::Locale_keys_currency} =
                @{$curr}{@Vend::Config::Locale_keys_currency};
    }

    $::Scratch->{mv_locale}   = $locale    if $persist and $locale;
    $::Scratch->{mv_currency} = $currency  if $persist and $currency;
    return '';
}


sub currency {
	my($amount, $noformat, $convert) = @_;
	$amount = $amount / $Vend::Cfg->{PriceDivide} if $convert;
	return $amount if $noformat;
	my $loc;
	my $sep;
	my $dec;
	my $fmt;
	my $precede = '';
	my $succede = '';
	if ($loc = $Vend::Cfg->{Locale}) {
		$sep = $loc->{mon_thousands_sep} || $loc->{thousands_sep} || ',';
		$dec = $loc->{mon_decimal_point} || $loc->{decimal_point} || '.';
		return picture_format($amount, $loc->{price_picture}, $sep, $dec)
			if defined $loc->{price_picture};
		$fmt = "%." . $loc->{frac_digits} .  "f";
		my $cs;
		if($cs = ($loc->{currency_symbol} ||$loc->{currency_symbol} || '') ) {
			if($loc->{p_cs_precedes}) {
				$precede = $cs;
				$precede = "$precede " if $loc->{p_sep_by_space};
			}
			else {
				$succede = $cs;
				$succede = " $succede" if $loc->{p_sep_by_space};
			}
		}
	}
	else {
		$fmt = "%.2f";
	}

	$amount = sprintf $fmt, $amount;
	$amount =~ s/\./$dec/ if defined $dec;
	$amount = commify($amount, $sep || undef)
		if $Vend::Cfg->{PriceCommas};
	return "$precede$amount$succede";
}

sub international_number {
	return (@_) unless $Vend::Cfg->{Locale};
	local($_) = shift;
	my $loc = $Vend::Cfg->{Locale};
	if ($loc->{picture}) {
        my ($sep, $dec);
        $sep = $loc->{thousands_sep} || $loc->{mon_thousands_sep} || ',';
        $dec = $loc->{decimal_point} || $loc->{mon_decimal_point} || '.';
        return picture_format($_, $loc->{picture}, $sep, $dec);
    }

	s/\.(\d*)$/ ($loc->{decimal_point} || $loc->{mon_decimal_point}) . $1/e;
	return $_;
}

## random_string

# leaving out 0, O and 1, l
my $random_chars = "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

# Return a string of random characters.

sub random_string {
    my ($len) = @_;
    $len = 8 unless $len;
    my ($r, $i);

    $r = '';
    for ($i = 0;  $i < $len;  ++$i) {
	$r .= substr($random_chars, int(rand(length($random_chars))), 1);
    }
    $r;
}

# To generate a unique key for caching
# Not very good without MD5
#
my $Md;
my $Keysub;

eval {require MD5 };

if(! $@) {
	$Md = new MD5;
	$Keysub = sub {
					return '' unless @_;
					$Md->reset();
					$Md->add(@_);
					$Md->hexdigest();
				};
}
else {
	$Keysub = sub {
		my $out = '';
		for(@_) {
			$out .= unpack "%32c*", $_;
			$out .= unpack "%32c*", substr($_,5);
			$out .= unpack "%32c*", substr($_,-1,5);
		}
		$out;
	};
}

sub generate_key { &$Keysub(@_) }

## UNEVAL

# Returns a string representation of an anonymous array, hash, or scaler
# that can be eval'ed to produce the same value.
# uneval([1, 2, 3, [4, 5]]) -> '[1,2,3,[4,5,],]'
# Uses either Storable::freeze or Data::Dumper::DumperX or uneval 
# in 

sub uneval {
	&{$Pretty_uneval}(@_);
}

sub uneval_fast {
	&{$Fast_uneval}(@_);
}

sub uneval_it {
    my($o) = @_;		# recursive
    my($r, $s, $i, $key, $value);

	local($) = 0;
    $r = ref $o;
    if (!$r) {
	$o =~ s/([\\"\$@])/\\$1/g;
	$s = '"' . $o . '"';
    } elsif ($r eq 'ARRAY') {
	$s = "[";
	foreach $i (0 .. $#$o) {
	    $s .= uneval_it($o->[$i]) . ",";
	}
	$s .= "]";
    } elsif ($r eq 'HASH') {
	$s = "{";
	while (($key, $value) = each %$o) {
	    $s .= "'$key' => " . uneval_it($value) . ",";
	}
	$s .= "}";
    } else {
	$s = "'something else'";
    }

    $s;
}


# See if we have Storable and the user has OKed its use
# If so, session storage/write will be about 5x faster
eval {
	die unless $ENV{MINIVEND_STORABLE};
	require Storable;
	import Storable 'freeze';
	$Fast_uneval = \&Storable::freeze;
	$Eval_routine = \&Storable::thaw;
};

# See if Data::Dumper is installed with XSUB
# If it is, session writes will be about 25-30% faster
eval {
		require Data::Dumper;
		import Data::Dumper 'DumperX';
		$Data::Dumper::Indent = 0;
		$Data::Dumper::Terse = 1;
		$Pretty_uneval = \&Data::Dumper::DumperX;
		$Fast_uneval = \&Data::Dumper::DumperX
			unless defined $Fast_uneval;
};


$Fast_uneval = \&uneval_it
		unless defined $Fast_uneval;
$Pretty_uneval  = \&uneval_it
		unless defined $Pretty_uneval;

sub evalr {
	return undef unless $_[0];
	return &{$Eval_routine}(@_) if defined $Eval_routine;
	return eval $_[0];
}

sub writefile {
    my($file, $data) = @_;

	$file = ">>$file" unless $file =~ /^[|>]/;

    eval {
		unless($file =~ s/^[|]\s*//) {
			open(Vend::LOGDATA, "$file") or die "open\n";
			lockfile(\*Vend::LOGDATA, 1, 1) or die "lock\n";
			seek(Vend::LOGDATA, 0, 2) or die "seek\n";
			if(ref $data) {
				print(Vend::LOGDATA $$data) or die "write to\n";
			}
			else {
				print(Vend::LOGDATA "$data\n") or die "write to\n";
			}
			unlockfile(\*Vend::LOGDATA) or die "unlock\n";
		}
		else {
            my (@args) = grep /\S/, Text::ParseWords::shellwords($file);
			open(Vend::LOGDATA, "|-") || exec @args;
			if(ref $data) {
				print(Vend::LOGDATA $$data) or die "pipe to\n";
			}
			else {
				print(Vend::LOGDATA "$data\n") or die "pipe to\n";
			}
		}
		close(Vend::LOGDATA) or die "close\n";
    };
    if ($@) {
		logError "Could not $@ log file '" . $file . "': $!\n" .
    		"to log this data:\n" .  $data ;
		return 0;
    }
	1;
}


# Log data fields to a data file.

sub logData {
    my($file,@msg) = @_;
    my $prefix = '';

	$file = ">>$file" unless $file =~ /^[|>]/;

	my $msg = tabbed @msg;

    eval {
		unless($file =~ s/^[|]\s*//) {
			open(Vend::LOGDATA, "$file")	or die "open\n";
			lockfile(\*Vend::LOGDATA, 1, 1)	or die "lock\n";
			seek(Vend::LOGDATA, 0, 2)		or die "seek\n";
			print(Vend::LOGDATA "$msg\n")	or die "write to\n";
			unlockfile(\*Vend::LOGDATA)		or die "unlock\n";
		}
		else {
            my (@args) = grep /\S/, Text::ParseWords::shellwords($file);
			open(Vend::LOGDATA, "|-") || exec @args;
			print(Vend::LOGDATA "$msg\n") or die "pipe to\n";
		}
		close(Vend::LOGDATA) or die "close\n";
    };
    if ($@) {
		logError "Could not $@ log file '" . $file . "': $!\n" .
    		"to log this data:\n" .  $msg ;
		return 0;
    }
	1;
}


sub file_modification_time {
    my ($fn) = @_;
    my @s = stat($fn) or die "Can't stat '$fn': $!\n";
    return $s[9];
}

sub quoted_comma_string {

my ($text) = @_;
my (@fields);
push(@fields, $+) while $text =~ m{
   "([^\"\\]*(?:\\.[^\"\\]*)*)"[\s,]?  ## std quoted string, w/possible space-comma
   | ([^\s,]+)[\s,]?                   ## anything else, w/possible space-comma
   | [,\s]+                            ## any comma or whitespace
        }gx;
    @fields;
}


# Modified from old, old module called Ref.pm
sub copyref {
    my($x,$r) = @_; 

    my($z, $y);

    my $rt = ref $x;

    if ($rt =~ /SCALAR/) {
        # Would \$$x work?
        $z = $$x;
        return \$z;
    } elsif ($rt =~ /HASH/) {
        $r = {} unless defined $r;
        for $y (sort keys %$x) {
            $r->{$y} = &copyref($x->{$y}, $r->{$y});
        }
        return $r;
    } elsif ($rt =~ /ARRAY/) {
        $r = [] unless defined $r;
        for ($y = 0; $y <= $#{$x}; $y++) {
            $r->[$y] = &copyref($x->[$y]);
        }
        return $r;
    } elsif ($rt =~ /REF/) {
        $z = &copyref($x);
        return \$z;
    } elsif (! $rt) {
        return $x;
    } else {
        die "do not know how to copy $x";
    }
}

sub check_gate {
	my($f, $gatedir) = @_;

	my $gate;
	if ($gate = readfile("$gatedir/.access_gate") ) {
#::logGlobal("found access_gate");
		$f =~ s:.*/::;
		$gate = Vend::Interpolate::interpolate_html($gate);
#::logGlobal("f=$f gate=$gate");
		if($gate =~ m!^$f(?:\.html?)?[ \t]*:!m ) {
			$gate =~ s!.*(\n|^)$f(?:\.html?)?[ \t]*:!!s;
#::logGlobal("gate=$gate");
			$gate =~ s/\n[\S].*//s;
			$gate =~ s/^\s+//;
		}
		elsif($gate =~ m{^\*(?:\.html?)?[: \t]+(.*)}m) {
			$gate = $1;
		}
		else {
			undef $gate;
		}
	}
	return $gate;
}

## READIN

my $Lang;

sub find_locale_bit {
	my $text = shift;
	$Lang = $::Scratch->{mv_locale} unless defined $Lang;
#::logGlobal("find_locale: $Lang");
	$text =~ m{\[$Lang\](.*)\[/$Lang\]}s
		and return $1;
	$text =~ s{\[(\w+)\].*\[/\1\].*}{}s;
	return $text;
}

# Reads in a page from the page directory with the name FILE and ".html"
# appended.  Returns the entire contents of the page, or undef if the
# file could not be read. Substitutes Locale bits as necessary.

sub readin {
    my($file, $only) = @_;
    my($fn, $contents, $gate, $pathdir, $dir, $level);
    local($/);

	$Global::Variable->{MV_PREV_PAGE} = $Global::Variable->{MV_PAGE}
		if defined $Global::Variable->{MV_PAGE};
	$Global::Variable->{MV_PAGE} = $file;

	$file =~ s#\.html?$##;
	($pathdir = $file) =~ s#/[^/]*$##;
	$pathdir =~ s:^/+::;
	my $try;
	foreach $try (
					$Vend::Cfg->{PageDir},
					@{$Vend::Cfg->{TemplateDir}},
					@{$Global::TemplateDir}          )
	{
		$dir = $try . "/" . $pathdir;
		my $suffix = $Vend::Cfg->{HTMLsuffix};
# DEBUG
#logDebug("dirname for readin: $dir")
#	if ::debug(0x2);
# END DEBUG
		if (-f "$dir/.access") {
			if (-s _) {
				$level = 3;
			}
			else {
				$level = '';
			}
			$gate = check_gate($file,$dir);
		}

		if( defined $level and ! check_security($file, $level, $gate) ){
			my $realm = $Vend::Cfg->{Variable}{COMPANY} || $Vend::Cfg->{CatalogName};
			$Vend::StatusLine = <<EOF if $Vend::InternalHTTP;
HTTP/1.0 401 Unauthorized
WWW-Authenticate: Basic realm="$realm"
EOF
			$file = find_special_page('violation');
			$fn = $try . "/" . escape_chars($file) . $suffix;
		}
		else {
			$fn = $try . "/" . escape_chars($file) . $suffix;
		}

		if (open(Vend::IN, $fn)) {
			binmode(Vend::IN) if $Global::Windows;
			undef $/;
			$contents = <Vend::IN>;
			close(Vend::IN);
			last;
		}
		last if defined $only;
	}
	if(defined $contents and $Vend::Cfg->{Locale}) {
		my $key;
		$contents =~ s~\[L(\s+([^\]]+))?\]([\000-\377]*?)\[/L\]~
						$key = $2 || $3;		
						defined $Vend::Cfg->{Locale}{$key}
						?  ($Vend::Cfg->{Locale}{$key})	: $3 ~eg;
		$contents =~ s~\[LC\]([\000-\377]*?)\[/LC\]~
						find_locale_bit($1) ~eg
				and undef $Lang;
	}
    $contents;
}

# Reads in an arbitrary file.  Returns the entire contents,
# or undef if the file could not be read.
# Careful, needs the full path, or will be read relative to
# VendRoot..and will return binary. Should be tested by
# the user.
#
# To ensure security in multiple catalog setups, leading
# / is not allowed unless $Global::NoAbsolute is set.
#
sub readfile {
    my($file, $no) = @_;
    my($contents);
    local($/);

	$Global::Variable->{MV_FILE} = $file;

# DEBUG
#Vend::Util::logDebug
#("readfile '$file'\n")
#	if ::debug(0x8);
# END DEBUG

	if($no and ($file =~ m:^\s*/: or $file =~ m#\.\./.*\.\.#)) {
#		logError("Can't read file '$file' with NoAbsolute set");
		logError( errmsg('Util.pm:3', "Can't read file '%s' with NoAbsolute set" , $file) );
#		logGlobal("Can't read file '$file' with NoAbsolute set");
		logGlobal( errmsg('Util.pm:4', "Can't read file '%s' with NoAbsolute set" , $file) );
		return undef;
	}

    if (open(Vend::IN, $file)) {
		binmode(Vend::IN) if $Global::Windows;
		undef $/;
		$contents = <Vend::IN>;
		close(Vend::IN);
    } else {
		$contents = undef;
    }

	if($Vend::Cfg->{Locale} and $Vend::Cfg->{Locale}->{ReadFile}) {
		my $key;
		$contents =~ s~\[L(\s+([^\]]+))?\]([\000-\377]*?)\[/L\]~
						$key = $2 || $3;		
						defined $Vend::Cfg->{Locale}->{$key}
						?  ($Vend::Cfg->{Locale}->{$key})	: $3 ~eg;
	}
    $contents;
}

sub is_yes {
    return( defined($_[$[]) && ($_[$[] =~ /^[yYtT1]/));
}

sub is_no {
	return( !defined($_[$[]) || ($_[$[] =~ /^[nNfF0]/));
}

# Returns a URL which will run the ordering system again.  Each URL
# contains the session ID as well as a unique integer to avoid caching
# of pages by the browser.

sub vendUrl
{
    my($path, $arguments, $r) = @_;
    $r = $Vend::Cfg->{VendURL}
		unless defined $r;

	$arguments =~ s!([^\w-_:#=/.%])! '%' . sprintf("%02x", ord($1))!eg
		if defined $arguments && $Vend::Cfg->{NewEscape};

	if(defined $Vend::Cfg->{AlwaysSecure}->{$path}) {
		$r = $Vend::Cfg->{SecureURL};
	}

	my $id = $CGI::cookie && $::Scratch->{mv_no_session_id}
			 ? '' : $Vend::SessionID;
	my $ct = $::Scratch->{mv_no_count}	
			 ? '' : ++$Vend::Session->{pageCount};
    $r .= '/' . $path;
	return $r unless ($id || $arguments || $ct);
	$r .= '?' . $id .  ';' . ($arguments || '');
	$r .= ";$ct" if $ct;
    return $r;
}    

sub secure_vendUrl
{
    my($path, $arguments) = @_;
    my($r);
	return undef unless $Vend::Cfg->{SecureURL};

	$arguments =~ s!([^\w-_:#=/.%])! '%' . sprintf("%02x", $1)!eg
		if defined $arguments && $Vend::Cfg->{NewEscape};

    $r = $Vend::Cfg->{SecureURL};

	my $id = $::Scratch->{mv_no_session_id}	? '' : $Vend::SessionID;
	my $ct = $::Scratch->{mv_no_count}		? '' : ++$Vend::Session->{pageCount};
    $r .= '/' . $path;
	return $r unless ($id || $arguments || $ct);
	$r .= '?' . $id .  ';' . ($arguments || '');
	$r .= ";$ct" if $ct;
    return $r;
}

my $debug = 0;
my $use = undef;

### flock locking

# sys/file.h:
my $flock_LOCK_SH = 1;          # Shared lock
my $flock_LOCK_EX = 2;          # Exclusive lock
my $flock_LOCK_NB = 4;          # Don't block when locking
my $flock_LOCK_UN = 8;          # Unlock

sub flock_lock {
    my ($fh, $excl, $wait) = @_;
    my $flag = $excl ? $flock_LOCK_EX : $flock_LOCK_SH;

    if ($wait) {
        flock($fh, $flag) or die "Could not lock file: $!\n";
        return 1;
    }
    else {
        if (! flock($fh, $flag | $flock_LOCK_NB)) {
            if ($! =~ m/^Try again/
                or $! =~ m/^Resource temporarily unavailable/
                or $! =~ m/^Operation would block/) {
                return 0;
            }
            else {
                die "Could not lock file: $!\n";
            }
        }
        return 1;
    }
}

sub flock_unlock {
    my ($fh) = @_;
    flock($fh, $flock_LOCK_UN) or die "Could not unlock file: $!\n";
}


### fcntl locking now done by File::Lock

sub fcntl_lock {
    my ($fh, $excl, $wait) = @_;
	my $cmd = '';
    $cmd .= $excl ? 'w' : 'r';
    $cmd .= $wait ? 'b' : 'n';


    File::Lock::fcntl($fh,$cmd)
    	or die "Could not lock file: $!\n";
	1;
}

sub fcntl_unlock {
    my ($fh) = @_;
    File::Lock::fcntl($fh,'u')
    	or die "Could not unlock file: $!\n";
    1;
}

### Select based on os

my $lock_function;
my $unlock_function;

unless (defined $use) {
    my $os = $Vend::Util::Config{'osname'};
    warn "lock.pm: os is $os\n" if $debug;
	$use = 'flock';
    if ($os eq 'solaris') {
        $use = 'fcntl'
			if defined $INC{'File/Lock.pm'};
    }
	elsif ($os =~ /win32/i) {
        $use = 'none';
	}

}
        
if ($use eq 'fcntl') {
    warn "lock.pm: using fcntl locking\n" if $debug;
    $lock_function = \&fcntl_lock;
    $unlock_function = \&fcntl_unlock;
}
elsif ($use eq 'none') {
    warn "lock.pm: using NO locking\n" if $debug;
    $lock_function = sub {1};
    $unlock_function = sub {1};
}
else {
    warn "lock.pm: using flock locking\n" if $debug;
    $lock_function = \&flock_lock;
    $unlock_function = \&flock_unlock;
}
    
sub lockfile {
    &$lock_function(@_);
}

sub unlockfile {
    &$unlock_function(@_);
}

# Returns the total number of items ordered.
# Uses the current cart if none specified.

sub tag_nitems {
	my($ref) = @_;
    my($cart, $total, $i);

	
	if($ref) {
		 $cart = $Vend::Session->{carts}->{$ref}
		 	or return 0;
	}
	else {
		$cart = $Vend::Items;
	}

    $total = 0;
    foreach $i (0 .. $#$cart) {
		$total += $cart->[$i]->{'quantity'};
    }
    $total;
}

sub dump_structure {
	my ($ref, $name) = @_;
	my $save;
	$name =~ s/\.cfg$//;
	$name .= '.structure';
	open(UNEV, ">$name") or die "Couldn't write structure $name: $!\n";
	if(defined $Data::Dumper::Indent) {
		$save = $Data::Dumper::Indent;
		$Data::Dumper::Indent = 2;
	}
	print UNEV uneval $ref;
	close UNEV;
	$Data::Dumper::Indent = $save if defined $save;
}

# Do an internal HTTP authorization check
sub check_authorization {
	my($auth, $pwinfo) = @_;

	$auth =~ s/^\s*basic\s+//i or return undef;
	my ($user, $pw) = split(
						":",
						MIME::Base64::decode_base64($auth),
						2,
						);
	my $cmp_pw;
	my $use_crypt = 1;
	if(!defined $Vend::Cfg) {
		$pwinfo = $Global::AdminUser;
		$pwinfo =~ s/^\s+//;
		$pwinfo =~ s/\s+$//;
		my (%compare) = split /[\s:]+/, $pwinfo;
		return undef unless $compare{$user};
		$cmp_pw = $compare{$user};
		undef $use_crypt if $Global::Variable->{MV_NO_CRYPT};
	}
	elsif(	$user eq $Vend::Cfg->{RemoteUser}	and
			$Vend::Cfg->{Password}					)
	{
		$cmp_pw = $Vend::Cfg->{Password};
		undef $use_crypt if $Vend::Cfg->{Variable}{MV_NO_CRYPT};
	}
	else {
		$pwinfo = $Vend::Cfg->{UserDatabase} unless $pwinfo;
		undef $use_crypt unless $Vend::Cfg->{Variable}{MV_USE_CRYPT};
		$cmp_pw = Vend::Interpolate::tag_data($pwinfo, 'password', $user)
			if defined $Vend::Cfg->{Database}{$pwinfo};
	}

	return undef unless $cmp_pw;

	if(! $use_crypt) {
		return $user if $pw eq $cmp_pw;
	}
	else {
		my $test = crypt($pw, $cmp_pw);
		return $user
			if $test eq $cmp_pw;
	}
	return undef;
}

# Check that the user is authorized by one or all of the
# configured security checks
sub check_security {
	my($item, $reconfig, $gate) = @_;

	my $msg;
	if(! $reconfig) {
# If using the new USERDB access control you may want to remove this next line
# for anyone with an HTTP basic auth will have access to everything
		#return 1 if $CGI::user and ! $Global::Variable->{MV_USERDB};
		if($gate) {
			$gate =~ s/\s+//g;
			return 1 if is_yes($gate);
		}
		elsif($Vend::Session->{logged_in}) {
			return 1 if $Vend::Cfg->{Variable}{MV_USERDB_REMOTE_USER};
			my $db;
			my $field;
			if ($db = $Vend::Cfg->{Variable}{MV_USERDB_ACL_TABLE}) {
				$field = $Vend::Cfg->{Variable}{MV_USERDB_ACL_COLUMN};
				my $access = Vend::Data::database_field(
								$db,
								$Vend::Session->{username},
								$field,
								);
				return 1 if $access =~ m{(^|\s)$item(\s|$)};
			}
		}
		my $besthost = $CGI::remote_host || $CGI::remote_addr;
        logGlobal qq{auth error host=$besthost ip=$CGI::remote_addr script=$CGI::script_name page=$CGI::path_info};
        return '';  
	}
	elsif($reconfig eq '1') {
		$msg = 'reconfigure catalog';
	}
	elsif ($reconfig eq '2') {
		$msg = "access protected database $item";
#::logGlobal("passed gate of $gate");
		return 1 if is_yes($gate);
	}
	elsif ($reconfig eq '3') {
		$msg = "access administrative function $item";
	}

	# Check if host IP is correct when MasterHost is set to something
	if (	$Vend::Cfg->{MasterHost}
				and
		(	$CGI::remote_host !~ /^($Vend::Cfg->{MasterHost})$/
				and
			$CGI::remote_addr !~ /^($Vend::Cfg->{MasterHost})$/	)	)
	{
		logGlobal <<EOF;
ALERT: Attempt to $msg at $CGI::script_name from:

	REMOTE_ADDR  $CGI::host
	REMOTE_USER  $CGI::user
	USER_AGENT   $CGI::useragent
	SCRIPT_NAME  $CGI::script_name
	PATH_INFO    $CGI::path_info
EOF

		return '';
	}

	# Check to see if password enabled, then check
	if (
		$reconfig eq '1'		and
		!$CGI::user				and
		$Vend::Cfg->{Password}	and
		crypt($CGI::reconfigure_catalog, $Vend::Cfg->{Password})
		ne  $Vend::Cfg->{Password})
	{
		logGlobal <<EOF;
ALERT: Password mismatch, attempt to $msg at $CGI::script_name from $CGI::host
EOF
			return '';
	}

	# Finally check to see if remote_user match enabled, then check
	if ($Vend::Cfg->{RemoteUser} and
		$CGI::user ne $Vend::Cfg->{RemoteUser})
	{
		logGlobal <<EOF;
ALERT: Attempt to $CGI::script_name $msg at with improper user name:

	REMOTE_HOST  $CGI::remote_host
	REMOTE_ADDR  $CGI::remote_addr
	REMOTE_USER  $CGI::user
	USER_AGENT   $CGI::useragent
	SCRIPT_NAME  $CGI::script_name
	PATH_INFO    $CGI::path_info
EOF
		return '';
	}

	# Don't allow random reconfigures without one of the three checks
	unless ($Vend::Cfg->{MasterHost} or
			$Vend::Cfg->{Password}   or
			$Vend::Cfg->{RemoteUser}) {
		logGlobal <<EOF;
Attempt to $msg on $CGI::script_name, secure operations disabled.

	REMOTE_ADDR  $CGI::host
	REMOTE_USER  $CGI::user
	USER_AGENT   $CGI::useragent
	SCRIPT_NAME  $CGI::script_name
	PATH_INFO    $CGI::path_info
EOF
			return '';

	}

	# Authorized if got here
	return 1;
}

# Replace the escape notation %HH with the actual characters.
#
sub unescape_chars {
    my($in) = @_;

    $in =~ s/%(..)/chr(hex($1))/ge;
    $in;
}

# Returns its arguments as a string of comma separated and quoted
# fields.  Double quotes in the argument values are converted to
# two double quotes.

sub csv {
    return join(',', map { $_ = '' unless defined $_;
                           s/\"/\"\"/g;
                           '"'. $_ .'"';
                         } @_);
}

## SEND_MAIL

# Send a mail message to the email address TO, with subject SUBJECT, and
# message BODY.  Returns true on success.

sub send_mail {
    my($to, $subject, $body, $reply, $use_mime, @extra_headers) = @_;
    my($ok);
#::logGlobal("send_mail: to=$to subj=$subject r=$reply mime=$use_mime\n");

	unless (defined $use_mime) {
		$use_mime = $Vend::MIME || undef;
	}

	if(!defined $reply) {
		$reply = $::Values->{'mv_email'}
				?  "Reply-To: $::Values->{'mv_email'}\n"
				: '';
	}
	elsif ($reply) {
		$reply = "Reply-To: $reply\n"
			unless $reply =~ /^reply-to:/i;
		$reply =~ s/\s+$/\n/;
	}

    $ok = 0;
	my $none;

	if("\L$Vend::Cfg->{SendMailProgram}" eq 'none') {
		$none = 1;
		$ok = 1;
	}

    SEND: {
		last SEND if $none;
		open(Vend::MAIL,"|$Vend::Cfg->{SendMailProgram} $to") or last SEND;
		my $mime = '';
		$mime = Vend::Interpolate::do_tag('mime header') if $use_mime;
		print Vend::MAIL "To: $to\n", $reply, "Subject: $subject\n"
	    	or last SEND;
		for(@extra_headers) {
			s/\s*$/\n/;
			print Vend::MAIL $_
				or last SEND;
		}
		$mime =~ s/\s*$/\n/;
		print Vend::MAIL $mime
	    	or last SEND;
		print Vend::MAIL $body
				or last SEND;
		print Vend::MAIL Vend::Interpolate::do_tag('mime boundary') . '--'
			if $use_mime;
		print Vend::MAIL "\r\n\cZ" if $Global::Windows;
		close Vend::MAIL or last SEND;
		$ok = ($? == 0);
    }
    
    if ($none or !$ok) {
		logError("Unable to send mail using $Vend::Cfg->{SendMailProgram}\n" .
		 	"To: $to\n" .
		 	"Subject: $subject\n" .
		 	"$reply\n\n$body");
    }

    $ok;
}

# Checks the Locale for a special page definintion mv_special_$key and
# returns it if found, otherwise goes to the default Vend::Cfg->{Special} array
sub find_special_page {
    my $key = shift;
    return $Vend::Cfg->{Special}{$key} || $key unless 
		$Vend::Cfg->{Locale};
    return $Vend::Cfg->{Locale}{"mv_special_$key"}
		if defined $Vend::Cfg->{Locale}{"mv_special_$key"};
    return $Vend::Cfg->{Special}{$key} || $key;
}

# Appends the string $value to the end of $filename.  The file is opened
# in append mode, and the string is written in a single system write
# operation, so this function is safe in a multiuser environment even
# without locking.

sub append_to_file {
    my ($filename, $value) = @_;

    open(OUT, ">>$filename") or die "Can't append to '$filename': $!\n";
    syswrite(OUT, $value, length($value))
        == length($value) or die "Can't write to '$filename': $!\n";
    close(OUT);
}

# Converts the passed field values into a single line in Ascii delimited
# format.  Two formats are available, selected by $format:
# "comma_separated_values" and "tab_separated".

sub field_line {
    my $format = shift;

    return csv(@_) . "\n"    if $format eq 'comma_separated_values';
    return tabbed(@_) . "\n" if $format eq 'tab_separated';

    die "Unknown format: $format\n";
}

# Appends the passed field values onto the end of $filename in a single
# system operation.

sub append_field_data {
    my $filename = shift;
    my $format = shift;

    append_to_file($filename, field_line($format, @_));
}

## ERROR

# Log the error MSG to the error file.

sub logDebug {
	return unless $Global::DEBUG;
	my ($msg, $level) = @_;
	return if $level and $level & $Global::DEBUG;
	$msg = (caller)[0] . " >>> $msg" if ::debug($Global::DHASH{CALLER});
	if(::debug($Global::DHASH{COMMENT} || 0)) {
		$Vend::DebugHTML .= $msg;
	}
	if(::debug(0x1800) ) {
		print $msg;
	}
	return;
}

sub errmsg {
	my($selector,$fmt, @strings) = @_;
	if($Global::Locale and defined $Global::Locale->{$selector}) {
	 	$fmt = $Global::Locale->{$selector};
	}
	elsif($Vend::Cfg->{Locale} and defined $Vend::Cfg->{Locale}->{$selector}) {
	 	$fmt = $Vend::Cfg->{Locale}->{$selector};
	}
	return sprintf $fmt, @strings;
}

sub logGlobal {
    my($msg) = shift;
	if(@_) {
		$msg .= "'" . (join "','", @_) . "'";
	}
	my(@params);

	print "$msg\n" if $Vend::Foreground and ! $Vend::Log_suppress;

    $msg = format_log_msg($msg);

	$Vend::Errors .= $msg if $Global::DisplayErrors;

    eval {
		open(Vend::ERROR, ">>$Global::ErrorFile") or die "open\n";
		lockfile(\*Vend::ERROR, 1, 1) or die "lock\n";
		seek(Vend::ERROR, 0, 2) or die "seek\n";
		print(Vend::ERROR $msg, "\n") or die "write to\n";
		unlockfile(\*Vend::ERROR) or die "unlock\n";
		close(Vend::ERROR) or die "close\n";
    };
    if ($@) {
		chomp $@;
		print "\nCould not $@ error file '";
		print $Global::Errorfile, "':\n$!\n";
		print "to report this error:\n", $msg;
		exit 1;
    }
}


# Log the error MSG to the error file.

sub logError {
    my($msg) = @_;
	my(@params);
	return unless defined $Vend::Cfg;

	print "$msg\n" if $Vend::Foreground and ! $Vend::Log_suppress;

	$Vend::Session->{'last_error'} = $msg;

    $msg = format_log_msg($msg) unless $msg =~ s/^\\//;

	$Vend::Errors .= $msg if ($Vend::Cfg->{DisplayErrors} ||
							  $Global::DisplayErrors);

    eval {
		open(Vend::ERROR, ">>$Vend::Cfg->{ErrorFile}")
											or die "open\n";
		lockfile(\*Vend::ERROR, 1, 1)		or die "lock\n";
		seek(Vend::ERROR, 0, 2)				or die "seek\n";
		print(Vend::ERROR $msg, "\n")		or die "write to\n";
		unlockfile(\*Vend::ERROR)			or die "unlock\n";
		close(Vend::ERROR)					or die "close\n";
    };
    if ($@) {
		chomp $@;
		logGlobal <<EOF;
Could not $@ error file $Vend::Cfg->{ErrorFile}: $!
		
to report this error:
$msg
EOF
    }
}

# Here for convenience in calls
sub set_cookie {
    my ($name, $value, $expire) = @_;
    $::Instance->{Cookies} = []
        if ! $::Instance->{Cookies};
    @{$::Instance->{Cookies}} = [$name, $value, $expire];
    return;
}

# Here for convenience in calls
sub read_cookie {
	my ($lookfor, $string) = @_;
	$string = $CGI::cookie
		unless defined $string;
	return undef unless $string =~ /\b$lookfor=([^\s;]+)/i;
 	return unescape_chars($1);
}

# These were stolen from File::Spec
# Can't use that because it INSISTS on object
# calls without returning a blessed object

my $abspat = $^O =~ /win32/i ? '^([a-z]:)?[\\\\/]' : '^/';

sub file_name_is_absolute {
    my($file) = @_;
    $file =~ m{$abspat}oi ;
}

sub win_catfile {
    my $file = pop @_;
    return $file unless @_;
    my $dir = catdir(@_);
    $dir =~ s/(\\\.)$//;
    $dir .= "\\" unless substr($dir,length($dir)-1,1) eq "\\";
    return $dir.$file;
}

sub unix_catfile {
    my $file = pop @_;
    return $file unless @_;
    my $dir = catdir(@_);
    for ($dir) {
	$_ .= "/" unless substr($_,length($_)-1,1) eq "/";
    }
    return $dir.$file;
}

sub unix_path {
    my $path_sep = ":";
    my $path = $ENV{PATH};
    my @path = split $path_sep, $path;
    foreach(@path) { $_ = '.' if $_ eq '' }
    @path;
}

sub win_path {
    local $^W = 1;
    my $path = $ENV{'PATH'} || $ENV{'Path'} || $ENV{'path'};
    my @path = split(';',$path);
    foreach(@path) { $_ = '.' if $_ eq '' }
    @path;
}

sub win_catdir {
    my @args = @_;
    for (@args) {
	# append a slash to each argument unless it has one there
	$_ .= "\\" if $_ eq '' or substr($_,-1) ne "\\";
    }
    my $result = canonpath(join('', @args));
    $result;
}

sub win_canonpath {
    my($path) = @_;
    $path =~ s/^([a-z]:)/\u$1/;
    $path =~ s|/|\\|g;
    $path =~ s|\\+|\\|g ;                          # xx////xx  -> xx/xx
    $path =~ s|(\\\.)+\\|\\|g ;                    # xx/././xx -> xx/xx
    $path =~ s|^(\.\\)+|| unless $path eq ".\\";   # ./xx      -> xx
    $path =~ s|\\$|| 
             unless $path =~ m#^([a-z]:)?\\#;      # xx/       -> xx
    $path .= '.' if $path =~ m#\\$#;
    $path;
}

sub unix_canonpath {
    my($path) = @_;
    $path =~ s|/+|/|g ;                            # xx////xx  -> xx/xx
    $path =~ s|(/\.)+/|/|g ;                       # xx/././xx -> xx/xx
    $path =~ s|^(\./)+|| unless $path eq "./";     # ./xx      -> xx
    $path =~ s|/$|| unless $path eq "/";           # xx/       -> xx
    $path;
}

sub unix_catdir {
    my @args = @_;
    for (@args) {
	# append a slash to each argument unless it has one there
	$_ .= "/" if $_ eq '' or substr($_,-1) ne "/";
    }
    my $result = join('', @args);
    # remove a trailing slash unless we are root
    substr($result,-1) = ""
	if length($result) > 1 && substr($result,-1) eq "/";
    $result;
}


my $catdir_routine;
my $canonpath_routine;
my $catfile_routine;
my $path_routine;

if($^O =~ /win32/i) {
	$catdir_routine = \&win_catdir;
	$catfile_routine = \&win_catfile;
	$path_routine = \&win_path;
	$canonpath_routine = \&win_canonpath;
}
else {
	$catdir_routine = \&unix_catdir;
	$catfile_routine = \&unix_catfile;
	$path_routine = \&unix_path;
	$canonpath_routine = \&unix_canonpath;
}

sub path {
	return &{$path_routine}(@_);
}

sub catfile {
	return &{$catfile_routine}(@_);
}

sub catdir {
	return &{$catdir_routine}(@_);
}

sub canonpath {
	return &{$canonpath_routine}(@_);
}

#print "catfile a b c --> " . catfile('a', 'b', 'c') . "\n";
#print "catdir a b c --> " . catdir('a', 'b', 'c') . "\n";
#print "canonpath a/b//../../c --> " . canonpath('a/b/../../c') . "\n";
#print "file_name_is_absolute a/b/c --> " . file_name_is_absolute('a/b/c') . "\n";
#print "file_name_is_absolute a:b/c --> " . file_name_is_absolute('a:b/c') . "\n";
#print "file_name_is_absolute /a/b/c --> " . file_name_is_absolute('/a/b/c') . "\n";

1;
__END__
