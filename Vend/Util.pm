# $Id: Util.pm,v 2.10 1997/01/18 15:03:38 mike Exp $

package Vend::Util;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(

blank
combine
commify
currency
file_modification_time
get_files
international_number
is_no
is_yes
logData
logError
logGlobal
lockfile
unlockfile
readfile
readin
random_string
quoted_string
quoted_comma_string
setup_escape_chars
escape_chars
unescape_chars
send_mail
set_cart
secure_vendUrl
tabbed
tag_nitems
tag_item_quantity
tainted
trim_desc
uneval
vendUrl
wrap

);
@EXPORT_OK = qw(append_field_data append_to_file csv field_line);

use strict;
use Carp;
use Config;
use Fcntl;
# We now use File::Lock for Solaris and SGI systems
#use File::Lock;

### END CONFIGURABLE MODULES


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

# Returns its arguments as a string of tab-separated fields.  Tabs in the
# argument values are converted to spaces.

sub tabbed {        
    return join("\t", map { $_ = '' unless defined $_;
                            s/\t/ /g;
                            $_;
                          } @_);
}

my(%Tab);

sub international_number {
    return $_[0] unless $Vend::Cfg->{Locale};
	unless (%Tab ||= () ) {
		%Tab = (	',' => $Vend::Cfg->{Locale}->{mon_thousands_sep},
					'.' => $Vend::Cfg->{Locale}->{mon_decimal_point}  );
	}
    $_[0] =~ s/([^0-9])/$Tab{$1}/g;
	return $_[0];
}

sub commify {
    local($_) = shift;
    1 while s/^(-?\d+)(\d{3})/$1,$2/;
    return $_;
}

# Trims the description output for the order and search pages
# Trims from $Vend::Cfg->{'DescriptionTrim'} onward
sub trim_desc {
	return $_[0] unless $Vend::Cfg->{'DescriptionTrim'};
	my($desc) = @_;
	$desc =~ s/$Vend::Cfg->{'DescriptionTrim'}(.*)//;
	$desc;
}

# Return AMOUNT formatted as currency.

