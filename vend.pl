#!/usr/bin/perl
#
# Vend version 0.2 (alpha)
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
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

$Config::VendRoot  = '/usr/vend';
$Config::ConfigFile = 'vend.conf';
$Config::ErrorFile  = 'error.log';

use strict;
use GDBM_File;
#use NDBM_File;
#use Fcntl;

$Config::ConfigFile = "$Config::VendRoot/$Config::ConfigFile"
    if ($Config::ConfigFile !~ m.^/.);
$Config::ErrorFile = "$Config::VendRoot/$Config::ErrorFile"
    if ($Config::ErrorFile !~ m.^/.);


## CURRANCY

# Return AMOUNT formatted as currancy.

sub currancy {
    my($amount) = @_;

    sprintf("%.2f", $amount);
}


# Return shipping costs.

sub shipping {
    $Config::Shipping;
}

sub blank {
    my($v) = @_;

    !defined($v) || $v eq '';
}


## ERROR

# Log the error MSG to the error file.

sub logError {
    my($msg) = @_;

    eval {
	open(Vend::ERROR, ">>$Config::ErrorFile") or die "open\n";
	flock(Vend::ERROR, $LOCK::exclusive) or die "lock\n";
	seek(Vend::ERROR, 0, 2) or die "seek\n";
	print(Vend::ERROR `date`, "$msg\n") or die "write to\n";
	flock(Vend::ERROR, $LOCK::unlock) or die "unlock\n";
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
      "start with 'http:'")
	unless $value =~ m/^http:/i;
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

sub parse_time {
    my($var, $value) = @_;
    my($n);

    $n = time_to_seconds($value);
    config_error("Bad time format ('$value') in the $var directive\n")
	unless defined $n;
    $n;
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
	['OrderReport',      'relative_dir',     'report'],
        ['DisplayErrors',    'yesno',            'Yes'],
	['SessionDatabase',  'relative_dir',     'session'],
	['WritePermission',  'permission',       'user'],
	['ReadPermission',   'permission',       'user'],
	['SessionExpire',    'time',             '1 day'],
	['MailOrderTo',      undef,              undef],
	['SendMailProgram',  undef,              '/usr/lib/sendmail'],
	['Finish_order',     undef,              'Finish Incomplete Order'],
	['Shipping',         undef,              0],
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
	s/#.*//;                #  comments,
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
    '-_.$';

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


## LOCK FLAGS

$LOCK::shared = 1;
$LOCK::exclusive = 2;
$LOCK::nonblocking = 4;
$LOCK::unlock = 8;


## SESSIONS implemented using files

sub open_session_file {
    my($fn);

    $fn = "sessions/" . session_name();
    open(Vend::SF, "+>>$fn") || die "Could not open '$fn':\n$!\n";
    flock(Vend::SF, $LOCK::exclusive)
	|| die "Could not lock session file '$fn':\n$!\n";
}

sub new_session_file {    
    for (;;) {
	$Vend::SessionID = random_string();
	open_session();
	last if (-s Vend::SF == 0);
	close_session();
    }
    init_session();
}

sub close_session_file {
    flock(Vend::SF, $LOCK::unlock)
	|| die "Could not unlock session file: $!";
    close(Vend::SF);
}

sub write_session_file {
    no strict 'subs';		# perl BUG: truncate does not accept filehandle
    seek(Vend::SF, 0, 0) || die "Couldn't seek: $!";
    truncate(Vend::SF, 0) || die "Couldn't truncate: $!";
    $Vend::Session->{'time'} = time;
    print Vend::SF uneval($Vend::Session);
}

sub read_session_file {
    my($s);

    if (-s Vend::SF == 0) {
	init_session();
    } else {
	seek(Vend::SF, 0, 0) || die "Couldn't seek: $!";
	read(Vend::SF, $s, -s Vend::SF);
	$Vend::Session = eval($s);
	die "Could not eval '$s' from session file: $@" if $@;
	$Vend::Items = $Vend::Session->{'items'};
    }
}


sub expire_sessions_file {
    my($time, $fn);

    $time = time;

    while(<sessions/*>) {
	print "<$_> ";
	m#(sessions/[%$ESCAPE_CHARS::ok_in_filename]+)#o
	    or die "strange characters in filename '$_'\n";
	$fn = $1;
	print "<$fn>\n";
	open(Vend::SF, "+>>$fn") || die "Could not open $fn: $!\n";
	flock(Vend::SF, $LOCK::exclusive)
	    or die "Could not lock session file: $!\n";
	read_session_file();
	if ($time - $Vend::Session->{'time'} > $Config::SessionExpire) {
	    unlink $fn or die "Could not delete $fn: $!\n";
	}
	close_session_file();
    }
}


sub dump_sessions_file {
    my($fn, $s);

    while(<sessions/*>) {
	m#(sessions/[%$ESCAPE_CHARS::ok_in_filename]+)#o
	    or die "strange characters in filename '$_'\n";
	$fn = $1;
	open(Vend::SF, "+>>$fn") || die "Could not open $fn: $!\n";
	flock(Vend::SF, $LOCK::exclusive)
	    or die "Could not lock session file: $!\n";
	seek(Vend::SF, 0, 0) || die "Couldn't seek: $!";
	read(Vend::SF, $s, -s Vend::SF);
	print "$fn $s\n\n";
	close_session_file();
    }
}


## SESSIONS implemented using DBM

sub open_session_dbm {
    open(Vend::SessionLock, "+>>session.lock")
	or die "Could not open 'session.lock': $!\n";
    flock(Vend::SessionLock, $LOCK::exclusive)
	or die "Could not lock 'session.lock': $!\n";
    
    # pick one
    tie(%Vend::SessionDBM, 'GDBM_File', $Config::SessionDatabase . ".gdbm",
	&GDBM_WRCREAT, $Config::FileCreationMask)
	or die "Could not tie to $Config::SessionDatabase: $!\n";

#    tie(%Vend::SessionDBM, 'NDBM_File', $Config::SessionDatabase,
#	&O_RDWR|&O_CREAT, $Config::FileCreationMask)
#	or die "Could not tie to $Config::SessionDatabase: $!\n";

#    dbmopen(%Vend::SessionDBM, $Config::SessionDatabase,
#	    $Config::FileCreationMask)
#	or die "Could not open DBM file '$Config::SessionDatabase: $!\n";

    $Vend::SessionName = session_name();
}

sub new_session_dbm {
    my($name);

    open_session_dbm();
    for (;;) {
	$Vend::SessionID = random_string();
	$name = session_name();
	last unless defined $Vend::SessionDBM{$name};
    }
    $Vend::SessionName = $name;
    init_session();
}

sub close_session_dbm {
    #pick one
    untie %Vend::SessionDBM
	or die "Could not close $Config::SessionDatabase: $!\n";

#    dbmclose(%Vend::SessionDBM)
#	or die "Could not close '$Config::SessionDatabase': $!\n";

    flock(Vend::SessionLock, $LOCK::unlock)
	or die "Could not unlock 'session.lock': $!\n";
    close(Vend::SessionLock)
	or die "Could not close 'session.lock': $!\n";
}

sub write_session_dbm {
    my($s);
    $Vend::Session->{'time'} = time;
    $s = uneval($Vend::Session);
    $Vend::SessionDBM{$Vend::SessionName} = $s;
    die "Data was not stored in DBM file\n"
	if $Vend::SessionDBM{$Vend::SessionName} ne $s;
}

sub read_session_dbm {
    my($s);

    $s = $Vend::SessionDBM{$Vend::SessionName};
    $Vend::Session = eval($s);
    die "Could not eval '$s' from session dbm: $@\n" if $@;
    $Vend::Items = $Vend::Session->{'items'};
}

sub expire_sessions_dbm {
    my($time, $session_name, $s, $session, @delete);

    $time = time;

    open_session_dbm();
    while(($session_name, $s) = each %Vend::SessionDBM) {
	$session = eval($s);
	die "Could not eval '$s' from session dbm: $@\n" if $@;
	if ($time - $session->{'time'} > $Config::SessionExpire) {
	    push @delete, $session_name;
	}
    }
    foreach $session_name (@delete) {
	delete $Vend::SessionDBM{$session_name};
    }
    close_session_dbm();
}

sub dump_sessions_dbm {
    my($session_name, $s);

    open_session_dbm();
    while(($session_name, $s) = each %Vend::SessionDBM) {
	print "$session_name $s\n\n";
    }
    close_session_dbm();
}


## SESSIONS

sub session_name {
    my($host, $user, $fn);

    $fn = escape_chars($Vend::SessionID) . ':'
	. escape_chars($CGI::host) . ':' . escape_chars($CGI::user);
    escape_chars($ENV{'GATEWAY_INTERFACE'});
    $fn;
}


sub init_session {
    $Vend::Session = {
	'version' => 1,
	'items' => []
    };
    $Vend::Items = $Vend::Session->{'items'};
}

sub write_and_close_session {
    write_session();
    close_session();
}

# pick one

#sub open_session { open_session_file(); }
#sub new_session { new_session_file(); }
#sub close_session { close_session_file(); }
#sub write_session { write_session_file(); }
#sub read_session { read_session_file(); }
#sub expire_sessions { expire_sessions_file(); }
#sub dump_sessions { dump_sessions_file(); }

sub open_session { open_session_dbm(); }
sub new_session { new_session_dbm(); }
sub close_session { close_session_dbm(); }
sub write_session { write_session_dbm(); }
sub read_session { read_session_dbm(); }
sub expire_sessions { expire_sessions_dbm(); }
sub dump_sessions { dump_sessions_dbm(); }


## PRODUCTS

# Read in the products file.

sub read_products {
    my($code, $desc, $price, @products);

    @products = ();
    open(Vend::PRODUCTS,"$Config::ProductDir/products")
	|| die "Could not open products: $!";
    while(<Vend::PRODUCTS>) {
	chomp;
	($code,$desc,$price) = split(/,/);
	push @products, $code;
	$Vend::Products{$code} = 1;
	$Vend::Product_description{$code} = $desc;
	$Vend::Product_price{$code} = $price;
    }
    close Vend::PRODUCTS;
}


## PAGE GENERATION

sub plain_header {
    print "Content-type: text/plain\n\n";
    $Vend::content_type = 'plain';
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

# Returns either a href to finish the ordering process (if at least
# one item has been ordered), or an empty string.

sub tag_finish_order {
    my($finish_order);

    if (@$Vend::Items > 0) {
	$finish_order =
	    '<a href="' . vendUrl("finish") . '">' .
	    $Config::Finish_order . "</a><p>";
    } else {
	$finish_order = '';
    }
    $finish_order;
}

# Returns an href to place an order for the product PRODUCT_CODE.

sub tag_order {
    my($product_code) = @_;

    '<a href="' . vendUrl('order', $product_code) . '">';
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
    currancy(shipping());
}

# Returns the total cost of items ordered.

sub tag_total_cost {
    my($total, $i);

    $total = 0;
    foreach $i (0 .. $#$Vend::Items) {
	$total += $Vend::Items->[$i]->{'quantity'} *
	    $Vend::Product_price{$Vend::Items->[$i]->{'code'}};
    }
    $total += shipping();
    currancy($total);
}

# Returns the href to process the completed order form.

sub tag_process_order {
    vendUrl('process');
}

# Evaluates the [...] tags.

sub interpolate_html {
    my($html) = @_;
    my($codere) = '[\w-_]+';

    $html =~ s:\[finish-order\]:tag_finish_order():ige;

    $html =~ s:\[page\s+($codere)\]:tag_page($1):igeo;
    $html =~ s:\[/page\]:</a>:ig;

    $html =~ s:\[last-page\]:tag_last_page():ige;
    $html =~ s:\[/last-page\]:</a>:ig;

    $html =~ s:\[order\s+($codere)\]:tag_order($1):igeo;
    $html =~ s:\[/order\]:</a>:ig;

    $html =~ s:\[value\s+($codere)\]:tag_value($1):igeo;

    $html =~ s:\[nitems\]:tag_nitems():ige;
    $html =~ s#\[shipping\]#tag_shipping()#ige;
    $html =~ s#\[total-cost\]#tag_total_cost()#ige;
    $html =~ s#\[price\s+($codere)\]#currancy($Vend::Product_price{$1})#igoe;
    $html =~ s#\[description\s+($codere)\]#
               $Vend::Product_description{$1}#igoe;

    $html =~ s#\[process-order\]#tag_process_order()#ige;
    $html;
}


## ORDER PAGE

sub tag_item_list {
    my($text) = @_;
    my($r, $i, $item, $code, $quantity, $price, $desc, $run);

    $r = "";
    foreach $i (0 .. $#$Vend::Items) {
	$item = $Vend::Items->[$i];
	$code = $item->{'code'};
	$quantity = $item->{'quantity'};
	$price = currancy($Vend::Product_price{$code});
	$desc = $Vend::Product_description{$code};

	$run = $text;
	$run =~ s:\[item-code\]:$code:ig;
	$run =~ s:\[item-description\]:$desc:ig;
	$run =~ s:\[item-quantity\]:$quantity:ig;
	$run =~ s:\[quantity-name\]:quantity$i:ig;
	$run =~ s:\[item-price\]:$price:ig;

	$r .= $run;
    }
    $r;
}

# Displays the order page with the special [item-list] tag evaluated.

sub order_page
{
    my($page);

    $page = readin("order");
    die "Missing special page: order\n" unless defined $page;
    $page =~ s:\[item-list\]([\000-\377]*?)\[/item-list\]:
              tag_item_list($1):ige;
    html_header();
    print interpolate_html($page);
}


## INTERFACE ERROR

# An incorrect response was returned from the browser, either because of a
# browser bug or bad html pages.

sub interaction_error {
    my($msg) = @_;
    my($page);

    logError("Difficulty interacting with browser:\n$msg");

    $page = readin("interact");
    if (defined $page) {
	$page =~ s#\[message\]#$msg#ig;
	$page = interpolate_html($page);
	html_header();
	print $page;
    } else {
	logError("Missing special page: interact\n");
	plain_header();
	print $msg, "\n";
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
    html_header();
    $page =~ s#\[subject\]#$subject#ig;
    print interpolate_html($page);
}

# Displays the catalog page NAME.  If the file is not found, displays
# the special page 'missing'.

sub display_page {
    my($name) = @_;
    my($page);

    $page = readin($name);
    if (defined $page) {
	html_header();
	print interpolate_html($page);
	return 1;
    } else {
	$page = readin('missing');
	die "Special page not found: 'missing'\n" unless defined $page;
	$page =~ s#\[subject\]#$name#ig;
	html_header();
	print interpolate_html($page);
	return 0;
    }
}

# Display the catalog page NAME.

sub do_page {
    my($name) = @_;

    display_page($name) and $Vend::Session->{'page'} = $name;
    write_and_close_session();
}


## DO ORDER

# Order an item with product code CODE.

sub do_order
{
    my($code) = @_;
    my($i, $found);

    if (!$Vend::Products{$code}) {
	logError("Attempt to order missing product code: $code\n");
	display_special_page('noproduct', $code);
	close_session();
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
    write_and_close_session();
}


## DO FINISH

# Finish an incomplete order.

sub do_finish {
    order_page();
    write_and_close_session();
}


## DO PROCESS

# Process the completed order page.

sub do_process {
    my($i, $quantity, $todo, $page, $key, $value);

    expect_form() || return;

    # Update the quantity ordered of each item.
    foreach $i (0 .. $#$Vend::Items) {
	$quantity = $CGI::values{"quantity$i"};
	if (defined($quantity) && $quantity =~ m/^\d+$/) {
	    $Vend::Items->[$i]->{'quantity'} = $quantity;
	} else {
	    interaction_error("Variable '$quantity' not passed from form\n");
	    close_session();
	    return;
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

    # Update the user-entered fields.
    while (($key, $value) = each %CGI::values) {
	next if ($key =~ m/^quantity\d+/);
	next if ($key eq 'todo');
	$Vend::Session->{'values'}->{$key} = $value;
    }

    $todo = $CGI::values{'todo'};
    if (!defined $todo) {
	interaction_error("Variable 'todo' not passed from form\n");
	close_session();
	return;
    }
    elsif ($todo eq 'submit') {
	my($ok);
	$ok = mail_order();
	@$Vend::Items = ();
	if ($ok) {
	    display_special_page("confirmation");
	} else {
	    display_special_page("failed");
	}
    } elsif ($todo eq 'return') {
	display_page($Vend::Session->{'page'});
    } elsif ($todo eq 'refresh') {
	order_page();
    } elsif ($todo eq 'cancel'){
	$page = $Vend::Session->{'page'};
	init_session();
	display_page($page);
    } else {
	interaction_error(
          "Form variable 'todo' value '$todo' not recognized\n");
	close_session();
	return;
    }

    write_and_close_session();
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
    } else {
	$r = "<no input box>";
    }
    $r;
}

sub order_report {
    my($seen) = @_;
    my($fn, $report, $values, $date);

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

    $date = `date`;
    chomp $date;
    $report =~ s#\$date#$date#ige;

    $values = $Vend::Session->{'values'};
    $report =~ s#\$(\w+)#report_field($1, $seen)#ge;

    $report;
}

sub order_list {
    my($body, $i, $item, $code, $quantity, $price);

    $body = <<'END';
Qty.     Item              Description                Price Each    Total
----  ----------  ----------------------------------  ----------  ----------
END

    foreach $i (0 .. $#$Vend::Items) {
	$item = $Vend::Items->[$i];
	$code = $item->{'code'};
	$quantity = $item->{'quantity'};
	$price = $Vend::Product_price{$code};
	$body .= sprintf( "%4s  %-10s  %-34s  %10s  %10s\n",
			 $quantity,
			 $code,
			 $Vend::Product_description{$code},
			 currancy($price),
			 currancy($quantity * $price) );
    }

    $body;
}

# Email the processed order.

sub mail_order {
    my($body, $i, $code, $ok, $seen, $blankline);
    my($values, $key, $value);

    $seen = {};
    $body = order_report($seen);
    return undef unless defined $body;

    $values = $Vend::Session->{'values'};
    $blankline = 0;
    while (($key, $value) = each %$values) {
	if (!$$seen{$key}) {
	    if (!$blankline) {
		$body .= "\n";
		$blankline = 1;
	    }
	    $body .= "$key: $value\n";
	}
    }

    $body .= "\n" . order_list();

    $ok = send_mail($Config::MailOrderTo, 'ORDER', $body);
    $ok;
}




## DISPATCH

# Parse the invoking URL and dispatch to the handling subroutine.

sub dispatch {
    my($query_string, $sessionid, $argument, $path, @path, $action);

    $query_string = $CGI::query_string;
    if (defined $query_string && $query_string ne '') {
	($sessionid, $argument) = split(/;/, $query_string);
    }

    if (defined $sessionid && $sessionid ne '') {
	$Vend::SessionID = $sessionid;
	open_session();
	read_session();
	if (time - $Vend::Session->{'time'} > $Config::SessionExpire) {
	    init_session();
	}
    } else {
	new_session();
    }

    $path = $CGI::path_info;

    # If the cgi-bin program was invoked with no extra path info,
    # just display the catalog page.
    if (!defined $path || $path eq '' || $path eq '/') {
	do_catalog();
	return;
    }

    @path = split('/', $path);
    shift @path if $path[0] eq '';
    $action = shift @path;
    #print Vend::DEBUG "action is $action\n";
    if    ($action eq 'order')    { do_order($argument);  }
    elsif ($action eq 'finish')   { do_finish();          }
    elsif ($action eq 'process')  { do_process();         }
    else {
	do_page(join('/', $action, @path));
    }
}

## DEBUG

sub dontwarn {
    $LOCK::shared +
    $LOCK::nonblocking +
    $Config::VendURL +
    $Config::PageDir +
    $Config::MailOrderTo +
    $Config::Finish_order +
    $Config::OrderReport +
    $Config::Shipping +
    $Config::ReadPermission +
    $Config::WritePermission +
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
	$CGI::values{$key} = $value;
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

    $CGI::request_method = $ENV{'REQUEST_METHOD'};
    die "REQUEST_METHOD is not defined" unless defined $CGI::request_method;

    $CGI::path_info = $ENV{'PATH_INFO'};
    die "PATH_INFO is not defined" unless defined $CGI::path_info;

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
        #dump_post();
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
	} elsif (m/^-t(est)?$/i) {
	    $Vend::mode = 'test';
	} elsif (m/^-e(xpire)?$/i) {
	    $Vend::mode = 'expire';
	} elsif (m/^-dump-sessions$/i) {
	    $Vend::mode = 'dump-sessions';
	} else {
	    die "Unknown command line option: $_\n" .
		"(Use -help for a list).\n";
	}
    }
}

sub version {
    print "Vend version 0.2 Copyright 1995 Andrew M. Wilcox\n";
}

sub usage {
    version();
    print <<'END';

Vend comes with ABSOLUTELY NO WARRANTY.  This is free software, and
you are welcome to redistribute and modify it under the terms of the
GNU General Public License.

Command line options:

     -config <file>   specify configuration file
     -test            report problems with config file
     -version         display program version
     -expire          expire old sessions
END
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
    if (defined $ENV{'GATEWAY_INTERFACE'}) {
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
	undef $Vend::mode;	# mode will be set by options
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
	read_products();
	dispatch();
    } elsif ($Vend::mode eq 'expire') {
	expire_sessions();
    } elsif ($Vend::mode eq 'dump-sessions') {
	dump_sessions();
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
