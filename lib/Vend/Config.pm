# Config.pm - Configure Minivend
#
# $Id: Config.pm,v 1.24 1997/11/08 16:43:44 mike Exp mike $
# 
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
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

package Vend::Config;
require Exporter;

@ISA = qw(Exporter);

@EXPORT		= qw( config global_config );

@EXPORT_OK	= qw( get_catalog_default get_global_default parse_time parse_database);


use strict;
use vars qw($VERSION $C %SetGlobals);
use Carp;
use Safe;
use Fcntl;
use Text::ParseWords;
use Vend::Util;

$VERSION = substr(q$Revision: 1.24 $, 10);

for( qw(search refresh cancel return secure unsecure submit control checkout) ) {
	$Global::LegalAction{$_} = 1;
}

my %DumpSource = (qw(
					Random				1
					Rotate				1
					ButtonBars			1
					SpecialPage			1
				));

my %DontDump = (qw(
					Catalog				1
					SubCatalog			1
					GlobalSub			1
					Random				1
					Rotate				1
					ButtonBars			1
					SpecialPage			1
					QuantityPriceRoutine 1
				));

#my %SetGlobals;

sub setcat {
	$C = $Vend::Cfg;
}

sub global_directives {

	my $directives = [
#   Order is not really important, catalogs are best first

#   Directive name      Parsing function    Default value

	['ConfigDir',		  undef,	         'etc/lib'],
    ['DumpStructure',	 'yesno',     	     'No'],
    ['PageCheck',		 'yesno',     	     'No'],
    ['DisplayErrors',    'yesno',            'No'],
    ['DisplayComments',  'yesno',            'No'],
    ['TcpPort',           undef,             '7786'],
	['Environment',      'array',            ''],
    ['TcpHost',           undef,             'localhost'],
	['SendMailProgram',  'executable',       $Global::SendMailLocation
												|| '/usr/lib/sendmail'],
    ['ForkSearches',	  undef,     	     ''],  # Prevent errors on 2.02 upgrade
	['HouseKeeping',      undef,             60],
	['Mall',	          'yesno',           'No'],
	['MaxServers',        undef,             2],
	['GlobalSub',		 'subroutine',       ''],
	['FullUrl',			 'yesno',            'No'],
	['IpHead',			 'yesno',            'No'],
	['DomainTail',		 'yesno',            'Yes'],
	['SafeSignals',	 	 'yesno',            'Yes'],
	['AcrossLocks',		 'yesno',            'No'],
    ['LogFile', 		  undef,     	     'etc/log'],
    ['SafeUntrap',       'array',            do { my $r = '249 148';
                                                  eval {require 5.00320};
                                                  unless($@) {
                                                      $r = 'ftfile sort'
                                                  }
                                                  $r } ],
	['MailErrorTo',		  undef,			 'webmaster'],
	['NoAbsolute',		 'yesno',			 'No'],
	['AllowGlobal',		 'boolean',			 ''],
	['AdminSub',		 'boolean',			 ''],
	['AdminUser',		  undef,			 ''],
	['AdminHost',		  undef,			 ''],
    ['HammerLock',		  undef,     	     30],
    ['DebugMode',		  undef,     	     0],
    ['CheckHTML',		  undef,     	     ''],
	['Variable',	  	 'variable',     	 ''],
    ['MultiServer',		 'yesno',     	     0],  # Prevent errors on 2.02 upgrade
    ['UserBuild',		 'yesno',     	     'No'],   # UNDOCUMENTED
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
	['PageDir',          'relative_dir',     'pages'],
	['ProductDir',       'relative_dir',     'products'],
	['OfflineDir',       'relative_dir',     'offline'],
	['DataDir',          'relative_dir',     'products'],
	['ConfigDir',        'relative_dir',     'config'],
	['Delimiter',        'delimiter',        'TAB'],
    ['DisplayErrors',    'yesno',            'No'],
	['RecordDelimiter',  'variable',         ''],
	['FieldDelimiter',   'variable',         ''],
    ['ParseVariables',	 'yesno',     	     'No'],
    ['SpecialPage',		 'special',     	 ''],
    ['ActionMap',		 'action',	     	 ''],
	['VendURL',          'url',              undef],
	['SecureURL',        'url',              undef],
	['OrderReport',      'valid_page',       'etc/report'],
	['ScratchDir',       'relative_dir',     'etc'],
	['SessionDatabase',  'relative_dir',     'session'],
	['SessionLockFile',  undef,     		 'etc/session.lock'],
	['Database',  		 'database',     	 ''],
	['Database',  		 'database',     	 'products products.asc 1'],
	['Sub',			  	 'variable',     	 ''],
	['SubArgs',			 'variable',     	 ''],
	['Replace',			 'replace',     	 ''],
	['Variable',	  	 'variable',     	 ''],
	['WritePermission',  'permission',       'user'],
	['ReadPermission',   'permission',       'user'],
	['SessionExpire',    'time',             '1 day'],
	['SaveExpire',       'time',             '30 days'],
	['MailOrderTo',      undef,              undef],
	['SendMailProgram',  'executable',       $Global::SendMailProgram],
	['PGP',              undef,       		 ''],
    ['Glimpse',          'executable',       ''],
    ['Locale',           'locale',           ''],
    ['RequiredFields',   undef,              ''],
    ['SqlHost',   	 	 undef,              'localhost'],
    ['MsqlProducts',   	 'warn',            ''],
    ['MsqlDB',   		 undef,              'minivend'],
    ['SqlDB',   		 undef,              'sqlvend'],
    ['ReceiptPage',      'valid_page',       ''],
    ['ReportIgnore',     undef, 			 'credit_card_no,credit_card_exp'],
    ['OrderCounter',	 undef,     	     ''],
    ['ImageAlias',	 	 'hash',     	     ''],
    ['ImageDir',	 	 undef,     	     ''],
    ['UseCode',		 	 undef,     	     'yes'],
    ['SetGroup',		 'valid_group',      ''],
    ['UseModifier',		 'array',     	     ''],
    ['TransparentItem',	 undef,     	     ''], 
    ['LogFile', 		  undef,     	     'etc/log'],
    ['CollectData', 	 'boolean',     	 ''],
    ['DynamicData', 	 'boolean',     	 ''],
    ['NoImport',	 	 'boolean',     	 ''],
    ['ProductFiles',	 'array',  	     	 ''],
    ['ProductFiles',	 'array',  	     	 'products'],
    ['CommonAdjust',	 undef,  	     	 ''],
    ['PriceAdjustment',	 'array',  	     	 ''],
    ['PriceBreaks',	 	 'array',  	     	 ''],
    ['PriceDivide',	 	 undef,  	     	 1],
    ['MixMatch',		 'yesno',     	     'No'],
    ['AlwaysSecure',	 'boolean',  	     ''],
	['Password',         undef,              ''],
    ['ExtraSecure',		 'yesno',     	     'No'],
    ['Cookies',			 'yesno',     	     'Yes'],
	['CookieDomain',     undef,              ''],
    ['MasterHost',		 undef,     	     ''],
    ['UserTag',			 'tag', 	    	 ''],
    ['RemoteUser',		 undef,     	     ''],
    ['TaxShipping',		 undef,     	     ''],
    ['OldShipping',		 'yesno',     	     'No'],
	['FractionalItems',  'yesno',			 'No'],
	['SeparateItems',    'yesno',			 'No'],
    ['PageSelectField',  undef,     	     ''],
    ['NonTaxableField',  undef,     	     ''],
    ['CyberCash',	 	 'yesno',     	     'No'],
    ['CreditCardAuto',	 'yesno',     	     'No'],
    ['CreditCards',		 'warn',     	     ''],
    ['SearchCache',	     'yesno',     	     'No'],
    ['NewTags',	     	 'yesno',    	     'No'],
    ['NoCache',	     	 'boolean',    	     ''],
    ['PageCache',	     'yesno',     	     'No'], 
    ['ClearCache',	     'yesno',     	     'No'],
    ['FormIgnore',	     'boolean',    	     ''],
    ['EncryptProgram',	 undef,     	     ''],
    ['AsciiTrack',	 	 undef,     	     ''],
    ['AsciiBackend',	 undef,     	     ''],
    ['Tracking',		 'warn',     	     ''],
    ['BackendOrder',	 undef,     	     ''],
    ['SalesTax',		 undef,     	     ''],
    ['NewReport',     	 'yesno', 			 'No'],
    ['Static',   	 	 'yesno',     	     'No'],
    ['StaticAll',		 'yesno',     	     'No'],
    ['StaticDepth',		 undef,     	     '1'],
    ['StaticFly',		 'yesno',     	     'No'],
    ['StaticDir',		 undef,     	     ''], 
    ['UserDatabase',	 undef,		     	 ''],  #undocumented, unused
    ['AdminDatabase',	 'boolean',     	 ''], 
    ['AdminPage',		 'boolean',     	 ''],
    ['LockoutCommand',	 undef,		     	 ''],  #undocumented
    ['RobotLimit',		 'integer',		      0],  #undocumented
    ['OrderLineLimit',	 'integer',		      0],  #undocumented
    ['PasswordFile',	 undef,		     	 ''],  #undocumented, unused
    ['GroupFile',		 undef,		     	 ''],  #undocumented, unused
    ['StaticPage',		 'boolean',     	 ''],
    ['StaticPath',		 undef,     	     '/'],
    ['StaticPattern',	 'regex',     	     ''],
    ['StaticSuffix',	 undef,     	     '.html'],
    ['CustomShipping',	 undef,     	     ''],
    ['DefaultShipping',	 undef,     	     'default'],
    ['UpsZoneFile',		 undef,     	     ''],
    ['OrderProfile',	 'profile',     	 ''],
    ['SearchProfile',	 'profile',     	 ''],
    ['PriceCommas',		 undef,     	     'yes'],
    ['ItemLinkDir',	 	 undef,     	     ''],
    ['FramesDefault', 	 'yesno',     	     'No'],
    ['FrameLinkDir', 	 undef,     	     'framefly'],
    ['SearchOverMsg',	 undef,           	 ''],
	['SecureOrderMsg',   'warn',             ''],
    ['SearchFrame',	 	 undef,     	     '_self'],
    ['OrderFrame',	     undef,              ''],
    ['CheckoutFrame',	 undef,              ''],
    ['CheckoutPage',	 'valid_page',       'basket'],
    ['FrameOrderPage',	 'valid_page',       ''],
    ['FrameSearchPage',	 'valid_page',       ''],
    ['FrameFlyPage',	 'valid_page',       ''],
    ['DescriptionTrim',  'warn',             ''],
    ['DescriptionField', undef,              'description'],
    ['PriceField',		 undef,              'price'],
    ['ItemLinkValue',    undef,              'More Details'],
	['FinishOrder',      undef,              'Finish Incomplete Order'],
	['Shipping',         undef,               0],
	['Help',            'help',              ''],
	['Random',          'random',            ''],
	['Rotate',          'random',            ''],
	['ButtonBars',      'buttonbar',         ''],
	['Mv_Background',   'color',             ''],
	['Mv_BgColor',      'color',             ''],
	['Mv_TextColor',    'color',             ''],
	['Mv_LinkColor',    'color',             ''],
	['Mv_AlinkColor',   'color',             ''],
	['Mv_VlinkColor',   'color',             ''],

    ];
	return $directives;
}

