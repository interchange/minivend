#!/usr/bin/perl
#
# MiniVend version 1.03
#
# $Id: minivend.pl,v 1.3.1.3 1996/05/18 19:58:53 mike Exp $
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
$Config::VendRoot = '/usr/local/lib/minivend';
$Config::ConfDir = '/usr/local/lib/minivend/etc';
}
$Config::ConfigFile = 'minivend.cfg';
$Config::ErrorFile = 'error.log';


# This must be 1 on Solaris and Irix 5 - they don't have
# the proper locking tools (the configure script should do this)
$Config::BadLocking = 0;

# BSD, among others, defines sendmail to be in /usr/sbin, and
# we want to make sure the program is there. Insert the location
# of you sendmail binary (the configure script should do this)
$Config::SendMailLocation = '/usr/lib/sendmail';

# Use the next line if we have the HTML::Parse module and want
# to check forms (the configure script should do this)
use HTML::Parse;

# Use the next line if you have the Des module and the
# proper library support (the configure script should do this)
#use Des;

# For the order counter, no huge deal if not there.  Included
# with the distribution, but will go bye-bye if you only have
# Perl 5.001
use File::CounterFile;

### END CONFIGURABLE VARIABLES

use strict;
use Fcntl;

use lib $Config::VendRoot;

#select a DBM

BEGIN {
	$Config::GDBM = $Config::DB_File = $Config::NDBM = 0;
	eval {require GDBM_File and $Config::GDBM = 1} ||
	eval {require DB_File and $Config::DB_File = 1} ||
	eval {require NDBM_File and $Config::NDBM = 1};
	if(defined $GDBM_File::VERSION or $Config::GDBM) {
		require Vend::Table::GDBM;
		import GDBM_File;
		$Config::GDBM = 1;
	}
	elsif(defined $DB_File::VERSION or $Config::DB_File) {
		require Vend::Table::DB_File;
		import DB_File;
		$Config::DB_File = 1;
	}
	elsif(defined $NDBM_File::VERSION or $Config::NDBM) {
		require Vend::Table::InMemory;
		import NDBM_File;
		$Config::NDBM = 1;
	}
	else {
		die "No DBM defined! MiniVend can't run.\n";
	}
}


use Vend::Server;
use Vend::Session;
use Vend::Config;
use Vend::Imagemap;
use Vend::Glimpse;
use Vend::Scan;
use Vend::TextSearch;
use Vend::UserSearch;
use Vend::Data;
use Vend::Util;
use Vend::Interpolate;

my $H;
sub http {
	$H;
}

$Config::ConfigFile = "$Config::VendRoot/$Config::ConfigFile"
    if ($Config::ConfigFile !~ m.^/.);
$Config::ErrorFile = "$Config::VendRoot/$Config::ErrorFile"
    if ($Config::ErrorFile !~ m.^/.);

