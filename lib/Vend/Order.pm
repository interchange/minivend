#!/usr/bin/perl
#
# MiniVend version 1.04
#
# $Id: Order.pm,v 1.40 1999/08/13 18:25:45 mike Exp $
#
# This program is largely based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Enhancements made by and
# Copyright 1996-1999 by Michael J. Heins <mike@heins.net>
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
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

package Vend::Order;
require Exporter;

$VERSION = substr(q$Revision: 1.40 $, 10);
$DEBUG = 0;

@ISA = qw(Exporter);

@EXPORT = qw (

check_required
check_order
cyber_charge
mail_order

);

use Vend::Util;
use Vend::Interpolate;
use Vend::Session;
use Vend::Data;
use Text::ParseWords;

my @Errors = ();
my $Fatal = 0;
my $Final = 0;
my $Success;

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

	return (undef, $var, "No format check routine for '$routine'")
		unless defined &{"_$routine"};

	my (@return) = &{'_' . $routine}($ref,$var,$val);
	if(! $return[0] and $message) {
		$return[2] = $message;
	}
	return @return;
}

my %Parse = (

	'&return'       =>	\&_return,
	'&fatal'       	=>	\&_fatal,
	'&format'		=> 	\&_format,
	'&final'		=>	\&_final,
	'&set'			=>	sub {		
							my($ref,$params) = @_;
							my ($var, $value) = split /\s+/, $params, 2;
						    $Vend::Session->{'values'}->{$var} = $value;
							},
);

my $CC2;
my $CC3;
my $CC3server;

eval {
	require CCLib;
	$CC2 = 1;
	my $ver = $CCLib::VERSION || '2.1';
	logGlobal( errmsg('Order.pm:1', "CyberCash module found (CyberCash 2).", $ver ) );
};

$Vend::CyberCash = ! $@;

eval {
	require CCMckLib3_2 ;
	import CCMckLib3_2 qw/InitConfig %Config $MCKversion/;
	require CCMckDirectLib3_2;
	import CCMckDirectLib3_2 qw/SendCC2_1Server doDirectPayment/;
	require CCMckErrno3_2;
	import CCMckErrno3_2 qw/MCKGetErrorMessage/;
	$CC3 = 1;
	$CC3server = 0;
	logGlobal( errmsg('Order.pm:2', "CyberCash module found (CyberCash 3).") );
};

$Vend::CyberCash = $Vend::CyberCash || ! $@;

sub testSetServer {
	my %options = @_;
	my $out = '';
	for(sort keys %options) {
		$out .= "$_=$options{$_}\n";
	}
	logError( errmsg('Order.pm:3', "Test CyberCash SetServer:\n%s\n" , $out) );
	1;
}

sub testsendmserver {
	my ($type, %options) = @_;
	my $out ="type=$type\n";
	for(sort keys %options) {
		$out .= "$_=$options{$_}\n";
	}
	logError("Test CyberCash sendmserver:\n$out\n");
	return ('MStatus', 'success', 'order-id', 1);
}

