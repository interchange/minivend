# Config.pm - Configure Interchange
#
# $Id$
#
# Copyright (C) 1996-2000 Akopia, Inc. <info@akopia.com>
#
# This program was originally based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
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
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA.

package Vend::Config;
require Exporter;

@ISA = qw(Exporter);

@EXPORT		= qw( config global_config );

@EXPORT_OK	= qw( get_catalog_default get_global_default parse_time parse_database);

my $OldDirectives = q{
	AdminDatabase
	AdminPage
	AsciiBackend
	BackendOrder
	ButtonBars
	CheckoutFrame
	CheckoutPage
	DataDir
	Delimiter
	DescriptionTrim
	DebugMode
	FieldDelimiter
	FrameFlyPage
	FrameLinkDir
	FrameOrderPage
	FrameSearchPage
	ItemLinkDir
	ItemLinkValue
	MsqlDB
	MsqlProducts
	Mv_AlinkColor
	Mv_Background
	Mv_BgColor
	Mv_LinkColor
	Mv_TextColor
	Mv_VlinkColor
    NewEscape
	NewReport
	NewTags
	OldShipping
	OrderFrame
	PageCache
	PriceDatabase
	Random
	ReceiptPage
	RecordDelimiter
	ReportIgnore
    RetireDBM
	Rotate
    SearchCache
	SearchFrame
	SearchOverMsg
	SecureOrderMsg
	SpecialFile
	SubArgs
	TolerateGet
    TransparentItem
	Tracking
};

use strict;
use vars qw(
			$VERSION $C $CanTie
			@Locale_directives_ary @Locale_directives_scalar
			@Locale_directives_currency @Locale_keys_currency
			);
use Safe;
use Fcntl;
use Vend::Parse;
use Vend::Util;

BEGIN {
	eval {
		require Tie::Watch or die;
		$CanTie = 1;
	};
}

$VERSION = substr(q$Revision$, 10);

my %CDname;

for( qw(search refresh cancel return secure unsecure submit control checkout) ) {
	$Global::LegalAction{$_} = 1;
}

@Locale_directives_currency = (
qw/
		CommonAdjust
		PriceCommas
		PriceDivide
		PriceField
		PriceDefault
		SalesTax
		TaxShipping

/	);

@Locale_keys_currency = (
qw/
	currency_symbol
	frac_digits
	int_curr_symbol
	int_frac_digits
	mon_decimal_point
	mon_grouping
	price_picture
	mon_thousands_sep
	n_cs_precedes
	negative_sign
	p_cs_precedes
	p_sep_by_space
	positive_sign

/   );

@Locale_directives_scalar = (
qw/
		Autoload
		AutoEnd
		CommonAdjust
		DescriptionField
		ImageDir
		ImageDirSecure
		PageDir
		SpecialPageDir
		PriceDivide
		PriceCommas
		PriceField
		PriceDefault
		SalesTax
		StaticPath
		HTMLsuffix
		TaxShipping

/   );

@Locale_directives_ary = (
qw/
	PriceAdjustment
	ProductFiles
	UseModifier
	AutoModifier
/   );

my %DumpSource = (qw(
					SpecialPage			1
				));

my %DontDump = (qw(
					GlobalSub			1
					SpecialPage			1
				));

my %UseExtended = (qw(
					Catalog				1
					SubCatalog			1
					Variable			1
				));

my $configfile;

# Report a fatal error in the configuration file.
sub config_error {
    my($msg) = @_;

	if($msg =~ /unknown\s+directive\s+'(\w+)/i) {
		my $check = $1;
		if($OldDirectives =~ /\b$check\b/i) {
			warn "MiniVend 3.x directive '$check' ignored at line $. of $configfile.\n";
			return 1;
		}
	}
	$msg = errmsg("%s\nIn line %s of the configuration file '%s':\n%s\n",
			$msg,
			$.,
			$configfile,
			$Vend::config_line,
	);
    if ($Vend::ExternalProgram) {
		warn "$msg\n" unless $Vend::Quiet;
	}
	else {
		::logGlobal({level => 'warn'}, $msg);
		die "$msg\n";
	}
}

sub config_warn {
    my($msg) = @_;

    ::logGlobal({level => 'notice'},
				errmsg("%s\nIn line %s of the configuration file '%s':\n%s\n",
						$msg,
						$.,
						$configfile,
						$Vend::config_line,
				)
	);
}

sub setcat {
	$C = $_[0] || $Vend::Cfg;
}

sub global_directives {

	my $directives = [
#   Order is not really important, catalogs are best first

#   Directive name      Parsing function    Default value

	['ConfigDir',		  undef,	         'etc/lib'],
	['ConfigDatabase',	 'config_db',	     ''],
	['ConfigAllBefore',	 'array',	         "$Global::VendRoot/catalog_before.cfg"],
	['ConfigAllAfter',	 'array',	         "$Global::VendRoot/catalog_after.cfg"],
    ['Message',          'message',           ''],
    ['VarName',          'varname',           ''],
    ['DumpStructure',	 'yesno',     	     'No'],
    ['DisplayErrors',    'yesno',            'No'],
    ['TcpPort',          'warn',             ''],
    ['TcpMap',           'hash',             ''],
	['Environment',      'array',            ''],
    ['TcpHost',           undef,             'localhost 127.0.0.1'],
	['SendMailProgram',  'executable',		$Global::SendMailLocation
												|| '/usr/lib/sendmail'],
	['PIDfile',     	  undef,             "$Global::VendRoot/etc/$Global::ExeName.pid"],
	['SocketFile',     	  undef,             "$Global::VendRoot/etc/socket"],
	['SocketPerms',      'integer',          0600],
	['HouseKeeping',     'integer',          60],
	['Mall',	          'yesno',           'No'],
	['ActionMap',		 'action',			 ''],
	['FormAction',		 'action',			 ''],
	['MaxServers',       'integer',          10],
	['GlobalSub',		 'subroutine',       ''],
	['Database',		 'database',         ''],
	['FullUrl',			 'yesno',            'No'],
	['Locale',			 'locale',            ''],
	['HitCount',		 'yesno',            'No'],
	['IpHead',			 'yesno',            'No'],
	['IpQuad',			 'integer',          '1'],
	['TemplateDir',      'root_dir', 	     ''],
	['DomainTail',		 'yesno',            'Yes'],
	['SafeSignals',	 	 'warn',             ''],
	['AcrossLocks',		 'yesno',            'No'],
	['PIDcheck',		 'integer',          '0'],
    ['LockoutCommand',    undef,             ''],
    ['SafeUntrap',       'array',            'ftfile sort'],
	['NoAbsolute',		 'yesno',			 'No'],
	['AllowGlobal',		 'boolean',			 ''],
	['AddDirective',	 'directive',		 ''],
	['UserTag',			 'tag',				 ''],
	['AdminSub',		 'boolean',			 ''],
	['AdminUser',		  undef,			 ''],
	['AdminHost',		  undef,			 ''],
    ['HammerLock',		 'integer',     	 30],
    ['DebugMode',		 'warn',     	     ''],
    ['DebugFile',		  undef,     	     ''],
    ['ErrorFile',		  undef,     	     undef],
    ['SysLog',			 'hash',     	     undef],
    ['CheckHTML',		  undef,     	     ''],
	['Variable',	  	 'variable',     	 ''],
	['Profiles',	  	 'profile',     	 ''],
    ['Catalog',			 'catalog',     	 ''],
    ['SubCatalog',		 'catalog',     	 ''],

    ];
	return $directives;
}


