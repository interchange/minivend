# Vend::Order - Interchange order routing routines
#
# $Id$
#
# Copyright (C) 1996-2001 Red Hat, Inc. <interchange@redhat.com>
#
# This program was originally based on Vend 0.2 and 0.3
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# CyberCash 3 native mode enhancements made by and
# Copyright 1998 by Michael C. McCune <mmccune@ibm.net>
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

package Vend::Order;
require Exporter;

$VERSION = substr(q$Revision$, 10);

@ISA = qw(Exporter);

@EXPORT = qw (
	add_items
	check_order
	check_required
	cyber_charge
	encrypt_standard_cc
	mail_order
	onfly
	route_order
	validate_whole_cc
);

push @EXPORT, qw (
	send_mail
);

use Vend::Util;
use Vend::Interpolate;
use Vend::Session;
use Vend::Data;
use Text::ParseWords;
use strict;

use autouse 'Vend::Error' => qw/do_lockout/;

my @Errors = ();
my $Fatal = 0;
my $And;
my $Final = 0;
my $Success;
my $Profile;
my $Tables;
my $Fail_page;
my $Success_page;
my $No_error;
use vars qw/$OrderCheck/;

my %Parse = (

	'&charge'       =>	\&_charge,
	'&credit_card'  =>	\&_credit_card,
	'&return'       =>	\&_return,
	'&fatal'       	=>	\&_fatal,
	'&and'       	=>	\&_and_check,
	'&or'       	=>	\&_or_check,
	'&format'		=> 	\&_format,
	'&tables'		=> 	sub { $Tables = $_[1]; return 1; },
	'&noerror'		=> 	sub { $No_error = $_[1] },
	'&success'		=> 	sub { $Success_page = $_[1] },
	'&fail'         =>  sub { $Fail_page    = $_[1] },
	'&final'		=>	\&_final,
	'&calc'			=>  sub { Vend::Interpolate::tag_calc($_[1]) },
	'&perl'			=>  sub { Vend::Interpolate::tag_perl($Tables, {}, $_[1]) },
	'&test'			=>	sub {		
								my($ref,$params) = @_;
								$params =~ s/\s+//g;
								return $params;
							},
	'length'		=>  sub {
							my($name, $value, $msg) = @_;
							$msg =~ s/^(\d+)(?:\s*-(\d+))?\s*//
								or return undef;
							my $min = $1;
							my $max = $2;
							my $len = length($value);

							if($len < $min) {
								$msg = errmsg(
										"%s length %s less than minimum length %s.",
										$name,
										$len,
										$min) if ! $msg;
								return(0, $name, $msg);
							}
							elsif($max and $len > $max) {
								$msg = errmsg(
										"%s length %s more than maximum length %s.",
										$name,
										$len,
										$max) if ! $msg;
								return(0, $name, $msg);
							}
							return (1, $name, '');
						},
	'filter'			=> sub {		
							my($name, $value, $code) = @_;
							my $message;
							my $filter;

							$code =~ s/\\/\\\\/g;
							if($code =~ /(["']).+?\1$/) {
								my @code = Text::ParseWords::shellwords($code);
								$message = pop(@code);
								$filter = join " ", @code;
							}
							else {
								($filter, $message) = split /\s+/, $code, 2;
							}

							my $test = Vend::Interpolate::filter_value($filter, $value, $name);
							if($test ne $value) {
								$message ||= errmsg("%s caught by filter %s", $name, $filter);
								return ( 0, $name, $message);
							}
							return (1, $name, '');
						},
	'regex'			=>	sub {		
							my($name, $value, $code) = @_;
							my $message;

							$code =~ s/\\/\\\\/g;
							my @code = Text::ParseWords::shellwords($code);
							if($code =~ /(["']).+?\1$/) {
								$message = pop(@code);
							}

							for(@code) {
								my $negate;
								s/^!\s*// and $negate = 1;
								my $op = $negate ? "!~" :  '=~';
								my $regex = qr($_);
								my $status;
								if($negate) {
									$status = ($value !~ $regex);
								}
								else {
									$status = ($value =~ $regex);
								}
								if(! $status) {
									$message = errmsg(
										"failed pattern - %s",
										"'$value' $op $_"
										) if ! $message;
									return ( 0, $name, $message);
								}
							}
							return (1, $name, '');
						},
	'unique'			=> sub {
							my($name, $value, $code) = @_;

							$code =~ s/(\w+)\s*//;
							my $tab = $1
								or return (0, $name, errmsg("no table specified"));
							my $msg = $code;

							my $db = database_exists_ref($tab)
								or do {
									$msg = errmsg(
										"Table %s doesn't exist",
										$tab,
									);
									return(0, $name, $msg);
								};
							if($db->record_exists($value)) {
								$msg = errmsg(
										"Key %s already exists in %s, try again.",
										$value,
										$tab,
									) unless $msg;
								return(0, $name, $msg);
							}
							return (1, $name, '');
						},
	'&set'			=>	sub {		
								my($ref,$params) = @_;
								my ($var, $value) = split /\s+/, $params, 2;
								$::Values->{$var} = $value;
							},
	'&setcheck'			=>	sub {		
								my($ref,$params) = @_;
								my ($var, $value) = split /\s+/, $params, 2;
								$::Values->{$var} = $value;
								my $msg = errmsg("%s set failed.", $var);
								return ($value, $var, $msg);
							},
);


sub _fatal {
	$Fatal = ( defined($_[1]) && ($_[1] =~ /^[yYtT1]/) ) ? 1 : 0;
}

sub _final {
	$Final = ( defined($_[1]) && ($_[1] =~ /^[yYtT1]/) ) ? 1 : 0;
}

sub _return {
	$Success = ( defined($_[1]) && ($_[1] =~ /^[yYtT1]/) ) ? 1 : 0;
}

sub _format {
	my($ref, $params, $message) = @_;
	no strict 'refs';
	my ($routine, $var, $val) = split /\s+/, $params, 3;

	my (@return);

::logDebug("OrderCheck = $OrderCheck routine=$routine");
	my $sub;
	my @args;
	if( $sub = $Parse{$routine}) {
		@args = ($var, $val, $message);
		undef $message;
	}
	elsif ($OrderCheck and $sub = $OrderCheck->{$routine}) {
::logDebug("Using coderef OrderCheck = $sub");
		@args = ($ref,$var,$val);
	}
	elsif (defined &{"_$routine"}) {
		$sub = \&{"_$routine"};
		@args = ($ref,$var,$val);
	}
	else {
		return (undef, $var, errmsg("No format check routine for '%s'", $routine));
	}

	@return = $sub->(@args);

	if(! $return[0] and $message) {
		$return[2] = $message;
	}
	return @return;
}

sub chain_checks {
	my ($or, $ref, $checks, $err) = @_;
	my ($var, $val, $mess, $message);
	my $result = 1;
	$mess = "$checks $err";
	while($mess =~ s/(\S+=\w+)[\s,]*//) {
		my $check = $1;
		($val, $var, $message) = do_check($check);
		return undef if ! defined $var;
		if($val and $or) {
			1 while $mess =~ s/(\S+=\w+)[\s,]*//;
			return ($val, $var, $message)
		}
		elsif ($val) {
			$result = 1;
			next;
		}
		else {
			next if $or;
			1 while $mess =~ s/(\S+=\w+)[\s,]*//;
			return($val, $var, $mess);
		}
	}
	return ($val, $var, $mess);
}

sub _and_check {
	if(! length($_[1]) ) {
		$And = 1;
		return (1);
	}
	return chain_checks(0, @_);
}

sub _or_check {
	if(! length($_[1]) ) {
		$And = 0;
		return (1);
	}
	return chain_checks(1, @_);
}

sub _charge {
	my ($ref, $params, $message) = @_;
	my $result;
	my $opt;
	if ($params =~ /^custom\s+/) {
		$opt = {};
	}
	else {
		$params =~ s/(\w+)\s*(.*)/$1/s;
		$opt = get_option_hash($2);
	}

	eval {
		$result = Vend::Payment::charge($params, $opt);
	};
	if($result) {
		# do nothing, OK
	}
	elsif($@) {
		my $msg = errmsg("Fatal error on charge operation '%s': %s", $params, $@);
		::logError($msg);
		$message = $msg;
	}
	elsif( $Vend::Session->{payment_error} ) {
		# do nothing, no extended messages
		$message = errmsg(
						"Charge failed, reason: %s",
						$Vend::Session->{payment_error},
					)
			if ! $message;
	}
	else {
		$message = errmsg(
					"Charge operation '%s' failed.",
					($ref->{mv_cyber_mode} || $params),
					)
			if ! $message;
	}
#::logDebug("charge result: result=$result params=$params message=$message");
	return ($result, $params, $message);
}

sub _credit_card {
	my($ref, $params) = @_;
	my $subname;
	my $sub;
	my $opt;

	$params =~ s/^\s+//;
	$params =~ s/\s+$//;

	# Make a copy if we need to keep the credit card number in memory for
	# a while

	# New or Compatibility to get options

	if($params =~ /=/) {		# New
		$params =~ s/^\s*(\w+)(\s+|$)//
			and $subname = $1;
		$subname = 'standard' if ! $subname;
		$opt = get_option_hash($params);
	}
	else {      				# Compat
		$opt = {};
		$opt->{keep} = 1 if $params =~ s/\s+keep//i;
	
		if($params =~ s/\s+(.*)//) {
			$opt->{accepted} = $1;
		}
		$subname = $params;
	}

	$sub = $subname eq 'standard'
		 ? \&encrypt_standard_cc
		 :	$Global::GlobalSub->{$subname};

	if(! $sub) {
		::logError("bad credit card check GlobalSub: '%s'", $subname);
		return undef;
	}

	if($opt->{keep}) {
		my (%cgi) = %$ref;
		$ref = \%cgi;
	}

	eval {
		@{$::Values}{ qw/
					mv_credit_card_valid
					mv_credit_card_info
					mv_credit_card_exp_month
					mv_credit_card_exp_year
					mv_credit_card_exp_all
					mv_credit_card_type
					mv_credit_card_reference
					mv_credit_card_error
					/}
				= $sub->($ref, undef, $opt );
	};

	if($@) {
		::logError("credit card check (%s) error: %s", $subname, $@);
		return undef;
	}
	elsif(! $::Values->{mv_credit_card_valid}) {
		return (0, 'mv_credit_card_valid', $::Values->{mv_credit_card_error});
	}
	else {
		return (1, 'mv_credit_card_valid');
	}
}

sub valid_exp_date {
	my ($expire) = @_;
	my $month;
	my $year;
	if($expire) {
		$expire =~ /(\d\d?)(.*)/;
		$month = $1;
		$year = $2;
		$year =~ s/\D+//;
	}
	else {
		$month = $CGI::values{mv_credit_card_exp_month};
		$year = $CGI::values{mv_credit_card_exp_year};
	}
	return '' if $month !~ /^\d+$/ || $year !~ /^\d+$/;
	return '' if $month <1 || $month > 12;
	$year += ($year < 70) ? 2000 : 1900 if $year < 1900;
	my (@now) = localtime();
	$now[5] += 1900;
	return '' if ($year < $now[5]) || ($year == $now[5] && $month <= $now[4]);
	return 1;
}

sub validate_whole_cc {
	my($mess) = join " ", @_;
	$mess =~ s:[^\sA-Za-z0-9/]::g ;
	my (@tok) = split /\s+/, $mess;
	my($num,$expire) = ('', '', '');
	for(@tok) {
		next if /^[A-Za-z]/;
		$num .= $_ if /^\d+$/;
		$expire = $_ if m:/: ;
	}
	return 0 unless valid_exp_date($expire);
	return luhn($num);

}


# Validate credit card routine
# by Jon Orwant, from Business::CreditCard and well-known algorithms

sub luhn {
	my ($number) = @_;
	my ($i, $sum, $weight);

	$number =~ s/\D//g;

	return 0 unless length($number) >= 13 && 0+$number;

	for ($i = 0; $i < length($number) - 1; $i++) {
		$weight = substr($number, -1 * ($i + 2), 1) * (2 - ($i % 2));
		$sum += (($weight < 10) ? $weight : ($weight - 9));
	}

	return 1 if substr($number, -1) == (10 - $sum % 10) % 10;
	return 0;
}


sub build_cc_info {
	my ($cardinfo, $template) = @_;

	if (ref $cardinfo eq 'SCALAR') {
		$cardinfo = { MV_CREDIT_CARD_NUMBER => $$cardinfo };
	} elsif (! ref $cardinfo) {
		$cardinfo = { MV_CREDIT_CARD_NUMBER => $cardinfo };
	} elsif (ref $cardinfo eq 'ARRAY') {
		my $i = 0;
		my %c = map { $_ => $cardinfo->[$i++] } qw(
			MV_CREDIT_CARD_NUMBER
			MV_CREDIT_CARD_EXP_MONTH
			MV_CREDIT_CARD_EXP_YEAR
			MV_CREDIT_CARD_CVV2
			MV_CREDIT_CARD_TYPE
		);
		$cardinfo = \%c;
	} elsif (ref $cardinfo ne 'HASH') {
		return;
	}

	$template = $template ||
		$::Variable->{MV_CREDIT_CARD_INFO_TEMPLATE} ||
		join("\t", qw(
			{MV_CREDIT_CARD_TYPE}
			{MV_CREDIT_CARD_NUMBER}
			{MV_CREDIT_CARD_EXP_MONTH}/{MV_CREDIT_CARD_EXP_YEAR}
			{MV_CREDIT_CARD_CVV2}
		)) . "\n";

	$cardinfo->{MV_CREDIT_CARD_TYPE} ||=
		guess_cc_type($cardinfo->{MV_CREDIT_CARD_NUMBER});

	return Vend::Interpolate::tag_attr_list($template, $cardinfo);
}


sub guess_cc_type {
	my ($ccnum) = @_;
	$ccnum =~ s/\D+//g;

	# based on logic by Karl Moore from http://www.vb-world.net/tips/tip509.html
	if ($ccnum eq '')										{ '' }
	elsif ($ccnum =~ /^4(?:\d{12}|\d{15})$/)				{ 'visa' }
	elsif ($ccnum =~ /^5[1-5]\d{14}$/)						{ 'mc' }
	elsif ($ccnum =~ /^6011\d{12}$/)						{ 'discover' }
	elsif ($ccnum =~ /^3[47]\d{13}$/)						{ 'amex' }
	elsif ($ccnum =~ /^3(?:6\d{12}|0[0-5]\d{11})$/)			{ 'dinersclub' }
	elsif ($ccnum =~ /^38\d{12}$/)							{ 'carteblanche' }
	elsif ($ccnum =~ /^2(?:014|149)\d{11}$/)				{ 'enroute' }
	elsif ($ccnum =~ /^(?:3\d{15}|2131\d{11}|1800\d{11})$/)	{ 'jcb' }
	else													{ 'other' }
}


# Takes a reference to a hash (usually %CGI::values) that contains
# the following:
# 
#    mv_credit_card_number      The actual credit card number
#    mv_credit_card_exp_all     A combined expiration MM/YY
#    mv_credit_card_exp_month   Month only, used if _all not present
#    mv_credit_card_exp_year    Year only, used if _all not present
#    mv_credit_card_cvv2        CVV2 verification number from back of card
#    mv_credit_card_type        A = Amex, D = Discover, etc. Attempts
#                               to guess from number if not there
#    mv_credit_card_separate    Causes mv_credit_card_info to contain only number, must
#                               then develop expiration from the above

sub encrypt_standard_cc {
	my($ref, $nodelete, $opt) = @_;
	my($valid, $info);

	$opt = {} unless ref $opt;
	my @deletes = qw /
					mv_credit_card_type		mv_credit_card_number
					mv_credit_card_exp_year	mv_credit_card_exp_month
					mv_credit_card_force	mv_credit_card_exp_reference
					mv_credit_card_exp_all	mv_credit_card_exp_separate  
					mv_credit_card_cvv2
					/;

	my $month	= $ref->{mv_credit_card_exp_month}	|| '';
	my $type	= $ref->{mv_credit_card_type}		|| '';
	my $num		= $ref->{mv_credit_card_number}		|| '';
	my $year	= $ref->{mv_credit_card_exp_year}	|| '';
	my $all		= $ref->{mv_credit_card_exp_all}	|| '';
	my $cvv2	= $ref->{mv_credit_card_cvv2}		|| '';
	my $force	= $ref->{mv_credit_card_force}		|| '';
	my $separate = $ref->{mv_credit_card_separate}  || $opt->{separate} || '';

	delete @$ref{@deletes}        unless ($opt->{nodelete} or $nodelete);

	# remove unwanted chars from card number
	$num =~ tr/0-9//cd;

	# error will be pushed on this if present
	my @return = (
				'',			# 0- Whether it is valid
				'',			# 1- Encrypted credit card information
				'',			# 2- Month
				'',			# 3- Year
				'',			# 4- Month/year
				'',         # 5- type
				'',         # 6- Reference number in form 41**1111
	);

	# Get the expiration
	if ($all =~ m!(\d\d?)[-/](\d\d)(\d\d)?! ){
		$month = $1;
		$year  = "$2$3";
	}
	elsif ($month >= 1  and $month <= 12 and $year) {
		$all = "$month/$year";
	}
	else {
		$all = '';
	}

	if ($all) {
		$return[2] = $month;
		$return[3] = $year;
		$return[4] = $all;
	}
	else {
		my $msg = errmsg("Can't figure out credit card expiration.");
		$Vend::Session->{errors}{mv_credit_card_valid} = $msg;
		push @return, $msg;
		return @return;
	}

	if(! valid_exp_date($all) ) {
		my $msg = errmsg("Card is expired.");
		$Vend::Session->{errors}{mv_credit_card_valid} = $msg;
		push @return, $msg;
		return @return;
	}

	$type = guess_cc_type($num) unless $type;

	if ($type and $opt->{accepted} and $opt->{accepted} !~ /\b$type\b/i) {
		my $msg = errmsg("Sorry, we don't accept credit card type '%s'.", $type);
		$Vend::Session->{errors}{mv_credit_card_valid} = $msg;
		push @return, $msg;
		return @return;
	}
	elsif ($type) {
		$return[5] = $type;
	}
	elsif(! $opt->{any}) {
		my $msg = errmsg("Can't figure out credit card type from number.");
		$Vend::Session->{errors}{mv_credit_card_valid} = $msg;
		push @return, $msg;
		return @return;
	}

	unless ($valid = luhn($num) || $force ) {
		my $msg = errmsg("Credit card number fails LUHN-10 check.");
		$Vend::Session->{errors}{mv_credit_card_valid} = $msg;
		push @return, $msg;
		return @return;
	}

	$return[0] = $valid;

	my $check_string = $num;
	$check_string =~ s/(\d\d).*(\d\d\d\d)$/$1**$2/;
	
	my $encrypt_string = $separate ? $num :
		build_cc_info( [$num, $month, $year, $cvv2, $type] );
	$info = pgp_encrypt ($encrypt_string);

	unless (defined $info) {
		my $msg = errmsg("Credit card encryption failed: %s", $! );
		$Vend::Session->{errors}{mv_credit_card_valid} = $msg;
		push @return, $msg;
		$return[0] = 0;
		return @return;
	}
	$return[1] = $info;
	$return[6] = $check_string;

	return @return;

}

# Old, old, old but still supported
*cyber_charge = \&Vend::Payment::charge;

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

sub onfly {
	my ($code, $qty, $opt) = @_;
	my $item_text;
	if (ref $opt) {
		$item_text = $opt->{text} || '';
	}
	else {
		$item_text = $opt;
		$opt = {};
	}

#	return create_onfly() if $opt->{create};

	my $joiner		= $::Variable->{MV_ONFLY_JOINER} || '|';
	my $split_fields= $::Variable->{MV_ONFLY_FIELDS} || undef;

	$item_text =~ s/\s+$//;
	$item_text =~ s/^\s+//;
	my @parms;
	my @fields;
	$joiner = quotemeta $joiner;
	@parms = split /$joiner/, $item_text;
	my ($k, $v);
	my $item = {};
	if(defined $split_fields) {
		@fields = split /[,\s]+/, $split_fields;
		@{$item}{@fields} = @parms;
	}
	else {
		for(@parms) {
			($k, $v)  = split /=/, $_;
			$item->{$k} = $v;
		}
	}
	$item->{mv_price} = $item->{price}
		if ! $item->{mv_price};
	$item->{code}	  = $code	if ! $item->{code};
	$item->{quantity} = $qty	if ! $item->{quantity};
	return $item;
}

# Email the processed order. This is a legacy routine, not normally used
# any more. Order email is normally sent via Route.
sub mail_order {
	my ($email, $order_no) = @_;
	$email = $Vend::Cfg->{MailOrderTo} unless $email;
	my($body, $ok);
	my($subject);
# LEGACY
	$body = readin($::Values->{mv_order_report})
		if $::Values->{mv_order_report};
# END LEGACY
	$body = readfile($Vend::Cfg->{OrderReport})
		if ! $body;
	unless (defined $body) {
		::logError(
			q{Cannot find order report in:

			OrderReport=%s
			mv_order_report=%s

trying one more time. Fix this.},
				$Vend::Cfg->{OrderReport},
				$::Values->{mv_order_report},
			);
		$body = readin($Vend::Cfg->{OrderReport});
		return undef if ! $body;
	}
	return undef unless defined $body;

	$order_no = update_order_number() unless $order_no;

	$body = interpolate_html($body);

	$body = pgp_encrypt($body) if $Vend::Cfg->{PGP};

	track_order($order_no, $body);

	$subject = $::Values->{mv_order_subject} || "ORDER %n";

	if(defined $order_no) {
		$subject =~ s/%n/$order_no/;
	}
	else { $subject =~ s/\s*%n\s*//g; }

	$ok = send_mail($email, $subject, $body);
	return $ok;
}

sub pgp_encrypt {
	my($body, $key, $cmd) = @_;
#::logDebug("called pgp_encrypt key=$key cmd=$cmd");
	$cmd = $Vend::Cfg->{EncryptProgram} unless $cmd;
	$key = $Vend::Cfg->{EncryptKey}	    unless $key;

	
	if("\L$cmd" eq 'none') {
		return ::errmsg("NEED ENCRYPTION ENABLED.");
	}
	elsif($cmd =~ m{^(?:/\S+/)?\bgpg$}) {
		$cmd .= " --batch --always-trust -e -a -r '%s'";
	}
	elsif($cmd =~ m{^(?:/\S+/)?pgpe$}) {
		$cmd .= " -fat -r '%s'";
	}
	elsif($cmd =~ m{^(?:/\S+/)?\bpgp$}) {
		$cmd .= " -fat - '%s'";
	}

	if($cmd =~ /[;|]/) {
		die ::errmsg("Illegal character in encryption command: %s", $cmd);
	}

	if($key) {
		$cmd =~ s/%%/:~PERCENT~:/g;
		$key =~ s/'/\\'/g;
		$cmd =~ s/%s/$key/g;
		$cmd =~ s/:~PERCENT~:/%/g;
	}

#::logDebug("after  pgp_encrypt key=$key cmd=$cmd");

	my $fpre = $Vend::Cfg->{ScratchDir} . "/pgp.$Vend::Session->{id}.$$";
	$cmd .= ">$fpre.out";
	$cmd .= " 2>$fpre.err" unless $cmd =~ /2>/;
	open(PGP, "|$cmd")
			or die "Couldn't fork: $!";
	print PGP $body;
	close PGP;
	if($?) {
		logError("PGP failed with status %s: %s", $? >> 8, $!);
		return 0;
	}
	$body = readfile("$fpre.out");
	unlink "$fpre.out";
	unlink "$fpre.err";
	return $body;
}

sub do_check {
		local($_) = shift;
		my $ref = \%CGI::values;
		my $vref = shift || $::Values;

		my $parameter = $_;
		my($var, $val, $m, $message);
		if (/^&/) {
			($var,$val) = split /[\s=]+/, $parameter, 2;
		}
		elsif ($parameter =~ /(\w+)[\s=]+(.*)/) {
			my $k = $1;
			my $v = $2;
			$m = $v =~ s/\s+(.*)// ? $1 : undef;
			($var,$val) =
				('&format',
				  $v . ' ' . $k  . ' ' .  $vref->{$k}
				  );
		}
		else {
			logError("Unknown order check '%s' in profile %s", $parameter, $Profile);
			return undef;
		}
		$val =~ s/&#(\d+);/chr($1)/ge;

		if ($Parse{$var}) {
			($val, $var, $message) = $Parse{$var}->($ref, $val, $m);
		}
		else {
			logError( "Unknown order check parameter in profile %s: %s=%s",
					$Profile,
					$var,
					$val,
					);
			return undef;
		}
		return ($val, $var, $message);
}

sub check_order {
	my ($profile, $vref) = @_;
	my($codere) = '[-\w_#/.]+';
	my $params;
	$Profile = $profile;
	if(defined $Vend::Cfg->{OrderProfileName}->{$profile}) {
		$profile = $Vend::Cfg->{OrderProfileName}->{$profile};
		$params = $Vend::Cfg->{OrderProfile}->[$profile];
	}
	elsif($profile =~ /^\d+$/) {
		$params = $Vend::Cfg->{OrderProfile}->[$profile];
	}
	elsif(defined $::Scratch->{$profile}) {
		$params = $::Scratch->{$profile};
	}
	else {
		::logError("Order profile %s not found", $profile);
		return undef;
	}
	return undef unless $params;

	my $ref = \%CGI::values;
	$params = interpolate_html($params);
	$params =~ s/\\\n//g;

	@Errors = ();
	$And = 1;
	$Fatal = $Final = 0;

	my $r;
	if( $r = $Vend::Cfg->{CodeDef}{OrderCheck} and $r = $r->{Routine}) {
		for(keys %$r) {
			$OrderCheck->{$_} = $r->{$_};
		}
	}

	my($var,$val,$message);
	my $status = 1;
	my(@param) = split /[\r\n]+/, $params;
	my $m;
	my $join;
	my $here;
	my $last_one = 1;

	for(@param) {
		if(/^$here$/) {
			$_ = $join;
			undef $here;
			undef $join;
		}
		($join .= "$_\n", next) if $here;
		if($join) {
			$_ = "$join$_";
			undef $join;
		}
		if(s/<<(\w+);?\s*$//) {
			$here = $1;
			$join = "$_\n";
			next;
		}
		next unless /\S/;
		next if /^\s*#/;
		if(s/\\$//) {
			$join = $_;
			next;
		}
		s/^\s+//;
		s/\s+$//;
		($val, $var, $message) = do_check($_, $vref);
		next if ! defined $var;
		if(defined $And) {
			if($And) {
				$val = ($last_one && $val);
			}
			else {
				$val = ($last_one || $val);
			}
			undef $And;
		}
		$last_one = $val;
		if ($val) {
			$::Values->{"mv_status_$var"} = $message
				if defined $message and $message;
			delete $Vend::Session->{errors}{$var};
			delete $::Values->{"mv_error_$var"};
		}
		else {
			$status = 0;
# LEGACY
			$::Values->{"mv_error_$var"} = $message;
# END LEGACY
			$Vend::Session->{errors} = {}
				if ! $Vend::Session->{errors};
			if( $No_error ) {
				# do nothing
			}
			elsif( $Vend::Session->{errors}{$var} ) {
				if ($message and $Vend::Session->{errors}{$var} !~ /\Q$message/) {
					$Vend::Session->{errors}{$var} = errmsg(
						'%s and %s',
						$Vend::Session->{errors}{$var},
						$message
					);
				}
			}
			else {
				$Vend::Session->{errors}{$var} = $message ||
					errmsg('%s: failed check', $var);
			}
			push @Errors, "$var: $message";
		}
		if (defined $Success) {
			$status = $Success;
			last;
		}
		last if $Fatal && ! $status;
	}
	my $errors = join "\n", @Errors;
	$errors = '' unless defined $errors and ! $Success;
#::logDebug("FINISH checking profile $Profile: Fatal=$Fatal Final=$Final Status=$status\nErrors:\n$errors\n");
	if($status) {
		$CGI::values{mv_nextpage} = $Success_page
			if $Success_page;
	}
	elsif ($Fail_page) {
		$CGI::values{mv_nextpage} = $Fail_page;
	}
	if($Final and ! scalar @{$Vend::Items}) {
		$status = 0;
		$::Values->{"mv_error_items"}       =
			$Vend::Session->{errors}{items}  =
				errmsg(
					"You might want to order something! No items in cart.",
				);

	}
	return ($status, $Final, $errors);
}

my $state = <<EOF;
| AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO |
| MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY |
| PR DC AA AE GU VI AS MP FM MH PW AP FP FPO APO |
EOF

my $province = <<EOF;
| AB BC MB NB NF NS NT ON PE QC SK YT YK |
EOF

sub _state_province {
	my($ref,$var,$val) = @_;
	$province = " $::Variable->{MV_VALID_PROVINCE} "
		if defined $::Variable->{MV_VALID_PROVINCE};
	$state = " $::Variable->{MV_VALID_STATE} "
		if defined $::Variable->{MV_VALID_STATE};
	if( $val =~ /\S/ and ($state =~ /\s$val\s/i or $province =~ /\s$val\s/i) ) {
		return (1, $var, '');
	}
	else {
		return (undef, $var,
			errmsg( "'%s' not a two-letter state or province code", $val )
		);
	}
}

sub _state {
	my($ref,$var,$val) = @_;
	$state = " $::Variable->{MV_VALID_STATE} "
		if defined $::Variable->{MV_VALID_STATE};

	if( $val =~ /\S/ and $state =~ /\s$val\s/i ) {
		return (1, $var, '');
	}
	else {
		return (undef, $var,
			errmsg( "'%s' not a two-letter state code", $val )
		);
	}
}

sub _province {
	my($ref,$var,$val) = @_;
	$province = " $::Variable->{MV_VALID_PROVINCE} "
		if defined $::Variable->{MV_VALID_PROVINCE};
	if( $val =~ /\S/ and $province =~ /\s$val\s/i) {
		return (1, $var, '');
	}
	else {
		return (undef, $var,
			errmsg( "'%s' not a two-letter province code", $val )
		);
	}
}

sub _array {
	return undef unless defined $_[1];
	[split /\s*[,\0]\s*/, $_[1]]
}

sub _yes {
	return( defined($_[2]) && ($_[2] =~ /^[yYtT1]/));
}

sub _postcode {
	my($ref,$var,$val) = @_;
	((_zip(@_))[0] or (_ca_postcode(@_))[0])
		and return (1, $var, '');
	return (undef, $var, errmsg("'%s' not a US zip or Canadian postal code", $val));
}

sub _ca_postcode {
	my($ref,$var,$val) = @_;
	$val =~ s/[_\W]+//g;
	defined $val
		and
	$val =~ /^[ABCEGHJKLMNPRSTVXYabceghjklmnprstvxy]\d[A-Za-z]\d[A-Za-z]\d$/
		and return (1, $var, '');
	return (undef, $var, errmsg("'%s' not a Canadian postal code", $val));
}

sub _zip {
	my($ref,$var,$val) = @_;
	defined $val and $val =~ /^\s*\d{5}(?:[-]\d{4})?\s*$/
		and return (1, $var, '');
	return (undef, $var, errmsg("'%s' not a US zip code", $val));
}

*_us_postcode = \&_zip;

sub _phone {
	my($ref,$var,$val) = @_;
	defined $val and $val =~ /\d{3}.*\d{3}/
		and return (1, $var, '');
	return (undef, $var, errmsg("'%s' not a phone number", $val));
}

sub _phone_us {
	my($ref, $var,$val) = @_;
	if($val and $val =~ /\d{3}.*?\d{4}/) {
		return (1, $var, '');
	}
	else {
		return (undef, $var, errmsg("'%s' not a US phone number", $val));
	}
}

sub _phone_us_with_area {
	my($ref, $var,$val) = @_;
	if($val and $val =~ /\d{3}\D*\d{3}\D*\d{4}/) {
		return (1, $var, '');
	}
	else {
		return (undef, $var, errmsg("'%s' not a US phone number with area code", $val));
	}
}

sub _phone_us_with_area_strict {
	my($ref, $var,$val) = @_;
	if($val and $val =~ /^\d{3}-\d{3}-\d{4}$/) {
		return (1, $var, '');
	}
	else {
		return (undef, $var,
			errmsg("'%s' not a US phone number with area code (strict formatting)", $val)
		);
	}
}

sub _email {
	my($ref, $var, $val) = @_;
	if($val and $val =~ /[\040-\176]+\@[-A-Za-z0-9.]+\.[A-Za-z]+/) {
		return (1, $var, '');
	}
	else {
		return (undef, $var,
			errmsg( "'%s' not an email address", $val )
		);
	}
}

# Contributed by Ton Verhagen -- April 15, 2000
sub _isbn {
	# $ref is to Vend::Session->{'values'} hash (well, actually ref to %CGI::values)
	# $var is the passed name of the variable
	# $val is current value of checked variable
	# This routine will return 1 if isbn is ok, else returns 0
	# Rules:
	# isbn number must contain exactly 10 digits.
	# isbn number:		0   9   4   0   0   1   6   3   3   8
	# weighting factor:	10  9   8   7   6   5   4   3   2   1
	# Values (product)	0 +81 +32 + 0 + 0 + 5 +24 + 9 + 6 + 8 --> sum is: 165
	# Sum must be divisable by 11 without remainder: 165/11=15 (no remainder)
	# Result: isbn 0-940016-33-8 is a valid isbn number.
	
	my($ref, $var, $val) = @_;
	$val =~ s/\D//g;	# weed out non-digits
	if( $val && length($val) == 10 ) {
	  my @digits = split("", $val);
	  my $sum=0;
	  for(my $i=10; $i > 0; $i--) {
		$sum += $digits[10-$i] * $i;
	  }
	  return ( $sum%11 ? 0 : 1, $var, '' );
	}
	else {
	  return (undef, $var, errmsg("'%s' not a valid isbn number", $val));
	}
}

sub _mandatory {
	my($ref,$var,$val) = @_;
	return (1, $var, '')
		if (defined $ref->{$var} and $ref->{$var} =~ /\S/);
	return (undef, $var, errmsg("blank"));
}

sub _true {
	my($ref,$var,$val) = @_;
	return (1, $var, '') if is_yes($val);
	return (undef, $var, errmsg("false"));
}

sub _false {
	my($ref,$var,$val) = @_;
	return (1, $var, '') if is_no($val);
	return (undef, $var, errmsg("true"));
}

sub _defined {
	my($ref,$var,$val) = @_;
	return (1, $var, '')
		if defined $::Values->{$var};
	return (undef, $var, errmsg("undefined"));
}

sub _required {
	my($ref,$var,$val) = @_;
	return (1, $var, '')
		if (defined $val and $val =~ /\S/);
	return (1, $var, '')
		if (defined $ref->{$var} and $ref->{$var} =~ /\S/);
	return (undef, $var, errmsg("blank"));
}

sub counter_number {
	my $file = shift || $Vend::Cfg->{OrderCounter};
	$Vend::CounterFile::DEFAULT_DIR = $Vend::Cfg->{VendRoot}
		unless $file =~ m!^/!;
	my $c = new Vend::CounterFile $file, "000000";
	return $c->inc;
}

sub update_order_number {

	my($c,$order_no);

	if($Vend::Cfg->{OrderCounter}) {
		$order_no = counter_number();
	}
	else {
		$order_no = $Vend::SessionID . '.' . time;
	}

	$::Values->{mv_order_number} = $order_no;
	$order_no;
}

# Places the order report in the AsciiTrack file
sub track_order {
	my ($order_no,$order_report) = @_;
	
	if ($Vend::Cfg->{AsciiTrack}) {
		logData ($Vend::Cfg->{AsciiTrack}, <<EndOOrder);
##### BEGIN ORDER $order_no #####
$order_report
##### END ORDER $order_no #####

EndOOrder
	}
}

sub route_profile_check {
	my (@routes) = @_;
	my $failed;
	my $errors = '';
	my ($status, $final, $missing);
	my $value_save = { %{$::Values} };
	local(%SIG);
	undef $SIG{__DIE__};
	foreach my $c (@routes) {
		$Vend::Interpolate::Values = $::Values = { %$value_save };
		eval {
			my $route = $Vend::Cfg->{Route_repository}{$c}
				or do {
					# Change to ::logDebug because of dynamic routes
					::logDebug("Non-existent order route %s, skipping.", $c);
					next;
				};
			if($route->{profile}) {
				($status, $final, $missing) = check_order($route->{profile});
				if(! $status) {
					die errmsg(
					"Route %s failed order profile %s. Final=%s. Errors:\n\n%s\n\n",
					$c,
					$route->{profile},
					$final,
					$missing,
					)
				}
			}
		};
		if($@) {
			$errors .= $@;
			$failed = 1;
			last if $final;
		}
	}
#::logDebug("check_only -- profile=$c status=$status final=$final failed=$failed errors=$errors missing=$missing");
	$Vend::Interpolate::Values = $::Values = { %$value_save };
	return (! $failed, $final, $errors);
}

sub route_order {
	my ($route, $save_cart, $check_only) = @_;
	my $main = $Vend::Cfg->{Route};
	return unless $main;
	$route = 'default' unless $route;

	my $cart = [ @$save_cart ];

	my $save_mime = $::Instance->{MIME} || undef;

	my $encrypt_program = $main->{encrypt_program};

	my (@routes);
	my $shelf = { };
	my $item;
	foreach $item (@$cart) {
		$shelf = { } unless $shelf;
		next unless $item->{mv_order_route};
		my(@r) = split /[\s\0,]+/, $item->{mv_order_route};
		for(@r) {
			next unless /\S/;
			$shelf->{$_} = [] unless defined $shelf->{$_};
			push @routes, $_;
			push @{$shelf->{$_}}, $item;
		}
	}
	my %seen;

	@routes = grep !$seen{$_}++, @routes;
	my (@main) = grep /\S/, split /[\s\0,]+/, $route;
	for(@main) {
		next unless $_;
		$shelf->{$_} = [ @$cart ];
	}

	# We empty @main so that we can push more routes on with cascade option
	push @routes, splice @main;

	my ($c,@out);
	my $status;
	my $errors = '';
	
	my @route_complete;
	my @route_failed;
	my @route_done;
	my $route_checked;

	### This used to be the check_only
	# Here we return if it is only a check
	#return route_profile_check(@routes) if $check_only;

	# Careful! If you set it on one order and not on another,
	# you must delete in between.
	if(! $check_only) {
		$::Values->{mv_order_number} = counter_number($main->{counter})
				unless $Vend::Session->{mv_order_number};
	}

	my $value_save = { %{$::Values} };

	my @trans_tables;

	# We aren't going to 
	my %override_key = qw/
		encrypt_program 1
	/;

	# Settable by user to indicate failure
	delete $::Scratch->{mv_route_failed};

	ROUTES: {
		BUILD:
	foreach $c (@routes) {
		my $route = $Vend::Cfg->{Route_repository}{$c} || {};
		$main = $route if $route->{master};
		my $old;

#::logDebug("route $c is: " . ::uneval($route));
		##### OK, can put variables in DB all the time. It can be dynamic
		##### from the database if $main->{dynamic_routes} is set. ITL only if
		##### $main->{expandable}.
		#####
		##### The encrypt_program key cannot be dynamic. You can set the
		##### key substition value instead.

		if($Vend::Cfg->{RouteDatabase} and $main->{dynamic_routes}) {
			my $ref = tag_data( $Vend::Cfg->{RouteDatabase},
								undef,
								$c, 
								{ hash => 1 }
								);
#::logDebug("Read dynamic route %s from database, got: %s", $c, $ref );
			if($ref) {
				$old = $route;
				$route = $ref;
				for(keys %override_key) {
					$route->{$_} = $old->{$_};
				}
			}
		}

		if(! %$route) {
			::logError("Non-existent order routing %s, skipping.", $c);
			next;
		}

		# Tricky, tricky
		if($route->{extended}) {
			my $ref = get_option_hash($route->{extended});
			if(ref $ref) {
				for(keys %$ref) {
#::logDebug("setting extended $_ = $ref->{$_}");
					$route->{$_} = $ref->{$_}
						unless $override_key{$_};
				}
			}
		}

		for(keys %$route) {
			$route->{$_} =~ s/^\s*__([A-Z]\w+)__\s*$/$::Variable->{$1}/;
			next unless $main->{expandable};
			next if $override_key{$_};
			next unless $route->{$_} =~ /\[/;
			$route->{$_} = ::interpolate_html($route->{$_});
		}
		#####
		#####
		#####

		# Compatibility 
		if($route->{cascade}) {
			my @extra = grep /\S/, split /[\s,\0]+/, $route->{cascade};
			for(@extra) {
				$shelf->{$_} = [ @$cart ];
				push @main, $_;
			}
		}

		$Vend::Interpolate::Values = $::Values = { %$value_save };
		$::Values->{mv_current_route} = $c;
		my $pre_encrypted;
		my $credit_card_info;

		$Vend::Items = $shelf->{$c};

		Vend::Interpolate::flag( 'transactions', {}, $route->{transactions})
			if $route->{transactions};

	eval {

	  PROCESS: {
		if(! $check_only and $route->{inline_profile}) {
			my $status;
			my $err;
			($status, undef, $err) = check_order($route->{inline_profile});
#::logDebug("inline profile returned status=$status errors=$err");
			die "$err\n" unless $status;
		}

		if ($CGI::values{mv_credit_card_number}) {
			$CGI::values{mv_credit_card_type} ||=
				guess_cc_type($CGI::values{mv_credit_card_number});
			my %attrlist = map { uc($_) => $CGI::values{$_} } keys %CGI::values;
			$::Values->{mv_credit_card_info} = build_cc_info(\%attrlist);
		}
		elsif ($::Values->{mv_credit_card_info}) {
			$::Values->{mv_credit_card_info} =~ /BEGIN\s+[PG]+\s+MESSAGE/
				and $pre_encrypted = 1;
		}

		if ($check_only and $route->{profile}) {
			$route_checked = 1;
			my ($status, $final, $missing) = check_order($route->{profile});
			if(! $status) {
				die errmsg(
				"Route %s failed order profile %s. Final=%s. Errors:\n\n%s\n\n",
				$c,
				$route->{profile},
				$final,
				$missing,
				)
			}
		}

	  	last PROCESS if $check_only;

		if($route->{payment_mode}) {
			my $ok;
			$ok = Vend::Payment::charge($route->{payment_mode});
			if (! $ok) {
				die errmsg("Failed online charge for routing %s: %s",
								$c,
								$Vend::Session->{mv_payment_error}
							);
			}
			else {
				$Vend::Session->{route_payment_id} ||= {};
				$Vend::Session->{route_payment_id}{$c} = $Vend::Session->{payment_id};
			}
		}
		if(  $route->{credit_card}
				and ! $pre_encrypted
			    and $::Values->{mv_credit_card_info}
				)
		{
			$::Values->{mv_credit_card_info} = pgp_encrypt(
								$::Values->{mv_credit_card_info},
								($route->{pgp_cc_key} || $route->{pgp_key}),
								($route->{encrypt_program} || $main->{encrypt_program} || $encrypt_program),
							);
		}

		if($Vend::Session->{mv_order_number}) {
			$::Values->{mv_order_number} = $Vend::Session->{mv_order_number};
		}
		elsif($route->{counter}) {
			$::Values->{mv_order_number} = counter_number($route->{counter});
		}
		elsif($route->{increment}) {
			$::Values->{mv_order_number} = counter_number();
		}
		my $pagefile;
		my $page;
		if($route->{empty} and ! $route->{report}) {
			$page = '';
		}
		else {
			$pagefile = $route->{'report'} || $main->{'report'};
			$page = readfile($pagefile);
		}
		die errmsg(
			"No order report %s or %s found.",
			$route->{'report'},
			$main->{'report'},
			) unless defined $page;

		my $use_mime;
		undef $::Instance->{MIME};
		if(not ($route->{credit_card} || $route->{encrypt}) ) {
			$::Values->{mv_credit_card_info}
				=~ s/^(\s*\w+\s+)(\d\d)[\d ]+(\d\d\d\d)/$1$2 NEED ENCRYPTION $3/;
		}
		eval {
			$page = interpolate_html($page) if $page;
		};
		if ($@) {
			die "Error while interpolating page $pagefile:\n $@";
		}
		$use_mime   = $::Instance->{MIME} || undef;
		$::Instance->{MIME} = $save_mime  || undef;

		if($route->{encrypt}) {
			$page = pgp_encrypt($page,
								$route->{pgp_key},
								($route->{encrypt_program} || $main->{encrypt_program} || $encrypt_program),
								);
		}
		my ($address, $reply, $to, $subject, $template);
		if($route->{attach}) {
			$Vend::Items->[0]{mv_order_report} = $page;
		}
		elsif ($route->{empty}) {
			# Do nothing
		}
		elsif ($address = $route->{email}) {
			$address = $::Values->{$address} if $address =~ /^\w+$/;
			$subject = $route->{subject} || $::Values->{mv_order_subject} || 'ORDER %s';
			$subject =~ s/%n/%s/;
			$subject = sprintf "$subject", $::Values->{mv_order_number};
			$reply   = $route->{reply} || $main->{reply};
			$reply   = $::Values->{$reply} if $reply =~ /^\w+$/;
			$to		 = $route->{email};
			my $ary = [$to, $subject, $page, $reply, $use_mime];
			if($route->{from}) {
				push @$ary, "From: $route->{from}";
			}
			push @out, $ary;
		}
		else {
			die "Empty order routing $c (and not explicitly empty).\nEither attach or email are required in the route setting.\n";
		}
		if ($route->{supplant}) {
			track_order($::Values->{mv_order_number}, $page);
		}
		if ($route->{track}) {
			my $fn = escape_chars($route->{track});
			Vend::Util::writefile($fn, $page)
				or ::logError("route tracking error writing %s: %s", $fn, $!);
			my $mode = $route->{track_mode} || '';
			if ($mode =~ s/^0+//) {
				chmod oct($mode), $fn;
			}
			elsif ($mode) {
				chmod $mode, $fn;
			}
		}
		if ($route->{individual_track}) {
			my $fn = Vend::Util::catfile(
							$route->{individual_track},
							$::Values->{mv_order_number} . 
							$route->{individual_track_ext},
						);
			Vend::Util::writefile( $fn, $page,	)
				or ::logError("route tracking error writing $fn: $!");
			my $mode = $route->{track_mode} || '';
			if ($mode =~ s/^0+//) {
				chmod oct($mode), $fn;
			}
			elsif ($mode) {
				chmod $mode, $fn;
			}
		}
		if($::Scratch->{mv_route_failed}) {
			my $msg = delete $::Scratch->{mv_route_error}
					|| ::errmsg('Route %s failed.', $c);
			::logError($msg);
			die $msg;
		}
	  } # end PROCESS
	};
		if($@) {
#::logDebug("route failed: $c");
			my $err = $@;
			$errors .=  errmsg(
							"Error during creation of order routing %s:\n%s",
							$c,
							$err,
						);
			if ($route->{error_ok}) {
				push @route_complete, $c;
				next BUILD;
			}
			next BUILD if $route->{continue};
			push @route_failed, $c;
			@out = ();
			@route_done = @route_complete;
			@route_complete = ();
			last ROUTES;
		}

		push @route_complete, $c;

	} #BUILD

	if(@main and ! @route_failed) {
		@routes = splice @main;
		redo ROUTES;
	}

  } #ROUTES

	my $msg;

	if($check_only) {
		$Vend::Interpolate::Values = $::Values = $value_save;
		$Vend::Items = $save_cart;
		if(@route_failed) {
			return (0, 0, $errors);
		}
		elsif($route_checked) {
			return (1, 1, '');	
		}
		else {
			return (1, undef, '');	
		}
	}

	foreach $msg (@out) {
		eval {
#### change this to use Vend::Mail::send
			send_mail(@$msg);
		};
		if($@) {
			my $err = $@;
			$errors .=  errmsg(
							"Error sending mail to %s:\n%s",
							$msg->[0],
							$err,
						);
			$status = 0;
			next;
		}
		else {
			$status = 1;
		}
	}

	$::Instance->{MIME} = $save_mime  || undef;
	$Vend::Interpolate::Values = $::Values = $value_save;
	$Vend::Items = $save_cart;

	for(@route_failed) {
		my $route = $Vend::Cfg->{Route_repository}{$_};
		if($route->{transactions}) {
			Vend::Interpolate::flag( 'rollback', {}, $route->{transactions})
		}
		next unless $route->{rollback};
		Vend::Interpolate::tag_perl(
					$route->{rollback_tables},
					{},
					$route->{rollback}
		);
	}

	for(@route_complete) {
		my $route = $Vend::Cfg->{Route_repository}{$_};
		if($route->{transactions}) {
			Vend::Interpolate::flag( 'commit', {}, $route->{transactions})
		}
		next unless $route->{commit};
		Vend::Interpolate::tag_perl(
					$route->{commit_tables},
					{},
					$route->{commit}
		);
	}

	if(! $errors) {
		delete $Vend::Session->{order_error};
	}
	elsif ($main->{errors_to}) {
		$Vend::Session->{order_error} = $errors;
#### change this to use Vend::Mail::send
		send_mail(
			$main->{errors_to},
			errmsg("ERRORS on ORDER %s", $::Values->{mv_order_number}),
			$errors
			);
	}
	else {
		$Vend::Session->{order_error} = $errors;
		::logError("ERRORS on ORDER %s:\n%s", $::Values->{mv_order_number}, $errors);
	}

	# Get rid of this puppy
	$::Values->{mv_credit_card_info}
			=~ s/^(\s*\w+\s+)(\d\d)[\d ]+(\d\d\d\d)/$1$2 NEED ENCRYPTION $3/;
	# If we give a defined value, the regular mail_order routine will not
	# be called
#::logDebug("route errors=$errors supplant=$main->{supplant}");
	if($main->{supplant}) {
		return ($status, $::Values->{mv_order_number}, $main);
	}
	return (undef, $::Values->{mv_order_number}, $main);
}

sub add_items {
	my($items,$quantities) = @_;

	$items = delete $CGI::values{mv_order_item} if ! defined $items;
	return unless $items;

	my($code,$found,$item,$base,$quantity,$i,$j,$q);
	my(@items);
	my(@skus);
	my(@quantities);
	my(@bases);
	my(@lines);
	my(@fly);
	my($attr,%attr);

	my $value;
	if ($value = delete $Vend::Session->{scratch}{mv_UseModifier}) {
		$Vend::Cfg->{UseModifier} = [split /[\s\0,]+/, $value];
	}

	::update_quantity() if ! defined $CGI::values{mv_orderline};

	my $cart;
	if($CGI::values{mv_cartname}) {
		$cart = $::Carts->{$CGI::values{mv_cartname}} ||= [];
	}
	else {
		$cart = $Vend::Items;
	}

	@items      = split /\0/, ($items), -1;
	@quantities = split /\0/, ($quantities || delete $CGI::values{mv_order_quantity} || ''), -1;
	@bases      = split /\0/, delete $CGI::values{mv_order_mv_ib}, -1
		if defined $CGI::values{mv_order_mv_ib};
	@lines      = split /\0/, delete $CGI::values{mv_orderline}, -1
		if defined $CGI::values{mv_orderline};

	if($CGI::values{mv_order_fly} and $Vend::Cfg->{OnFly}) {
		if(scalar @items == 1) {
			@fly = $CGI::values{mv_order_fly};
		}
		else {
			@fly = split /\0/, $CGI::values{mv_order_fly}, -1;
		}
	}

	if(defined $CGI::values{mv_item_option}) {
		$Vend::Cfg->{UseModifier} = [] if ! $Vend::Cfg->{UseModifier};
		my %seen;
		my @mods = (grep $_ !~ /^mv_/, split /\0/, $CGI::values{mv_item_option});
		@mods = grep ! $seen{$_}++, @mods;
		push @{$Vend::Cfg->{UseModifier}}, @mods;
	}

	if($CGI::values{mv_sku}) {
		my @sku = split /\0/, $CGI::values{mv_sku}, -1;
		for (@sku) {
			$_ = $::Variable->{MV_VARIANT_JOINER} || '0' if ! length($_);
		}
		$skus[0]   = $items[0];
		$items[0] = join '-', @sku;
	}

	if ($Vend::Cfg->{UseModifier}) {
		foreach $attr (@{$Vend::Cfg->{UseModifier} || []}) {
			$attr{$attr} = [];
			next unless defined $CGI::values{"mv_order_$attr"};
			@{$attr{$attr}} = split /\0/, $CGI::values{"mv_order_$attr"}, -1;
		}
	}

	my ($group, $found_master, $mv_mi, $mv_si, $mv_mp, @group, @modular);

	my $separate;
	if( $CGI::values{mv_order_modular} ) {
		@modular = split /\0/, delete $CGI::values{mv_order_modular};
		for( my $i = 0; $i < @modular; $i++ ) {
		   $attr{mv_mp}->[$i] = $modular[$i] if $modular[$i];
		}
		$separate = 1;
	}
	else {
		$separate = defined $CGI::values{mv_separate_items}
					? is_yes($CGI::values{mv_separate_items})
					: (
						$Vend::Cfg->{SeparateItems} ||
						(
							defined $Vend::Session->{scratch}->{mv_separate_items}
						 && is_yes( $Vend::Session->{scratch}->{mv_separate_items} )
						 )
						);
	}

	@group   = split /\0/, (delete $CGI::values{mv_order_group} || ''), -1;
	for( my $i = 0; $i < @group; $i++ ) {
	   $attr{mv_mi}->[$i] = $group[$i] ? ++$Vend::Session->{pageCount} : 0;
	}

	$j = 0;
	my $set;
	foreach $code (@items) {
		undef $item;
		$quantity = defined $quantities[$j] ? $quantities[$j] : 1;
		$set = $quantity =~ s/^=//;
		$quantity =~ s/^(-?)\D+/$1/;
		$quantity =~ s/^(-?\d*)\D.*/$1/
			unless $Vend::Cfg->{FractionalItems};
		($j++,next) unless $quantity;
		if(! $fly[$j]) {
			$base = product_code_exists_tag($code, $bases[$j] || undef);
		}
		else {
			$base = 'mv_fly';
			my $ref;
#::logError("onfly call=$Vend::Cfg->{OnFly} ($code, $quantity, $fly[$j])");
			eval {
				$item = Vend::Parse::do_tag($Vend::Cfg->{OnFly},
												$code,
												$quantity,
												$fly[$j],
											);
			};
			if($@) {
				::logError(
					"failed on-the-fly item add with error %s for: tag=%s sku=%s, qty=%s, passed=%s",
					$@,
					$Vend::Cfg->{OnFly},
					$code,
					$quantity,
					$fly[$j],
				);
				next;
			}
		}
		if (! $base ) {
			logError( "Attempt to order missing product code: %s", $code);
			next;
		}

		INCREMENT: {
			# Check that the item has not been already ordered.
			# But let us order separates if so configured
			$found = -1;
			last INCREMENT if $separate;
			last INCREMENT if defined $lines[$j] and length($lines[$j]);

			foreach $i (0 .. $#$cart) {
				if ($cart->[$i]->{'code'} eq $code) {
					next unless $base eq $cart->[$i]->{mv_ib};
					$found = $i;
					# Increment quantity. This is different than
					# the standard handling because we are ordering
					# accessories, and may want more than 1 of each
					$cart->[$i]{quantity} = $set ? $quantity : $cart->[$i]{quantity} + $quantity;
				}
			}
		} # INCREMENT

		# And if not, start with a whole new line.
		# If mv_orderline is set, will replace a line.
		if ($found == -1) {
			$item = {'code' => $code, 'quantity' => $quantity, mv_ib => $base}
				if ! $item;

			# Add the master item/sub item ids if appropriate
			if(@group) {
				if($attr{mv_mi}->[$j]) {
					$item->{mv_mi} = $mv_mi = $attr{mv_mi}->[$j];
					$item->{mv_mp} = $mv_mp = $attr{mv_mp}->[$j];
					$item->{mv_si} = $mv_si = 0;
				}
				else {
					$item->{mv_mi} = $mv_mi;
					$item->{mv_si} = ++$mv_si;
					$item->{mv_mp} = $attr{mv_mp}->[$j] || $mv_mp;
				}
			}

			$item->{mv_sku} = $skus[$i] if defined $skus[$i];

			if($Vend::Cfg->{UseModifier}) {
				foreach $i (@{$Vend::Cfg->{UseModifier}}) {
					$item->{$i} = $attr{$i}->[$j];
				}
			}
			if($Vend::Cfg->{AutoModifier}) {
				foreach $i (@{$Vend::Cfg->{AutoModifier}}) {
					my ($table,$key) = split /:/, $i;
					unless ($key) {
						$key = $table;
						$table = $base;
					}
					$item->{$key} = tag_data($table, $key, $code);
				}
			}
			if($lines[$j] =~ /^\d+$/ and defined $cart->[$lines[$j]] ) {
				$cart->[$lines[$j]] = $item;
			}
			else {
# TRACK
				$Vend::Track->add_item($cart,$item) if $Vend::Track;
# END TRACK
				push @$cart, $item;
			}
		}
		$j++;
	}

	if($Vend::Cfg->{OrderLineLimit} and $#$cart >= $Vend::Cfg->{OrderLineLimit}) {
		@$cart = ();
		my $msg = errmsg(
			"WARNING:\n" .
			"Possible bad robot. Cart limit of %s exceeded. Cart emptied.\n",
			$Vend::Cfg->{OrderLineLimit}
		);
		do_lockout($msg);
	}
	Vend::Cart::toss_cart($cart);
}


# Compatibility with old globalsub payment
*send_mail = \&Vend::Util::send_mail;

# Compatibility with old globalsub payment
*map_actual = \&Vend::Payment::map_actual;

1;
__END__