sub cyber_charge {

	my $val = $Vend::Session->{'values'};

    my %map = qw(
		mv_credit_card_number       mv_credit_card_number
		name                        name
		b_name                      b_name
		address                     address
		b_address                   b_address
		city                        city
		b_city                      b_city
		state                       state
		b_state                     b_state
		zip                         zip
		b_zip                       b_zip
		country                     country
		b_country                   b_country
		mv_credit_card_exp_month    mv_credit_card_exp_month
		mv_credit_card_exp_year     mv_credit_card_exp_year
		cyber_mode                  mv_cyber_mode
		amount                      amount
    );

	# Allow remapping of the variable names
	my $remap = $Vend::Cfg->{Variable}->{CYBER_REMAP};
	$remap =~ s/^\s+//;
	$remap =~ s/\s+$//;
	%remap = split /[\s=]+/, $remap;
	for (keys %remap) {
		$map{$_} = $remap{$_};
	}

	my %actual;
	my $key;

	# pick out the right values, need alternate billing address
	# substitution
	foreach $key (keys %map) {
		$actual{$key} = $val->{$map{$key}} || $CGI::values{$key}
			and next;
		my $secondary = $key;
		next unless $secondary =~ s/^b_//;
		$actual{$key} = $val->{$map{$secondary}} ||
						$CGI::values{$map{$secondary}};
	}
#::logGlobal ("cyber_charge, mode $CGI::values{mv_cyber_mode}");
    my $currency = $Vend::Cfg->{Variable}->{CYBER_CURRENCY} || 'usd';
    $actual{mv_credit_card_exp_month} =~ s/\D//g;
    $actual{mv_credit_card_exp_month} =~ s/^0+//;
    $actual{mv_credit_card_exp_year} =~ s/\D//g;
    $actual{mv_credit_card_exp_year} =~ s/\d\d(\d\d)/$1/;

    $actual{mv_credit_card_number} =~ s/\D//g;

    my $exp = $actual{mv_credit_card_exp_month} . '/' .
    		  $actual{mv_credit_card_exp_year};

    $actual{cyber_mode} = 'mauthcapture'
		unless $actual{cyber_mode};

    my($orderID);
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());

    # We'll make an order ID based on date, time, and MiniVend session

    # $mon is the month index where Jan=0 and Dec=11, so we use
    # $mon+1 to get the more familiar Jan=1 and Dec=12
    $orderID = sprintf("%02d%02d%02d%02d%02d%05d%s",
            $year + 1900,$mon + 1,$mday,$hour,$min,$Vend::SessionName);

    # The following characters are illegal in an order ID:
    #    : < > = + @ " % = &
    #
    # If you want, you could use a line similar to the following
    # to remove these illegal characters:

    $orderID =~ tr/:<>=+\@\"\%\&/_/d;

    #
    # Or use something like the following line to only allow
    # alphanumeric and dash, converting other characters to underscore:
    #    $orderID =~ tr/A-Za-z0-9\-/_/c;

    # Our test order ID only contains digits, so we don't have
    # to strip any characters here. You might have to if you
    # use a different scheme.

	my $precision = $Vend::Cfg->{Variable}{CYBER_PRECISION} || 2;
    $amount = Vend::Interpolate::total_cost();
	$amount = sprintf("%.${precision}f", $amount);
    $amount = "$currency $amount";

