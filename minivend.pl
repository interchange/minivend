#!/usr/local/bin/perl
#
# MiniVend version 2.03b
#
# $Id: minivend.pl,v 2.16 1997/03/17 00:59:52 mike Exp mike $
#
# This program is largely based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Enhancements made by and
# Copyright 1996, 1997 by Michael J. Heins <mikeh@iac.net>
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
$Global::VendRoot = '/home/minivend';
$Global::ConfDir = "$Global::VendRoot/etc";

# Uncomment next line if you want to guarantee use of DB_File
#$ENV{MINIVEND_DBFILE} = 1;

# Uncomment next line if you want to use no DBM, sessions
# stored in files and databases in memory (or mSQL)
#$ENV{MINIVEND_NODBM} = 1;

}
$Global::ConfigFile = 'minivend.cfg';
$Global::ErrorFile = 'error.log';

use lib $Global::VendRoot;

# BSD, among others, defines sendmail to be in /usr/sbin, and
# we want to make sure the program is there. Insert the location
# of you sendmail binary (the configure script should do this)
$Global::SendMailLocation = '/usr/lib/sendmail';

# For the order counter, no huge deal if not there.  Included
# with the distribution.
use File::CounterFile;

### END CONFIGURABLE VARIABLES

use strict;
use Fcntl;

#select a DBM

BEGIN {
	$Global::GDBM = $Global::DB_File = $Global::Msql = 0;
	eval {require Msql and $Global::Msql = 1};

	AUTO: {
		last AUTO if 
			(defined $ENV{MINIVEND_DBFILE} and $Global::DB_File = 1);
		last AUTO if 
			(defined $ENV{MINIVEND_NODBM} and $Global::Msql == 1);
		eval {require GDBM_File and $Global::GDBM = 1} ||
		eval {require DB_File and $Global::DB_File = 1};
	}

	if($Global::GDBM) {
		require Vend::Table::GDBM;
		import GDBM_File;
		$Global::GDBM = 1;
	}
	elsif($Global::DB_File) {
		require Vend::Table::DB_File;
		import DB_File;
		$Global::DB_File = 1;
	}
	else {
		require Vend::Table::InMemory;
	}
}


use Vend::Server;
use Vend::Session;
use Vend::Config;
use Vend::Imagemap;
use Vend::Glimpse;
use Vend::Scan;
use Vend::TextSearch;
use Vend::Order;
use Vend::Data;
use Vend::Util;
use Vend::Interpolate;
use Vend::ValidCC;
use Vend::Cart;
use Vend::PageBuild;

my $H;
sub http {
	$H;
}

$Global::ConfigFile = "$Global::VendRoot/$Global::ConfigFile"
    if ($Global::ConfigFile !~ m.^/.);
$Global::ErrorFile = "$Global::VendRoot/$Global::ErrorFile"
    if ($Global::ErrorFile !~ m.^/.);


## PAGE GENERATION

sub plain_header {
    print "Content-type: text/plain\n\n";
    $Vend::content_type = 'plain';
}

sub response {
	my ($type,$output,$debug) = @_;

	# Abortive try to get server to parse our doc
	#if (defined $Vend::Tag_SSI and $Vend::Tag_SSI) {
	#	$type = 'x-server-parsed-html'
	#		if $type eq 'html';
	#}

	$Vend::content_type = $type;
	http()->respond("text/$type",$output,$debug);
}

sub html_header {
    print "Content-type: text/html\n\n";
    $Vend::content_type = 'html';
}

## INTERFACE ERROR

# An incorrect response was returned from the browser, either because of a
# browser bug or bad html pages.