sub currency {
    my($amount) = @_;
	my $fmt = "%.2f";
	$fmt = "%." . $Vend::Cfg->{Locale}->{frac_digits} .  "f"
		if $Vend::Cfg->{Locale} && defined $Vend::Cfg->{Locale}->{frac_digits};

    $amount = sprintf $fmt, $amount;
    $amount = commify($amount)
        if is_yes($Vend::Cfg->{'PriceCommas'});

    return international_number($amount);
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


sub combine {
    my $r;

    if (@_ == 1) {
	$_[0];
    } elsif (@_ == 2) {
	"$_[0] and $_[1]";
    } else {
	$r = $_[0];
	foreach (1 .. $#_ - 1) {
	    $r .= ", $_[$_]";
	}
	$r .= ", and " . $_[$#_];
	$r;
    }
}

sub blank {
    my ($x) = @_;
    return (!defined($x) or $x eq '');
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

## ERROR

# Log the error MSG to the error file.

sub logGlobal {
    my($msg) = @_;
    my $prefix = '';

	my	$errorfile = $Global::ErrorFile;

    eval {
		open(Vend::ERROR, ">>$errorfile") or die "open\n";
		lockfile(\*Vend::ERROR, 1, 1) or die "lock\n";
		$prefix = "$$: " if $Global::MultiServer;
		seek(Vend::ERROR, 0, 2) or die "seek\n";
		print(Vend::ERROR $prefix, `date`) or die "write to\n";
		print(Vend::ERROR $prefix, "$msg\n") or die "write to\n";
		unlockfile(\*Vend::ERROR) or die "unlock\n";
		close(Vend::ERROR) or die "close\n";
    };
    if ($@) {
		chomp $@;
		print "\nCould not $@ error file '";
		print $errorfile, "':\n$!\n";
		print "to report this error:\n", $msg;
		exit 1;
    }
}


# Log the error MSG to the error file.

sub logError {
    my($msg) = @_;
    my $prefix = '';

	my $errorfile;
	if(defined $Vend::Cfg) {
		$errorfile = $Vend::Cfg->{'ErrorFile'};
	}
	else {
		$errorfile = $Global::ErrorFile;
	}

    eval {
		open(Vend::ERROR, ">>$errorfile") or die "open\n";
		lockfile(\*Vend::ERROR, 1, 1) or die "lock\n";
		$prefix = "$$: " if $Global::MultiServer;
		seek(Vend::ERROR, 0, 2) or die "seek\n";
		print(Vend::ERROR $prefix, `date`) or die "write to\n";
		print(Vend::ERROR $prefix, "$msg\n") or die "write to\n";
		unlockfile(\*Vend::ERROR) or die "unlock\n";
		close(Vend::ERROR) or die "close\n";
    };
    if ($@) {
		chomp $@;
		print "\nCould not $@ error file '";
		print $errorfile, "':\n$!\n";
		print "to report this error:\n", $msg;
		exit 1;
    }
}

# Log data fields to a data file.

sub logData {
    my($file,@msg) = @_;
    my $prefix = '';

	$file = ">>$file" unless $file =~ /^[|>]/;

	my $msg = tabbed @msg;

    eval {
		unless($file =~ s/^[|]\s*//) {
			open(Vend::LOGDATA, "$file") or die "open\n";
			lockfile(\*Vend::LOGDATA, 1, 1) or die "lock\n";
			seek(Vend::LOGDATA, 0, 2) or die "seek\n";
			print(Vend::LOGDATA "$msg\n") or die "write to\n";
			unlockfile(\*Vend::LOGDATA) or die "unlock\n";
		}
		else {
            my (@args) = grep /\S/, quoted_string($file);
			open(Vend::LOGDATA, "|-") || exec @args;
			print(Vend::LOGDATA "$msg\n") or die "pipe to\n";
		}
		close(Vend::LOGDATA) or die "close\n";
    };
    if ($@) {
    chomp $@;
    logError "Could not $@ log file '" . $file . "':\n$!\n" .
    		"to log this data:\n" .  $msg ;
    }
}


=head2 C<wrap($str, $width)>

Wraps the passed string to fit the specified maximum width.  An array
of lines, each $width or less, is returned.  The line is wrapped at a
space if one exists in the string.

(The function could also wrap on other characters, such as a dash, but
currently does not).

=cut

sub wrap {
    my ($str, $width) = @_;
    my @a = ();
    my ($l, $b);

    for (;;) {
        $str =~ s/^ +//;
        $l = length($str);
        last if $l == 0;
        if ($l <= $width) {
            push @a, $str;
            last;
        }
        $b = rindex($str, " ", $width - 1);
        if ($b == -1) {
            push @a, substr($str, 0, $width);
            $str = substr($str, $width);
        }
        else {
            push @a, substr($str, 0, $b);
            $str = substr($str, $b + 1);
        }
    }
    return @a;
}

sub file_modification_time {
    my ($fn) = @_;
    my @s = stat($fn) or die "Can't stat '$fn': $!\n";
    return $s[9];
}


sub quoted_string {

my ($text) = @_;
my (@fields);
push(@fields, $+) while $text =~ m{
   "([^\"\\]*(?:\\.[^\"\\]*)*)"\s?  ## standard quoted string, w/ possible space
   | ([^\s]+)\s?                    ## anything else, w/ possible space
   | \s+                            ## any whitespace
        }gx;
    @fields;
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


# Returns its arguments as a string of comma separated and quoted
# fields.  Double quotes in the argument values are converted to
# two double quotes.

sub csv {
    return join(',', map { $_ = '' unless defined $_;
                           s/\"/\"\"/g;
                           '"'. $_ .'"';
                         } @_);
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


## READIN

# Reads in a page from the page directory with the name FILE and ".html"
# appended.  Returns the entire contents of the page, or undef if the
# file could not be read.

sub readin {
    my($file,$dir) = @_;
    my($fn, $contents);
    local($/);
	
	$dir = $Vend::Cfg->{'PageDir'} unless defined $dir;
    $fn = "$dir/" . escape_chars($file) . ".html";
    if (open(Vend::IN, $fn)) {
		undef $/;
		$contents = <Vend::IN>;
		close(Vend::IN);
    } else {
		$contents = undef;
    }
    $contents;
}

# Reads in an arbitrary file.  Returns the entire contents,
# or undef if the file could not be read.
# Careful, needs the full path, or will be read relative to
# VendRoot..and will return binary. Should be tested by
# the user.
sub readfile {
    my($file) = @_;
    my($fn, $contents);
    local($/);

    if (open(Vend::IN, $file)) {
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
	my($dir, @files) = @_;
	my(@out);
	my($file, $contents);

	foreach $file (@files) {
		push(@out,"\n") unless
			push(@out,readin($file, $dir));
	}
	
	@out;
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
    $r = $Vend::Cfg->{'VendURL'}
		unless defined $r;
	$arguments = '' unless defined $arguments;

	if(defined $Vend::Cfg->{'AlwaysSecure'}->{$path}) {
		$r = $Vend::Cfg->{'SecureURL'};
	}

    $r .= '/' . $path . '?' . $Vend::SessionID .
	';' . $arguments . ';' . ++$Vend::Session->{'pageCount'};
    $r;
}    

sub secure_vendUrl
{
    my($path, $arguments) = @_;
    my($r);

	return undef unless $Vend::Cfg->{'SecureURL'};

    $r = $Vend::Cfg->{'SecureURL'} . '/' . $path . '?' . $Vend::SessionID .
	';' . $arguments . ';' . ++$Vend::Session->{'pageCount'};
    $r;
}    

## SEND_MAIL

# Send a mail message to the email address TO, with subject SUBJECT, and
# message BODY.  Returns true on success.

sub send_mail {
    my($to, $subject, $body) = @_;
	my($reply) = '';
    my($ok);

	$reply = "Reply-To: $Vend::Session->{'values'}->{'mv_email'}\n"
		if defined $Vend::Session->{'values'}->{'mv_email'};

    $ok = 0;
    SEND: {
		open(Vend::MAIL,"|$Vend::Cfg->{'SendMailProgram'} -t") or last SEND;
		print Vend::MAIL "To: $to\n", $reply, "Subject: $subject\n\n", $body
	    	or last SEND;
		close Vend::MAIL or last SEND;
		$ok = ($? == 0);
    }
    
    if (!$ok) {
		logError("Unable to send mail using $Vend::Cfg->{'SendMailProgram'}\n" .
		 	"To '$to'\n" .
		 	"With subject '$subject'\n" .
		 	"With reply-to '$reply'\n" .
		 	"And body:\n$body");
    }

    $ok;
}

sub tainted {
    my($v) = @_;
    my($r);
    local($@);

    eval { open(Vend::FOO, ">" . "FOO" . substr($v,0,0)); };
    close Vend::FOO;
    ($@ ? 1 : 0);
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
        flock($fh, $flag) or confess "Could not lock file: $!\n";
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
                confess "Could not lock file: $!\n";
            }
        }
        return 1;
    }
}

sub flock_unlock {
    my ($fh) = @_;
    flock($fh, $flock_LOCK_UN) or confess "Could not unlock file: $!\n";
}


### fcntl locking now done by File::Lock

sub fcntl_lock {
    my ($fh, $excl, $wait) = @_;
	my $cmd = '';
    $cmd .= $excl ? 'w' : 'r';
    $cmd .= $wait ? 'b' : 'n';


    File::Lock::fcntl($fh,$cmd)
    	or confess "Could not lock file: $!\n";
	1;
}

sub fcntl_unlock {
    my ($fh) = @_;
    File::Lock::fcntl($fh,'u')
    	or confess "Could not unlock file: $!\n";
    1;
}

### Select based on os

my $lock_function;
my $unlock_function;

unless (defined $use) {
    my $os = $Vend::Util::Config{'osname'};
    warn "lock.pm: os is $os\n" if $debug;
    if ($os eq 'solaris') {
        $use = 'fcntl';
    }
    else {
        $use = 'flock';
    }
}
        
if ($use eq 'fcntl') {
    warn "lock.pm: using fcntl locking\n" if $debug;
    $lock_function = \&fcntl_lock;
    $unlock_function = \&fcntl_unlock;
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

# Returns the number ordered of a single item code
# Uses the current cart if none specified.

sub tag_item_quantity {
	my($code,$ref) = @_;
    my($i,$cart);
	
	if(ref $Vend::Session->{carts}->{$ref}) {
		 $cart = $Vend::Session->{carts}->{$ref};
	}
	else {
		$cart = $Vend::Items;
	}

	my $q = 0;
    foreach $i (0 .. $#$cart) {
		$q += $cart->[$i]->{'quantity'}
			if $code eq $cart->[$i]->{'code'};
    }
	$q;
}

# Returns the total number of items ordered.
# Uses the current cart if none specified.

sub tag_nitems {
	my($ref) = @_;
    my($cart, $total, $i);

	
	if(ref $Vend::Session->{carts}->{$ref}) {
		 $cart = $Vend::Session->{carts}->{$ref};
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

1;