sub set_directive {
	my ($directive, $value) = @_;
	my $directives = catalog_directives();
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

sub substitute_variable {
	my($val) = @_;
print "before=$val\n" if $Global::DEBUG;
	# Return after globals so can others can be contained
	$val =~ s/\@\@([A-Z][A-Z_0-9]+[A-Z0-9])\@\@/$Global::Variable->{$1}/g
		and return $val;
	return $val unless $val =~ /([_%])\1/;
	1 while $val =~ s/__([A-Z][A-Z_0-9]+[A-Z0-9])__/$C->{Variable}->{$1}/g;
print " after=$val\n" if $Global::DEBUG;
	# YALOS (yet another level)
	return $val unless $val =~ /%%[A-Z]/;
	$val =~ s/%%([A-Z][A-Z_0-9]+[A-Z0-9])%%/$Global::Variable->{$1}/g;
	$val =~ s/__([A-Z][A-Z_0-9]+[A-Z0-9])__/$C->{Variable}->{$1}/g;
print "  post=$val\n" if $Global::DEBUG;
	return $val;
}

## CONFIG

# Parse the configuration file for directives.  Each directive sets
# the corresponding variable in the Vend::Cfg:: package.  E.g.
# "DisplayErrors No" in the config file sets Vend::Cfg->{DisplayErrors} to 0.
# Directives which have no default value ("undef") must be specified
# in the config file.

sub config {
	my($catalog, $dir, $confdir, $subconfig, $options) = @_;
    my($directives, $d, %name, %parse, $var, $value, $lvar, $parse);
    my($directive);
	my $filecount = 0;

	$C = {};
	$C->{'CatalogName'} = $catalog;
	$C->{'VendRoot'} = $dir;
	$C->{'ConfDir'} = $confdir;

	$options = {} unless defined $options;

	unless (defined $subconfig) {
		$C->{'ErrorFile'} = $Global::ErrorFile;
		$C->{'ConfigFile'} = defined $Global::Standalone
							 ? 'minivend.cfg' : 'catalog.cfg';
	}
	else {
        $C->{'ConfigFile'} = "$catalog.cfg";
		$C->{'BaseCatalog'} = $subconfig;
	}

    no strict 'refs';

    $directives = catalog_directives();

	foreach $d (@$directives) {
		($directive = $d->[0]) =~ tr/A-Z/a-z/;
		$name{$directive} = $d->[0];
		if (defined $d->[1]) {
			$parse = 'parse_' . $d->[1];
		} else {
			$parse = undef;
		}
		$parse{$directive} = $parse;

		# We don't set up defaults if it is a subconfiguration
		next if defined $subconfig;

		$value = $d->[2];
		if (defined $parse and defined $value and ! defined $subconfig) {
			$value = &$parse($d->[0], $value);
		}
		$C->{$name{$directive}} = $value;
	}

	my(@include) = ();
	my $done_one;
	my ($before, $after);

CONFIGLOOP: {

	# See if anything is defined in options to do before the
	# main configuration file.  If there is a file, then we
	# will do it (after pushing the main one on @include).
	# If there is a structure defined, we will copy it over
	# (strings will be evaled first).
	# 
	# We delete the 'before' structure to ensure this will only happen
	# once.
	#
	# No replace (as in after) as there is nothing to replace yet. 8-)

	if(defined $options->{before}) {
		$before = delete $options->{before};

		# normally you would not use if -stream was defined
		if (defined $before->{file}) {
			push @include, $C->{ConfigFile};
			$C->{ConfigFile} = $before->{file};
		}

		# normally you would not use if -file was defined
		if (defined $before->{stream}) {
			my $file = "tmpconfig.$$." . $filecount++;
			open(TEMPCONFIG, ">$file")		or die "creat $file: $!\n";
			print TEMPCONFIG $before->{stream};
			close TEMPCONFIG;
			push @include, $file;
		}

		if ($before->{structure}) {
			my $ref = $before->{structure};
			for (keys %$ref) {
				$ref->{$_} = eval $ref->{$_} if 
					$ref->{$_} =~ /^\s*[{\[]/;
			}
			copyref $before->{structure}, $C;
		}
	}

    open(Vend::CONFIG, $C->{ConfigFile})
		or do {
			my $msg = "Could not open configuration file '" . $C->{ConfigFile} .
					"' for catalog '" . $catalog . "':\n$!";
			if(defined $done_one) {
				warn "$msg\n";
				open (Vend::CONFIG, '');
			}
			else {
				die "$msg\n";
			}
		};
    while(<Vend::CONFIG>) {
		chomp;			# zap trailing newline,
		if(/^\s*#include\s+(\S+)/) {
			push @include, $1;
			next;
		}
		s/^\s*#.*//;    # comments,
		s/\s+$//;		#  trailing spaces
		next if $_ eq '';
		$Vend::config_line = $_;
		# lines read from the config file become untainted
		m/^(\w+)\s+(.*)/ or config_error("Syntax error");
		$var = $1;
		$value = $2;
		($lvar = $var) =~ tr/A-Z/a-z/;
		my($codere) = '[\w-_#/.]+';

		if ($value =~ /^(.*)<<(.*)/) {                  # "here" value
			my $begin  = $1 || '';
			my $mark  = $2;
			my $startline = $.;
			$value = $begin . read_here(\*Vend::CONFIG, $mark);
			unless (defined $value) {
				config_error (sprintf('%d: %s', $startline,
					qq#no end marker ("$mark") found#));
			}
		}
		elsif ($value =~ /^(\S+)?(\s*)?<\s*($codere)$/o) {   # read from file
			#local($) = 0;
			$value = $1 || '';
			my $file = $3;
			$value .= "\n" if $value;
			unless (defined $C->{ConfigDir}) {
				config_error
					("$name{$lvar}: Can't read from file until ConfigDir defined");
			}
			$file = $name{$lvar} unless $file;
			if($Global::NoAbsolute) {
			config_error(
			  "No leading / allowed if NoAbsolute set. Contact administrator.\n")
				if $file =~ m.^/.;
			config_error(
			  "No leading ../.. allowed if NoAbsolute set. Contact administrator.\n")
				if $file =~ m#^\.\./.*\.\.#;
			config_error(
			  "Symbolic links not allowed if NoAbsolute set. Contact administrator.\n")
				if -l $file;
			}
			$file = "$C->{ConfigDir}/$file" unless $file =~ m!^/!;
			$file = escape_chars($file);			# make safe for filename
			my $tmpval = readfile($file);
			unless( defined $tmpval ) {
				config_warn ("$name{$lvar}: read from non-existent file, skipping.");
				next;
			}
			chomp($tmpval) unless $tmpval =~ m!.\n.!;
			$value .= $tmpval;
		}
			
		# Don't error out on Global directives if we are standalone, just skip
		next if defined $Global::Standalone && defined $SetGlobals{$lvar};

		# Now we can give an unknown error
		config_error("Unknown directive '$var'") unless defined $name{$lvar};

		$parse = $parse{$lvar};
					# call the parsing function for this directive
		if($C->{ParseVariables} and $value =~ /([_%@])\1/) {
			save_variable($name{$lvar}, $value);
			$value = substitute_variable($value);
		}
		$value = &$parse($name{$lvar}, $value) if defined $parse;
					# and set the $C->directive variable
		$C->{$name{$lvar}} = $value;
    }
	$done_one = 1;
    close Vend::CONFIG;

	# See if anything is defined in options to do after the
	# main configuration file.  This includes any command-line
	# options other than the before= stuff. If there is a file, then we
	# will do it 
	#
	# If there is a replace key defined, we will TOTALLY
	# REPLACE all defined options in that section. Be careful.
	#
	# If there is a structure defined, we will copy it over
	# (strings will be evaled first). It will not destroy
	# definitions already there, but if you want to remove a
	# key you will have to replace first.
	# 
	# We delete the 'after' structure to ensure this will only happen
	# once. If you want this repeatable, you will have to
	# restart the program or supply a whole new structure,
	# both before and after.
	if(defined $options->{after}) {
		my $after = delete $options->{after};
		if (defined $after->{file}) {
			push @include, $after->{file};
		}

		if (defined $after->{replace}) {
			my $ref = $after->{replace};
			for (keys %$ref) {
				$ref->{$_} = eval $ref->{$_} if 
					$ref->{$_} =~ /^\s*[{\[]/;
			}
			for (keys %{$after->{replace}}) {
				$C->{$_} = $after->{replace}->{$_};
			}
		}
		if ($after->{structure}) {
			my $ref = $after->{structure};
			for (keys %$ref) {
				$ref->{$_} = eval $ref->{$_} if 
					$ref->{$_} =~ /^\s*[{\[]/;
			}
			copyref $after->{structure}, $C;
		}

		if (defined $after->{stream}) {
			my $file = "tmpconfig.$$." . $filecount++;
			open(TEMPCONFIG, ">$file")		or die "creat $file: $!\n";
			print TEMPCONFIG $after->{stream};
			close TEMPCONFIG;
			push @include, $file;
		}
	}

	if(@include) {
		$C->{ConfigFile} = shift @include;
		redo CONFIGLOOP;
	}

} # end CONFIGLOOP
    # check for unspecified directives that don't have default values

	REQUIRED: {
		last REQUIRED if defined $subconfig;
		foreach $var (keys %name) {
			if (!defined $C->{$name{$var}}) {
				die "Please specify the $name{$var} directive in the\n" .
				"configuration file '$C->{'ConfigFile'}'\n";
			}
		}
	}
	$C->{'Special'} = $C->{'SpecialPage'} if defined $C->{SpecialPage};
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
	$value;
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
		$value = $d->[2];

		if (defined $DumpSource{$name{$directive}}) {
			$Global::Structure{ $name{$directive} } = $value;
		}

		if (defined $parse and defined $value) {
			$value = &$parse($d->[0], $value);
		}

		${'Global::' . $name{$directive}} = $value;

		$Global::Structure{ $name{$directive} } = $value
			unless defined $DontDump{ $name{$directive} };

    }

	my (@include);
	my $configfile = $Global::ConfigFile;
GLOBLOOP: {
    open(Vend::GLOBAL, $configfile)
		or die "Could not open configuration file '" .
                $configfile . "':\n$!\n";
    while(<Vend::GLOBAL>) {
		chomp;			# zap trailing newline,
        if(/^\s*#include\s+(\S+)/) {
            push @include, $1;
            next;
        }
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
		my($codere) = '[\w-_#/.]+';

		if ($value =~ /^(.*)<<(.*)/) {                  # "here" value
			my $begin = $1 || '';
			my $mark = $2;
			my $startline = $.;
			$value = $begin . read_here(\*Vend::GLOBAL, $mark);
			unless (defined $value) {
				config_error (sprintf('%d: %s', $startline,
					qq#no end marker ("$mark") found#));
			}
		}
		elsif ($value =~ /^(\S+)?(\s*)?<\s*($codere)$/o) {   # read from file
			#local($) = 0;
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
				config_warn ("$name{$lvar}: read from non-existent file, skipping.");
				next;
			}
			chomp($tmpval) unless $tmpval =~ m!.\n.!;
			$value .= $tmpval;
		}

		# Error out on extra parameters only if we know
		# we are not standalone
		unless (defined $name{$lvar}) {
			next unless $seen_catalog;
			config_error("Unknown directive '$var'")
		}
		else {
			$seen_catalog = 1 if $lvar eq 'catalog';
			$SetGlobals{$lvar} = 1;
		}

		$parse = $parse{$lvar};
					# call the parsing function for this directive

		if (defined $DumpSource{$name{$directive}}) {
			$Global::Structure{ $name{$directive} } = $value;
		}

		$value = &$parse($name{$lvar}, $value) if defined $parse;
					# and set the Global::directive variable
		${'Global::' . $name{$lvar}} = $value;
		$Global::Structure{ $name{$lvar} } = $value
			unless defined $DontDump{ $name{$lvar} };
    }
    close Vend::GLOBAL;
    if(@include) {
        $configfile = shift @include;
        redo GLOBLOOP;
    }
} # end GLOBLOOP;

    # check for unspecified directives that don't have default values
    foreach $var (keys %name) {
        if (!defined ${'Global::' . $name{$var}}) {
            die "Please specify the $name{$var} directive in the\n" .
            "configuration file '$Global::ConfigFile'\n";
        }
    }

	unless($Global::Catalog) {
		print "Configuring standalone catalog...";
		$Global::Standalone = 0;
		$Global::Standalone =
			 config('standalone', $Global::VendRoot, $Global::ConfDir);
		print "done.\n";
	}

	dump_structure(\%Global::Structure, $Global::ConfigFile)
		if $Global::DumpStructure;
}

1;

# Report an error MSG in the configuration file.

sub config_error {
    my($msg) = @_;
	my $name = defined $C ? $C->{ConfigFile} : 'minivend.cfg';

    die "$msg\nIn line $. of the configuration file '$name':\n" .
	"$Vend::config_line\n";
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
		config_error(
		  "No leading ../.. allowed if NoAbsolute set. Contact administrator.\n")
		if $file =~ m#^\.\./.*\.\.# and $Global::NoAbsolute;
##print "Got to get_files: '$dir' '@files'\n" if $Global::DEBUG;
		push(@out,"\n") unless
			push(@out,readfile("$dir/$file.html"));
	}
	
	@out;
}

# Uncomment to autoload
#1;
#__END__

# Report a warning MSG about the configuration file.

sub config_warn {
    my($msg) = @_;
	my $name = defined $C ? $C->{ConfigFile} : 'minivend.cfg';

    logGlobal("$msg\nIn line $. of the configuration file '" .
	     $name . "':\n" . $Vend::config_line . "\n");
}

# Allow a subcatalog value to completely replace a base value
sub parse_replace {
    my($name, $val) = @_;

	return {} unless $val;

    $C->{$val} = get_catalog_default($val);
	$C->{$name}->{$val} = 1;
	$C->{$name};
}

# Warn about directives no longer supported in the configuration file.

sub parse_warn {
    my($name, $val) = @_;

	return '' unless $val;

    my $msg = "The $name directive is no longer supported.";
    logGlobal("$msg\nIn line $. of the configuration file '" .
         $name . "':\n" . $Vend::config_line . "\n");
}

# Each of the parse functions accepts the value of a directive from the
# configuration file as a string and either returns the parsed value or
# signals a syntax error.

# Sets a boolean array for any type of item
sub parse_boolean {
	my($item,$settings) = @_;
	my(@setting) = split /[\s,]+/, $settings;
	my $c;
	unless (@setting) {
		$c = {};
		return $c;
	}

	$c = $C->{$item};

	for (@setting) {
		$c->{$_} = 1;
	}
	return $c;
}

# Adds an action to the Action Map
# Deletes if the action is delete
sub parse_action {
	my($item,$setting) = @_;

	unless ($setting) {
		# Set the initial action map
		my $c = {};
		%$c = (
		'account'		=>  'secure',
		'browse'		=>  'return',
		'cancel'		=>  'cancel',
		'check out'		=>  'checkout',
		'checkout'		=>  'checkout',
		'control'		=>  'control',
		'find'			=>  'search',
		'log out'		=>  'cancel',
		'order'			=>  'submit',
		'place'			=>  'submit',
		'place order'	=>  'submit',
		'recalculate'	=>  'refresh',
		'refresh'		=>  'refresh',
		'return'		=>  'return',
		'scan'			=>  'scan',
		'search'		=>  'search',
		'secure'		=>  'secure',
		'submit order'	=>  'submit',
		'submit'		=>  'submit',
		'unsecure'		=>  'unsecure',
		'update'		=>  'refresh',
		);
		return $c;
	}

	my($action,$string) = split /\s+/, $setting, 2;
	$action = lc $action;
	return delete $C->{'ActionMap'}->{$string} if $action eq 'delete';
	$C->{'ActionMap'}->{$string} = $action;
	config_error("Unrecognized action '$action'")
		unless $Global::LegalAction{$action};
	return $C->{'ActionMap'};
}

use POSIX;

# Sets the special locale array. Tries to use POSIX setlocale,
# accepts a 'custom' setting with the proper definitions of
# decimal_point,  mon_thousands_sep, and frac_digits (the only supported at
# the moment).  Otherwise uses US-English settings if not set.
sub parse_locale {
    my($item,$settings) = @_;
	return '' unless $settings;
	$settings = '' if "\L$settings" eq 'default';
    my $name;
    my $c = {};

    # Try POSIX first.
    $name = POSIX::setlocale(POSIX::LC_ALL, $settings);

    if (defined $name and $name) {
        $c = POSIX::localeconv();
        $c->{mon_thousands_sep} = ','
            unless $c->{mon_thousands_sep};
        $c->{decimal_point} = '.'
            unless $c->{decimal_point};
        $c->{frac_digits} = 2
            unless defined $c->{frac_digits};
        $c->{Name} = $name;
    }
    # else Try to read the ones we have defined
    elsif($settings eq 'pt') {
        $c->{decimal_point} = ',';
        $c->{mon_thousands_sep} = '.';
        $c->{frac_digits} = 2;
        $c->{Name} = 'Portugal';
    }
    elsif ($settings =~ /^custom\s+/) {

        my(@setting) = split /\s+/, $settings;
        $c->{Name} = shift(@setting);
        my(%setting) = @setting;
        for (keys %setting) {
            $c->{$_} = $setting{$_};
        }
        $c->{mon_thousands_sep} = ','
            unless $c->{mon_thousands_sep};
        $c->{decimal_point} = '.'
            unless $c->{decimal_point};
        $c->{frac_digits} = 2
            unless defined $c->{frac_digits};
    }
    else {
        config_error("Bad Locale setting $settings.\n");
    }

    return $c;
}


# Sets the special page array
sub parse_special {
	my($item,$settings) = @_;
	unless ($settings) {
		my $c = {};
	# Set the special page array
		%$c = (
		qw(
			badsearch		badsearch
			canceled		canceled
			catalog			catalog
			checkout		checkout
			confirmation	confirmation
			control			control
			failed			failed
			flypage			flypage
			interact		interact
			missing			missing	
			needfield		needfield
			nomatch			nomatch
			noproduct		noproduct
			notfound		notfound
			order			order
			search			search
			violation		violation
			)
		);
		return $c;
	}
	my(%setting) = grep /\S/, split /[\s,]+/, $settings;
	for (keys %setting) {
		$C->{'SpecialPage'}->{$_} = $setting{$_};
	}
	return $C->{'SpecialPage'};
}

sub parse_hash {
	my($item,$settings) = @_;
	my(@setting) = grep /\S/, split /[\s,]+/, $settings;

	my $c;

	unless (@setting) {
		$c = {};
		return $c;
	}

	$c = $C->{$item};

	my $i;
	for ($i = 0; $i < @setting; $i += 2) {
		$c->{$setting[$i]} = $setting[$i + 1];
	}
	$c;
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
		push @{$c}, $_;
	}
	$c;
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

# Prepend the VendRoot pathname to the relative directory specified,
# unless it already starts with a leading /.

sub parse_relative_dir {
    my($var, $value) = @_;

    config_error(
      "Please specify the VendRoot directive before the $var directive\n")
		unless defined $C->{'VendRoot'};
		config_error(
		  "No leading / allowed if NoAbsolute set. Contact administrator.\n")
		if $value =~ m.^/. and $Global::NoAbsolute;
		config_error(
		  "No leading ../.. allowed if NoAbsolute set. Contact administrator.\n")
		if $value =~ m#^\.\./.*\.\.# and $Global::NoAbsolute;
	
    $value = "$C->{'VendRoot'}/$value" unless $value =~ m.^/.;
    $value =~ s./$..;
    $value;
}


sub parse_integer {
    my($var, $value) = @_;

    config_error("The $var directive (now set to '$value') must be an integer\n")
		unless $value =~ /^\d+$/;
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
    config_error("$var: MiniVend user '$name' not in group '$value'\n")
		unless $members =~ /\b$name\b/;
    $gid;
}

sub parse_valid_page {
    my($var, $value) = @_;
    my($page,$x);

	return $value if !$C->{'PageCheck'};

	if( ! defined $value or $value eq '') {
		return $value;
	}

    config_error("Can't find valid page ('$value') for the $var directive\n")
		unless -s "$C->{'PageDir'}/$value.html";
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

	$C->{'Source'}->{$var} = $value;

    $n = time_to_seconds($value);
    config_error("Bad time format ('$value') in the $var directive\n")
	unless defined $n;
    $n;
}

sub parse_catalog {
	my ($var, $value) = @_;
	my $num = ! defined $Global::Catalog ? 0 : $Global::Catalog;
	return $num unless (defined $value && $value); 

	my($name,$base,$dir,$script);
	if($var =~ /subcatalog/i) {
		($name,$base,$dir,$script) = split /[\s,]+/, $value, 4;
		${Global::Catalog{$name}}->{'base'} = $base;
	}
	else {
		($name,$dir,$script) = split /[\s,]+/, $value, 3;
	}

print "parsing name=$name dir=$dir script=$script\n" if $Global::DEBUG;

	$Global::Catalog{$name}->{'name'} = $name;
	$Global::Catalog{$name}->{'dir'} = $dir;

	my(@scripts) = split /[\s,]+/, $script;

	# Strip leading http:// if present
	for(@scripts) { s!^http://!! }

	# Define the main script name and array of aliases
	${Global::Catalog{$name}}->{'script'} = shift @scripts;
	${Global::Catalog{$name}}->{'alias'} = [@scripts]
		if @scripts;
	return ++$num;
}

my %Hash_ref = (  qw!
							COLUMN_DEF   COLUMN_DEF
					! );

my %Ary_ref = (   qw!
							NAME         NAME
							NUMERIC      NUMERIC
							BINARY       BINARY 
					! );


sub parse_database {
	my ($var, $value) = @_;
	my ($c, $new);
	unless (defined $value && $value) { 
		$c = {};
		return $c;
	}
	$c = $C->{'Database'};

	my($database,$remain) = split /[\s,]+/, $value, 2;
	
	if($database ne 'products') {
		$new = 1 if ! defined $c->{$database};
	}
	elsif( defined $c->{$database}->{",default"} ) {
		$new = 1 if not defined $c->{$database}->{",initialized"};
		$c->{$database}->{",initialized"} = 1;
	}
	else {
		$c->{$database}->{",default"} = 1;
		$new = 1;
	}
	
	$c->{$database}->{'name'} = $database;
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
		elsif(	$type =~ /^msql\b/i	) {
			$d->{'type'} = 7;
		}
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
			$d->{'DELIMITER'} = $type;
		}
	}
	else {
		my($p, $val) = split /\s+/, $remain, 2;
		$p = uc $p;

		if(defined $Hash_ref{$p}) {
			my($k, $v);
			my(@v) = quoted_comma_string($val);
			$d->{$p} = {} unless defined $d->{$p};
			for(@v) {
				($k,$v) = split /\s*=\s*/, $_;
				$d->{$p}->{$k} = $v;
			}
		}
		elsif(defined $Ary_ref{$p}) {
			my(@v) = quoted_string($val);
			$d->{$p} = [] unless defined $d->{$p};
			push @{$d->{$p}}, @v;
		}
		else {
			config_warn "Database '$database' scalar parameter '$p' redefined."
				if defined $d->{$p};
			$d->{$p} = $val;
		}
	}
	if($Global::DEBUG) {
		print "Defining database $database\n";
		for (keys %$d) {
			print "$_=$d->{$_}\n";
		}
	}
		
	return $c;
}

sub parse_profile {
	my ($var, $value) = @_;
	my ($c, $n, $i);
	unless (defined $value && $value) { 
		$c = [];
		$C->{"${var}Name"} = {};
		return $c;
	}

	$c = $C->{$var};

	$C->{'Source'}->{$var} = $value;

	$n = $C->{"${var}Name"};

	my (@files) = split /[\s,]+/, $value;
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
		if($c->[$i] =~ s/(^|\n)__NAME__\s+(.+)\n//) {
			my $name = $2;
			$n->{$name} = $i;
		}
	}

	return $c;
}

# Designed to parse catalog subroutines and all vars
sub save_variable {
	my ($var, $value) = @_;
	my ($c, $name, $param);

	return 0 unless $var eq 'Variable';

    if(defined $C) {
        $c = $C->{$var};
    }
    else { 
        no strict 'refs';
        $c = ${"Global::$var"};
    }

	$value =~ s/^\s*(\w+)\s*//;
	$name = $1;
	return 1 if defined $c->{'save'}->{$name};
	$value =~ s/\s+$//;
	$c->{'save'}->{$name} = $value;
	return 1;
}

my %tagCanon = ( qw(
     alias        	 Alias
     order           Order
     posnumber       PosNumber
     posroutine      PosRoutine
     required        Required
     routine         Routine
     cannest         canNest
     hasendtag       hasEndTag
     interpolate     Interpolate
     isendanchor     isEndAnchor
     invalidatecache InvalidateCache
));


my %tagAry 	= ( qw! Order 1 Required 1 ! );
my %tagBool = ( qw!
				hasEndTag	1
				Interpolate 1
				Implicit 	1
				canNest		1
				isEndAnchor	1
				isOperator	1
				! );

# Parses the user tags
sub parse_tag {
	my ($var, $value) = @_;
	my ($c, $new);
	unless (defined $value && $value) { 
		$c = {};
		return $c;
	}
	$c = $C->{'UserTag'};

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

		unless($Global::AllowGlobal->{$C->{CatalogName}}) {
			my $safe = new Safe;
			my $code = $val;
#print("Safe check $tag $code\n") if $Global::DEBUG;
			$safe->untrap(@{$Global::SafeUntrap});
			$sub = $safe->reval($code);
			if($@) {
				config_warn "UserTag '$tag' subroutine failed safe check: $@";
				return $c;
			}
		}
		eval {
			$sub = eval $val;
		};
		if($@) {
			config_warn "UserTag '$tag' subroutine failed compilation: $@";
			return $c;
		}
		config_warn "UserTag '$tag' code is not a subroutine reference"
			unless $sub =~ /CODE/;
print("Routine is $sub\n") if $Global::DEBUG;
		$c->{$p}{$tag} = $sub;
		$c->{Order}{$tag} = []
			unless defined $c->{Order}{$tag};
	}
	elsif(defined $tagAry{$p}) {
		my(@v) = quoted_string($val);
		$c->{$p}{$tag} = [] unless defined $c->{$p}{$tag};
		push @{$c->{$p}{$tag}}, @v;
	}
	elsif(defined $tagBool{$p}) {
		$c->{$p}{$tag} = 1
			unless defined $val and $val =~ /^[0nf]/i;
	}
	else {
		config_warn "UserTag '$tag' scalar parameter '$p' redefined."
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

# Designed to parse catalog subroutines and all vars
sub parse_variable {
	my ($var, $value) = @_;
	my ($c, $name, $param);

	# Allow certain catalogs global subs
	if($var eq 'Sub' and $Global::AllowGlobal->{$C->{CatalogName}}) {
		return parse_subroutine(@_);
	}
	unless (defined $value and $value) { 
		$c = { 'save' => {} };
		return $c;
	}

	if(defined $C) {
		$c = $C->{$var};
	}
	else {
		no strict 'refs';
print("global ") if $Global::DEBUG;
		$c = ${"Global::$var"};
	}

	if($value =~ s/^\s*sub\s+(\w+)\s*{\s*//) {
		$name = $1;
		($param = $value) =~ s/}\s*$//;
	}
	elsif($value =~ s/^\s*literal\s+(\w+)\r?\n//) {
		$name = $1;
		$value =~ s/\n$//;
		$param = $value;
	}
	elsif($value =~ /\n/) {
		($name, $param) = split /\r?\n/, $value, 2;
		$name =~ s/^\s+//;
		$name =~ s/\s+$//;
		chomp $param;
	}
	else {
		($name, $param) = split /\s+/, $value, 2;
	}
print("variable $name\n") if $Global::DEBUG;
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
	$c = ${"Global::$var"}
		unless defined $C;

	$value =~ s/\s*sub\s+(\w+)\s*{/sub {/;
	config_error("Bad $var: no subroutine name? ") unless $name = $1;
	# Untainting
	$value =~ /([\000-\377]*)/;
	$value = $1;

	$c->{$name} = eval $value;
	config_error("Bad $var '$name'") if $@;
	return $c;
}

sub parse_buttonbar {
	my ($var, $value) = @_;
	my ($c);
	unless (defined $value and $value) { 
		$c = [];
		return $c;
	}
	$c = $C->{'ButtonBars'};

	$C->{'Source'}->{'ButtonBars'} = $value;

	@{$c}[0..15] = get_files($C->{'PageDir'}, split /\s+/, $value);
	return $c;
}

sub parse_delimiter {
	my ($var, $value) = @_;

	return "\t" unless (defined $value && $value); 

	$C->{'Source'}->{$var} = $value;
	
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
	my ($c, $chunk, $item, $help, $key);
	unless (defined $value && $value) { 
		$c = {};
		return $c;
	}
	$c = $C->{'Help'};
	$var = lc $var;
	$C->{'Source'}->{'Help'} = $value;
	@files = get_files($C->{'PageDir'}, split /\s+/, $value);
	foreach $chunk (@files) {
		@items = split /\n\n/, $chunk;
		foreach $item (@items) {
			($key,$help) = split /\s*\n/, $item, 2;
			if(defined $c->{$key}) {
				$c->{$key} .= $help;
			}
			else {
				$c->{$key} = $help;
			}
				
		}
	}
	return $c;
}
		

sub parse_random {
	my ($var, $value) = @_;
	return '' unless (defined $value && $value); 
	my $c = [];
	$var = lc $var;
	$C->{'Source'}->{'Random'} = $value;
	@{$c} = get_files($C->{'PageDir'}, split /\s+/, $value);
	return $c;
}
		
sub parse_color {
    my ($var, $value) = @_;
	return '' unless (defined $value && $value);
    $var = lc $var;
	$C->{Color}->{$var} = [];
    @{$C->{'Color'}->{$var}}[0..15] = split /\s+/, $value, 16;
    return $value;
}
    

# Returns 1 for Yes and 0 for No.

sub parse_yesno {
    my($var, $value) = @_;
#print "$var=$value\n" if $Global::DEBUG;
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
__END__