sub interaction_error {
    my($msg) = @_;
    my($page);

    logError ("Difficulty interacting with browser: $msg\n");

    $page = readin($Vend::Cfg->{'Special'}->{'interact'});
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

# Logs page hits in tracking file
sub track_page {
	my $page = shift;
	logData($Vend::Cfg->{'LogFile'}, 'page', time, $Vend::SessionID, $page)
			 if defined $Vend::Cfg->{'CollectData'}->{'page'};
    return unless $Vend::Cfg->{'Tracking'};
	open_tracking();
	$Vend::Tracking{$page} = $Vend::Tracking{$page} + 1;
	close_tracking();
}


## ACTIONS SPECIFIED BY THE INVOKING URL

## DO CATALOG

# Display the initial catalog page.

sub do_catalog {
    do_page($Vend::Cfg->{'Special'}->{'catalog'});
}


## DO PAGE

sub display_special_page {
    my($name, $subject) = @_;
    my($page);

    $page = readin($name);
    die "Missing special page: $name\n" unless defined $page;
    $page =~ s#\[subject\]#$subject#ig;
    return response('html',interpolate_html($page));
}

# Displays the catalog page NAME.  If the file is not found, displays
# the special page 'missing'.
# 

sub display_page {
    my($name) = @_;
    my($page);

	if($Vend::Cfg->{'ExtraSecure'} and
		$Vend::Cfg->{AlwaysSecure}->{$name}
		and !$CGI::secure) {
		$name = $Vend::Cfg->{'Special'}->{'violation'};
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
		$page = readin($Vend::Cfg->{'Special'}->{'missing'});
		die "Special page not found: $Vend::Cfg->{'Special'}->{'missing'}\n"
			unless defined $page;
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
    my($code,$path) = @_;
    my($i, $found, $item, $save, %att);
	
	my($cart,$page) = split m:/:, $path, 2;

	$cart = get_cart $cart;

    if (!product_code_exists($code)) {
		logError("Attempt to order missing product code: $code\n");
		display_special_page($Vend::Cfg->{'Special'}->{'noproduct'}, $code);
		return;
    }


    INC: {

		# Check that the item has not been already ordered.
		$found = -1;

		# Check to see if we should push an already-ordered item instead of 
		# ignoring it 
		my $separate =
				$Vend::Cfg->{SeparateItems} ||
					(
						defined $Vend::Session->{scratch}->{mv_separate_items}
					 && is_yes( $Vend::Session->{scratch}->{mv_separate_items} )
					 );
		last INC if $separate;

		foreach $i (0 .. $#$cart) {
			if ($cart->[$i]->{'code'} eq $code) {
				$found = $i;
			}
		}

	} # INC

    # And if not found or separate, start with a single quantity.
    if ($found == -1) {
		$item = {'code' => $code, 'quantity' => 1};
		if($Vend::Cfg->{UseModifier}) {
			foreach $i (@{$Vend::Cfg->{UseModifier}}) {
				$item->{$i} = '';
			}
		}
		push @$cart, $item;
    }

    order_page($page);		# display the order page
    put_session();
}


sub untaint {
	my $tainted = $_[0];
	$tainted =~ /(.*)/;
	$tainted = $1;
}	

## DO SEARCH

sub do_search {
	my($c) = \%CGI::values;

	if($Vend::Cfg->{SearchCache}) {
		my($key,$page) = check_search_cache($c);
		return response('html',$page) if defined $page;
		$c->{mv_cache_key} = $key if $key;
	}

	perform_search($c,@_);

}

sub do_scan {

	# This is quite tricky -- I would be happy for
	# suggestions on how to make it more regular 8-)
	my($argument,$path) = @_;
	my ($key,$page);

	if($Vend::Cfg->{SearchCache}) {
		($key,$page) = check_scan_cache($argument, $path);
		return response('html',$page) if defined $page;
	}

	my($c) = { mv_cache_key => $key || '' };

	find_search_params($c,$path);

	perform_search($c,$argument);
}

# Returns undef if interaction error
sub update_quantity {
	my($h, $i, $quantity, $modifier, $cart);

    return 1 unless defined  $CGI::values{"quantity0"};

	$cart = get_cart($CGI::values{mv_cartname});

	if(ref $Vend::Cfg->{UseModifier}) {
		foreach $h (@{$Vend::Cfg->{UseModifier}}) {
			foreach $i (0 .. $#$cart) {
				$modifier = $CGI::values{"$h$i"};
				if (defined($modifier)) {
					$modifier =~ s/\0+/\0/g;
					$modifier =~ s/\0$//;
					$modifier =~ s/^\0//;
					$modifier =~ s/\0/, /g;
					$cart->[$i]->{$h} = $modifier;
					$Vend::Session->{'values'}->{"$h$i"} = $modifier;
					#delete $Vend::Session->{'values'}->{"$h$i"};
				}
			}
		}
	}

	foreach $i (0 .. $#$cart) {
    	$quantity = $CGI::values{"quantity$i"};
    	if (defined($quantity) && $quantity =~ m/^\d+$/) {
        	$cart->[$i]->{'quantity'} = $quantity;
    	}
    	elsif (defined($quantity) && $quantity =~ m/^[\d.]+$/
				and $Vend::Cfg->{FractionalItems} ) {
        	$cart->[$i]->{'quantity'} = $quantity;
    	}
		# This allows a multiple input of item quantity to
		# pass -- FIRST ONE CONTROLS
		elsif (defined $quantity && $quantity =~ s/\0.*//) {
			$CGI::values{"quantity$i"} = $quantity;
			redo;
		}
		elsif (defined $quantity) {
			my $item = $cart->[$i]->{'code'};
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
    toss_cart($cart);

	1;

}

sub add_items {

	my($items,$quantities) = @_;
	my(@items);
	my($code,$found,$item,$quantity,$i,$j,$q);
	my(@quantities);

	@items = split /\0/, $items;

	my $cart = $CGI::values{mv_cartname};

	$cart = get_cart($cart);

	if($quantities ||= '') {
		@quantities = split /\0/, $quantities;
	}

	my $separate =
			$Vend::Cfg->{SeparateItems} ||
				(
					defined $Vend::Session->{scratch}->{mv_separate_items}
				 && is_yes( $Vend::Session->{scratch}->{mv_separate_items} )
				 );
	$j = 0;
	foreach $code (@items) {
		if (!product_code_exists($code)) {
			logError("Attempt to order missing product code: $code\n");
			display_special_page($Vend::Cfg->{'Special'}->{'noproduct'}, $code);
			return;
		}
		$quantity = $quantities[$j++] ||= 1;


		INCREMENT: {

			# Check that the item has not been already ordered.
			# But let us order separates if so configured
			$found = -1;
			last INCREMENT if $separate;

			foreach $i (0 .. $#$cart) {
				if ($cart->[$i]->{'code'} eq $code) {
					$found = $i;
					# Increment quantity. This is different than
					# the standard handling because we are ordering
					# accessories, and may want more than 1 of each
					$cart->[$i]->{'quantity'} += $quantity;
				}
			}
		} # INCREMENT

		# An if not, start of with a single quantity.
		if ($found == -1) {
			$item = {'code' => $code, 'quantity' => $quantity};
			if($Vend::Cfg->{UseModifier}) {
				foreach $i (@{$Vend::Cfg->{UseModifier}}) {
					$item->{$i} = '';
				}
			}
			my $next = $#$cart + 1;
			push @$cart, $item;
			$CGI::values{"quantity$next"} = $quantity;
		}
	}
}
	
## DO FINISH

# Finish an incomplete order.

sub do_finish {
	my($page) = shift || $Vend::Cfg->{'CheckoutPage'};
	$page =~ s/^finish_?_?//;
    order_page($page);
    put_session();
}

# Update the user-entered fields.
sub update_data {
	my($key,$value);
    # Update a database record

	unless (defined $CGI::values{'mv_data_table'} and 
		    defined $CGI::values{'mv_data_key'}      ) {
		logError("Attempted database operation without table or key.\n" .
				 "Table: '$CGI::values{'mv_data_table'}'\n" .
				 "Key:   '$CGI::values{'mv_data_key'}'  \n"     );
		
		return undef;
	}

	my $table = $CGI::values{'mv_data_table'};
	my $function = $CGI::values{'mv_data_function'};
	my @fields = split /\s*,\s*/, $CGI::values{'mv_data_fields'};
	my $prikey = $CGI::values{'mv_data_key'};

	$function = $function =~ /insert/i ? 'insert' : 'update';

	my (%data);
	for(@fields) {
		$data{$_} = [];
	}

    while (($key, $value) = each %CGI::values) {
        next unless defined $data{$key};
		@{$data{$key}} = split /\0/, $value;
	}

	unless ($data{$prikey}) {
		logError("No key '$prikey' found in database $function operation.\n" .
				 "Table: '$CGI::values{'mv_data_table'}'\n" .
				 "Key:   '$CGI::values{'mv_data_key'}'  \n"   );
		return undef;
	}

	my ($query,$i);
	my (@k);
	my (@v);
	my (@c);

	for($i = 0; $i < @{$data{$prikey}}; $i++) {
		@k = (); @v = ();
		for(keys %data) {
			next unless (($value = $data{$_}->[$i]) || $CGI::values{mv_update_empty});
			push(@k, $_);
			$value =~ s/'/\\'/g;
			push(@v, $value);
		}
		if($function eq 'insert') {
			$query = "insert into $table (";
			$query .= join ",", @k;
			$query .= ") VALUES ('";
			$query .= join "','", @v;
			$query .= "')";
		}
		else {
			$query = "UPDATE $table SET ";
			my $what;
			@c = ();
			while (@k) {
				( ($key = shift @k), ($value = shift @v), next )
					if $k[0] eq $prikey;
				$what = (shift @k) . "='" . (shift @v) . "'";
				push @c, $what;
			}
			$query .= join ", ", @c;
			$query .= " WHERE $key = '$value'";
		}
		logGlobal("query: $query\n");
		msql_query('set', $query);
	}


}

sub parse_click {
	my ($ref, $click, $extra) = @_;
    my($codere) = '[\w-_#/.]+';
	my $params = $Vend::Session->{'scratch'}->{$click} || return 1;

	my($var,$val,$parameter);
	$params = interpolate_html($params);
	my(@param) = split /\n+/, $params;

	for(@param) {
		next unless /\S/;
		next if /^\s*#/;
		s/^[\r\s]+//;
		s/[\r\s]+$//;
		$parameter = $_;
		($var,$val) = split /[\s=]+/, $parameter, 2;
		$val =~ s/&#(\d+);/chr($1)/ge;
		$ref->{$var} = $val;
		$extra->{$var} = $val
			if defined $extra;
	}
}

# This is the set of CGI-passed variables to ignore, in other words
# never set in the user session.  If set in the mv_check pass, though,
# they will stick.
my %Ignore = qw(
	mv_todo  1
	mv_todo.submit.x  1
	mv_todo.submit.y  1
	mv_todo.return.x  1
	mv_todo.return.y  1
	mv_todo.checkout.x  1
	mv_todo.checkout.y  1
	mv_todo.todo.x  1
	mv_todo.todo.y  1
	mv_todo.map  1
	mv_doit  1
	mv_check  1
	mv_click  1
	mv_nextpage  1
	);

# Update the user-entered fields.
sub update_user {
	my($key,$value);
    # Update the user-entered fields.

	if (defined $CGI::values{'mv_order_item'} and 
		$value = $CGI::values{'mv_order_item'} ) {
		my $quantities = $CGI::values{mv_order_quantity} ||= '';
		add_items($value,$quantities);
		delete $CGI::values{mv_order_quantity};
		delete $CGI::values{mv_order_item};
	}

	#

	if( $Vend::Cfg->{CreditCardAuto} and $CGI::values{mv_credit_card_number} ) {
		#logGlobal join "\n",
			#encrypt_standard_cc(\%CGI::values);
		(
			$Vend::Session->{'values'}->{mv_credit_card_valid},
			$Vend::Session->{'values'}->{mv_credit_card_info},
			$Vend::Session->{'values'}->{mv_credit_card_exp_month},
			$Vend::Session->{'values'}->{mv_credit_card_exp_year},
			$Vend::Session->{'values'}->{mv_credit_card_exp_all},
			$Vend::Session->{'values'}->{mv_credit_card_type},
			$Vend::Session->{'values'}->{mv_credit_card_error}
		)
			= encrypt_standard_cc(\%CGI::values);
	}	


    while (($key, $value) = each %CGI::values) {
        next if defined $Ignore{$key};
        next if ($key =~ m/^quantity\d+/);
		# We add any checkbox ordered items, but don't update -- 
		# we don't want to order them twice
        $Vend::Session->{'values'}->{$key} = $value;

		next unless $key =~ /^credit_card/;

		if(	defined $Vend::Cfg->{'Password'} &&
			$Vend::Cfg->{'CreditCards'}			)
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
			undef $CGI::values{$key};
		}
    }

	if(defined $CGI::values{'mv_check'}) {
		delete $Vend::Session->{'values'}->{mv_nextpage};
		my(@checks) = split /\s*[,\0]+\s*/, $CGI::values{'mv_check'};
		my($check);
		foreach $check (@checks) {
				parse_click $Vend::Session->{'values'}, $check, \%CGI::values;	
		}
	}

}

## DO PROCESS

# Find an action from the submitted value
sub minivend_action {
	my ($todo) = (@_);

	return undef unless defined $todo;
	$todo = lc $todo;
	
	if(defined $Vend::Cfg->{'ActionMap'}->{$todo}) {
		return  $Vend::Cfg->{'ActionMap'}->{$todo};
	}
	for (keys %{$Vend::Cfg->{'ActionMap'}}) {
		return $Vend::Cfg->{'ActionMap'}->{$_} if $todo =~ /$_/i;
	}
	return $todo;
}


# Process the completed order or search page.

sub do_process {
    my($i, $doit, $quantity, $todo, $page, $key, $value);
	my($status, $nextpage, $orderpage, $ordered_items);

    expect_form() || return;

	if(defined $CGI::values{'mv_click'}) {
		my(@clicks) = split /\s*[,\0]+\s*/, $CGI::values{'mv_click'};
		my($click);
		foreach $click (@clicks) {
			parse_click \%CGI::values, $click;	
		}
	}

    $doit = $CGI::values{'mv_doit'};
    $todo = $CGI::values{'mv_todo'};

    $nextpage = $CGI::values{'mv_nextpage'} || $Vend::Session->{'page'};
    $orderpage = $CGI::values{'mv_orderpage'} || $Vend::Cfg->{'Special'}->{'order'};
    $ordered_items = $CGI::values{'mv_order_item'};

	# Maybe we have an imagemap input, if not, use $doit
    if (!defined $todo) {
		if (defined $CGI::values{'mv_todo.x'}) {
				my $x = $CGI::values{'mv_todo.x'};
				my $y = $CGI::values{'mv_todo.y'};
				my $map = $CGI::values{'mv_todo.map'};
				$todo = action_map($x,$y,$map);
		}
		elsif (defined $CGI::values{'mv_todo.submit.x'}) {
			$todo = 'submit';
		}
		elsif (defined $CGI::values{'mv_todo.checkout.x'}) {
			$todo = 'checkout';
		}
		elsif (defined $CGI::values{'mv_todo.return.x'}) {
			$todo = 'return';
		}
		else {
			$todo = $doit if defined $doit;
		}
	}

	$todo = minivend_action($todo);

	#Check again, see if we have a todo
    if (!defined $todo) {
			interaction_error("No action passed from form\n");
			return;
    }

	if ($todo eq 'secure') {
		if ($CGI::secure) {
			$Vend::Session->{'secure'} = 1;
			update_user();
			do_page($Vend::Session->{'values'}->{mv_nextpage} || $nextpage);
			return;
		}
		else {
			do_page($Vend::Cfg->{'Special'}->{'violation'});
			return;
		}
    }
	elsif ($todo eq 'unsecure') {
		$Vend::Session->{'secure'} = 0;
		do_page($nextpage);
		return;
	}
	elsif ($todo eq 'checkout') {
		update_user();
		unless(update_quantity()) {
			interaction_error("quantities");
			return;
		}
		my $next = $CGI::values{'mv_checkout'} || $orderpage;
		order_page($next);
	}
	elsif ($todo eq 'control') {
		update_user();
		do_page($Vend::Session->{'values'}->{mv_nextpage} || $nextpage);
		return;
	}
	elsif ($todo eq 'submit') {
		update_user();
		update_quantity() || return; #Return on error
		my($ok);
		my($missing,$next,$status,$final);
		my($values) = $Vend::Session->{'values'};

		# Set shopping cart
		
		$Vend::Items = get_cart $CGI::values{mv_cartname};

	  CHECK_ORDER: {

		if (defined $CGI::values{'mv_order_profile'}) {
			($status,$final,$missing) =
				check_order($CGI::values{'mv_order_profile'});
			update_user();
		}
		else {
			$status = $final = 1;
		}

		if($status) {
			$next = $Vend::Session->{'values'}->{'mv_successpage'} || $orderpage;
			display_page($next) unless $final;
		}
		else {
			$next = $CGI::values{'mv_failpage'} || $Vend::Cfg->{'Special'}->{'needfield'};
			display_special_page($next, $missing);
			last CHECK_ORDER;
		}

		last CHECK_ORDER unless $final;

		($status, $missing) = check_required($values);
		if (!$status) {
			display_special_page($Vend::Cfg->{'Special'}->{'needfield'}, $missing);
			put_session();
			return;
		}

		# This function (followed down) now does the backend ordering
		$ok = mail_order();

		# Display a receipt if configured

		if ($ok && $Vend::Session->{'values'}->{'mv_order_receipt'}) {
	    	display_special_page($Vend::Session->{'values'}->{'mv_order_receipt'});
		}
		elsif ($ok && $Vend::Cfg->{'ReceiptPage'}) {
	    	display_special_page($Vend::Cfg->{'ReceiptPage'});
		}
		elsif ($ok) {
	    	display_special_page($Vend::Cfg->{'Special'}->{'confirmation'});
		} else {
	    	display_special_page($Vend::Cfg->{'Special'}->{'failed'});
		}

		# Remove the items
		@$Vend::Items = ();
	  }

    }
	elsif ($todo eq 'set') {
		update_data();
		display_page($Vend::Session->{'values'}->{mv_nextpage} || $nextpage);
    }
	elsif ($todo eq 'return') {
		update_user();
		update_quantity() || return; #Return on error
		display_page($Vend::Session->{'values'}->{mv_nextpage} || $nextpage);
    }
	elsif ($todo eq 'refresh') {
		update_user();
		update_quantity() || return; #Return on error
		order_page($orderpage);
    }
	elsif ($todo eq 'search') {
		update_user();
		do_search();
    }
	elsif ($todo eq 'cancel') {
		$Vend::Session->{'values'}->{'credit_card_no'} = 'xxxxxxxxxxxxxxxxxxxxxx';
		$Vend::Session->{'values'}->{'credit_card_exp'} = 'xxxxxxxx';
		$Vend::Session->{'login'} = '';
		my $frames = $Vend::Session->{'frames'};
		put_session();
		get_session();
		init_session();
		$Vend::Session->{'frames'} = $frames;
		display_page($Vend::Cfg->{'Special'}->{'canceled'});
    }
	else {
		interaction_error(
          "Form variable 'mv_todo or mv_doit' value '$todo' not recognized\n");
		return;
    }
    put_session();
}

# does message for page build
sub do_msg {
    my ($msg, $size) = @_;
    $size = 60 unless defined $size;
    my $len = length $msg;

    return "$msg.." if ($len + 2) >= $size;
    $msg .= '.' x ($size - $len);
    return $msg;
}


sub config_named_catalog {
	my ($script_name, $source) = @_;
	my ($g,$c,$conf);

	for (keys %Global::Catalog) {
         next unless $Global::Catalog{$_}->{'script'} eq $script_name;
         $g = $Global::Catalog{$_};
    }
    logGlobal "Re-configuring catalog " . $g->{'name'} .
            ' from ' . $source;
    chdir $g->{'dir'}
            or die "Couldn't change to $g->{'dir'}: $!\n";
    $conf = $g->{'dir'} . '/etc';
    eval {
        $c = config($g->{'name'}, $g->{'dir'}, $conf);
    };
    if($@) {
        logGlobal "\n$@\n\a$g->{'name'}: error in configuration file. Aborting re-configuration.\n";
        logError "\n$@\n\a$g->{'name'}: error in configuration file. Aborting re-configuration.\n";
     	undef $c;
    }
	else {
		$Vend::Cfg = $c;	
		read_accessories();
		read_salestax();
		read_shipping();
		read_pricing();
		unless($Global::GDBM or $Global::DB_File) {
			import_products();
			open_databases();
			close_products();
			close_database();
		}
		undef $Vend::Cfg;
	}

	return $c;
}

sub build_page {
    my($name,$dir) = @_;
    my($base,$page);


    $page = readin($name);
	# Try for on-the-fly if not there
	if(! defined $page) {
		$page = fly_page($name);
		$name = $Vend::Cfg->{ItemLinkDir} . $name
			if $Vend::Cfg->{ItemLinkDir};
	}

    if (defined $page) {
		open(BUILD_PAGE, ">$dir/$name.html")
			or die "Couldn't create file $dir/$name.html: $!\n";
		if($Vend::Cfg->{StaticPath}) {
			$name = $Vend::Cfg->{StaticPath};
		}
    	print BUILD_PAGE interpolate_html(fake_html($page,$name));
		close BUILD_PAGE;
    }

}


# Build a static page tree from the database
# The session is faked, but all other operations
# should work the same.
sub build_all {
	my($catalog,$outdir) = @_;
	my($g, $sub, $p, $spec, $key, $val);
	my(@files);
	for(keys %Global::Catalog) {
		next unless $Global::Catalog{$_}->{'name'} eq $catalog;
		$g = $Global::Catalog{$_}->{'script'};
	}

	$spec = $Vend::BuildSpec || '';
	CHECKSPEC: {
		my $test = 'NevVAIRBbe';
		eval { $test =~ s:^/tmp/whatever/$spec::; };
		die "Bad -files spec '$spec'\n" if $@;
	}
	die "$catalog: no such catalog!\n"
		unless defined $g;
	$Vend::Cfg = $Global::Selector{$g};
	chdir $Vend::Cfg->{'VendRoot'} 
		or die "Couldn't change to $Vend::Cfg{'VendRoot'}: $!\n";

	$Vend::Cfg->{'ReadPermission'} = 'world';
	$Vend::Cfg->{'WritePermission'} = 'user';
	set_file_permissions();
	umask $Vend::Cfg->{'Umask'};

	# do some basic checks to make sure we don't clobber
    # anything with a value of '/', and have an
	# absolute file path
	$outdir = 'static' unless defined $outdir;
	$outdir =~ s:/+$::;
	die "No output directory specified.\n" unless $outdir;
	$outdir = "$Vend::Cfg->{VendRoot}/$outdir"
		unless $outdir =~ m:^/:;
	unless(-d $outdir) {
		! -f $outdir
			or die "Output directory '$outdir' is a file. Abort.\n";
		print do_msg("Making output directory $outdir");
		mkdir ($outdir, 0755)
			or die "Couldn't make output directory $outdir: $!\n";
		print "done.\n"
	}

	if(	$Vend::Cfg->{ItemLinkDir} and
		! -d "$outdir/$Vend::Cfg->{ItemLinkDir}" ) {
		print do_msg("Making items directory $outdir/$Vend::Cfg->{ItemLinkDir}");
		mkdir ("$outdir/$Vend::Cfg->{ItemLinkDir}", 0755)
			or (system "mkdir -p $outdir/$Vend::Cfg->{ItemLinkDir}"
				and die <<EOF);
Couldn't make item link directory $outdir: $!

This is probably because its parent doesn't exist. Make it manually,
then try again.

EOF
		print "done.\n"
	}

	open_databases();
	import_products();
	$Vend::SessionID = '';
	$Vend::SessionName = '';
	init_session();
	$Vend::Session->{'frames'} = 1;
	my $basedir = $Vend::Cfg->{'PageDir'};
	require File::Find or die "No standard Perl library File::Find!\n";
	$sub = sub {
					my $name = $File::Find::name;
					die "Bad file name $name\n"
						unless $name =~ s:^$basedir/?::;

					if ($spec) {
						return unless $name =~ m!^$spec!o;
					}
						
					if (-d $File::Find::name) {
						die "$outdir/$name is a file, not a dir.\n"
							if -f "$outdir/$name";
						return if -d "$outdir/$name";
						mkdir ("$outdir/$name", 0755)
							or die "Couldn't make dir $outdir/$name: $!\n";
						return;
					}
					return unless $name =~ s/\.html?$//;
					push @files, $name;
			};
	print do_msg("Finding files...");
	File::Find::find($sub, $Vend::Cfg->{PageDir});
	print "done.\n";
	
	chdir $Vend::Cfg->{'VendRoot'} 
		or die "Couldn't change to $Vend::Cfg{'VendRoot'}: $!\n";

	$p = products_ref();
	$Vend::Session->{'pageCount'} = -1;
	my $save = $;
	$ = 0;
	for(@files) {
		print do_msg("Building page from file $_ ...");
		build_page($_,$outdir);
		$Vend::Session->{'pageCount'} = -1;
		print "done.\n";
	}
	return if $spec;
	while( ($key,$val) = $p->each_record() ) {
		print do_msg("Building part number $key ...");
		build_page($key,$outdir);
		$Vend::Session->{'pageCount'} = -1;
		print "done.\n";
	}
	$ = 0;
}


sub map_cgi {

    my($host, $user);

    $CGI::request_method = ::http()->Method;
    die "REQUEST_METHOD is not defined" unless defined $CGI::request_method;

    $CGI::path_info = ::http()->Path_Info;

	# Uncomment if secure and non-secure servers both do DNS
    #$host = http()->Client_Hostname;
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
    $CGI::cookie = http()->Cookie;

    #$CGI::content_length = http()->Content_Length;
    $CGI::content_type = http()->Content_Type;
    $CGI::reconfigure_catalog = http()->Reconfigure;
    $CGI::query_string = http()->Query;
    $CGI::script_name = http()->Script;

	$CGI::post_input = http()->read_entity_body(http());
	parse_post();
}

## DISPATCH

# Parse the invoking URL and dispatch to the handling subroutine.

sub dispatch {
	my($http, $socket, $debug) = @_;
	$H = $http;

	map_cgi($H);

    my($sessionid, $argument, $path);
	my(@path);
	my($g, $action);

	unless (defined $Global::Standalone) {
		unless (defined $Global::Selector{$CGI::script_name}) {
			logGlobal("Call for undefined catalog from $CGI::script_name");
			return '';
		}
		$Vend::Cfg = $Global::Selector{$CGI::script_name}
	}
	else {
		$Vend::Cfg = $Global::Standalone;
	}

	if (defined $CGI::reconfigure_catalog) {

		# First some security checks
		# Check if host IP is correct when MasterHost is set to something
		if ($Vend::Cfg->{MasterHost} and
			$CGI::host ne $Vend::Cfg->{MasterHost})
		{
			logGlobal <<EOF;
ALERT: Attempt to reconfigure catalog at $CGI::script_name from:

	REMOTE_ADDR  $CGI::host
	REMOTE_USER  $CGI::user
	USER_AGENT   $CGI::useragent
	SCRIPT_NAME  $CGI::script_name
	PATH_INFO    $CGI::path_info
EOF
			return '';
		}

		# Check to see if password enabled, then check
		if ($Vend::Cfg->{Password} and
			crypt($CGI::reconfigure_catalog, $Vend::Cfg->{Password})
			ne  $Vend::Cfg->{Password})
		{
			logGlobal <<EOF;
ALERT: Password mismatch on reconfigure of $CGI::script_name from $CGI::host
EOF
			return '';
		}

		# Finally ceck to see if remote_user match enabled, then check
		if ($Vend::Cfg->{RemoteUser} and
			$CGI::user ne $Vend::Cfg->{RemoteUser})
		{
			logGlobal <<EOF;
ALERT: Attempt to reconfigure catalog at $CGI::script_name from:

	REMOTE_ADDR  $CGI::host
	REMOTE_USER  $CGI::user
	USER_AGENT   $CGI::useragent
	SCRIPT_NAME  $CGI::script_name
	PATH_INFO    $CGI::path_info
EOF
			return '';
		}

		# Don't allow random reconfigures without one of the three checks
		unless ($Vend::Cfg->{MasterHost} or $Vend::Cfg->{Password}
				or $Vend::Cfg->{RemoteUser}) {
			logGlobal <<EOF;
Attempt to reconfigure catalog on $CGI::script_name, reconfiguration disabled.
EOF
			return '';

		}

		logData("$Global::ConfDir/reconfig", $CGI::script_name);
		logGlobal <<EOF;
Reconfiguring catalog on $CGI::script_name, INET mode:

	REMOTE_ADDR  $CGI::host
	REMOTE_USER  $CGI::user
	USER_AGENT   $CGI::useragent
	SCRIPT_NAME  $CGI::script_name
	PATH_INFO    $CGI::path_info

EOF
			
	}

	chdir $Vend::Cfg->{'VendRoot'} 
		or die "Couldn't change to $Vend::Cfg{'VendRoot'}: $!\n";
	set_file_permissions();
	umask $Vend::Cfg->{'Umask'};
	open_databases();
	import_products();
	
    if (defined $CGI::query_string && $CGI::query_string ne '') {
		($sessionid, $argument) = split(/;/, $CGI::query_string);
		if ($CGI::cookie =~ /\bMV_SESSION_ID=\w{8}
								: ( 
								\d{1,3}\.
								\d{1,3}\.
								\d{1,3}\.
								\d{1,3})		\b/x) {
			$CGI::cookiehost = $1;
		}
    }

	# Get a cookie if we have no session id (and its there)
    unless (defined $sessionid && $sessionid ne '') {
		if ($CGI::cookie =~ /\bMV_SESSION_ID=(\w{8})
							:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})?\b/x) {
			$sessionid = $1;
			$CGI::cookiehost = $2;
		}
	}

    if (defined $sessionid && $sessionid ne '') {
		$Vend::SessionID = $sessionid;
    	$Vend::SessionName = session_name();
		get_session();
		if (time - $Vend::Session->{'time'} > $Vend::Cfg->{'SessionExpire'}) {
	    	init_session();
		}
    }
	else {
		new_session();
    }

    $path = $CGI::path_info;

    # If the cgi-bin program was invoked with no extra path info,
    # just display the catalog page.
    if (!defined $path || $path eq '' || $path eq '/') {
		do_catalog();
		release_session() if $Vend::HaveSession;
		close_database();
		close_products();
		undef $H;
		undef $Vend::Cfg;
		return 0;
    }

	$path =~ s:^/::;
    @path = split('/', $path, 2);
    $action = shift @path;

    if    ($action eq 'order')    { do_order($argument,@path); }
    elsif ($action eq 'search')   { do_search($argument);      } 
    elsif ($action eq 'scan')     { do_scan($argument,@path);  } 
    elsif ($action eq 'process')  { do_process();              }
    else {
		# will try the on-the-fly page if it fails
		do_page($path);
    }
	release_session() if $Vend::HaveSession;
	close_database();
	close_products();
	undef $H;
	undef $Vend::Cfg;
	return 1;
}

## DEBUG

sub dontwarn {
	#my $junk = *Config;
	$Global::DebugMode +
	$Global::MailErrorTo +
	$File::Find::name +
	#$Config::ExtraSecure +
	#$Config::ReadPermission +
	#$Config::WritePermission +

	1;
}


sub dump_env {
    my($var, $value);

    open(Vend::E, ">$Vend::Cfg->{'VendRoot'}/env");
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

## COMMAND LINE OPTIONS

sub parse_options {
	while ($_ = shift @ARGV) {
		if (m/^-c(onfig)?$/i) {
			$Global::ConfigFile = shift @ARGV;
			die "Missing file argument for -config option\n"
				if blank($Global::ConfigFile);
		} elsif (m/^-s(erve)?$/i) {
			$Vend::mode = 'serve';
		} elsif (m/^-b(uild)?$/i) {
			$Vend::mode = 'build';
			$Vend::CatalogToBuild = shift @ARGV;
		} elsif (m/^-f(iles)?$/i) {
			$Vend::BuildSpec = shift @ARGV;
			die "Missing file spec for -files option\n"
				if blank($Vend::BuildSpec);
		} elsif (m/^-o(utdir)?$/i) {
			$Vend::OutputDirectory = shift @ARGV;
			die "Missing file argument for -outdir option\n"
				if blank($Vend::OutputDirectory);
		} elsif (m/^-i(netmode)?$/i) {
			$Global::Inet_Mode = 1;
		} elsif (m/^-v(ersion)?$/i) {
			version();
			exit 0;
		} elsif (m/^-h(elp)?$/i) {
			usage();
			exit 0;
		} elsif (m/^-n(otify)$/i) {
			$Vend::mode = 'notify';
		} elsif (m/^-t(est)$/i) {
			$Vend::mode = 'test';
		} else {
		    $? = 2;
			die "Unknown command line option: $_\n" .
				"(Use -help for a list).\n";
		}
	}
}

sub version {
	print "MiniVend version 2.03b Copyright 1995 Andrew M. Wilcox\n";
	print "                       Copyright 1996, 1997 Michael J. Heins\n";
}

sub usage {
	version();
	print <<'END';

MiniVend comes with ABSOLUTELY NO WARRANTY.  This is free software, and
you are welcome to redistribute and modify it under the terms of the
GNU General Public License.

Command line options:

     -build <catalog> build static page tree for <catalog>
     -config <file>   specify configuration file
     -files <spec>    filespec (perl regexp OK) for static page tree
     -inetmode        run with Internet-domain socket (TCP)
     -outdir <dir>    specify output directory for static page tree
     -serve           start server
     -test            report problems with config files
     -version         display program version
END
}

sub scrub_sockets {

	my (@sockets);
	my $dir = $Global::ConfDir;

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

	$r = $Vend::Cfg->{'ReadPermission'};
	if    ($r eq 'user')  { $p = 0400;   $u = 0277; }
	elsif ($r eq 'group') { $p = 0440;   $u = 0227; }
	elsif ($r eq 'world') { $p = 0444;   $u = 0222; }
	else                  { die "Invalid value for ReadPermission\n"; }

	$w = $Vend::Cfg->{'WritePermission'};
	if    ($w eq 'user')  { $p += 0200;  $u &= 0577; }
	elsif ($w eq 'group') { $p += 0220;  $u &= 0557; }
	elsif ($w eq 'world') { $p += 0222;  $u &= 0555; }
	else                  { die "Invalid value for WritePermission\n"; }

	$Vend::Cfg->{'FileCreationMask'} = $p;
	$Vend::Cfg->{'Umask'} = $u;
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
	my $status = 0;

	undef $Vend::mode;      # mode will be set by options
	parse_options();
	if (!defined $Vend::mode) {
			usage();
			exit 0;
	}

	umask 077;
	global_config();
	CATCONFIG: {
		my $i = 0;
		my ($g, $selector, $conf);
		for (sort keys %Global::Catalog) {
			$g =  $Global::Catalog{$_};
			print "Configuring catalog " . $g->{'name'} . '...';
			chdir $g->{'dir'}
				or die "Couldn't change to $g->{'dir'}: $!\n";
			$selector = 'Catalog' . $i++;
			die "Two catalogs with same script name $g->{'script'}.\n"
				if exists $Global::Selector{$g->{'script'}};
			$conf = $g->{'dir'} . '/etc';
			eval {
				$Vend::Cfg = $Global::Selector{$g->{'script'}} = 
					config($g->{'name'}, $g->{'dir'}, $conf);
				};
			if($@) {
				print "\n$@\n\a$g->{'name'}: error in configuration file. Skipping.\n";
				undef $Global::Selector{$g->{'script'}};
			}
			else {
				read_accessories();
				read_salestax();
				read_shipping();
				read_pricing();
				unless($Global::GDBM or $Global::DB_File) {
					import_products();
					open_databases();
					close_products();
					close_database();
				}
				undef $Vend::Cfg;
				print "done.\n";
			}
		}
	}

	if ($Vend::mode eq 'serve') {
		# This should never return unless killed or an error
		# We set debug mode to -1 to communicate with the server
		# that no output is desired
		$0 = 'minivend';
		scrub_sockets() unless $Global::MultiServer;

        select STDERR; 
        $| = 1;
        select STDOUT;
        $| = 1;

        Vend::Server::run_server($Global::MultiServer, $Global::DebugMode);
	}
	elsif ($Vend::mode eq 'notify') {
		send_mail($Global::MailErrorTo, "MiniVend server not responding", <<EOF );
The MiniVend server serving the catalog named '$Vend::Cfg->{CatalogName}' did
not respond when called by the VLINK executable.

EOF
	}
	elsif ($Vend::mode eq 'build') {
		build_all($Vend::CatalogToBuild,
		          $Vend::OutputDirectory,
				  $Vend::BuildSpec);
	}
	elsif ($Vend::mode eq 'test') {
		# Blank by design, this option only tests config files
	}
	else {
		die "No mode!\n";
	}
	
}

eval { main(); };
if ($@) {
	my($msg) = ($@);
	logGlobal( $msg );
	if (!defined $Global::DisplayError || $Global::DisplayError) {
		print "$msg\n";
	}
}