sub catalog_directives {

	my $directives = [
#   Order is somewhat important, the first 6 especially

#   Directive name      Parsing function    Default value

	['ErrorFile',        undef,              'error.log'],
	['ActionMap',		 'action',			 ''],
	['FormAction',		 'action',			 ''],
	['PageDir',          'relative_dir',     'pages'],
	['SpecialPageDir',   undef,     		 'special_pages'],
	['ProductDir',       'relative_dir',     'products'],
	['OfflineDir',       'relative_dir',     'offline'],
	['ConfigDir',        'relative_dir',	 'config'],
	['TemplateDir',      'dir_array', 		 ''],
	['ConfigDatabase',	 'config_db',	     ''],
	['Require',			 'require',			 ''],
    ['Message',          'message',           ''],
	['Variable',	  	 'variable',     	 ''],
	['ScratchDefault',	 'hash',     	 	 ''],
	['Profile',			 'hash',     	 	 ''],
	['ValuesDefault',	 'hash',     	 	 ''],
    ['ProductFiles',	 'array_complete',  'products'],
    ['DisplayErrors',    'yesno',            'No'],
    ['ParseVariables',	 'yesno',     	     'No'],
    ['SpecialPage',		 'special',     	 'order ord/basket results results search results flypage flypage'],
	['Sub',				 'subroutine',       ''],
	['VendURL',          'url',              undef],
	['SecureURL',        'url',              undef],
	['History',          'integer',          0],
	['OrderReport',      undef,       'etc/report'],
	['ScratchDir',       'relative_dir',     'tmp'],
	['SessionDB',  		 undef,     		 ''],
	['SessionType', 	 undef,     		 'File'],
	['SessionDatabase',  'relative_dir',     'session'],
	['SessionLockFile',  undef,     		 'etc/session.lock'],
	['Database',  		 'database',     	 ''],
	['Autoload',		 undef,		     	 ''],
	['AutoEnd',			 undef,		     	 ''],
	['Replace',			 'replace',     	 ''],
	['Member',		  	 'variable',     	 ''],
	['WritePermission',  'permission',       'user'],
	['ReadPermission',   'permission',       'user'],
	['SessionExpire',    'time',             '1 hour'],
	['SaveExpire',       'time',             '30 days'],
	['MailOrderTo',      undef,              undef],
	['SendMailProgram',  'executable',		$Global::SendMailProgram],
	['PGP',              undef,       		 ''],
# GLIMPSE
    ['Glimpse',          'executable',       ''],
# END GLIMPSE
 	['Locale',           'locale',           ''],
    ['Route',            'locale',           ''],
	['LocaleDatabase',    undef,             ''],
	['DbDatabase',        'dbdatabase',        ''],
	['RouteDatabase',     'routeconfig',        ''],
	['DirectiveDatabase', 'dbconfig',        ''],
	['VariableDatabase',  'dbconfig',        ''],
    ['RequiredFields',   undef,              ''],
    ['NoSearch',         'wildcard',         'userdb'],
    ['OrderCounter',	 undef,     	     ''],
    ['ImageAlias',	 	 'hash',     	     ''],
    ['TableRestrict',	 'hash',     	     ''],
    ['Filter',		 	 'hash',     	     ''],
    ['ImageDirSecure',   undef,     	     ''],
    ['ImageDirInternal', undef,     	     ''],
    ['ImageDir',	 	 undef,     	     ''],
    ['UseCode',		 	 undef,     	     'yes'],
    ['SetGroup',		 'valid_group',      ''],
    ['UseModifier',		 'array',     	     ''],
    ['AutoModifier',	 'array',     	     ''],
    ['LogFile', 		  undef,     	     'etc/log'],
    ['Pragma',		 	 'boolean',     	 ''],
    ['DynamicData', 	 'boolean',     	 ''],
    ['NoImport',	 	 'boolean',     	 ''],
    ['NoImportExternal', 'yesno',	     	 'no'],
    ['CommonAdjust',	 undef,  	     	 ''],
    ['PriceAdjustment',	 'array',  	     	 ''],
    ['PriceBreaks',	 	 'array',  	     	 ''],
    ['PriceDivide',	 	 undef,  	     	 1],
    ['PriceCommas',		 'yesno',     	     'Yes'],
    ['MixMatch',		 'yesno',     	     'No'],
    ['DifferentSecure',	 'boolean',  	     ''],
    ['AlwaysSecure',	 'boolean',  	     ''],
	['Password',         undef,              ''],
    ['ExtraSecure',		 'yesno',     	     'No'],
    ['FallbackIP',		 'yesno',     	     'No'],
    ['WideOpen',		 'yesno',     	     'No'],
    ['Cookies',			 'yesno',     	     'Yes'],
	['CookieLogin',      'yesno',            'No'],
	['CookieDomain',     undef,              ''],
    ['MasterHost',		 undef,     	     ''],
    ['UserTag',			 'tag', 	    	 ''],
    ['RemoteUser',		 undef,     	     ''],
    ['TaxShipping',		 undef,     	     ''],
	['FractionalItems',  'yesno',			 'No'],
	['SeparateItems',    'yesno',			 'No'],
    ['PageSelectField',  undef,     	     ''],
    ['NonTaxableField',  undef,     	     ''],
    ['CyberCash',	 	 'yesno',     	     'No'],
    ['CreditCardAuto',	 'yesno',     	     'No'],
    ['NoCache',	     	 'boolean',    	     ''],
    ['ClearCache',	     'yesno',     	     'No'],
    ['FormIgnore',	     'boolean',    	     ''],
    ['EncryptProgram',	 undef,     	     ''],
    ['AsciiTrack',	 	 undef,     	     ''],
    ['TrackFile',	 	 undef,     	     ''],
    ['SalesTax',		 undef,     	     ''],
    ['SalesTaxFunction', undef,     	     ''],
    ['StaticDBM',  	 	 undef,     	     ''],
    ['Static',   	 	 'yesno',     	     'No'],
    ['StaticAll',		 'yesno',     	     'No'],
    ['StaticDepth',		 undef,     	     '1'],
    ['StaticFly',		 'yesno',     	     'No'],
    ['StaticLogged',	 'yesno',     	     'No'],
    ['StaticDir',		 undef,     	     ''], 
	['UserDB',			 'locale',	     	 ''], 
	['UserDatabase',	 undef,		     	 ''],  #undocumented
    ['RobotLimit',		 'integer',		      0],
    ['OrderLineLimit',	 'integer',		      0],
    ['StaticPage',		 'boolean',     	 ''],
    ['StaticPath',		 undef,     	     '/'],
    ['StaticPattern',	 'regex',     	     ''],
    ['StaticSuffix',	 undef,     	     '.html'],
    ['HTMLsuffix',	     undef,     	     '.html'],
    ['CustomShipping',	 undef,     	     ''],
    ['DefaultShipping',	 undef,     	     'default'],
    ['UpsZoneFile',		 undef,     	     ''],
    ['OrderProfile',	 'profile',     	 ''],
    ['SearchProfile',	 'profile',     	 ''],
    ['OnFly',		 	 undef,     	     ''],
    ['HTMLmirror',		 'yesno',            'No'],
    ['DescriptionField', undef,              'description'],
    ['PriceDefault',	 undef,              'price'],
    ['PriceField',		 undef,              'price'],
	['Shipping',         'locale',           ''],
    ['IPC',		 		 'array',     	 	 ''],
    ['IPCmode',		 	 'integer',    	 	 '0777'],
    ['IPCdir',		 	 undef,    	 	     ''],

    ];

	push @$directives, @$Global::AddDirective
		if $Global::AddDirective;
	return $directives;
}

sub set_directive {
    my ($directive, $value, $global) = @_;
    my $directives;

	if($global)	{ $directives = global_directives(); }
	else		{ $directives = catalog_directives(); }

    my ($d, $dir, $parse);
    no strict 'refs';
    foreach $d (@$directives) {
        next unless (lc $directive) eq (lc $d->[0]);
        if (defined $d->[1]) {
            $parse = 'parse_' . $d->[1];
        } else {
            $parse = undef;
        }
        $dir = $d->[0];
        $value = &{$parse}($dir, $value)
            if defined $parse;
        last;
    }
    return [$dir, $value] if defined $dir;
    return undef;
}


sub get_catalog_default {
	my ($directive) = @_;
	my $directives = catalog_directives();
	my $value;
	for(@$directives) {
		next unless (lc $directive) eq (lc $_->[0]);
		$value = $_->[2];
	}
	return undef unless defined $value;
	return $value;
}

sub get_global_default {
	my ($directive) = @_;
	my $directives = global_directives();
	my $value;
	for(@$directives) {
		next unless (lc $directive) eq (lc $_->[0]);
		$value = $_->[2];
	}
	return undef unless defined $value;
	return $value;
}

sub evaluate_ifdef {
	my ($ifdef, $reverse, $global) = @_;
#::logDebug("ifdef '$ifdef'");
	my $status;
	$ifdef =~ /^\s*(\@?)(\w+)\s*(.*)/;
	$global = $1 || $global || undef;
	my $var  = $2;
	my $cond = $3;
	my $var_ref = ! $global ? $C->{Variable} : $Global::Variable;
#::logDebug("Variable value '$var_ref->{$var}'");
	if (! $cond) {
		$status = ! (not $var_ref->{$var});
	}
	elsif ($cond) {
		my $val = $var_ref->{$var} || '';
		my $safe = new Safe;
		my $code = "q{$val}" . " " . $cond;
		$status = $safe->reval($code);
		if($@) {
			config_warn(
				errmsg("Syntax error in ifdef evaluation at line %s of %s",
						$.,
						$configfile,
					),
			);
			$status = '';
		}
	}
#::logDebug("ifdef status '$status', reverse=" . !(not $reverse));
	return $reverse ? ! $status : $status;
}

# This is what happens when ParseVariables is true
sub substitute_variable {
	my($val) = @_;
	# Return after globals so can others can be contained
	$val =~ s/\@\@([A-Z][A-Z_0-9]+[A-Z0-9])\@\@/$Global::Variable->{$1}/g
		and return $val;
	return $val unless $val =~ /([_%])\1/;
	1 while $val =~ s/__([A-Z][A-Z_0-9]*?[A-Z0-9])__/$C->{Variable}->{$1}/g;
	# YALOS (yet another level)
	return $val unless $val =~ /%%[A-Z]/;
	$val =~ s/%%([A-Z][A-Z_0-9]+[A-Z0-9])%%/$Global::Variable->{$1}/g;
	$val =~ s/__([A-Z][A-Z_0-9]*?[A-Z0-9])__/$C->{Variable}->{$1}/g;
	return $val;
}

# Parse the configuration file for directives.  Each directive sets
# the corresponding variable in the Vend::Cfg:: package.  E.g.
# "DisplayErrors No" in the config file sets Vend::Cfg->{DisplayErrors} to 0.
# Directives which have no defined default value ("undef") must be specified
# in the config file.

