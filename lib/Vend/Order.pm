#!/usr/bin/perl
#
# MiniVend version 1.04
#
# $Id: Order.pm,v 1.5 1997/05/22 07:00:05 mike Exp $
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

$VERSION = substr(q$Revision: 1.5 $, 10);
$DEBUG = 0;

# AUTOLOAD
#use AutoLoader;
#@ISA = qw(Exporter AutoLoader);
#*AUTOLOAD = \&AutoLoader::AUTOLOAD;
# END AUTOLOAD

# NOAUTO
@ISA = qw(Exporter);
# END NOAUTO

@EXPORT = qw (

check_required
check_order
mail_order

);

use Carp;
use Vend::Util;
use Vend::Interpolate;
use Vend::Session;
use Vend::Data;
use Text::ParseWords;

# AUTOLOAD
#use vars qw(
#@Errors
#$Fatal
#$Final
#);
# END AUTOLOAD

# AUTOLOAD
#@Errors = ();
#$Fatal = 0;
#$Final = 0;
# END AUTOLOAD

# NOAUTO
my @Errors = ();
my $Fatal = 0;
my $Final = 0;
# END NOAUTO

sub _fatal {
	$Fatal = ( defined($_[1]) && ($_[1] =~ /^[yYtT1]/) ) ? 1 : 0;
}

sub _final {
	$Final = ( defined($_[1]) && ($_[1] =~ /^[yYtT1]/) ) ? 1 : 0;
}

sub _format {
	my($ref,$params) = @_;
	no strict 'refs';
	my ($routine, $var, $val) = split /\s+/, $params, 3;

# NOAUTO
	return (undef, $var, "No format check routine for '$routine'")
		unless defined &{"_$routine"};
# END NOAUTO

	return &{'_' . $routine}($ref,$var,$val);
}

# AUTOLOAD
#%Parse = (
# END AUTOLOAD

# NOAUTO
my %Parse = (
# END NOAUTO

	'&fatal'       	=>	\&_fatal,
	'&format'		=> 	\&_format,
	'&final'		=>	\&_final,
	'&set'			=>	sub {		
							my($ref,$params) = @_;
							my ($var, $value) = split /\s+/, $params, 2;
						    $Vend::Session->{'values'}->{$var} = $value;
							},
);

# AUTOLOAD
#1;
#__END__
# END AUTOLOAD

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
	my $email = shift || $Vend::Cfg->{MailOrderTo};
    my($body, $i, $code, $ok, $seen, $blankline);
    my($values, $key, $value, $order_no, $pgp, $subject);
	my(%modifiers);
	my $new = 0;
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

	$order_no = update_order_number();

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

	track_order($order_no, $body);

    $body .= "\n" . order_list()
		unless $new;

	$subject = $CGI::values{mv_order_subject} || "ORDER %n";

	if(defined $order_no) {
	    $subject =~ s/%n/$order_no/;
    	$body .= "\n\nORDER NUMBER: $order_no\n"
			unless $Vend::Cfg->{NewReport};
	}
	else { $subject =~ s/\s*%n\s*//g; }

	if($pgp = $Vend::Cfg->{'PGP'} ||= '') {
		open(Vend::Order::PGP, "|$pgp > pgp$$.out 2>pgp$$.err")
			or die "Couldn't fork: $!";
		print Vend::Order::PGP $body;
		close Vend::Order::PGP;
		if($?) {
			logError("PGP failed with status " . $? << 8 . ": $!");
			return 0;
		}
		$body = `cat pgp$$.out`;
		unlink "pgp$$.out";
		unlink "pgp$$.err";
	}
    $ok = send_mail($email, $subject, $body);
    $ok;
}


sub check_order {
	my ($profile) = @_;
	my $ref = \%CGI::values;
    my($codere) = '[\w-_#/.]+';
	unless($profile =~ /^\d+$/) {
		return undef
			unless defined $Vend::Cfg->{'OrderProfileName'}->{$profile};
		$profile = $Vend::Cfg->{'OrderProfileName'}->{$profile};
	}
	my $params = $Vend::Cfg->{'OrderProfile'}->[$profile];
	return undef unless $params;
	$params = interpolate_html($params);
	@Errors = ();
	$Fatal = $Final = 0;

	my($var,$val);
	my $status = 1;
	my(@param) = split /\n+/, $params;

	for(@param) {
		next unless /\S/;
		next if /^\s*#/;
		s/^\s+//;
		s/\s+$//;
		$parameter = $_;
		if (/^&/) {
			($var,$val) = split /[\s=]+/, $parameter, 2;
		}
		else {
			$parameter =~ /(\w+)[\s=]+(.*)/;
			$k = $1;
			$v = $2;
			($var,$val) =
				('&format', $v . ' ' . $k  . ' ' .
					$Vend::Session->{'values'}->{$k} );
		}
		$val =~ s/&#(\d+);/chr($1)/ge;

		if (defined $Parse{$var}) {
			($val, $var, $message) = &{$Parse{$var}}($ref, $val);
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
		last if $Fatal && ! $status;
	}
	my $errors = join "\n", @Errors;
	$errors = '' unless defined $errors;
	return ($status, $Final, $errors);
}

sub _column {
	return undef unless defined $_[1];
	my @fields = split /\s*[,\0]\s*/, $_[1];
	my $col;
	for(@fields) {
		($_ = column_exists($_) + 1)
			unless /^\d+$/;
	}
	\@fields;
}

sub _array {
	return undef unless defined $_[1];
	[split /\s*[,\0]\s*/, $_[1]]
}

sub _yes {
	return( defined($_[2]) && ($_[2] =~ /^[yYtT1]/));
}

sub _phone {
	my($ref,$var,$val) = @_;
	defined $val and $val =~ /\d{3}.*\d{3}/;
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
	if($val and $val =~ /\w+@[-A-Za-z0-9.]+\.[A-Za-z]+/) {
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

sub _required {
	my($ref,$var,$val) = @_;
	return (1, $var, '')
		if (defined $val and $val =~ /\S/);
	return (1, $var, '')
		if (defined $ref->{$var} and $ref->{$var} =~ /\S/);
	return (undef, $var, "blank");
}

sub update_order_number {

	my($c,$order_no);

	if($Vend::Cfg->{'OrderCounter'}) {
		$File::CounterFile::DEFAULT_DIR = $Vend::Cfg->{'VendRoot'}
			unless $Vend::Cfg->{'OrderCounter'} =~ m!^/!;
		my $c = new File::CounterFile $Vend::Cfg->{'OrderCounter'}, "000000";
		$order_no = $c->inc;
		undef $c;
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

1;
__END__
