# $Id: Config.pm,v 1.4 1996/05/25 07:06:03 mike Exp mike $

package Vend::Config;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(

config

);

use strict;
use Carp;
use Vend::Util;
use Vend::Data 'import_database';

for( qw(search refresh cancel secure unsecure submit control checkout) ) {
	$Config::LegalAction{$_} = 1;
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

# Sets a boolean array for any type of item, currently only
# AlwaysSecure
sub parse_boolean {
	my($item,$settings) = @_;
	my(@setting) = split /\s*,\s*/, $settings;
	return 0 unless @setting;
	no strict 'refs';
	for (@setting) {
		${"Config::$item"}{$_} = 1;
	}
	1;
}


# Adds an action to the Action Map
# Deletes if the action is delete
sub parse_action {
	my($item,$setting) = @_;
	return '' unless $setting;
	my($action,$string) = split /\s+/, $setting, 2;
	$action = lc $action;
	return delete $Config::ActionMap{$string} if $action eq 'delete';
	$Config::ActionMap{$string} = $action;
	config_error("Unrecognized action '$action'")
		unless $Config::LegalAction{$action};
}

# Sets the special page array
sub parse_special {
	my($item,$settings) = @_;
	my(%setting) = split /\s+/, $settings;
	for (keys %setting) {
		$Config::Special{$_} = $setting{$_};
	}
	1;
}

sub parse_array {
	my($item,$settings) = @_;
	my(@setting) = split /[\s,]+/, $settings;
	return 0 unless @setting;
	no strict 'refs';
	for (@setting) {
		push @{"Config::$item"}, $_;
	}
	1;
}

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

sub parse_valid_page {
    my($var, $value) = @_;
    my($page,$x);

	return $value if !$Config::PageCheck;

	if( ! defined $value or $value eq '') {
		return $value;
	}

    config_error("Can't find valid page ('$value') for the $var directive\n")
		unless -s "$Config::PageDir/$value.html";
    $value;
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

sub parse_database {
	my ($var, $value) = @_;
	my $num = ! defined $Config::Database ? 0 : $Config::Database;
	return $num unless (defined $value && $value); 

	my($database,$file,$type) = split /[\s,]+/, $value, 3;
	$file = $database unless defined $file;

	$Vend::Database{$database} = import_database($file,$type);
	return ++$num;
}

sub parse_profile {
	my ($var, $value) = @_;
	return '' unless (defined $value && $value); 
	my (@files) = split /[\s,]+/, $value;
	for(@files) {
		push @Config::SearchProfile, readfile($_);
	}
	return $value;
}

sub parse_buttonbar {
	my ($var, $value) = @_;
	return '' unless (defined $value && $value); 
	@Config::ButtonBar[0..15] = get_files(split /\s+/, $value);
	return $value;
}

sub parse_delimiter {
	my ($var, $value) = @_;

	return "\t" unless (defined $value && $value); 
	
	$value =~ /^CSV$/i and return 'CSV';
	$value =~ /^tab$/i and return "\t";
	$value =~ /^pipe$/i and return "\|";
	$value =~ s/^\\// and return $value;
	$value =~ s/^'(.*)'$/$1/ and return $value;
	return quotemeta $value;
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
	['DataDir',          'relative_dir',     'products'],
	['Delimiter',        'delimiter',        'TAB'],
    ['PageCheck',		 'yesno',     	     'no'],
    ['SpecialPage',		 'special',     	 ''],
    ['ActionMap',		 'action',	     	 ''],
	['VendURL',          'url',              undef],
	['SecureURL',        'url',              undef],
	['OrderReport',      'valid_page',       'report'],
	['ScratchDir',       'relative_dir',     'etc'],
    ['DisplayErrors',    'yesno',            'Yes'],
	['SessionDatabase',  'relative_dir',     'session'],
	['Database',  		 'database',     	 ''],
	['WritePermission',  'permission',       'user'],
	['ReadPermission',   'permission',       'user'],
	['SessionExpire',    'time',             '1 day'],
	['MailOrderTo',      undef,              undef],
	['SendMailProgram',  'executable',       $Config::SendMailLocation],
    ['Glimpse',          'executable',       ''],
    ['RequiredFields',   undef,              ''],
    ['ReceiptPage',      'valid_page',       ''],
    ['ReportIgnore',     undef, 			 'credit_card_no,credit_card_exp'],
    ['OrderCounter',	 undef,     	     ''],
    ['UseCode',		 	 undef,     	     'yes'],
    ['PriceBreaks',	 	 'array',  	     	 ''],
    ['PriceDivide',	 	 undef,  	     	 1],
    ['MixMatch',		 'yesno',     	     'No'],
    ['AlwaysSecure',	 'boolean',  	     ''],
    ['ExtraSecure',		 'yesno',     	     'No'],
    ['Cookies',			 'yesno',     	     'No'],
    ['TaxShipping',		 undef,     	     ''],
    ['NonTaxableField',  undef,     	     ''],
    ['HammerLock',		 undef,     	     30],
    ['CreditCards',		 'yesno',     	     'No'],
    ['EncryptProgram',	 undef,     	     ''],
    ['AsciiTrack',	 	 undef,     	     ''],
    ['AsciiBackend',	 undef,     	     ''],
    ['Tracking',		 undef,     	     ''],
    ['BackendOrder',	 undef,     	     ''],
    ['SalesTax',		 undef,     	     ''],
    ['CustomShipping',	 undef,     	     ''],
    ['DefaultShipping',	 undef,     	     'default'],
    ['DebugMode',		 undef,     	     0],
    ['SearchProfile',	 'profile',     	 ''],
    ['MultiServer',		 undef,     	     0],
    ['PriceCommas',		 undef,     	     'yes'],
    ['ItemLinkDir',	 	 undef,     	     ''],
    ['SearchOverMsg',	 undef,           	 ''],
	['SecureOrderMsg',   undef,              'Use Order Security'],
    ['SearchFrame',	 	 undef,     	     '_self'],
    ['OrderFrame',	     undef,              '_top'],
    ['CheckoutFrame',	 undef,              '_top'],
    ['CheckoutPage',	 'valid_page',       'order'],
    ['FrameOrderPage',	 'valid_page',       ''],
    ['FrameSearchPage',	 'valid_page',       ''],
    ['DescriptionTrim',  undef,              ''],
    ['DescriptionField', undef,              'description'],
    ['PriceField',		 undef,              'price'],
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
	['ButtonBars',      'buttonbar',         ''],
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

1;