sub config {
	my($catalog, $dir, $confdir, $subconfig) = @_;
    my($directives, $d, %parse, $var, $value, $lvar, $parse);
    my($directive);
	%CDname = ();
	$C = {};
	$C->{CatalogName} = $catalog;
	$C->{VendRoot} = $dir;
	$C->{ConfDir} = $confdir;

	unless (defined $subconfig) {
		$C->{ErrorFile} = 'error.log';
		$C->{ConfigFile} = 'catalog.cfg';
	}
	else {
        $C->{ConfigFile} = "$catalog.cfg";
		$C->{BaseCatalog} = $subconfig;
	}

    no strict 'refs';

    $directives = catalog_directives();

	foreach $d (@$directives) {
		($directive = $d->[0]) =~ tr/A-Z/a-z/;
		$CDname{$directive} = $d->[0];
		if (defined $d->[1]) {
			$parse = 'parse_' . $d->[1];
		} else {
			$parse = undef;
		}
		$parse{$directive} = $parse;

		# We don't set up defaults if it is a subconfiguration
		next if defined $subconfig;

		$value = ( 
					! defined $MV::Default{$catalog} or
					! defined $MV::Default{$catalog}{$d->[0]}
				 )
				 ? $d->[2]
				 : $MV::Default{$catalog}{$d->[0]};

		if (defined $parse and defined $value and ! defined $subconfig) {
			$value = &$parse($d->[0], $value);
		}
		$C->{$CDname{$directive}} = $value;
	}

	my(@include) = ($C->{ConfigFile});
	my $done_one;
	my ($db, $dname, $nm);
	my ($before, $after);
	my $recno = 'C0001';

	my @hidden_config;
	@hidden_config = grep -f $_, 
							 "$C->{CatalogName}.site",
							 "$Global::ConfDir/$C->{CatalogName}.before",
							 @{$Global::ConfigAllBefore},
						 ;

	# Backwards because of unshift;
	for (@hidden_config) {
		unshift @include, $_;
	}

	@hidden_config = grep -f $_, 
							 "$Global::ConfDir/$C->{CatalogName}.after",
							 @{$Global::ConfigAllAfter},
						 ;

	for (@hidden_config) {
		push @include, $_;
	}

	# %MV::Default holds command-line mods to config, which we write
	# to a file for easier processing 
	if(defined $MV::Default{$catalog}) {
		my $fn = "$Global::ConfDir/$catalog.cmdline";
		open(CMDLINE, ">$fn")
			or die "Can't create cmdline configfile $fn: $!\n";
		for(@{$MV::DefaultAry{$catalog}}) {
			my ($d, $v) = split /\s+/, $_, 2;
			if($v =~ /\n/) {
				$v = "<<EndOfMvD\n$v\nEndOfMvD\n";
			}
			else {
				$v .= "\n";
			}
			printf CMDLINE '%-19s %s', $d, $v;
		}
		close CMDLINE;
		push @include, $fn;
	}

	# Create closure that reads and sets config values
	my $read = sub {
		my ($lvar, $value, $tie) = @_;
		$parse = $parse{$lvar};
					# call the parsing function for this directive
		if($C->{ParseVariables} and $value =~ /([_%@])\1/) {
			save_variable($CDname{$lvar}, $value);
			$value = substitute_variable($value);
		}
		$value = &$parse($CDname{$lvar}, $value) if defined $parse and ! $tie;
		# and set the $C->directive variable
		if($tie) {
			watch ( $CDname{$lvar}, $value );
		}
		else {
			$C->{$CDname{$lvar}} = $value;
		}
	};

#print "include starts with @include\n";
CONFIGLOOP:
	while ($configfile = shift @include) {
		my $tellmark;
		if(ref $configfile) {
			($configfile, $tellmark)  = @$configfile;
#print "recalling $configfile (pos $tellmark)\n";
		}

	# See if anything is defined in options to do before the
	# main configuration file.  If there is a file, then we
	# will do it (after pushing the main one on @include).
	
    -f $configfile && open(CONFIG, "< $configfile")
		or do {
			my $msg = "Could not open configuration file '" . $configfile .
					"' for catalog '" . $catalog . "':\n$!";
			if(defined $done_one) {
				warn "$msg\n";
				open (CONFIG, '');
			}
			else {
				die "$msg\n";
			}
		};
	seek(CONFIG, $tellmark, 0) if $tellmark;
#print "seeking to $tellmark in $configfile, include is @include\n";
	my ($ifdef, $begin_ifdef);
    while(<CONFIG>) {
		chomp;			# zap trailing newline,
		if(/^#endif\s*$/) {
			undef $ifdef;
			undef $begin_ifdef;
			next;
		}
		if(/^#if(n?)def\s+(.*)/) {
			if(defined $ifdef) {
				config_error("Can't overlap #ifdef at line $. of $configfile");
			}
			$ifdef = evaluate_ifdef($2,$1);
			$begin_ifdef = $.;
			next;
		}
		if(defined $ifdef) {
			next unless $ifdef;
		}
		if(/^\s*#include\s+(.+)/) {
			my $spec = $1;
			my $ref = [ $configfile, tell(CONFIG)];
#print "saving config $configfile (pos $ref->[1])\n";
			#unshift @include, [ $configfile, tell(CONFIG) ];
			unshift @include, $ref;
			close CONFIG;
			unshift @include, grep -f $_, glob($spec);
			next CONFIGLOOP;
		}
		my $tie = undef;
		s/^\s*#.*//;    # comments,
		s/\s+$//;		#  trailing spaces
		next if $_ eq '';
		$Vend::config_line = $_;
		# lines read from the config file become untainted
		m/^(\w+)\s+(.*)/ or config_error("Syntax error");
		$var = $1;
		$value = $2;
		($lvar = $var) =~ tr/A-Z/a-z/;
		my($codere) = '[-\w_#/.:]+';

		if ($value =~ /^(.*)<<(\w+)\s*/) {                  # "here" value
			my $begin  = $1 || '';
			$begin .= "\n" if $begin;
			my $mark  = $2;
			my $startline = $.;
			$value = $begin . read_here(\*CONFIG, $mark);
			unless (defined $value) {
				config_error (sprintf('%d: %s', $startline,
					qq#no end marker ("$mark") found#));
			}
		}
		elsif ($value =~ /^(.*)<&(\w+)\s*/) {                # "here sub" value
			my $begin  = $1 || '';
			$begin .= "\n" if $begin;
			my $mark  = $2;
			my $startline = $.;
			$value = $begin . read_here(\*CONFIG, $mark);
			unless (defined $value) {
				config_error (sprintf('%d: %s', $startline,
					qq#no end marker ("$mark") found#));
			}
			if ($CanTie) {
				$tie = 1;
			}
			else {
				config_warn errmsg(
					"No Tie::Watch module installed at %s, setting %s to default.",
								$startline,
								$var,
							);
				$value = '';
			}
		}
		elsif ($value =~ /^(\S+)?(\s*)?<\s*($codere)$/o) {   # read from file
			$value = $1 || '';
			my $file = $3;
			$value .= "\n" if $value;
			unless (defined $C->{ConfigDir}) {
				config_error
					("$CDname{$lvar}: Can't read from file until ConfigDir defined");
			}
			$file = $CDname{$lvar} unless $file;
			if($Global::NoAbsolute) {
				config_error(<<EOF) if Vend::Util::file_name_is_absolute($file);
Absolute filenames not allowed if NoAbsolute set. Contact administrator.
EOF
				config_error(
			  "No leading ../.. allowed if NoAbsolute set. Contact administrator.\n")
					if $file =~ m#^\.\./.*\.\.#;
				config_error(
			  "Symbolic links not allowed if NoAbsolute set. Contact administrator.\n")
					if -l $file;
			}
			$file = "$C->{ConfigDir}/$file"
				unless Vend::Util::file_name_is_absolute($file);
			$file = escape_chars($file);			# make safe for filename
			my $tmpval = readfile($file);
			unless( defined $tmpval ) {
				config_warn errmsg(
						"%s: read from non-existent file %s, skipping.",
						$CDname{$lvar},
						$file,
						);
				next;
			}
			chomp($tmpval) unless $tmpval =~ m!.\n.!;
			# untaint
			$tmpval =~ /([\000-\377]*)/;
			$value .= $1;
		}
			
		# Now we can give an unknown error
		config_error("Unknown directive '$var'"), next unless defined $CDname{$lvar};

		# Use our closure defined above
		&$read($lvar, $value, $tie);

		# If we have passed off configuration to a database we stop here...
		last if $C->{ConfigDatabase}->{ACTIVE};

		# See if we want to load the config database
		if(! $db and $C->{ConfigDatabase}->{LOAD}) {
			$db = $C->{ConfigDatabase}->{OBJECT}
				or config_error(
					"ConfigDatabase $C->{ConfigDatabase}->{'name'} not active.");
			$dname = $C->{ConfigDatabase}{name};
		}

		# Actually load ConfigDatabase if present
		if($db) {
			$nm = $CDname{$lvar};
			my ($extended, $status);
			undef $extended;

			# set directive name
			$status = Vend::Data::set_field($db, $recno, 'directive', $nm);
			config_error("ConfigDatabase failed for $dname, field 'directive'")
				unless defined $status;

			# use extended value field if necessary or directed
			if (length($value) > 250 or $UseExtended{$nm}) {
				$extended = $value;
				$extended =~ s/(\S+)\s*//;
				$value = $1 || '';
				$status = Vend::Data::set_field($db, $recno, 'extended', $extended);
				config_error("ConfigDatabase failed for $dname, field 'extended'")
					unless defined $status;
			}

			# set value -- just a name if extended was used
			$status = Vend::Data::set_field($db, $recno, 'value', $value);
			config_error("Configdatabase failed for $dname, field 'value'")
				unless defined $status;

			$recno++;
		}
		
    }
	$done_one = 1;
    close CONFIG;

	# See if we have an active configuration database
	if($C->{ConfigDatabase}->{ACTIVE}) {
		my ($key,$value,$dir,@val);
		my $name = $C->{ConfigDatabase}->{name};
		$db = $C->{ConfigDatabase}{OBJECT} or 
			config_error("ConfigDatabase called ACTIVE with no database object.\n");
		my $items = $db->array_query("select * from $name order by code");
		my $one;
		foreach $one ( @$items ) {
			($key, $dir, @val) = @$one;
			$value = join " ", @val;
			$value =~ s/\s/\n/ if $value =~ /\n/;
			$value =~ s/^\s+//;
			$value =~ s/\s+$//;
			$lvar = lc $dir;
			&$read($lvar, $value);
		}
	}

	# We need to make this directory if it isn't already there....
	if($C->{ScratchDir} and ! -e $C->{ScratchDir}) {
		mkdir $C->{ScratchDir}, 0700
			or die "Can't make temporary directory $C->{ScratchDir}: $!\n";
	}

	if(defined $ifdef) {
		config_error("Failed to close #ifdef on line $begin_ifdef.");
	}

} # end CONFIGLOOP

    # check for unspecified directives that don't have default values

	# but set some first if appropriate
	set_defaults();

	REQUIRED: {
		last REQUIRED if defined $subconfig;
		last REQUIRED if defined $Vend::ExternalProgram;
		foreach $var (keys %CDname) {
			if (! defined $C->{$CDname{$var}}) {
				my $msg = errmsg(
					"Please specify the %s directive in the configuration file '%s'",
					$CDname{$var},
					$configfile,
				);

				die "$msg\n";
			}
		}
	}
	# Ugly legacy stuff so API won't break
	$C->{Special} = $C->{SpecialPage} if defined $C->{SpecialPage};
	%CDname = ();
	return $C;
}

sub read_here {
	my($handle, $marker) = @_;
	my $foundeot = 0;
	my $startline = $.;
	my $value = '';
	while (<$handle>) {
		if ($_ =~ m{^$marker$}) {
			$foundeot = 1;
			last;
		}
		$value .= $_;
	}
    return undef unless $foundeot;
	#untaint
	$value =~ /([\000-\377]*)/;
	$value = $1;
	return $value;
}

# Parse the global configuration file for directives.  Each directive sets
# the corresponding variable in the Global:: package.  E.g.
# "DisplayErrors No" in the config file sets Global::DisplayErrors to 0.
# Directives which have no default value ("undef") must be specified
# in the config file.

sub global_config {
    my($directives, $d, %name, %parse, $var, $value, $lvar, $parse);
    my($directive, $seen_catalog);
    no strict 'refs';

    $directives = global_directives();

	$Global::Structure = {} unless $Global::Structure;

	# Prevent parsers from thinking it is a catalog
	undef $C;

    foreach $d (@$directives) {
		($directive = $d->[0]) =~ tr/A-Z/a-z/;
		$name{$directive} = $d->[0];
		if (defined $d->[1]) {
			$parse = 'parse_' . $d->[1];
		} else {
			$parse = undef;
		}
		$parse{$directive} = $parse;
		undef $value;
		$value = ( 
					! defined $MV::Default{mv_global} or
					! defined $MV::Default{mv_global}{$d->[0]}
				 )
				 ? $d->[2]
				 : $MV::Default{mv_global}{$d->[0]};

		if (defined $DumpSource{$name{$directive}}) {
			$Global::Structure->{ $name{$directive} } = $value;
		}

		if (defined $parse and defined $value) {
			$value = &$parse($d->[0], $value);
		}

		if(defined $value) {
			${'Global::' . $name{$directive}} = $value;

			$Global::Structure->{ $name{$directive} } = $value
				unless defined $DontDump{ $name{$directive} };
		}

    }

	my (@include) = $Global::ConfigFile; 

	# Create closure for reading of value

	my $read = sub {
		my ($lvar, $value) = @_;
		# Error out on extra parameters only if we know
		# we are not standalone
		unless (defined $name{$lvar}) {
			config_error("Unknown directive '$var'");
			return;
		}

		$parse = $parse{$lvar};
					# call the parsing function for this directive

		if (defined $DumpSource{$name{$directive}}) {
			$Global::Structure->{ $name{$directive} } = $value;
		}

		$value = &$parse($name{$lvar}, $value) if defined $parse;
					# and set the Global::directive variable
		${'Global::' . $name{$lvar}} = $value;
		$Global::Structure->{ $name{$lvar} } = $value
			unless defined $DontDump{ $name{$lvar} };
	};
	my $done_one;
GLOBLOOP:
	while ($configfile = shift @include) {
		my $tellmark;
		if(ref $configfile) {
			($configfile, $tellmark)  = @$configfile;
#print "recalling $configfile (pos $tellmark)\n";
		}

    -f $configfile && open(GLOBAL, "< $configfile")
		or do {
			my $msg = errmsg(
						"Could not open global configuration file '%s': %s",
						$configfile,
						$!,
						);
			if(defined $done_one) {
				warn "$msg\n";
				open (GLOBAL, '');
			}
			else {
				die "$msg\n";
			}
		};
	seek(GLOBAL, $tellmark, 0) if $tellmark;
#print "seeking to $tellmark in $configfile, include is @include\n";
	my ($ifdef, $begin_ifdef);
    while(<GLOBAL>) {
		if(/^#endif\s*$/) {
			undef $ifdef;
			undef $begin_ifdef;
			next;
		}
		if(/^#if(n?)def\s+(.*)/) {
			if(defined $ifdef) {
				config_error("Can't overlap #ifdef at line $. of $configfile");
			}
			$ifdef = evaluate_ifdef($2,$1,1);
			$begin_ifdef = $.;
			next;
		}
		if(defined $ifdef) {
			next unless $ifdef;
		}
		if(/^\s*#include\s+(.+)/) {
			my $spec = $1;
			my $ref = [ $configfile, tell(GLOBAL)];
#print "saving config $configfile (pos $ref->[1])\n";
			unshift @include, $ref;
			close GLOBAL;
			chomp;
			unshift @include, grep -f $_, glob($spec);
			next GLOBLOOP;
		}
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
		my($codere) = '[-\w_#/.]+';

		if ($value =~ /^(.*)<<(\w+)\s*/) {                  # "here" value
			my $begin  = $1 || '';
			$begin .= "\n" if $begin;
			my $mark = $2;
			my $startline = $.;
			$value = $begin . read_here(\*GLOBAL, $mark);
			unless (defined $value) {
				config_error (sprintf('%d: %s', $startline,
					qq#no end marker ("$mark") found#));
			}
		}
		elsif ($value =~ /^(\S+)?(\s*)?<\s*($codere)$/o) {   # read from file
			$value = $1 || '';
			my $file = $3;
			$value .= "\n" if $value;
			unless (defined $Global::ConfigDir) {
				config_error
					("$name{$lvar}: Can't read from file until ConfigDir defined");
			}
			$file = $name{$lvar} unless $file;
			$file = "$Global::ConfigDir/$file" unless $file =~ m!^/!;
			$file = escape_chars($file);			# make safe for filename
			my $tmpval = readfile($file);
			unless( defined $tmpval ) {
				config_warn errmsg(
						"%s: read from non-existent file %s, skipping.",
						$name{$lvar},
						$file,
						);
				next;
			}
			chomp($tmpval) unless $tmpval =~ m!.\n.!;
			$value .= $tmpval;
		}

		&$read($lvar, $value);

   }
    close GLOBAL;
	$done_one = 1;
} # end GLOBLOOP;

    # check for unspecified directives that don't have default values
    foreach $var (keys %name) {
		last if defined $Vend::ExternalProgram;
        if (!defined ${'Global::' . $name{$var}}) {
            die "Please specify the $name{$var} directive in the\n" .
            "configuration file '$Global::ConfigFile'\n";
        }
    }

	# Inits Global UserTag entries
	ADDTAGS: {
		Vend::Parse::global_init;
	}

	dump_structure($Global::Structure, "$Global::ConfDir/$Global::ExeName")
		if $Global::DumpStructure;
	return 1;
}

# Use Tie::Watch to attach subroutines to config variables
sub watch {
	my($name, $value) = @_;
	my ($ref, $orig);
#::logDebug("Contents of $name: " . ::uneval($C->{$name}));
	if(ref($C->{$name}) =~ /ARRAY/) {
#::logDebug("watch ref=array");
		$ref = $C->{$name};
		$orig = [ @{ $C->{$name} } ];
	}
	elsif(ref($C->{$name}) =~ /HASH/) {
#::logDebug("watch ref=hash");
		$ref = $C->{$name};
		$orig = { %{ $C->{$name} } };
	}
	else {
#::logDebug("watch ref=scalar");
		$ref = \$C->{$name};
		$orig = $C->{$name};
	}
#::logDebug("watch ref=$ref orig=$orig name=$name value=$value");
	$C->{WatchIt} = { _mvsafe => $C->{ActionMap}{_mvsafe} } if ! $C->{WatchIt};
	parse_action('WatchIt', "$name $value");
	my $coderef = $C->{WatchIt}{$name}
		or return undef;
	my $recode = sub {
					package Vend::Interpolate;
					init_calc();
					my $key = $_[0]->Args(-fetch)->[0];
					return $coderef->(@_, $key);
				};
	package Vend::Interpolate;
	$Vend::Config::C->{WatchIt}{$name} = Tie::Watch->new(
					-variable => $ref,
					-fetch => [$recode,$orig],
					);
}

# Set up an ActionMap or FormAction
sub parse_action {
	my ($var, $value) = @_;
	return {} if ! $value;
	my $c;
	if(defined $C) {
		$c = $C->{$var};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$var"};
		
	}
	if (defined $C and ! $c->{_mvsafe}) {
		my $calc = Vend::Interpolate::reset_calc();
		$c->{_mvsafe} = $calc;
	}
	my ($name, $sub) = split /\s+/, $value, 2;

	# Untaint and strip this pup
	$sub =~ s/^\s*([\000-\377]*\S)\s*//;
	$sub = $1;

	if($sub !~ /\s/) {
		$c->{$name} = $Global::GlobalSub->{$_}
			if defined $Global::GlobalSub->{$_};
		return $c;
	}
	elsif ( $sub !~ /^sub\b/) {
		my $code = <<EOF;
sub {
				return Vend::Interpolate::interpolate_html(<<EndOfThisHaiRYTHING);
$sub
EndOfThisHaiRYTHING
}
EOF
		$c->{$name} = eval $code;
	}
	elsif (! $C or $Global::AllowGlobal->{$C->{CatalogName}}) {
		package Vend::Interpolate;
		$c->{$name} = eval $sub;
	}
	else {
		package Vend::Interpolate;
		$c->{$name} = $c->{_mvsafe}->reval($sub);
	}
	if($@) {
		config_warn(errmsg("Action '%s' did not compile correctly.", $name));
	}
	return $c;
	
}

# Checks to see if a globalsub, sub, or usertag is present

sub parse_require {
	my($var, $val) = @_;

	return if $Vend::ExternalProgram;

	my $require;
	my $name;
	if($val =~ s/^globalsub\s+//i) {
		$require = $Global::GlobalSub;
		$name = 'GlobalSub';
	}
	elsif($val =~ s/^sub\s+//i) {
		$require = $C->{Sub};
		$name = 'Sub';
	}
	elsif($val =~ s/^usertag\s+//i) {
		$require = $Global::UserTag->{Routine};
		$name = 'UserTag';
	}
	my @requires = grep /\S/, split /\s+/, $val;

	for(@requires) {
		next if defined $require->{$_};
		config_error("Required $name $_ not present. Aborting catalog.");
	}
	return '';	
}

# Sets the special variable remap array
#

my $Varnames;
INITVARS: {
	local($/);
	$Varnames = <DATA>;
}

sub parse_varname {
    my($item,$settings) = @_;
	my($iv,$vn,$k,$v,@set);
#logDebug("parse_varname: $settings");
	if(defined $C) {
		return '' if ! $settings;
		$C->{IV} = { %{$Global::IV} } if ! $C->{IV};
		$C->{VN} = { %{$Global::VN} } if ! $C->{VN};
		$iv = $C->{IV};
		$vn = $C->{VN};
	}
	else {
		if (! $Global::VarName) {
			unless (-s "$Global::ConfDir/varnames" && -r _) {
				$settings = $Varnames . "\n$settings";
				Vend::Util::writefile("$Global::ConfDir/varnames", $Varnames);
			}
			else {
				$settings = Vend::Util::readfile("$Global::ConfDir/varnames");
			}
		}
		undef $Varnames;
		$Global::IV = {} if ! $Global::IV;
		$Global::VN = {} if ! $Global::VN;
		$iv = $Global::IV;
		$vn = $Global::VN;
	}

    @set = grep /\S/, split /\s+/, $settings;
	while( $k = shift @set, $v = shift @set ) {
		$vn->{$k} = $v;
		$iv->{$v} = $k;
	}
	return 1;
}


# Allow addition of a new catalog directive
sub parse_directive {
    my($name, $val) = @_;

	return '' unless $val;
	my($dir, $parser, $default) = split /\s+/, $val, 3 ;
	$parser = undef unless defined &{"parse_$parser"};
	$default = '' if ! $default or $default eq 'undef';
	$Global::AddDirective = [] unless $Global::AddDirective;
	push @$Global::AddDirective, [ $dir, $parser, $default ];
	return $Global::AddDirective;
}

# Allow a subcatalog value to completely replace a base value
sub parse_replace {
    my($name, $val) = @_;

	return {} unless $val;

    $C->{$val} = get_catalog_default($val);
	$C->{$name}->{$val} = 1;
	$C->{$name};
}


# Send a message during configuration, goes to terminal if during
# daemon startup, always goes to error log
sub parse_message {
    my($name, $val) = @_;

	return '' unless $val;

    ::logGlobal({level => 'info'},
				errmsg($val,
						$name,
						$.,
						$configfile,
				)
	);
}


# Warn about directives no longer supported in the configuration file.
sub parse_warn {
    my($name, $val) = @_;

	return '' unless $val;

    ::logGlobal({level => 'info'},
				errmsg("Directive %s no longer supported at line %s of %s.",
						$name,
						$.,
						$configfile,
				)
	);
}

# Each of the parse functions accepts the value of a directive from the
# configuration file as a string and either returns the parsed value or
# signals a syntax error.

# Sets a boolean array for any type of item
sub parse_boolean {
	my($item,$settings) = @_;
	my(@setting) = split /[\s,]+/, $settings;
	my $c;

	my $val = $item eq "StaticPage" ? '' : 1;

	if(defined $C) {
		$c = $C->{$item} || {};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"} || {};
	}

	for (@setting) {
		$c->{$_} = $val;
	}
	return $c;
}

use POSIX qw(
				setlocale localeconv
				LC_ALL		LC_CTYPE	LC_COLLATE
				LC_MONETARY	LC_NUMERIC	LC_TIME
			);

# Sets the special locale array. Tries to use POSIX setlocale,
# accepts a 'custom' setting with the proper definitions of
# decimal_point,  mon_thousands_sep, and frac_digits (the only supported at
# the moment).  Otherwise uses US-English settings if not set.
#
sub parse_locale {
    my($item,$settings) = @_;
	return ($settings || '') unless $settings =~ /[^\d.]/;
	$settings = '' if "\L$settings" eq 'default';
    my $name;
    my ($c, $store);
	if(defined $C) {
		$c = $C->{$item} || { };
		$C->{$item . "_repository"} = {}
			unless $C->{$item . "_repository"};
		$store = $C->{$item . "_repository"};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"} || {};
		${"Global::$item" . "_repository"} = {}
			unless ${"Global::$item" . "_repository"};
		$store = ${"Global::$item" . "_repository"};
	}

    # Try POSIX first if Locale.
    $name = POSIX::setlocale(POSIX::LC_ALL, $settings)
		if $item eq 'Locale';

	my ($eval, $safe);
    if (defined $name and $name and $item eq 'Locale') {
        $c = POSIX::localeconv();
        $c->{mon_thousands_sep} = ','
            unless $c->{mon_thousands_sep};
        $c->{decimal_point} = '.'
            unless $c->{decimal_point};
        $c->{frac_digits} = 2
            unless defined $c->{frac_digits};
		$store->{$name} = $c;
    }
    elsif ($settings =~ s/^\s*(\w+)\s+//) {
		$name = $1;

		undef $eval;
		$settings =~ /^\s*{/
			and $settings =~ /}\s*$/
				and $eval = 1;
		$eval and ! $safe and $safe = new Safe;
		if(! defined $store->{$name} and $item eq 'Locale') {
			if(POSIX::setlocale(POSIX::LC_ALL, $settings) ) {
				$store->{$name} = POSIX::localeconv();
			}
		}
#		if(defined $store->{$name}) {
#			for (sort keys %{$store->{$name}}) {
#				printf "%-5s %-16s %s\n", $name, $_, $store->{$name}{$_};
#			}
#		}
        my($sethash);
		if ($eval) {
			$sethash = $safe->reval($settings)
				or config_warn(errmsg("bad Locale setting in %s: %s", $name,$settings)),
						$sethash = {};
		}
		elsif(index($settings, "\n") > -1) {
			$settings =~ s/^(\S+\s+)"([\000-\377]*)"\s+$/$1$2/;
			$sethash = {};
			%{$sethash} = split(/\s+/, $settings, 2);
		}
		else {
			$sethash = {};
			%{$sethash} = Text::ParseWords::shellwords($settings);
		}
		$c = $store->{$name} || {};
        for (keys %{$sethash}) {
            $c->{$_} = $sethash->{$_};
        }
		if($item eq 'Locale') {
			$Vend::Cfg->{DefaultLocale} = $name;
			$c->{mon_thousands_sep} = ','
				unless defined $c->{mon_thousands_sep};
			$c->{decimal_point} = '.'
				unless $c->{decimal_point};
			$c->{frac_digits} = 2
				unless defined $c->{frac_digits};
		}
    }
    else {
        config_error("Bad locale setting $settings.\n");
    }

	$store->{$name} = $c unless $store->{$name};

    return $c;
}

#
# Sets a structure like Locale but with the depth and access via key
# No evaled structure setting, only key-value with shell quoting
# 
sub parse_structure {
	my ($item, $settings) = @_;
	return {} unless $settings;
	my $key;
	my @rest;
	($key, @rest) = Text::ParseWords::shellwords($settings);
	my ($c, $e);
	if(defined $C) {
		$c = $C->{$item};
		$e = $c->{$key} || { };
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"};
		$e = $c->{$key} || {};
	}

	while(scalar @rest) {
		my $k = shift @rest;
		$e->{$k} = shift @rest;
	}
	$c->{$key} = $e;
	return $c;
}


# Sets the special page array
sub parse_special {
	my($item,$settings) = @_;
	return {} unless $settings;
	my(%setting) = grep /\S/, split /[\s,]+/, $settings;
	for (keys %setting) {
		if($Global::NoAbsolute and file_name_is_absolute($setting{$_}) ) {
			config_warn(errmsg("Absolute file name not allowed: %s", $setting{$_}));
			next;
		}
		$C->{$item}{$_} = $setting{$_};
	}
	return $C->{$item};
}

# Sets up a hash value from a configuration directive, syntax is
# 
#   Directive  "key" "value"
# 
# quotes are optional if word-only chars

sub parse_hash {
	my($item,$settings) = @_;
	return {} if ! $settings;
	$settings =~ s/^\s+//;
	$settings =~ s/\s+$//;
	my(@setting) = Text::ParseWords::shellwords($settings);

	my $c;

	if(defined $C) {
		$c = $C->{$item} || {};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"} || {};
	}

	my $i;
	for ($i = 0; $i < @setting; $i += 2) {
		$c->{$setting[$i]} = $setting[$i + 1];
#::logDebug("$item hash $setting[$i]=$setting[$i+1]");
	}
	$c;
}

# Set up illegal values for certain directives
my %IllegalValue = (

		AutoModifier => { qw/   mv_mi 1
								mv_si 1
								mv_ib 1
								group 1
								code  1
								quantity 1
								item  1     /
						},
		UseModifier => { qw/   mv_mi 1
								mv_si 1
								mv_ib 1
								group 1
								code  1
								quantity 1
								item  1     /
						}
);


# Set up defaults for certain directives
my $Have_set_global_defaults;
my %Default = (
		UserDB => sub {
							shift;
							my $set = $C->{UserDB_repository};
							for(keys %$set) {
								next unless defined $set->{$_}{admin};
								$C->{AdminUserDB} = {} unless $C->{AdminUserDB};
								$C->{AdminUserDB}{$_} = $set->{$_}{admin};
							}
							return 1;
						},
		# Turn the array of IPC keys into a hash value so that we can
		# grep for enables
		IPC => sub {
							my $ref = shift;
							return 1 unless ref $ref;
							my $hash = {};
							for(@$ref) {
								$hash->{$_} = 1;
							}
							$C->{IPCkeys} = $hash;
							return 1;
						},
		TcpMap => sub {
							shift;
							return 1 if defined $Have_set_global_defaults;
							$Have_set_global_defaults = 1;
							my (@sets) = keys %{$Global::TcpMap};
							if(scalar @sets == 1 and $sets[0] eq '-') {
								$Global::TcpMap = {};
							}
							return 1 if @sets;
							$Global::TcpMap->{7786} = '-';
							return 1;
						},

		ProductFiles => sub {
							shift;
							my $setting = $C->{ProductFiles};
							if (defined $C->{Variable}{MV_DEFAULT_SEARCH_FILE}
								and  ! ref $C->{Variable}{MV_DEFAULT_SEARCH_FILE})
							{
								$C->{Variable}{MV_DEFAULT_SEARCH_FILE} =
									[ $C->{Variable}{MV_DEFAULT_SEARCH_FILE} ];
								return 1;
							}
							my @out;
							for(@$setting) {
								next unless defined $C->{Database}{$_}{'file'};
								push @out, $C->{Database}{$_}{'file'};
								if( defined $Vend::Cfg->{OnlyProducts} ) {
									undef $Vend::Cfg->{OnlyProducts};
									next;
								}
								else {
									$Vend::Cfg->{OnlyProducts} = 
										$C->{Database}{$_}{'name'};
								}
							}
							return (undef, "No default search file!") 
								unless scalar @out;
							$C->{Variable}{MV_DEFAULT_SEARCH_FILE} = \@out;
							return 1;
						},
);

sub set_defaults {
	for(keys %Default) {
		my ($status, $error) = $Default{$_}->($C->{$_});
		next if $status;
		return config_error(
				errmsg(
					'Directive %s returned default setting error: %s',
					$_,
					$error
				)
		);
	}
	return;
}

sub check_legal {
	my ($directive, $value) = @_;
	return 1 unless defined $IllegalValue{$directive}->{$value};
	config_error ("\nYou may not use a value of '$value' in the $directive directive.");
}

sub parse_array {
	my($item,$settings) = @_;
	return '' unless $settings;
	my(@setting) = grep /\S/, split /[\s,]+/, $settings;

	my $c;

	if(defined $C) {
		$c = $C->{$item} || [];
	}
	else {
		no strict 'refs';
		$c = ${"Global::$item"} || [];
	}

	for (@setting) {
		check_legal($item, $_);
		push @{$c}, $_;
	}
	$c;
}

sub parse_array_complete {
	my($item,$settings) = @_;
	return '' unless $settings;
	my(@setting) = grep /\S/, split /[\s,]+/, $settings;

	my $c = [];

	for (@setting) {
		check_legal($item, $_);
		push @{$c}, $_;
	}

	$c;
}
# Make a dos-ish regex into a Perl regex, check for errors
sub parse_wildcard {
    my($var, $value) = @_;

	$value =~ s/\./\\./g;
	$value =~ s/\*/.*/g;
	$value =~ s/\*/.*/g;
	$value =~ s/\s+/|/g;
	eval {  
		my $never = 'NeVAirBE';
		$never =~ m{$value};
	};

	if($@) {
		config_error("Bad regular expression in $var.");
	}
    return $value;
}


# Check that a regex won't cause a syntax error. Uses m{}, which
# should be used for all user-input regexes.
sub parse_regex {
    my($var, $value) = @_;

	eval {  
		my $never = 'NeVAirBE';
		$never =~ m{$value};
	};

	if($@) {
		config_error("Bad regular expression in $var.");
	}
    return $value;
}

# Prepend the Global::VendRoot pathname to the relative directory specified,
# unless it already starts with a leading /.

sub parse_root_dir {
    my($var, $value) = @_;
	return [] unless $value;
    $value = "$Global::VendRoot/$value"
		unless Vend::Util::file_name_is_absolute($value);
    $value =~ s./+$..;
	no strict 'refs';
    my $c = ${"Global::$var"} || [];
    push @$c, $value;
	return $c;
}

sub parse_dir_array {
    my($var, $value) = @_;
	return [] unless $value;
    $value = "$C->{VendRoot}/$value"
		unless Vend::Util::file_name_is_absolute($value);
    $value =~ s./+$..;
    $C->{$var} = [] unless $C->{$var};
    my $c = $C->{$var} || [];
    push @$c, $value;
	return $c;
}

# Prepend the CatalogRoot pathname to the relative directory specified,
# unless it already starts with a leading /.

sub parse_relative_dir {
    my($var, $value) = @_;

	config_error(
	  "No leading / allowed if NoAbsolute set. Contact administrator.\n"
	  )
	  if Vend::Util::file_name_is_absolute($value) and $Global::NoAbsolute;
	config_error(
	  "No leading ../.. allowed if NoAbsolute set. Contact administrator.\n"
	  )
	  if $value =~ m#^\.\./.*\.\.# and $Global::NoAbsolute;

    $value = "$C->{VendRoot}/$value"
		unless Vend::Util::file_name_is_absolute($value);
    $value =~ s./+$..;
    $value;
}

# Ensure only an integer value in the directive
sub parse_integer {
    my($var, $value) = @_;
	$value = hex($value) if $value =~ /^0x[\dA-Fa-f]+$/;
	$value = oct($value) if $value =~ /^0[0-7]+$/;
    config_error("The $var directive (now set to '$value') must be an integer\n")
		unless $value =~ /^\d+$/;
    $value;
}

# Make sure no trailing slash in VendURL etc.
sub parse_url {
    my($var, $value) = @_;
    $value =~ s,/+$,,;
    $value;
}

# Parses a time specification such as "1 day" and returns the
# number of seconds in the interval, or undef if the string could
# not be parsed.

sub time_to_seconds {
    my($str) = @_;
    my($n, $dur);

    ($n, $dur) = ($str =~ m/(\d+)[\s\0]*(\w+)?/);
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

sub parse_valid_group {
    my($var, $value) = @_;

	return '' unless $value;

	my($name,$passwd,$gid,$members) = getgrnam($value);

    config_error("$var: Group name '$value' is not a valid group\n")
		unless defined $gid;
	$name = getpwuid($<);
    config_error("$var: Interchange user '$name' not in group '$value'\n")
		unless $members =~ /\b$name\b/;
    $gid;
}

sub parse_executable {
    my($var, $value) = @_;
    my($x);
	my $root = $value;
	$root =~ s/\s.*//;

	return $value if $Global::Windows;
	if( ! defined $value or $value eq '') {
		$x = '';
	}
	elsif( $value eq 'none') {
		$x = 'none';
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

	$C->{Source}->{$var} = [$value];

    $n = time_to_seconds($value);
    config_error("Bad time format ('$value') in the $var directive\n")
	unless defined $n;
    $n;
}

# Determine catalog structure from Catalog config line(s)
sub parse_catalog {
	my ($var, $setting) = @_;
	my $num = ! defined $Global::Catalog ? 0 : $Global::Catalog;
	return $num unless (defined $setting && $setting); 

	my($name,$base,$dir,$script, @rest);
	($name,@rest) = Text::ParseWords::shellwords($setting);

	my %remap = qw/
					base      base
					alias     alias
					aliases   alias
					directory dir
					dir       dir
					script    script
					directive directive
					fullurl   full_url
					full      full_url
					/;

	my ($cat, $key, $value);
	if ($Global::Catalog{$name}) {
		# already defined
		$cat   = $Global::Catalog{$name};
		$key   = shift @rest;
		$value = shift @rest;
	}
	elsif(
			$var =~ /subcatalog/i and
			@rest > 2
			and file_name_is_absolute($rest[1]) 
		  )
	{
		$cat = {
			name   => $name,
			base   => $rest[0],
			dir    => $rest[1],
			script => $rest[2],
		};
		splice(@rest, 0, 3);
		$cat->{alias} = [ @rest ]
			if @rest;
	}
	elsif( file_name_is_absolute($rest[0]) ) {
		$cat = {
			name   => $name,
			dir    => $rest[0],
			script => $rest[1],
		};
		splice(@rest, 0, 2);
		$cat->{alias} = [ @rest ]
			if @rest;
	}
	else {
		$key   = shift @rest;
		$value = shift @rest;
		$cat = { name   => $name };
	}

	$key = $remap{$key} if $key && defined $remap{$key};

	if(! $key) {
		# Nada
	}
	elsif($key eq 'alias' or $key eq 'server') {
		$cat->{$key} = [] if ! $cat->{$key};
		push @{$cat->{$key}}, $value;
		push @{$cat->{$key}}, @rest if @rest;
	}
	elsif($key eq 'global') {
		$cat->{$key} = $Global::AllowGlobal{$name} = is_yes($value);
	}
	elsif($key eq 'directive') {
		no strict 'refs';
		my $p = $value;
		my $v = join " ", @rest;
		$cat->{$key} = {} if ! $cat->{$key};
		my $ref = set_directive($p, $v, 1);

		if(ref $ref->[1] =~ /HASH/) {
			if(! $cat->{$key}{$ref->[0]} ) {
				$cat->{$key}{$ref->[0]} =  { %{"Global::$ref->[0]"} };
			}
			for (keys %{$ref->[1]}) {
				$cat->{$key}{$ref->[0]}{$_} = $ref->[1]->{$_};
			}
		}
		else {
			$cat->{$key}{$ref->[0]} = $ref->[1];
		}
	}
	else {
		$cat->{$key} = $value;
	}

#::logDebug ("parsing catalog $name = " . ::uneval($cat));

	$Global::Catalog{$name} = $cat;

	# Define the main script name and array of aliases
	return ++$num;
}

my %Hash_ref = (  qw!
							FILTER_FROM   FILTER_FROM
							FILTER_TO     FILTER_TO 
							COLUMN_DEF    COLUMN_DEF
							FIELD_ALIAS   FIELD_ALIAS
							NUMERIC       NUMERIC
							WRITE_CATALOG WRITE_CATALOG
					! );

my %Ary_ref = (   qw!
							NAME         NAME
							BINARY       BINARY 
							POSTCREATE   POSTCREATE 
					! );

sub parse_config_db {
    my($name, $value) = @_;
	my ($d, $new);
	unless (defined $value && $value) { 
		$d = {};
		return $d;
	}

	if($C) {
		$d = $C->{ConfigDatabase};
	}
	else {
		$d = $Global::ConfigDatabase;
	}

	my($database,$remain) = split /[\s,]+/, $value, 2;

	$d->{'name'} = $database;
	
	if(!defined $d->{'file'}) {
		my($file, $type) = split /[\s,]+/, $remain, 2;
		$d->{'file'} = $file;
		if(		$type =~ /^\d+$/	) {
			$d->{'type'} = $type;
		}
		elsif(	$type =~ /^(dbi|sql)\b/i	) {
			$d->{'type'} = 8;
			if($type =~ /^dbi:/) {
				$d->{DSN} = $type;
			}
		}
# LDAP
		elsif(	$type =~ /^ldap\b/i) {
			$d->{'type'} = 9;
			if($type =~ /^ldap:(.*)/i) {
				$d->{LDAP_HOST} = $1;
			}
		}
# END LDAP
		elsif(	"\U$type" eq 'TAB'	) {
			$d->{'type'} = 6;
		}
		elsif(	"\U$type" eq 'PIPE'	) {
			$d->{'type'} = 5;
		}
		elsif(	"\U$type" eq 'CSV'	) {
			$d->{'type'} = 4;
		}
		elsif(	"\U$type" eq 'DEFAULT'	) {
			$d->{'type'} = 1;
		}
		elsif(	$type =~ /[%]{1,3}|percent/i	) {
			$d->{'type'} = 3;
		}
		elsif(	$type =~ /line/i	) {
			$d->{'type'} = 2;
		}
		else {
			$d->{'type'} = 1;
			$d->{DELIMITER} = $type;
		}
	}
	else {
		my($p, $val) = split /\s+/, $remain, 2;
		$p = uc $p;

		if(defined $Hash_ref{$p}) {
			my($k, $v);
			my(@v) = Vend::Util::quoted_comma_string($val);
			@v = grep defined $_, @v;
			$d->{$p} = {} unless defined $d->{$p};
			for(@v) {
				($k,$v) = split /\s*=\s*/, $_;
				$d->{$p}->{$k} = $v;
			}
		}
		elsif(defined $Ary_ref{$p}) {
			my(@v) = Text::ParseWords::shellwords($val);
			$d->{$p} = [] unless defined $d->{$p};
			push @{$d->{$p}}, @v;
		}
		else {
			config_warn errmsg(
				"ConfigDatabase scalar parameter %s redefined to '%s', was %s.",
							$p,
							$val,
							$d->{$p},
						)
				if defined $d->{$p};
			$d->{$p} = $val;
		}
	}

#::logDebug("d object: " . ::uneval($d));
	if($d->{ACTIVE} and ! $d->{OBJECT}) {
		my $name = $d->{'name'};
		$d->{OBJECT} = Vend::Data::import_database($d)
			or config_error("Config database $name failed import.\n");
	}
	elsif($d->{LOAD} and ! $d->{OBJECT}) {
		my $name = $d->{'name'};
		$d->{OBJECT} = Vend::Data::import_database($d)
			or config_error("Config database $name failed import.\n");
		if( $d->{type} == 8 ) {
			$d->{OBJECT}->set_query("delete from $name where 1 = 1");
		}
	}

	return $d;
	
}

sub parse_database {
	my ($var, $value) = @_;
	my ($c, $new);

	if (! $value) {
		$c = {};
		return $c;
	}

#::logDebug("parse_database: $value");
	$c = $C ? $C->{Database} : $Global::Database;

	my($database,$remain) = split /[\s,]+/, $value, 2;

	if( ! defined $c->{$database} ) {
		$c->{$database} = { 'name' => $database, included_from => $configfile };
		$new = 1;
	}

	my $d = $c->{$database};

	if($new) {
		my($file, $type) = split /[\s,]+/, $remain, 2;
		$d->{'file'} = $file;
		if(		$type =~ /^\d+$/	) {
			$d->{'type'} = $type;
		}
		elsif(	$type =~ /^(dbi|sql)\b/i	) {
			$d->{'type'} = 8;
			if($type =~ /^dbi:/) {
				$d->{DSN} = $type;
			}
		}
# LDAP
		elsif(	$type =~ /^ldap\b/i) {
			$d->{'type'} = 9;
			if($type =~ /^ldap:(.*)/i) {
				$d->{LDAP_HOST} = $1;
			}
		}
# END LDAP
		elsif(	"\U$type" eq 'TAB'	) {
			$d->{'type'} = 6;
		}
		elsif(	"\U$type" eq 'PIPE'	) {
			$d->{'type'} = 5;
		}
		elsif(	"\U$type" eq 'CSV'	) {
			$d->{'type'} = 4;
		}
		elsif(	"\U$type" eq 'DEFAULT'	) {
			$d->{'type'} = 1;
		}
		elsif(	$type =~ /[%]{1,3}|percent/i	) {
			$d->{'type'} = 3;
		}
		elsif(	$type =~ /line/i	) {
			$d->{'type'} = 2;
		}
		else {
			$d->{'type'} = 1;
			$d->{DELIMITER} = $type;
		}
		if    ($d->{'type'} eq '8')	{ $d->{Class} = 'DBI'						}
		elsif ($d->{'type'} eq '9') { $d->{Class} = 'LDAP'						}
		else 						{ $d->{Class} = $Global::Default_database	}

		$d->{HOT} = 1 if $d->{Class} eq 'MEMORY';
#::logDebug("parse_database: type $type -> $d->{type}");
	}
	else {
		my($p, $val) = split /\s+/, $remain, 2;
		$p = uc $p;
#::logDebug("parse_database: parameter $p = $val");

		if(defined $Hash_ref{$p}) {
			my($k, $v);
			my(@v) = Vend::Util::quoted_comma_string($val);
			@v = grep defined $_, @v;
			$d->{$p} = {} unless defined $d->{$p};
			for(@v) {
				($k,$v) = split /\s*=\s*/, $_;
				$d->{$p}->{$k} = $v;
			}
		}
		elsif(defined $Ary_ref{$p}) {
			my(@v) = Text::ParseWords::shellwords($val);
			$d->{$p} = [] unless defined $d->{$p};
			push @{$d->{$p}}, @v;
		}
		elsif ($p =~ /^(MEMORY|GDBM|DB_FILE|LDAP)$/i) {
			$d->{Class} = uc $p;
		}
		elsif ($p eq 'ALIAS') {
			if (defined $c->{$val}) {
				config_warn("Database '$val' already exists, can't alias.");
			}
			else {
				$c->{$val} = $d;
			}
		}
		else {
			config_warn errmsg(
				"ConfigDatabase scalar parameter %s redefined to '%s', was %s.",
							$p,
							$val,
							$d->{$p},
						)
				if defined $d->{$p};
			$d->{$p} = $val;
		}
		$d->{HOT} = 1 if $d->{Class} eq 'MEMORY';
	}

	return $c;
}

sub get_configdb {
	my ($var, $value) = @_;
	my ($table, $file, $type);
	unless ($C->{Database}{$value}) {
		return if $Vend::ExternalProgram;
		($table, $file, $type) = split /\s+/, $value, 3;
		$file = "$table.txt" unless $file;
		$type = 'TAB' unless $type;
		parse_database('Database',"$table $file $type");
		unless ($C->{Database}{$table}) {
			config_warn(
				errmsg(	"Bad $var value '%s': %s\n%s",
						"Database $table $file $type",
						::uneval($C->{Database}),
						)
			);
			return '';
		}
	}
	else {
		$table = $value;
	}

	my $db;
	unless ($db = $C->{Database}{$table}) {
		return if $Vend::ExternalProgram;
		my $err = $@;
		config_warn(
			errmsg("Bad $var '%s': %s", $table, $err)
		);
		return '';
	}
	$db = Vend::Data::import_database($db);
	if(! $db) {
		my $err = $@;
		config_warn(
			errmsg("Bad $var '%s': %s", $table, $err)
		);
		return '';
	}
	return ($db, $table);
}

sub parse_routeconfig {
	my ($var, $value) = @_;

	my ($file, $type);
	return '' if ! $value;
	local($Vend::Cfg) = $C;

	my ($db, $table) = get_configdb($var, $value);

	return '' if ! $db;

	my ($k, @f);	# key and fields
	my @l;			# refs to locale repository
	my @n;			# names of locales
	my @h;			# names of locales

	@n = $db->columns();
	shift @n;
	my $i;
	while( ($k, undef, @f ) = $db->each_record) {
#::logDebug("Got route key=$k f=@f");
		for ($i = 0; $i < @f; $i++) {
			next unless length($f[$i]);
			$C->{Route_repository}{$k}{$n[$i]} = $f[$i];
		}
	}
	$db->close_table();
	return $table;
}

sub parse_dbconfig {
	my ($var, $value) = @_;

	my ($file, $type);
	return '' if ! $value;
	local($Vend::Cfg) = $C;

	my ($db, $table) = get_configdb($var, $value);

	return '' if ! $db;

	my ($k, @f);	# key and fields
	my @l;			# refs to locale repository
	my @n;			# names of locales
	my @h;			# names of locales

	@n = $db->columns();
	shift @n;
	my $extra;
	for(@n) {
		my $real = $CDname{lc $_};
		if (! ref $Vend::Cfg->{$real} or $Vend::Cfg->{$real} !~ /HASH/) {
			# ignore non-existent directive, but put in hash
			my $ref = {};
			push @l, $ref;
			push @h, [$real, $ref];
			next;
		}
		push @l, $Vend::Cfg->{$real};
	}
	my $i;
	while( ($k, undef, @f ) = $db->each_record) {
#::logDebug("Got key=$k f=@f");
		for ($i = 0; $i < @f; $i++) {
			next unless length($f[$i]);
			$l[$i]->{$k} = $f[$i];
		}
	}
	for(@h) {
		$Vend::Cfg->{Hash}{$_->[0]} = $_->[1];
	}
	$db->close_table();
	return $table;
}

sub parse_dbdatabase {
	my ($var, $value) = @_;

	return '' if ! $value;
	local($Vend::Cfg) = $C;
	my ($db, $table) = get_configdb($var, $value);
	$db = $db->ref();
	my $kindex = $db->config('KEY_INDEX');
#::logGlobal("kindex=$kindex");
	local($^W) = 0;
	my ($k, @f);	# key and fields
	my @l;			# refs to locale repository
	my @n;			# names of locales
	my $name;		# names of current locale

	@n = $db->columns();
	$k = 0;
	foreach $name (@n) {
		next if $k++ == $kindex;
		my $file = $db->field('_file', $name);
		my $type = $db->field('_type', $name);
		next unless $file and $type;
		parse_database('', "$name $file $type");
	}
	while( ($k , @f ) = $db->each_record) {
		next if $k =~ /^_/;
		my $i;
		for ($i = 0; $i < @f; $i++) {
			next if $i == $kindex;
			next unless length $f[$i];
#::logGlobal("f-i=$f[$i] i=$i kindex=$kindex");
			Vend::Config::parse_database('', "$n[$i] $k $f[$i]");
		}
	}
	$db->close_table();
	return $table;
}

sub parse_profile {
	my ($var, $value) = @_;
	my ($c, $ref, $sref, $i);

	if($C) {
		$C->{"${var}Name"} = {} if ! $C->{"${var}Name"};
		$sref = $C->{Source};
		$ref = $C->{"${var}Name"};
		$c = $C->{$var} || [];
	}
	else {
		no strict 'refs';
		$sref = $Global::Source;
		${"Global::${var}Name"} = {}
			 if ! ${"Global::${var}Name"};
		$ref = ${"Global::${var}Name"};
		$c = ${"Global::$var"} || [];
	}

	$sref->{$var} = $value;

	my (@files) = glob($value);
	for(@files) {
		config_error(
		  "No leading / allowed if NoAbsolute set. Contact administrator.\n")
		if m.^/. and $Global::NoAbsolute;
		config_error(
		  "No leading ../.. allowed if NoAbsolute set. Contact administrator.\n")
		if m#^\.\./.*\.\.# and $Global::NoAbsolute;
		push @$c, (split /\s*[\r\n]+__END__[\r\n]+\s*/, readfile($_));
	}
	for($i = 0; $i < @$c; $i++) {
		if($c->[$i] =~ s/(^|\n)__NAME__\s+([^\n\r]+)\r?\n//) {
			my $name = $2;
			$ref->{$name} = $i;
		}
	}

	return $c;
}

# Designed to parse catalog subroutines and all vars
sub save_variable {
	my ($var, $value) = @_;
	my ($c, $name, $param);

    if(defined $C) {
        $c = $C->{$var};
    }
    else { 
        no strict 'refs';
        $c = ${"Global::$var"};
    }

	if ($var eq 'Variable' || $var eq 'Member') {
		$value =~ s/^\s*(\w+)\s*//;
		$name = $1;
		return 1 if defined $c->{'save'}->{$name};
		$value =~ s/\s+$//;
		$c->{'save'}->{$name} = $value;
	}
	elsif ( !defined $C) { 
		return 0;
	}
	elsif ( defined $C->{Source}{$var} && ref $C->{Source}{$var}) {
		push @{$C->{Source}{$var}}, $value;
	}
	elsif ( defined $C->{Source}{$var}) {
		$C->{Source}{$var} .= "\n$value";
	}
	else {
		$C->{Source}{$var} = $value;
	}
	return 1;

}

my %tagCanon = ( qw(

	alias			Alias
	addattr  		addAttr
	attralias		attrAlias
	cannest			canNest
	documentation	Documentation
	endhtml			endHTML
	hasendtag		hasEndTag
	implicit		Implicit
	inserthtml		insertHTML
	insidehtml		insideHTML
	interpolate		Interpolate
	invalidatecache	InvalidateCache
	isendanchor		isEndAnchor
	lookaheadhtml	lookaheadHTML
	order			Order
	posnumber		PosNumber
	posroutine		PosRoutine
	replaceattr		replaceAttr
	replacehtml		replaceHTML
	required		Required
	routine			Routine

));


my %tagAry 	= ( qw! Order 1 Required 1 ! );
my %tagHash	= ( qw!
				replaceAttr	1
				Implicit	1
				attrAlias	1
				! );
my %tagBool = ( qw!
				hasEndTag	1
				Interpolate 1
				canNest		1
				isEndAnchor	1
				addAttr 	1
				isOperator	1
				! );

# Parses the user tags
sub parse_tag {
	my ($var, $value) = @_;
	my ($c, $new);

	unless (defined $value && $value) { 
		return {};
	}

	$c = defined $C ? $C->{UserTag} : $Global::UserTag;

	my($tag,$p,$val) = split /\s+/, $value, 3;
	
	# Canonicalize
	$p = $tagCanon{lc $p};
	$tag =~ tr/-/_/;
	$tag =~ s/\W//g
		and config_warn("Bad characters removed from '$tag'.");

	unless ($p) {
		config_warn "Bad user tag parameter '$p' for '$tag', skipping.";
		return $c;
	}

	if($p eq 'Routine' or $p eq 'posRoutine') {

		my $sub;
		$c->{Source}->{$tag}->{$p} = $val;
		unless(!defined $C or $Global::AllowGlobal->{$C->{CatalogName}}) {
			my $safe = new Safe;
			my $code = $val;
			$code =~ s'$Vend::Session->'$foo'g;
			$code =~ s'$Vend::Cfg->'$bar'g;
			$safe->untrap(@{$Global::SafeUntrap});
			$sub = $safe->reval($code);
			if($@) {
				config_warn(
					 errmsg(
						"UserTag '%s' subroutine failed safe check: %s",
						$tag,
						$@,
						)
				);
				return $c;
			}
		}
		my $fail;
		{
			local $SIG{'__WARN__'} = sub {$fail .= "@_";};
			eval {
				package Vend::Interpolate;
				$sub = eval $val;
				die $@ if $@;
			};
		}
		if($@ or $fail) {
			config_warn(
					 errmsg(
						"UserTag '%s' subroutine failed compilation:\n\n\t%s",
						$tag,
						"$fail $@",
						)
			);
			return $c;
		}
		else {
			config_warn(
				errmsg(
					"UserTag '%s' code is not a subroutine reference",
					$tag,
				)
			) unless ref($sub) =~ /CODE/;
		}
		$c->{$p}{$tag} = $sub;
		$c->{Order}{$tag} = []
			unless defined $c->{Order}{$tag};
	}
	elsif(defined $tagAry{$p}) {
		my(@v) = Text::ParseWords::shellwords($val);
		$c->{$p}{$tag} = [] unless defined $c->{$p}{$tag};
		push @{$c->{$p}{$tag}}, @v;
	}
	elsif(defined $tagHash{$p}) {
		my(%v) = Text::ParseWords::shellwords($val);
		$c->{$p}{$tag} = {} unless defined $c->{$p}{$tag};
		for (keys %v) {
		  $c->{$p}{$tag}{$_} = $v{$_};
		}
	}
	elsif(defined $tagBool{$p}) {
		$c->{$p}{$tag} = 1
			unless defined $val and $val =~ /^[0nf]/i;
	}
	else {
		config_warn errmsg("UserTag %s scalar parameter %s redefined.", $tag, $p)
			if defined $c->{$p}{$tag};
		$c->{$p}{$tag} = $val;
	}

	return $c;
}

sub parse_eval {
	my($var,$value) = @_;
	return '' unless $value =~ /\S/;
	return eval $value;
}

# Designed to parse all Variable settings
sub parse_variable {
	my ($var, $value) = @_;
	my ($c, $name, $param);

	# Allow certain catalogs global subs
	unless (defined $value and $value) { 
		$c = { 'save' => {} };
		return $c;
	}

	if(defined $C) {
		$c = $C->{$var};
	}
	else {
		no strict 'refs';
		$c = ${"Global::$var"};
	}

	if($value =~ /\n/) {
		($name, $param) = split /\s+/, $value, 2;
		chomp $param;
	}
	else {
		($name, $param) = split /\s+/, $value, 2;
	}
	$c->{$name} = $param;
	return $c;
}


# Designed to parse Global subroutines only
sub parse_subroutine {
	my ($var, $value) = @_;
	my ($c, $name);
	unless (defined $value and $value) { 
		$c = {};
		return $c;
	}

	no strict 'refs';
	$c = defined $C ? $C->{$var} : ${"Global::$var"};

	$value =~ s/\s*sub\s+(\w+)\s*{/sub {/;
	config_error("Bad $var: no subroutine name? ") unless $name = $1;
	# Untainting
	$value =~ /([\000-\377]*)/;
	$value = $1;
	if(! defined $C) {
		$c->{$name} = eval $value;
	}
	elsif($Global::AllowGlobal->{$C->{CatalogName}}) {
		package Vend::Interpolate;
		$c->{$name} = eval $value;
	}
	else {
		package Vend::Interpolate;
		my $calc = Vend::Interpolate::reset_calc();
		package Vend::Config;
		$C->{ActionMap} = { _mvsafe => $calc }
			if ! defined $C->{ActionMap}{_mvsafe};
		$c->{$name} = $C->{ActionMap}{_mvsafe}->reval($value);
	}

#::logDebug("Parsing subroutine/variable (C=$C) $var=$name");
	config_error("Bad $var '$name'") if $@;
	return $c;
}

sub parse_delimiter {
	my ($var, $value) = @_;

	return "\t" unless (defined $value && $value); 

	$C->{Source}->{$var} = $value;
	
	$value =~ /^CSV$/i and return 'CSV';
	$value =~ /^tab$/i and return "\t";
	$value =~ /^pipe$/i and return "\|";
	$value =~ s/^\\// and return $value;
	$value =~ s/^'(.*)'$/$1/ and return $value;
	return quotemeta $value;
}

# Returns 1 for Yes and 0 for No.

sub parse_yesno {
    my($var, $value) = @_;
    $_ = $value;
    if (m/^y/i || m/^t/i || m/^1/) {
		return 1;
    }
	elsif (m/^n/i || m/^f/i || m/^0/) {
		return 0;
    }
	else {
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

1;

__DATA__
mv_action                mv_action
mv_admin                 mv_admin
mv_alinkcolor            mv_alinkcolor
mv_all_chars             mv_all_chars
mv_arg                   mv_arg
mv_argument              mv_argument
mv_background            mv_background
mv_base_directory        mv_base_directory
mv_begin_string          mv_begin_string
mv_bgcolor               mv_bgcolor
mv_cache_key             mv_cache_key
mv_cache_price           mv_cache_price
mv_cartname              mv_cartname
mv_case                  mv_case
mv_cat                   mv_cat
mv_change_frame          mv_change_frame
mv_check                 mv_check
mv_click                 mv_click
mv_click_arg             mv_click_arg
mv_click_map             mv_click_map
mv_column_op             mv_column_op
mv_control               mv_control
mv_cookie_password       mv_cookie_password
mv_cookie_username       mv_cookie_username
mv_coordinate            mv_coordinate
mv_credit_card_error     mv_credit_card_error
mv_credit_card_exp_all   mv_credit_card_exp_all
mv_credit_card_exp_month mv_credit_card_exp_month
mv_credit_card_exp_year  mv_credit_card_exp_year
mv_credit_card_force     mv_credit_card_force
mv_credit_card_info      mv_credit_card_info
mv_credit_card_number    mv_credit_card_number
mv_credit_card_type      mv_credit_card_type
mv_credit_card_valid     mv_credit_card_valid
mv_currency              mv_currency
mv_cyber_mode            mv_cyber_mode
mv_cybermode             mv_cybermode
mv_data_decode           mv_data_decode
mv_data_fields           mv_data_fields
mv_data_function         mv_data_function
mv_data_key              mv_data_key
mv_data_table            mv_data_table
mv_data_verify           mv_data_verify
mv_delay_page            mv_delay_page
mv_dict_end              mv_dict_end
mv_dict_fold             mv_dict_fold
mv_dict_limit            mv_dict_limit
mv_dict_look             mv_dict_look
mv_dict_order            mv_dict_order
mv_discount              mv_discount
mv_doit                  mv_doit
mv_email                 mv_email
mv_error_                mv_error_
mv_exact_match           mv_exact_match
mv_expire_time           mv_expire_time
mv_failpage              mv_failpage
mv_field_names           mv_field_names
mv_first_match           mv_first_match
mv_global                mv_global
mv_handling              mv_handling
mv_head_skip             mv_head_skip
mv_ib                    mv_ib
mv_ignore_frame          mv_ignore_frame
mv_index_delim           mv_index_delim
mv_item_object           mv_item_object
mv_last                  mv_last
mv_linkcolor             mv_linkcolor
mv_list_only             mv_list_only
mv_locale                mv_locale
mv_matchlimit            mv_matchlimit
mv_max_matches           mv_max_matches
mv_mi                    mv_mi
mv_min_string            mv_min_string
mv_more_matches          mv_more_matches
mv_more_id               mv_more_id
mv_negate                mv_negate
mv_nextpage              mv_nextpage
mv_no_cache              mv_no_cache
mv_no_count              mv_no_count
mv_no_order_increment    mv_no_order_increment
mv_no_session_id         mv_no_session_id
mv_numeric               mv_numeric
mv_order_                mv_order_
mv_order_base            mv_order_base
mv_order_group           mv_order_group
mv_order_mv_ib           mv_order_mv_ib
mv_order_number          mv_order_number
mv_order_profile         mv_order_profile
mv_order_quantity        mv_order_quantity
mv_order_receipt         mv_order_receipt
mv_order_report          mv_order_report
mv_order_route           mv_order_route
mv_order_subject         mv_order_subject
mv_orderpage             mv_orderpage
mv_orsearch              mv_orsearch
mv_page                  mv_page
mv_password              mv_password
mv_password_old          mv_password_old
mv_pc                    mv_pc
mv_profile               mv_profile
mv_range_alpha           mv_range_alpha
mv_range_look            mv_range_look
mv_range_max             mv_range_max
mv_range_min             mv_range_min
mv_raw_dict_look         mv_raw_dict_look
mv_raw_searchspec        mv_raw_searchspec
mv_record_delim          mv_record_delim
mv_return_all            mv_return_all
mv_return_delim          mv_return_delim
mv_return_fields         mv_return_fields
mv_return_file_name      mv_return_file_name
mv_return_format         mv_return_format
mv_return_reference      mv_return_reference
mv_return_spec           mv_return_spec
mv_save_session          mv_save_session
mv_search_arg            mv_search_arg
mv_search_debug          mv_search_debug
mv_search_field          mv_search_field
mv_search_file           mv_search_file
mv_search_immediate      mv_search_immediate
mv_search_line_return    mv_search_line_return
mv_search_map            mv_search_map
mv_search_match_count    mv_search_match_count
mv_search_over_msg       mv_search_over_msg
mv_search_page           mv_search_page
mv_searchspec            mv_searchspec
mv_searchtype            mv_searchtype
mv_separate_items        mv_separate_items
mv_session_id            id
mv_shipmode              mv_shipmode
mv_si                    mv_si
mv_sort_field            mv_sort_field
mv_sort_option           mv_sort_option
mv_special_              mv_special_
mv_spelling_errors       mv_spelling_errors
mv_sql_array             mv_sql_array
mv_sql_hash              mv_sql_hash
mv_sql_hash_order        mv_sql_hash_order
mv_sql_names             mv_sql_names
mv_sql_param             mv_sql_param
mv_sql_query             mv_sql_query
mv_status_               mv_status_
mv_sub                   mv_sub
mv_subroutine            mv_subroutine
mv_substring_match       mv_substring_match
mv_textcolor             mv_textcolor
mv_todo                  mv_todo
mv_unique                mv_unique
mv_update_empty          mv_update_empty
mv_username              mv_username
mv_value                 mv_value
mv_verbatim_columns      mv_verbatim_columns
mv_verify                mv_verify
mv_vlinkcolor            mv_vlinkcolor
mv_all_chars             ac
mv_base_directory        bd
mv_begin_string          bs
mv_coordinate            co
mv_case                  cs
mv_dict_end              de
mv_dict_fold             df
mv_dict_limit            di
mv_dict_look             dl
mv_dict_order            do
mv_delay_page            dp
mv_record_delim          dr
mv_exact_match           em
mv_spelling_errors       er
mv_search_file           fi
mv_first_match           fm
mv_field_names           fn
mv_head_skip             hs
mv_index_delim           ix
mv_search_line_return    lr
mv_list_only             lo
mv_matchlimit            ml
mv_max_matches           mm
mv_more_matches          MM
mv_more_id               mi
mv_profile               mp
mv_min_string            ms
mv_negate                ne
mv_numeric               nu
mv_column_op             op
mv_orsearch              os
mv_return_all            ra
mv_search_immediate      si
mv_return_delim          rd
mv_return_fields         rf
mv_range_alpha           rg
mv_range_look            rl
mv_range_min             rm
mv_return_file_name      rn
mv_return_reference      rr
mv_return_spec           rs
mv_range_max             rx
mv_searchspec            se
mv_search_field          sf
mv_search_page           sp
mv_sql_query             sq
mv_searchtype            st
mv_substring_match       su
mv_sort_field            tf
mv_sort_option           to
mv_unique                un
mv_value                 va