# Set the special page array
%Config::Special = (
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
# Set the action map
%Config::ActionMap = (
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

# Encrypts a credit card number with DES or the like
# Prefers internal Des module, if was included
sub encrypt_cc {
	my($enclair) = @_;
	my($password) = $Config::Password || return undef;
	my($encrypted, $status, $cmd);
	my $firstline = 0;

	$cmd = $Config::EncryptProgram;

	# This is the internal function, will return the value
	# if it was found. Takes the IVEC from the first
	# 8 characters of the encrypted password
	if (defined @Des::EXPORT) {
		my $key = string_to_key($Config::Password);
		my $sched = set_key($key);
		$encrypted = pcbc_encrypt($enclair,undef,$sched,$Config::Pw_Ivec);
		open(CAT, ">test.out");
		print CAT $encrypted;
		close CAT;
		return $encrypted;
	}

	#Substitute the password
	unless ($cmd =~ s/%p/$Config::Password/) {
		$firstline = 1;
	}

	my $tempfile = $Vend::SessionID . '.cry';

	#Substitute the filename, else concatenate
	unless ($cmd =~ s/%f/$tempfile/) {
		$cmd .= " $tempfile";
	}

	# Send the CC to a tempfile
	open(CARD, ">$tempfile") ||
		die "Couldn't write $tempfile: $!\n";

	# Put the cardnumber there, and maybe password first
	print CARD "$Config::Password\n" if $firstline;
	print CARD $enclair;
	#close CARD;

	# Encrypt the string, but key on arg line will be exposed
	# to ps(1) for systems that allow it
	open(CRYPT, "$cmd |") || die "Couldn't fork: $!\n";
	chomp($encrypted = <CRYPT>);
	close CRYPT;
	$status = $?;

	if($status) {
		logError("Encryption didn't work, status $status: $!\n"
					. "Command: $cmd\n");
		return undef;
	}

	$encrypted;
}

## PAGE GENERATION

sub plain_header {
    print "Content-type: text/plain\n\n";
    $Vend::content_type = 'plain';
}

sub response {
	my ($type,$output,$debug) = @_;
	$Vend::content_type = $type;
	if(defined $Vend::ServerMode) {
		http()->respond("text/$type",$output,$debug);
	}
	else {
		if ($Config::Cookies) {
			print "Set-Cookie: MV_SESSION_ID=$Vend::SessionID; path=/\r\n";
		}
		print "Content-type: text/$type\r\n\r\n";
		print $output;
	}
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

    $page = readin($Config::Special{'interact'});
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

# Places the order report in the Tracking file
sub track_order {
	my $order_report = shift;
	my ($c,$i);
	my $order_no;
	my (@backend);
	
	if($Config::Tracking) {
		open_tracking();
		$order_no = $Vend::Tracking{'mv_next_order'};

		# See if we have an order number already
		unless (defined $order_no) {
			$order_no = $Config::Tracking;
			$order_no =~ s/[^A-Za-z0-9]//g &&
				logError("Removed non-letter/non-digit chars from Order number");
		}

		# Put the text of the order in tracking
		$Vend::Tracking{$order_no} = $order_report;
	}
	elsif ($Config::AsciiTrack) {
		if($Config::OrderCounter) {
			$File::CounterFile::DEFAULT_DIR = $Config::VendRoot
				unless $Config::OrderCounter =~ m!^/!;
			my $c = new File::CounterFile $Config::OrderCounter, "000000";
			$order_no = $c->inc;
			undef $c;
			$Vend::Session->{'values'}->{'mv_order_number'} = $order_no;
			logData ($Config::AsciiTrack, "ORDER $order_no\n$order_report");
		}
		else {
			$order_no = $Vend::SessionID . '.' . time;
		}
	}
	else {
		return;		# Nothing to do!
	}

	@backend = split /\s*,\s*/, $Config::BackendOrder;
	
	# Put in the backend order values if enabled
	if(@backend and $Config::Tracking) {
		my(@ary);
		for(@backend) {
			push @ary, $Vend::Session->{'values'}->{$_};
		}
		my $order_info = join "\0", @ary;
		foreach $i (0 .. $#$Vend::Items) {
			$order_info .=  "\0" . $Vend::Items->[$i]->{'code'} .
							"\0" . $Vend::Items->[$i]->{'quantity'};
		}
		$Vend::Tracking{"Backend$order_no"} = $order_info;
		if($Config::CreditCards) {
			$Vend::Tracking{"Cc$order_no"} = 
				$Vend::Session->{'values'}->{'credit_card_no'};
			$Vend::Tracking{"Exp$order_no"} = 
				$Vend::Session->{'values'}->{'credit_card_exp'};
		}
	}
	elsif(@backend and $Config::AsciiBackend) {
		my(@ary);
		push @ary, $order_no;
		for(@backend) {
			push @ary, $Vend::Session->{'values'}->{$_};
		}
		foreach $i (0 .. $#$Vend::Items) {
			push @ary, $Vend::Items->[$i]->{'code'};
			push @ary, $Vend::Items->[$i]->{'quantity'};
		}
		logData ($Config::AsciiBackend, tabbed(@ary));
	}

	my $this_order = $order_no;

	if($Config::Tracking) {
		$order_no++;
		$Vend::Tracking{'mv_next_order'} = $order_no;
		close_tracking();
	}

	$this_order;
}

# Logs page hits in tracking file
sub track_page {
    return unless $Config::Tracking;
	open_tracking();
	my $page = shift;
	$Vend::Tracking{$page} = $Vend::Tracking{$page} + 1;
	close_tracking();
}


## ACTIONS SPECIFIED BY THE INVOKING URL

## DO CATALOG

# Display the initial catalog page.

sub do_catalog {
    do_page($Config::Special{'catalog'});
}


## DO PAGE

sub display_special_page {
    my($name, $subject) = @_;
    my($page);

    $page = readin($name);
    die "Missing special page: $name\n" unless defined $page;
    $page =~ s#\[subject\]#$subject#ig;
    response('html',interpolate_html($page));
}

# Displays the catalog page NAME.  If the file is not found, displays
# the special page 'missing'.
# 

sub display_page {
    my($name) = @_;
    my($page);

	if($Config::ExtraSecure and
		$name =~ /^(order\b|fr_order\b|account\b)/
		and !$CGI::secure) {
		$name = $Config::Special{'violation'};
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
		$page = readin($Config::Special{'missing'});
		die "Special page not found: $Config::Special{'missing'}\n"
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
    my($code,$page) = @_;
    my($i, $found);

    if (!product_code_exists($code)) {
		logError("Attempt to order missing product code: $code\n");
		display_special_page($Config::Special{'noproduct'}, $code);
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
	return perform_search($c,@_)
		if $Config::BadLocking;
	unless(fork) { # This is the child
		unless (fork) { # Grandchild
			select(undef,undef,undef,0.100) until getppid == 1;
			perform_search($c,@_);
			unlink $Vend::ActiveSocket;
			exit 0;
		}
		exit 0;
	}
	wait;
}

sub do_scan {

	# This is quite tricky -- I would be happy for
	# suggestions on how to make it more regular
	my($argument,$path) = @_;
	my($c) = {};

	find_search_params($c,$path);

	return perform_search($c,$argument)
		if $Config::BadLocking;
	unless(fork) { # This is the child
		unless (fork) { # Grandchild
			select(undef,undef,undef,0.050) until getppid == 1;
			perform_search($c,$argument);
			unlink $Vend::ActiveSocket;
			exit 0;
		}
		exit 0;
	}
	wait;
}

# Returns undef if interaction error
sub update_quantity {
	my($i, $quantity);

	foreach $i (0 .. $#$Vend::Items) {
    	$quantity = $CGI::values{"quantity$i"};
    	if (defined($quantity) && $quantity =~ m/^\d+$/) {
        	$Vend::Items->[$i]->{'quantity'} = $quantity;
    	}
		elsif (defined $quantity) {
			my $item = $Vend::Items->[$i]->{'code'};
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
    DELETE: for (;;) {
        foreach $i (0 .. $#$Vend::Items) {
            if ($Vend::Items->[$i]->{'quantity'} == 0) {
                splice(@$Vend::Items, $i, 1);
                next DELETE;
            }
        }
        last DELETE;
    }

	1;

}

sub add_items {

	my($items) = @_;
	my(@items);
	my($code,$found,$i,$q);

	@items = split /\0/, $items;

	foreach $code (@items) {
		if (!product_code_exists($code)) {
			logError("Attempt to order missing product code: $code\n");
			display_special_page($Config::Special{'noproduct'}, $code);
			return;
		}

		# Check that the item has not been already ordered.
		$found = -1;
		foreach $i (0 .. $#$Vend::Items) {
			if ($Vend::Items->[$i]->{'code'} eq $code) {
				$found = $i;
				# Increment quantity. This is different than
				# the standard handling because we are ordering
				# accessories, and may want more than 1 of each
				$Vend::Items->[$i]->{'quantity'}++;
				$CGI::values{"quantity$i"}++;
			}
		}

		# An if not, start of with a single quantity.
		if ($found == -1) {
			push @$Vend::Items, {'code' => $code, 'quantity' => 1};
			$q = $#{$Vend::Items};
			$CGI::values{"quantity$q"} = 1;
		}
	}
}
	
## DO FINISH

# Finish an incomplete order.

sub do_finish {
	my($page) = shift || $Config::CheckoutPage;
	$page =~ s/^finish_?_?//;
    order_page($page);
    put_session();
}

# Update the user-entered fields.
sub update_user {
	my($key,$value);
    # Update the user-entered fields.
    while (($key, $value) = each %CGI::values) {
        next if ($key =~ m/^quantity\d+/);
        next if ($key =~ /^mv_(todo|nextpage|doit)/);
		# Add any checkbox-ordered items, but don't update --
		# we don't want to order them twice
		if ($key eq 'mv_order_item') {
			add_items($value);
			next;
		}
        $Vend::Session->{'values'}->{$key} = $value;
		next unless $key =~ /credit_card/i;
		if(	defined $Config::Password &&
			$Config::CreditCards			)
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
		}
			
    }
}

## DO PROCESS

# Find an action from the submitted value
sub minivend_action {
	my ($todo) = (@_);

	return undef unless defined $todo;
	$todo = lc $todo;
	
	if(defined $Config::ActionMap{$todo}) {
		return  $Config::ActionMap{$todo};
	}
	for (keys %Config::ActionMap) {
		return $Config::ActionMap{$_} if $todo =~ /$_/i;
	}
	return $todo;
}

# Process the completed order or search page.

sub do_process {
    my($i, $doit, $quantity, $todo, $page, $key, $value);
	my($status, $nextpage, $orderpage, $ordered_items);

    expect_form() || return;

    $doit = $CGI::values{'mv_doit'};
    $todo = $CGI::values{'mv_todo'};
    $nextpage = $CGI::values{'mv_nextpage'} || $Vend::Session->{'page'};
    $orderpage = $CGI::values{'mv_orderpage'} || $Config::Special{'order'};
    $ordered_items = $CGI::values{'mv_order_item'};

	# Maybe we have an imagemap input, if not, use $doit
    if (!defined $todo) {
		if (defined $CGI::values{'mv_todo.x'}) {
				my $x = $CGI::values{'mv_todo.x'};
				my $y = $CGI::values{'mv_todo.y'};
				my $map = $CGI::values{'mv_todo.map'};
				$todo = action_map($x,$y,$map);
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
	#if ($doit =~ /\baccount\b/i) {
		if ($CGI::secure) {
			$Vend::Session->{'secure'} = 1;
			update_user();
			do_page($nextpage);
			return;
		}
		else {
			do_page($Config::Special{'violation'});
			return;
		}
    }
	elsif ($todo eq 'unsecure') {
		$Vend::Session->{'secure'} = 0;
		do_page($nextpage);
		return;
	}
	elsif ($todo eq 'checkout') {
	#elsif ($todo =~ /check ?out/i) {
		update_user();
		unless(update_quantity()) {
			interaction_error("quantities");
			return;
		}
		my $next = $CGI::values{'mv_checkout'} || $orderpage;
		order_page($next);
	}
	elsif ($todo eq 'control') {
	#elsif ($doit =~ /\bcontrol\b/i) {
		update_user();
		do_page($nextpage);
		return;
	}
	elsif ($todo eq 'submit') {
	#elsif ($todo =~ /submit|order/i) {
		update_user();
		update_quantity() || return; #Return on error
		my($ok);
		my($missing);
		my($values) = $Vend::Session->{'values'};
		($ok, $missing) = check_required($values);
		if (!$ok) {
	    	display_special_page($Config::Special{'needfield'}, $missing);
    		put_session();
			return;
		}

		# This function (followed down) now does the backend ordering
		$ok = mail_order();

		# Display a receipt if configured

		if ($ok && $Config::ReceiptPage) {
	    	display_special_page($Config::ReceiptPage);
		}
		elsif ($ok) {
	    	display_special_page($Config::Special{'confirmation'});
		} else {
	    	display_special_page($Config::Special{'failed'});
		}

		# Remove the items
		@$Vend::Items = ();

    }
	elsif ($todo eq 'return') {
	#elsif ($todo =~ /return/i) {
		update_user();
		display_page($nextpage);
    }
	elsif ($todo eq 'refresh') {
	#elsif ($todo =~ /finish|refresh|recalc/i) {
		update_user();
		update_quantity() || return; #Return on error
		order_page($orderpage);
    }
	elsif ($todo eq 'search') {
	#elsif ($todo =~ /search/i or $doit =~ /search/i) {
		update_user();
    	put_session();
		return do_search(); # Will fork the actual search, session var
		             		# changes make no difference but shouldn't be done
    }
	elsif ($todo eq 'cancel') {
	#elsif ($todo =~ /(cancel|log out)/i) {
		$Vend::Session->{'values'}->{'credit_card_no'} = 'xxxxxxxxxxxxxxxxxxxxxx';
		$Vend::Session->{'values'}->{'credit_card_exp'} = 'xxxxxxxx';
		$Vend::Session->{'login'} = '';
		my $frames = $Vend::Session->{'frames'};
		put_session();
		get_session();
		init_session();
		$Vend::Session->{'frames'} = $frames;
		display_page($Config::Special{'canceled'});
    }
	else {
		interaction_error(
          "Form variable 'mv_todo or mv_doit' value '$todo' not recognized\n");
		return;
    }
    put_session();
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
	}


    $date = localtime();
	$report =~ s#\$date#$date#ige;
	$report =~ s#\$(\w+)#report_field($1, $seen)#ge;
	$report;
}

sub order_list {
    my($body, $i, $item, $code, $quantity, $desc, $price);

    $body = <<'END';
Qty     Item                 Description                     Price      Total
---  ------------  --------------------------------------  --------  ---------
END

    foreach $i (0 .. $#$Vend::Items) {
	$item = $Vend::Items->[$i];
	$code = $item->{'code'};
	$quantity = $item->{'quantity'};
	$price = product_price($code);
	$desc  = product_description($code);
	$desc =~ s/<.*?>/ /g;
	$body .= sprintf( "%3s  %-12s  %-38s  %8s  %9s\n",
			 $quantity,
			 $code,
			 substr($desc,0,38),
			 currency($price),
			 currency($quantity * $price) );
    }
	$body .= sprintf "%3s  %-12s  %-38s  %8s  %9s\n",
			'','','SUBTOTAL','', currency(subtotal());
	$body .= sprintf "%3s  %-12s  %-38s  %8s  %9s\n",
			'','','SALES TAX','', currency(salestax());
	$body .= sprintf "%3s  %-12s  %-38s  %8s  %9s\n",
			'','','SHIPPING',
			$Vend::Session->{'values'}->{'mv_shipmode'},
			currency(shipping());
	$body .= sprintf "%3s  %-12s  %-38s  %8s  %9s\n",
			'','','','TOTAL', tag_total_cost();
    $body;
}

sub check_required {
	my $val = shift;
	my $item;
	my @missing;
	my @req = split(/\s*,\s*/, $Config::RequiredFields);
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

	@ignore = split(/\s*,\s*/, $Config::ReportIgnore);
	foreach $field (@ignore) {
		$ignore->{$field} = 1;
	}
	$ignore;
}

# Email the processed order.

sub mail_order {
    my($body, $i, $code, $ok, $seen, $blankline);
    my($values, $key, $value, $order_no, $subject);
	my $new = 0;
    $seen = get_ignored();
    $body = order_report($seen);
    return undef unless defined $body;

    $values = $Vend::Session->{'values'};

    $blankline = 0;
    while (($key, $value) = each %$values) {
		next if $key =~ /^mv_/i;
		if (!$new && !$$seen{$key}) {
			if (!$blankline) {
			$body .= "\n";
			$blankline = 1;
			}
			$body .= "$key: $value\n";
		}
    }

	if(defined $values->{'mv_order_report'}
		and $values->{'mv_order_report'}) {
		$new = 1;
		$body = interpolate_html($body);
	}

    $body .= "\n" . order_list()
		unless $new;
	$order_no = track_order($body);
	if(defined $order_no) {
	    $subject = "ORDER $order_no";
    	$body .= "\n\nORDER NUMBER: $order_no\n";
	}
	else { $subject = 'ORDER'; }
    $ok = send_mail($Config::MailOrderTo, $subject, $body);
    $ok;
}


sub map_cgi {

    my($cgi, $major, $minor, $host, $user, $secure, $length);

    $CGI::request_method = ::http()->Method;
    die "REQUEST_METHOD is not defined" unless defined $CGI::request_method;

    $CGI::path_info = ::http()->Path_Info;

    $host = http()->Client_Hostname;
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

    $CGI::content_length = http()->Content_Length;
    $CGI::content_type = http()->Content_Type;
    $CGI::query_string = http()->Query;

	$CGI::post_input = http()->read_entity_body(http());
	parse_post();
}

## DISPATCH

# Parse the invoking URL and dispatch to the handling subroutine.

sub dispatch {
	my($http, $socket, $debug) = @_;
	my $forked = 0;
	$H = $http;
	if( defined $Vend::ServerMode) {
		map_cgi($H);
		# We do this so that we can unlink it if we fork an op
		$Vend::ActiveSocket = $socket;
	}
    my($query_string, $sessionid, $argument, $path, @path, $action);

    $query_string = $CGI::query_string;
    if (defined $query_string && $query_string ne '') {
	($sessionid, $argument) = split(/;/, $query_string);
    }

	# Get a cookie if we have no session id (and its there)
    unless (defined $sessionid && $sessionid ne '') {
		if ($CGI::cookie =~ /\bMV_SESSION_ID=(\w{8})\b/) {
			$sessionid = $1;
		}
	}

    if (defined $sessionid && $sessionid ne '') {
		$Vend::SessionID = $sessionid;
    		$Vend::SessionName = session_name();
		get_session();
		if (time - $Vend::Session->{'time'} > $Config::SessionExpire) {
	    	init_session();
		}
    }
	else {
		new_session();
    }

    $path = $CGI::path_info;

	# If this is left at 0, then we will try the on-the-fly page
	$Vend::RegularPage = 0;

    # If the cgi-bin program was invoked with no extra path info,
    # just display the catalog page.
    if (!defined $path || $path eq '' || $path eq '/') {
		do_catalog();
		release_session() if $Vend::HaveSession;
		return 0;
    }

	$path =~ s:^/::;
    @path = split('/', $path, 2);
    $action = shift @path;

	# The do_search routine now forks a process and does
	# the search in the background. Be careful if you hack
	# the search routine to use a DBM cache!
	# Will fork the actual search, session var
	# changes make no difference but shouldn't be done
    if    ($action eq 'order')    { do_order($argument,@path);  }
    elsif ($action eq 'search')   { $forked = do_search($argument); } # forks
    elsif ($action eq 'scan')     { $forked = do_scan($argument,@path); } # forks
    elsif ($action eq 'process')  { $forked = do_process(); } # possibly forks
    else {
		# try the on-the-fly page if it fails
		$Vend::RegularPage = 1;
		do_page($path);
    }
	release_session() if $Vend::HaveSession;
	$forked = 0 if $Config::BadLocking;
	return $forked;
}

## DEBUG

sub dontwarn {
	$Config::AsciiBackend +
	$Config::AsciiTrack +
	$Config::BackendOrder +
	$Config::CreditCards +
	$Config::CheckoutPage +
	$Config::DebugMode +
	$Config::DescriptionField +
	$Config::DefaultShipping +
	$Config::ExtraSecure +
	$Config::FinishOrder +
	$Config::HammerLock +
	$Config::ItemLinkDir +
	$Config::ItemLinkValue +
	$Config::MailOrderTo +
	$Config::MultiServer +
	$Config::OrderReport +
	$Config::PageCheck +
	$Config::PageDir +
	$Config::PriceCommas +
	$Config::PriceField +
	$Config::ProductDir +
	$Config::ReadPermission +
	$Config::ReportIgnore +
	$Config::RequiredFields +
	$Config::SalesTax +
	$Config::ScratchDir +
	$Config::SearchFrame +
	$Config::SearchOverMsg +
	$File::CounterFile::DEFAULT_DIR +
	$Config::SecureOrderMsg +
	$Config::SecureURL +
	$Config::Shipping +
	$Config::TaxShipping +
	$Config::UseCode +
	$Config::VendURL +
	$Config::WritePermission +
	$Vend::Shipping_criterion +
	$Vend::Shipping_desc +

	1;
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

	$CGI::useragent = $ENV{'HTTP_USER_AGENT'};
	$CGI::request_method = $ENV{'REQUEST_METHOD'};
	die "REQUEST_METHOD is not defined" unless defined $CGI::request_method;

	$CGI::path_info = $ENV{'PATH_INFO'};
	# Commented out by Mike Heins, no need for this trap
	# die "PATH_INFO is not defined" unless defined $CGI::path_info;

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
	#&dump_post();
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
		} elsif (m/^-i(nit)?$/i) {
			$Vend::mode = 'init';
		} elsif (m/^-t(est)?$/i) {
			$Vend::mode = 'test';
			last; # Need to do this to preserve @ARGV
		} elsif (m/^-e(xpire)?$/i) {
			$Vend::mode = 'expire';
		} elsif (m/^-n(etstart)?$/i) {
			$Vend::mode = 'netstart';
		} elsif (m/^-n(otify)?$/i) {
			$Vend::mode = 'notify';
		} elsif (m/^-s(erve)?$/i) {
			$Vend::mode = 'serve';
		} elsif (m/^-r(estart)?$/i) {
			$Vend::mode = 'restart';
		} elsif (m/^-dump-sessions$/i) {
			$Vend::mode = 'dump-sessions';
		} else {
		    $? = 2;
			die "Unknown command line option: $_\n" .
				"(Use -help for a list).\n";
		}
	}
}

sub version {
	print "MiniVend version 1.02 Copyright 1995 Andrew M. Wilcox\n";
	print "                      Copyright 1996 Michael J. Heins\n";
}

sub usage {
	version();
	print <<'END';

MiniVend comes with ABSOLUTELY NO WARRANTY.  This is free software, and
you are welcome to redistribute and modify it under the terms of the
GNU General Public License.

Command line options:

	 -config <file>   specify configuration file
	 -test            report problems with config file or pages
	 -version         display program version
	 -expire          expire old sessions
	 -serve           start server
	 -netstart        start server from the net
	 -restart         restart server (re-read config file)
END
}

sub scrub_sockets {

	my (@sockets);
	my $dir = $Config::ConfDir;

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

	#dump_env();

	# Were we called from an HTTPD server as a cgi-bin program?
	if (defined $ENV{'GATEWAY_INTERFACE'} && $ENV{'GATEWAY_INTERFACE'}) {
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
		undef $Vend::mode;      # mode will be set by options
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
		# No import_database because done in Config
		import_products();
		undef $Vend::ServerMode;
		dispatch();
		close_products();
		close_database();
	} elsif ($Vend::mode eq 'serve' or $Vend::mode eq 'netstart') {
		# This should never return unless killed or an error
		# We set debug mode to -1 to communicate with the server
		# that no output is desired
		scrub_sockets() unless $Config::MultiServer;
		# No import_database because done in Config
		import_products();
		my $pipestat = $|;
		my $save = select STDERR; 
        my $stderr = $|;
        $| = 1;
        select STDOUT;
        my $stdout = $|;
        $| = 1;
		my $bad = 0;
		my $errors;
		if($Config::PageCheck) {
			require Vend::PageSyntax;
			($bad,$errors) =
				Vend::PageSyntax::check_pages("$Config::ConfDir/variables.def");
			if($errors ||= 0) { print $errors, "\n" }
		}
		die "\n\nThere " .
				($bad > 1 ? 'were' : 'was') .
				" $bad bad " .
				($bad > 1 ? 'pages' : 'page') .
				" can't start server!\n"
			if $bad;
		if($Vend::mode eq 'netstart') {
			$Config::DebugMode = -1;
		}
		else {
			read_password();
		}

        no strict 'refs';
        select STDERR; 
        $| = $stderr;
        select STDOUT;
        $| = $stdout;
        select $save;
        $| = $pipestat;
        use strict 'refs';

        $Vend::ServerMode = 1;
        Vend::Server::run_server($Config::MultiServer, $Config::DebugMode);
        undef $Vend::ServerMode;
        close_products();
        close_database();
	} elsif ($Vend::mode eq 'init') {
		# No import_database because done in Config
		import_products();
		close_products();
		close_database();
	} elsif ($Vend::mode eq 'expire') {
		expire_sessions();
	} elsif ($Vend::mode eq 'dump-sessions') {
		dump_sessions();
	} elsif ($Vend::mode eq 'notify') {
	    my $to = $Config::MailOrderTo;
	    my $subject = "MiniVend not running";
		my $msg = <<EOM;
A user tried to access MiniVend with the URL
"$Config::VendURL" and the server
was not running.
EOM
		send_mail($to, $subject, $msg) or die "Couldn't send mail: $!\n";
	} elsif ($Vend::mode eq 'test') {
		# No import_database because done in Config
		import_products();
		require Vend::PageSyntax;
		my ($mv_status,$errors) =
			Vend::PageSyntax::check_pages("$Config::ConfDir/variables.def", @ARGV);
		close_products();
		close_database();
		if($errors ||= 0) { print $errors, "\n" }
		exit $mv_status;
	} else {
		die "Unknown mode: $Vend::mode\n";
	}
}

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