# DEBUG
#Vend::Util::logDebug
#("cyber_charge: amount is '$amount'\n")
#	if ::debug(0x1);
# END DEBUG

    my %result;

    unless ($actual{cyber_mode} eq 'minivend_test') {
		# Live interface operations follow
		unless	(defined	$Vend::Cfg->{Variable}{CYBER_VERSION}
				and			$Vend::Cfg->{Variable}{CYBER_VERSION} >= 3 )
		{
			undef $CC3;
			undef $CC3server;
		}
		elsif ( $Vend::Cfg->{Variable}{CYBER_VERSION} >= 3.2 ) {
			$CC3server = 1;
		}

		if($CC3){
			# Cybercash 3.x libraries to be used.
			# Initialize the merchant configuration file
			my $status = InitConfig($Vend::Cfg->{Variable}{CYBER_CONFIGFILE});
			if ($status != 0) {
				$Vend::Session->{cybercash_error} = MCKGetErrorMessage($status);
				return undef;
			}
			unless($Vend::Cfg->{Variable}->{CYBER_HOST}) {
				$Vend::Cfg->{Variable}->{CYBER_HOST} = $Config{CCPS_HOST};
			}
		}
		if($CC3server) {
			# Cybercash 3.x server and libraries to be used.

			if ($status != 0) {
				$Vend::Session->{cybercash_error} = MCKGetErrorMessage($status);
				return undef;
			}
			$sendurl = $Vend::Cfg->{Variable}->{CYBER_HOST} . 'directcardpayment.cgi';

			my %paymentNVList;
			$paymentNVList{'mo.cybercash-id'} = $Config{'CYBERCASH_ID'};
			$paymentNVList{'mo.version'} = $MCKversion;

			$paymentNVList{'mo.signed-cpi'} = "no";
			$paymentNVList{'mo.order-id'} = $orderID;
			$paymentNVList{'mo.price'} = $amount;

			$paymentNVList{'cpi.card-number'} = $actual{mv_credit_card_number};
			$paymentNVList{'cpi.card-exp'} = $exp;
			$paymentNVList{'cpi.card-name'} = $actual{b_name};
			$paymentNVList{'cpi.card-address'} = $actual{b_address};
			$paymentNVList{'cpi.card-city'} = $actual{b_city};
			$paymentNVList{'cpi.card-state'} = $actual{b_state};
			$paymentNVList{'cpi.card-zip'} = $actual{b_zip};
			$paymentNVList{'cpi.card-country'} = $actual{b_country};

			my (  $POPref, $tokenlistref, %tokenlist );
			($POPref, $tokenlistref ) = 
							  doDirectPayment( $sendurl, \%paymentNVList );
			
			%tokenlist = %$tokenlistref;
			$result{MStatus}    = $POPref->{'pop.status'};
			$result{MErrMsg}     = $POPref->{'pop.error-message'};
			$result{'order-id'} = $POPref->{'pop.order-id'};

			$Vend::Session->{cybercash_result} = $POPref;

			# other values found in POP which might be used in some way:
			#		$POP{'pop.auth-code'};
			#		$POP{'pop.ref-code'};
			#		$POP{'pop.txn-id'};
			#		$POP{'pop.sale_date'};
			#		$POP{'pop.sign'};
			#		$POP{'pop.avs_code'};
			#		$POP{'pop.price'};
		}
		else {
			# Cybercash 2.x server interface follows
			if ($CC3){
				# Use Cybercash 3.x libraries
				*sendmserver = \&CCMckDirectLib3_2::SendCC2_1Server;
			}
			else {
				# Constants to find the merchant payment server
				#
				my %payment = (
					'host' => $Vend::Cfg->{Variable}->{CYBER_HOST} || 'localhost',
					'port' => $Vend::Cfg->{Variable}->{CYBER_PORT} || 8000,
					'secret' => $Vend::Cfg->{Variable}->{CYBER_SECRET} || '',
				);
				*sendmserver = \&CCLib::sendmserver;
				# Use Cybercash 2.x libraries
				CCLib::SetServer(%payment);
			}
			%result = sendmserver(
				$actual{cyber_mode},
				'Order-ID'     => $orderID,
				'Amount'       => $amount,
				'Card-Number'  => $actual{mv_credit_card_number},
				'Card-Name'    => $actual{b_name},
				'Card-Address' => $actual{b_address},
				'Card-City'    => $actual{b_city},
				'Card-State'   => $actual{b_state},
				'Card-Zip'     => $actual{b_zip},
				'Card-Country' => $actual{b_country},
				'Card-Exp'     => $exp,
			);
			$Vend::Session->{cybercash_result} = \%result;
		}
    }
    else {
		# Minivend test mode
		my %payment = (
			'host' => $Vend::Cfg->{Variable}->{CYBER_HOST} || 'localhost',
			'port' => $Vend::Cfg->{Variable}->{CYBER_PORT} || 8000,
			'secret' => $Vend::Cfg->{Variable}->{CYBER_SECRET} || '',
		);
		&testSetServer ( %payment );
		%result = testsendmserver(
					$actual{cyber_mode},
			'Order-ID'     => $orderID,
			'Amount'       => $amount,
			'Card-Number'  => $actual{mv_credit_card_number},
			'Card-Name'    => $actual{b_name},
			'Card-Address' => $actual{b_address},
			'Card-City'    => $actual{b_city},
			'Card-State'   => $actual{b_state},
			'Card-Zip'     => $actual{b_zip},
			'Card-Country' => $actual{b_country},
			'Card-Exp'     => $exp,
		);
    }

	if($result{MStatus} !~ /^success/) {
		$Vend::Session->{cybercash_error} = $result{MErrMsg};
		return undef;
	}
	elsif($result{MStatus} =~ /success-duplicate/) {
		$Vend::Session->{cybercash_error} = $result{MErrMsg};
	}
	else {
		$Vend::Session->{cybercash_error} = '';
	}
	$Vend::Session->{cybercash_id} = $result{'order-id'};
	if($Vend::Cfg->{EncryptProgram} =~ /pgp/i) {
		$CGI::values{mv_credit_card_force} = 1;
		(
			$val->{mv_credit_card_valid},
			$val->{mv_credit_card_info},
			$val->{mv_credit_card_exp_month},
			$val->{mv_credit_card_exp_year},
			$val->{mv_credit_card_exp_all},
			$val->{mv_credit_card_type},
			$val->{mv_credit_card_error}
		)	= Vend::ValidCC::encrypt_standard_cc(\%CGI::values);
	}
        logError( errmsg('Order.pm:3', "Order id: 
                          $Vend::Session->{cybercash_id}\n") );
	return $result{'order-id'};
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

#sub create_onfly {
#	my $opt = shift;
#	if($opt->{create}) {
#		delete $opt->{create};
#		my $href = $opt->{href} || '';
#		my $secure = $opt->{secure} || '';
#		if(defined $split_fields) {
#			return join $joiner, @{$opt}{ split /[\s,]+/, $split_fields };
#		}
#		else {
#			my @out;
#			my @fly;
#			for(keys %{$opt}) {
#				$opt->{$_} =~ s/[\0\n]/\r/g unless $v;
#				push @fly, "$_=$opt->{$_}";
#			}
#			push @out, "mv_order_fly=" . join $joiner, @fly;
#			push @out, "mv_order_item=$opt->{code}"
#				if ! $opt->{mv_order_item} and $opt->{code};
#			push @out, "mv_order_quantity=$opt->{quantity}"
#				if ! $opt->{mv_order_quantity} and $opt->{quantity};
#			push @out, "mv_todo=refresh"
#				if ! $opt->{mv_todo};
#		}
#		my $form = join "\n", @out;
#		return Vend::Interpolate::form_link( $href, '', $secure, { form => $form } );
#	}
#
#}

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

	my $joiner		= $Vend::Cfg->{Variable}{MV_ONFLY_JOINER} || '|';
	my $split_fields= $Vend::Cfg->{Variable}{MV_ONFLY_FIELDS} || undef;

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

sub order_report {
    my($seen) = @_;
    my($fn, $report, $values, $date);
    $values = $Vend::Session->{'values'};
	my $old = 0;
	$report = '';

	if(defined $values->{'mv_order_report'}
		and $values->{'mv_order_report'}) {
		$report = readin($values->{'mv_order_report'});
	}

	unless ($report) {
		$old = 1;
		$fn = $Vend::Cfg->{'OrderReport'};
		if (!open(Vend::IN, $fn)) {
			logError("Could not open report file '$fn': $!");
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
	}

	$report;
}

sub order_list {
    my($body, $i, $item, $code, $quantity, $desc, $price);

    $body = <<'END';
Qty     Item              Description                      Price       Total
---  ------------    ----------------------------------   --------   ---------
END

    foreach $i (0 .. $#$Vend::Items) {
	$item = $Vend::Items->[$i];
	$code = $item->{'code'};
	$quantity = $item->{'quantity'};
	$price = item_price($item);
	$desc  = item_description($item);
	$desc =~ s/<.*?>/ /g;
	$body .= sprintf( "%3s  %-14s  %-34s  %9s  %10s\n",
			 $quantity,
			 $code,
			 substr($desc,0,34),
			 currency($price),
			 currency($quantity * $price) );
    }
	$body .= sprintf "%3s  %-14s  %-34s  %9s  %10s\n",
			'','','SUBTOTAL','', currency(subtotal());
	$body .= sprintf "%3s  %-14s  %-34s  %9s  %10s\n",
			'','','SALES TAX','', currency(salestax());
	$body .= sprintf "%3s  %-14s  %-34s  %9s  %10s\n",
			'','','SHIPPING',
			$Vend::Session->{'values'}->{'mv_shipmode'},
			currency(shipping());
	$body .= sprintf "%3s  %-14s  %-34s  %9s  %10s\n",
			'','','','TOTAL', tag_total_cost();
    $body;
}

sub check_required {
	my $val = shift;
	my $item;
	my @missing;
	my @req = split(/\s*,\s*/, $Vend::Cfg->{'RequiredFields'});
	foreach $item (@req) {
	   push(@missing,$item)
	   		unless $val->{$item};
	}
	push(@missing, "items: you might want to order something!")
		unless @$Vend::Items;
	if(!@missing) {
		return(1);
	} else{
		return(0,join("\n", @missing));
	}
}

# Get fields to ignore for report, returns anon_hash ref
sub get_ignored {
	my @ignore;
	my $ignore = {};
	my $field;

	@ignore = split(/[\s,]+/, $Vend::Cfg->{'ReportIgnore'});
	foreach $field (@ignore) {
		$ignore->{$field} = 1;
	}
	$ignore;
}

# Email the processed order.

sub mail_order {
	my ($email, $order_no) = @_;
	$email = $Vend::Cfg->{MailOrderTo} unless $email;
    my($body, $i, $code, $ok, $seen, $blankline);
    my($values, $key, $value, $pgp, $subject);
	my(%modifiers);
	my $new = $Vend::Cfg->{NewReport};
    $seen = get_ignored();
    $body = order_report($seen);
    return undef unless defined $body;

	# To ignore the modifiers in the mailed report
	if($Vend::Cfg->{UseModifier}) {
		for (@{$Vend::Cfg->{UseModifier}}) {
			$modifiers{$_} = 1;
		}
	}

    $values = $Vend::Session->{'values'};

	$order_no = update_order_number() unless $order_no;

	if(defined $values->{'mv_order_report'}
		and $values->{'mv_order_report'}) {
		$new = 1;
	}

    $blankline = 0;
	OLD: {
		last OLD if $Vend::Cfg->{NewReport};
		while (($key, $value) = each %$values) {
			next if $key =~ /^mv_/i;
			if($key =~ /\d+$/) {
				$tmpkey = $key;
				$tmpkey =~ s/\d+$//;
				next if $modifiers{$tmpkey};
			}
			if (!$new && !$$seen{$key}) {
				if (!$blankline) {
					$body .= "\n";
					$blankline = 1;
				}
				$body .= "$key: $value\n";
			}
		}
	}

	$body = interpolate_html($body) if $new;

    $body .= "\n" . order_list()
		unless $new;

	$body = pgp_encrypt($body) if $Vend::Cfg->{PGP};

	track_order($order_no, $body);

	$subject = $::Values->{mv_order_subject} || "ORDER %n";

	if(defined $order_no) {
	    $subject =~ s/%n/$order_no/;
    	$body .= "\n\nORDER NUMBER: $order_no\n"
			unless $Vend::Cfg->{NewReport};
	}
	else { $subject =~ s/\s*%n\s*//g; }

    $ok = send_mail($email, $subject, $body);
    $ok;
}

sub pgp_encrypt {
	my($body, $key, $cmd) = @_;
	$cmd = $Vend::Cfg->{PGP} unless $cmd;
	if($key) {
		$cmd =~ s/%%/:~PERCENT~:/g;
		$cmd =~ s/%s/$key/g;
		$cmd =~ s/:~PERCENT~:/%/g;
	}
	my $fpre = $Vend::Cfg->{ScratchDir} . "/pgp.$$";
	open(Vend::Order::PGP, "|$cmd >$fpre.out 2>$fpre.err")
			or die "Couldn't fork: $!";
	print Vend::Order::PGP $body;
	close Vend::Order::PGP;
	if($?) {
		logError("PGP failed with status " . $? << 8 . ": $!");
		return 0;
	}
	$body = readfile("$fpre.out");
	unlink "$fpre.out";
	unlink "$fpre.err";
	return $body;
}

sub check_order {
	my ($profile) = @_;
    my($codere) = '[\w-_#/.]+';
	my $params;
	if(defined $Vend::Cfg->{'OrderProfileName'}->{$profile}) {
		$profile = $Vend::Cfg->{'OrderProfileName'}->{$profile};
		$params = $Vend::Cfg->{'OrderProfile'}->[$profile];
	}
	elsif($profile =~ /^\d+$/) {
		$params = $Vend::Cfg->{'OrderProfile'}->[$profile];
	}
	elsif(defined $Vend::Session->{'scratch'}->{$profile}) {
		$params = $Vend::Session->{'scratch'}->{$profile};
	}
	else { return undef }
	return undef unless $params;

	my $ref = \%CGI::values;
	$params = interpolate_html($params);
	@Errors = ();
	$Fatal = $Final = 0;

	my($var,$val);
	my $status = 1;
	my(@param) = split /[\r\n]+/, $params;
	my $m;
	my $join;

	for(@param) {
		if($join) {
			$_ = "$join$_";
			undef $join;
		}
		next unless /\S/;
		next if /^\s*#/;
		if(s/\\$//) {
			$join = $_;
			next;
		}
		s/^\s+//;
		s/\s+$//;
		$parameter = $_;
		if (/^&/) {
			($var,$val) = split /[\s=]+/, $parameter, 2;
		}
		elsif ($parameter =~ /(\w+)[\s=]+(.*)/) {
			$k = $1;
			$v = $2;
			$m = $v =~ s/\s+(.*)// ? $1 : undef;
			($var,$val) =
				('&format',
				  $v . ' ' . $k  . ' ' .  $::Values->{$k}
				  );
		}
		else {
			logError("Unknown order check '$parameter' in profile $profile");
			next;
		}
		$val =~ s/&#(\d+);/chr($1)/ge;

		if (defined $Parse{$var}) {
			($val, $var, $message) = &{$Parse{$var}}($ref, $val, $m || undef);
		}
		else {
			logError("Unknown order check parameter in profile $profile:\n" .
					 "	parameter '$var'	(args '$val')" );
			next;
		}

		unless (defined $val and $val) {
			$status = 0;
			if (defined $var) {
				$Vend::Session->{'values'}->{"mv_error_$var"} = $message;
				push @Errors, "$var: $message";
			}
			else {
				push @Errors, "Error: $parameter";
			}
		}
		elsif (defined $var) {
 			$Vend::Session->{'values'}->{"mv_status_$var"} = $message
				if defined $message and $message;
 			undef $Vend::Session->{'values'}->{"mv_error_$var"};
		}
		($status = $Success and last) if defined $Success;
		last if $Fatal && ! $status;
	}
	my $errors = join "\n", @Errors;
	$errors = '' unless defined $errors and ! $Success;
	return ($status, $Final, $errors);
}

my $state = <<EOF;
AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD
MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA PR RI
SC SD TN TX UT VT VA WA WV WI WY DC AP FP FPO APO GU VI
EOF

my $province = <<EOF;
AB BC MB NB NF NS NT ON PE QC SK YT YK
EOF

sub _state_province {
	my($ref,$var,$val) = @_;
	if( (_state(@_))[0] or (_province(@_))[0] ) {
		return (1, $var, '');
	}
	else {
		return (undef, $var, "'$val' not a two-letter state or province code");
	}
}

sub _state {
	my($ref,$var,$val) = @_;
	if( $state =~ /\b$val\b/i) {
		return (1, $var, '');
	}
	else {
		return (undef, $var, "'$val' not a two-letter state code");
	}
}

sub _province {
	my($ref,$var,$val) = @_;
	if( $province =~ /\b$val\b/i) {
		return (1, $var, '');
	}
	else {
		return (undef, $var, "'$val' not a two-letter province code");
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
	_zip(@_) or _ca_postcode(@_);
}

sub _ca_postcode {
	my($ref,$var,$val) = @_;
	$val =~ s/[_\W]+//g;
	defined $val
		and
	$val =~ /^[ABCEGHJKLMNPRSTVXYabceghjklmnprstvxy]\d[A-Za-z]\d[A-Za-z]\d$/
}

sub _zip {
	my($ref,$var,$val) = @_;
	defined $val and $val =~ /^\s*\d{5}(?:[-]\d{4})?\s*$/;
}

*_us_postcode = \&_zip;

sub _phone {
	my($ref,$var,$val) = @_;
	defined $val and $val =~ /\d{3}.*\d{3}/
		and return (1, $var, '');
}

sub _phone_us {
	my($ref, $var,$val) = @_;
	if($val and $val =~ /\d{3}.*?\d{4}/) {
		return (1, $var, '');
	}
	else {
		return (undef, $var, 'not a US phone number');
	}
}

sub _email {
	my($ref, $var, $val) = @_;
	if($val and $val =~ /[\040-\176]+\@[-A-Za-z0-9.]+\.[A-Za-z]+/) {
		return (1, $var, '');
	}
	else {
		return (undef, $var, "$val not an email address");
	}
}

sub _mandatory {
	my($ref,$var,$val) = @_;
	return (1, $var, '')
		if (defined $ref->{$var} and $ref->{$var} =~ /\S/);
	return (undef, $var, "blank");
}

sub _true {
	my($ref,$var,$val) = @_;
	return (1, $var, '') if is_yes($val);
	return (undef, $var, "false");
}

sub _false {
	my($ref,$var,$val) = @_;
	return (1, $var, '') if is_no($val);
	return (undef, $var, "true");
}

sub _required {
	my($ref,$var,$val) = @_;
	return (1, $var, '')
		if (defined $val and $val =~ /\S/);
	return (1, $var, '')
		if (defined $ref->{$var} and $ref->{$var} =~ /\S/);
	return (undef, $var, "blank");
}

sub counter_number {
	my $file = shift || $Vend::Cfg->{'OrderCounter'};
	$File::CounterFile::DEFAULT_DIR = $Vend::Cfg->{'VendRoot'}
		unless $file =~ m!^/!;
	my $c = new File::CounterFile $file, "000000";
	return $c->inc;
}

sub update_order_number {

	my($c,$order_no);

	if($Vend::Cfg->{'OrderCounter'}) {
		$order_no = counter_number();
	}
	else {
		$order_no = $Vend::SessionID . '.' . time;
	}

	$Vend::Session->{'values'}->{'mv_order_number'} = $order_no;
	$order_no;
}

# Places the order report in the Tracking file
sub track_order {
	my ($order_no,$order_report) = @_;
	my ($c,$i);
	my (@backend);
	
	if ($Vend::Cfg->{'AsciiTrack'}) {
		logData ($Vend::Cfg->{'AsciiTrack'}, "ORDER $order_no\n$order_report");
	}

	@backend = split /\s*,\s*/, $Vend::Cfg->{'BackendOrder'};
	
	if(@backend and $Vend::Cfg->{'AsciiBackend'}) {
		my(@ary);
		push @ary, $order_no;
		for(@backend) {
			push @ary, $Vend::Session->{'values'}->{$_};
		}
		foreach $i (0 .. $#$Vend::Items) {
			push @ary, $Vend::Items->[$i]->{'code'};
			push @ary, $Vend::Items->[$i]->{'quantity'};
			if ($Vend::Cfg->{UseModifier}) {
				foreach $j (@{$Vend::Cfg->{UseModifier}}) {
					push @ary, $Vend::Items->[$i]->{$j}
				}
			}
		}
		logData ($Vend::Cfg->{'AsciiBackend'}, @ary);
	}

}

sub route_order {
	my ($route, $save_cart) = @_;
	my $cart = [ @$save_cart ];
	if(! $Vend::Cfg->{Route}) {
		$Vend::Cfg->{Route} = {
			report		=> "pages/$::Values->{mv_order_report}.html" || 'etc/report',
			receipt		=> $::Values->{mv_order_receipt} || 
									$Vend::Cfg->{ReceiptPage}  ||
									find_special_page('confirmation'),
			encrypt_program	=> '',
			encrypt		=> 0,
			pgp_key		=> '',
			pgp_cc_key	=> '',
			cybermode	=> $CGI::values{mv_cybermode} || undef,
			credit_card	=> 1,
			profile		=> '',
			email		=> $Vend::Cfg->{MailOrderTo},
			attach		=> 0,
			counter		=> '',
			increment	=> 0,
			supplant	=> 0,
			track   	=> '',
			errors_to	=> $Vend::Cfg->{MailOrderTo},
		};
	}

	my $main = $Vend::Cfg->{Route};

	my $save_mime = $Vend::MIME || undef;

	my $encrypt_program = $main->{encrypt_program} || 'pgpe -fat -r %s';
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

	push @routes, @main;

	my ($c,@out);
	my $status;
	my $errors = '';

	$::Values->{mv_order_number} = counter_number($main->{counter});

	my $value_save = { %{$::Values} };

		BUILD:
	foreach $c (@routes) {
		$Data::Dumper::Indent = 3;
		my $route = $Vend::Cfg->{Route_repository}{$c};
#::logGlobal("Route $c:\n" . Data::Dumper::Dumper($route) 
#						.	"values:\n" .  Data::Dumper::Dumper($::Values)
#							);
		$::Values = { %$value_save };
		my $pre_encrypted;
		my $credit_card_info;
		if ( $Vend::Cfg->{CreditCardAuto} )
		{
			$pre_encrypted = 1;
		}
		else {
			if(! $CGI::values{mv_credit_card_type} and
				 $CGI::values{mv_credit_card_number} )
			{
				if($CGI::values{mv_credit_card_number} =~ /\s*4/) {
					$CGI::values{mv_credit_card_type} = 'visa';
				}
				elsif($CGI::values{mv_credit_card_number} =~ /\s*5/) {
					$CGI::values{mv_credit_card_type} = 'mc';
				}
				elsif($CGI::values{mv_credit_card_number} =~ /\s*3/) {
					$CGI::values{mv_credit_card_type} = 'amex';
				}
				else {
					$CGI::values{mv_credit_card_type} = 'diners/other';
				}
			}
			$::Values->{mv_credit_card_info} = join "\t", 
								$CGI::values{mv_credit_card_type},
								$CGI::values{mv_credit_card_number},
								$CGI::values{mv_credit_card_exp_month} .
								"/" . $CGI::values{mv_credit_card_exp_year};
		}

		$Vend::Items = $shelf->{$c};
		if(! defined $Vend::Cfg->{Route_repository}{$c}) {
			logError(errmsg('Order.pm:4', "Non-existent order routing %s", $c));
			next;
		}
	eval {

		if($route->{profile}) {
			check_order($route->{profile})
				or die "Failed order profile $route->{profile}";
		}

		if($CGI::values{mv_cyber_mode} and $route->{cyber_mode}) {
			my $save = $CGI::values{mv_cyber_mode};
			$CGI::values{mv_cyber_mode} = $route->{cyber_mode};
			my $glob = {};
			my (@vars) =  (qw/ CYBER_CONFIGFILE CYBER_CURRENCY CYBER_HOST
							CYBER_PORT CYBER_REMAP CYBER_SECRET CYBER_VERSION /);
			for(@vars) {
				next unless $route->{$_};
				$glob->{$_} = $Vend::Cfg->{Variable}{$_};
				$Vend::Cfg->{Variable}{$_} = $route->{$_};
			}
			my $ok;
			eval {
				$ok = cyber_charge();
			};
			for(@vars) {
				next unless exists $glob->{$_};
				$Vend::Cfg->{Variable}{$_} = $glob->{_};
			}
			$CGI::values{mv_cyber_mode} = $save;
			unless ($ok) {
				$errors .= errmsg('Order.pm:5',
								"Failed online charge for routing %s: %s",
								$c,
								$Vend::Session->{cybercash_error}
							);
			}
		}
		elsif($route->{credit_card} and ! $pre_encrypted) {
			$::Values->{mv_credit_card_info} = pgp_encrypt(
								$::Values->{mv_credit_card_info},
								($route->{pgp_cc_key} || $route->{pgp_key}),
								($route->{encrypt_program} || $encrypt_program),
							);
		}

		if($route->{counter}) {
			$::Values->{mv_order_number} = counter_number($route->{counter});
		}
		elsif($route->{increment}) {
			$::Values->{mv_order_number} = counter_number();
		}
		my $page = readfile($route->{'report'} || $main->{'report'});
		die "No order report $route->{'report'} or $main->{'report'} found."
			unless defined $page;

		my $use_mime;
		undef $Vend::MIME;
		$page = interpolate_html($page);

#::logGlobal("MIME=$Vend::MIME");
		$use_mime   = $Vend::MIME || undef;
		$Vend::MIME = $save_mime  || undef;

		if($route->{encrypt}) {
			$page = pgp_encrypt($page,
								$route->{pgp_key},
								$route->{encrypt_program} || $encrypt_program,
								);
		}
		my ($address, $reply, $to, $subject, $template);
		if($route->{attach}) {
			$Vend::Items->[0]{mv_order_report} = $page;
		}
		elsif ($address = $route->{email}) {
			$address = $::Values->{$address} if $address =~ /^\w+$/;
			$subject = $::Values->{mv_order_subject} || 'ORDER %s';
			$subject =~ s/%n/%s/;
			$subject = sprintf "$subject", $::Values->{mv_order_number};
			$reply   = $route->{reply} || $main->{reply};
			$reply   = $::Values->{$reply} if $reply =~ /^\w+$/;
			$to		 = $route->{email};
			push @out, [$to, $subject, $page, $reply, $use_mime];
		}
		elsif ($route->{empty}) {
			# Do nothing
		}
		else {
			die "Empty order routing $c (and not explicitly empty)";
		}
		if ($route->{supplant}) {
			track_order($::Values->{mv_order_number}, $page);
		}
		if ($route->{track}) {
			Vend::Util::writefile($route->{track}, $page)
				or ::logError("route tracking error writing $route->{track}: $!");
			chmod($route->{track_mode}, $route->{track}) if $route->{track_mode};
		}
		if ($route->{individual_track}) {
			my $fn = Vend::Util::catfile(
							$route->{individual_track},
							$::Values->{mv_order_number},
						);
			Vend::Util::writefile( $fn, $page,	)
				or ::logError("route tracking error writing $fn: $!");
			chmod($route->{track_mode}, $fn) if $route->{track_mode};
		}
	};
		if($@) {
			my $err = $@;
			$errors .=  errmsg('Order.pm:6',
						"Error during creation of order routing %s:\n%s",
						$c, $err
						)
					;
			next BUILD;
		}

	} #BUILD
	my $msg;

	foreach $msg (@out) {
		eval {
			send_mail(@$msg);
		};
		if($@) {
			my $err = $@;
			$errors .=  errmsg('Order.pm:7',
						"Error sending mail to %s:\n%s",
							$msg->[0], $err
						);
			$status = 0;
			next;
		}
		else {
			$status = 1;
		}
	}

	$Vend::MIME = $save_mime  || undef;
	$::Values = $value_save;
	$Vend::Items = $save_cart;

	if(! $errors) {
		delete $Vend::Session->{order_error};
	}
	elsif ($main->{errors_to}) {
		$Vend::Session->{order_error} = $errors;
		send_mail(
			$main->{errors_to},
			errmsg('Order.pm:8', "ERRORS on ORDER %s", $::Values->{mv_order_number}),
			$errors
			);
	}
	else {
		$Vend::Session->{order_error} = $errors;
		::logError(
			errmsg('Order.pm:9',
					"ERRORS on ORDER %s:\n%s",
					$::Values->{mv_order_number},
					$errors
				)
		);
	}

	# If we give a defined value, the regular mail_order routine will not
	# be called
	if($main->{supplant}) {
		return ($status, $::Values->{mv_order_number});
	}
	return (undef, $::Values->{mv_order_number});
	1;
}


1;
__END__
