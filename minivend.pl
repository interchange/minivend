#!/usr/local/bin/perl
#
# MiniVend version 2.00
#
# $Id: minivend.pl,v 1.7 1997/05/05 20:13:51 mike Exp $
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
$Global::VendRoot = '/ext/minivend';
$Global::ConfDir = "$Global::VendRoot/etc";

# Uncomment next line if you want to guarantee use of DB_File
#$ENV{MINIVEND_DBFILE} = 1;

# Uncomment next line if you want to use no DBM, sessions
# stored in files and databases in memory (or mSQL)
#$ENV{MINIVEND_NODBM} = 1;

$Global::ErrorFile = 'error.log';
}
$Global::ConfigFile = 'minivend.cfg';

use lib "$Global::VendRoot/lib";
use vars qw($VERSION);

# BSD, among others, defines sendmail to be in /usr/sbin, and
# we want to make sure the program is there. Insert the location
# of you sendmail binary (the configure script should do this)
$Global::SendMailLocation = '/usr/lib/sendmail';

# For the order counter, no huge deal if not there.  Included
# with the distribution.
use File::CounterFile;

### END CONFIGURABLE VARIABLES

$VERSION = '3.00pre';
use strict;
use Fcntl;

#select a DBM

BEGIN {
	chdir $Global::VendRoot
		or die "Couldn't change directory to $Global::VendRoot: $!\n";
	$Global::GDBM = $Global::DB_File = $Global::Msql = $Global::DBI = 0;
	$Global::DBDtype = $ENV{MINIVEND_DBD} || 'mSQL';
	eval {require Msql and $Global::Msql = 1};
	#eval {require DBI and $Global::DBI = 1};

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
# GLIMPSE
use Vend::Glimpse;
# END GLIMPSE
use Vend::Scan;
use Vend::TextSearch;
use Vend::Order;
use Vend::Data;
use Vend::Util;
use Vend::Interpolate;
use Vend::ValidCC;
use Vend::Cart;

# STATICPAGE
use Vend::PageBuild;
# END STATICPAGE

my $H;
sub http {
	$H;
}

$Global::ConfigFile = "$Global::VendRoot/$Global::ConfigFile"
    if ($Global::ConfigFile !~ m.^/.);
$Global::ErrorFile = "$Global::VendRoot/$Global::ErrorFile"
    if ($Global::ErrorFile !~ m.^/.);

sub response {
	my ($type,$output,$debug) = @_;
	#$Vend::content_type = $type;
	my $content = $Vend::ContentType || "text/$type";
	http()->respond($content,$output,$debug);
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
    }
	else {
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
    my($name, $arg) = @_;
    my($page);

	if($Vend::Cfg->{'ExtraSecure'} and
		$Vend::Cfg->{AlwaysSecure}->{$name}
		and !$CGI::secure) {
		$name = $Vend::Cfg->{'Special'}->{'violation'};
	}

    $page = readin($name);
	# Try for on-the-fly if not there
	if(! defined $page) {
		$page = fly_page($name,$arg);
	}

    if (defined $page) {
		response('html',interpolate_html($page));
		return 1;
    } else {
		display_special_page($Vend::Cfg->{'Special'}->{'missing'}, $name);
		return 0;
		$page = readin($Vend::Cfg->{'Special'}->{'missing'});
		die "Special page not found: $Vend::Cfg->{'Special'}->{'missing'}\n"
			unless defined $page;
		$page =~ s#\[subject\]#$name#ig;
    	response('html',interpolate_html($page));
		return 0;
    }
}


sub cache_page {
    my($name, $arg) = @_;
    my($page);
	my $pagedir = $Vend::Cfg->{ScratchDir} . '/PageCache';
	my $pagename =  generate_key($name,$arg);

	if($page = readfile("$pagedir/$pagename.html")) {
#print("Hit cache $pagename\n") if $Global::DEBUG;
    	response('html', $page);
		return 1;
	}

	$page = readin($name);
	# Try for on-the-fly if not there
	if(! defined $page) {
		$page = fly_page($name, $arg);
	}

    if (defined $page) {
    	$page = cache_html($page);
		if(defined $Vend::CachePage) {
			logData($Vend::Cfg->{'LogFile'}, 'cache', time, "$arg:$name", $pagename)
				if defined $Vend::Cfg->{CollectData}->{cache};
			open PAGECACHE, ">$pagedir/$pagename.html"
				or do {
					logGlobal "Cache failure for $Vend::Cfg->{CatalogName}: $!\n";
					die "Cache failure: $!\n";
				};
			print PAGECACHE $page;
			close PAGECACHE;
		}
		put_session();
    	response('html',$page);
		return 1;
    }
	else {
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
    my($name, $arg) = @_;

	if($Vend::Cfg->{PageCache}	and
		$CGI::cookie			and
		! defined $Vend::Cfg->{NoCache}->{$name})
	{
		cache_page($name, $arg || undef) and $Vend::Session->{'page'} = $name;
	}
	else { 
		display_page($name, $arg || undef) and $Vend::Session->{'page'} = $name;
		put_session();
	}
}


## DO ORDER

# Order an item with product code CODE.

sub do_order
{
    my($code,$path,$catalog) = @_;
    my($i, $found, $item, $save, %att);
	
#warn ("do_order: '" . (join "','", @_) . "'\n") if $Global::DEBUG;
	my($cart,$page) = split m:/:, $path || '', 2;

	$cart = get_cart $cart;

    my $base = product_code_exists_tag($code, $catalog || undef);

    if (! $base ) {
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
				$CGI::values{mv_separate_items} ||
				(
					defined $Vend::Session->{scratch}->{mv_separate_items}
				 && is_yes( $Vend::Session->{scratch}->{mv_separate_items} )
				 );
		last INC if $separate;

		foreach $i (0 .. $#$cart) {
			if ($cart->[$i]->{'code'} eq $code) {
				next unless $cart->[$i]->{mv_ib} eq $base;
				$found = $i;
			}
		}

	} # INC

    # And if not found or separate, start with a single quantity.
    if ($found == -1) {
		$item = {'code' => $code, 'quantity' => 1, mv_ib => $base};
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


## DO SEARCH

sub do_search {
	my($c) = \%CGI::values;

	if($Vend::Cfg->{SearchCache} and $CGI::cookie) {
		my($key,$page) = check_search_cache($c);
		return response('html',$page) if defined $page;
		$c->{mv_cache_key} = $key if defined $key;
	}

	my $status = perform_search($c,@_);
	put_session if $Vend::Session->{scratch}->{mv_put_session};
	return $status;
}

sub do_scan {
	my($argument,$path) = @_;
	my ($key,$page);

	if($Vend::Cfg->{SearchCache} and $CGI::cookie) {
		($key,$page) = check_scan_cache($path);
		return response('html',$page) if defined $page;
	}

	my($c) = { mv_cache_key => $key || '' };

	find_search_params($c,$path);

	my $status = perform_search($c,$argument);
	put_session if $Vend::Session->{scratch}->{mv_put_session};
	return $status;
}

sub fake_scan {

	my($argument,$path) = @_;
	my ($key,$page);
	my $c = {};
	find_search_params($c,$path);
	return perform_search($c,$argument);
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

	my($items,$quantities,$bases) = @_;
	my(@items);
	my($code,$found,$item,$base,$quantity,$i,$j,$q);
	my(@quantities);
	my(@bases);
	my($attr,%attr);

	@items = split /\0/, $items;

	my $cart = $CGI::values{mv_cartname};

	$cart = get_cart($cart);

	if($quantities ||= '') {
		@quantities = split /\0/, $quantities;
	}

	$bases = $bases || $CGI::values{mv_order_mv_ib} || '';
	if($bases) {
		@bases = split /\0/, $bases;
	}

	foreach $attr (@{$Vend::Cfg->{UseModifier}}) {
		$attr{$attr} = [];
		next unless defined $CGI::values{"mv_order_$attr"};
		@{$attr{$attr}} = split /\0/, $CGI::values{"mv_order_$attr"};
	}

	my $separate =
				$Vend::Cfg->{SeparateItems} ||
				$CGI::values{mv_separate_items} ||
				(
					defined $Vend::Session->{scratch}->{mv_separate_items}
				 && is_yes( $Vend::Session->{scratch}->{mv_separate_items} )
				 );
	$j = 0;
	foreach $code (@items) {
		$quantity = $quantities[$j] ||= 1;
		$base = product_code_exists_tag($code, $bases[$j] || undef);
		if (! $base ) {
			logError("Attempt to order missing product code: $code\n");
			return;
		}


		INCREMENT: {

			# Check that the item has not been already ordered.
			# But let us order separates if so configured
			$found = -1;
			last INCREMENT if $separate;

			foreach $i (0 .. $#$cart) {
				if ($cart->[$i]->{'code'} eq $code) {
					next unless $base eq $cart->[$i]->{mv_ib};
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
			$item = {'code' => $code, 'quantity' => $quantity, mv_ib => $base};
			if($Vend::Cfg->{UseModifier}) {
				foreach $i (@{$Vend::Cfg->{UseModifier}}) {
					$item->{$i} = $attr{$i}->[$j];
				}
			}
			my $next = $#$cart + 1;
			push @$cart, $item;
			$CGI::values{"quantity$next"} = $quantity;
		}
		$j++;
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
		msql_query('set', "", $query);
	}


}

# Parse the mv_click and mv_check special variables
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
        next if defined $Vend::Cfg->{FormIgnore}->{$key};
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

	check_save if defined $CGI::values{'mv_save_session'};

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

	my($click, @clicks);
	if(defined $CGI::values{'mv_click'}) {
		@clicks = split /\s*[\0]+\s*/, $CGI::values{'mv_click'};
	}

	if(defined $CGI::values{'mv_click_map'}) {
		my(@map) = split /\s*[\0]+\s*/, $CGI::values{'mv_click_map'};
		foreach $click (@map) {
			push (@clicks, $click)
				if defined $CGI::values{"mv_click.$click.x"};
		}
	}

	foreach $click (@clicks) {
		parse_click \%CGI::values, $click;	
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

	if ($todo eq 'search') {
		update_user();
    	put_session();
		return do_search();
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
	elsif ($todo eq 'refresh') {
		update_user();
		update_quantity() || return; #Return on error
		order_page($orderpage);
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
	elsif ($todo eq 'secure') {
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
	my ($script_name, $source, $build) = @_;
	my ($g,$c,$conf);

	for (keys %Global::Catalog) {
         next unless $Global::Catalog{$_}->{'script'} eq $script_name;
         $g = $Global::Catalog{$_};
    }
	return undef unless defined $g;
    logGlobal "Re-configuring catalog " . $g->{'name'} . $source;
    chdir $g->{'dir'}
            or die "Couldn't change to $g->{'dir'}: $!\n";
    $conf = $g->{'dir'} . '/etc';
    eval {
        $c = config($g->{'name'}, $g->{'dir'}, $conf);
    };
    if($@) {
		my $msg = $@;
        logGlobal <<EOF;
$msg

$g->{'name'}: error in configuration file. Aborting configuration.
EOF
        logError <<EOF;
$msg
		
Error in configuration file. Aborting configuration.
EOF
     	return undef;
    }

	eval {
		if ($c->{StaticAll}) {
			print "loading static page names...";
			my $basedir = $c->{PageDir};
			open STATICPAGE, "$basedir/.static"
				or warn <<EOF;
Couldn't read static page status file $basedir/.static: $!
EOF
			while(<STATICPAGE>) {
				chomp;
				$c->{StaticPage}->{$_} = 1;
			}
			close STATICPAGE;
		}
		if($c->{ClearCache}) {
			for('PageCache', 'SearchCache') {
				next unless $c->{$_};
				require File::Path;
				my $dir = $c->{'ScratchDir'} . "/$_";
				File::Path::rmtree([$dir]);
				mkdir $dir, 0777
					or die "Couldn't make $dir: $!\n";
				eval { logError("Cleared $dir") };
			}
		}
		$Vend::Cfg = $c;	
		read_accessories();
		read_salestax();
		read_shipping();
		open_database();
		(
			$Vend::Cfg->{ItemPriceRoutine},
			$Vend::Cfg->{QuantityPriceRoutine}
		)	= read_pricing();
		if($build) {
			$Vend::BuildingPages = 1;
			# Depends on whether user builds are enabled globally
			build_all($g->{'name'})
				if $Global::UserBuild;
			undef $Vend::BuildingPages;
		}
		close_database();
	};
	undef $Vend::Cfg;
	undef $Vend::BuildingPages;  # In case of eval error
    if($@) {
		my $msg = $@;
        logGlobal <<EOF;
$msg

$g->{'name'}: error in configuration file. Aborting configuration.
EOF
		eval {
        logError <<EOF;
$msg

Error in configuration file. Aborting configuration.
EOF
		};
     	return undef;
    }

	return $c;

}

sub build_page {
    my($name,$dir,$check) = @_;
    my($base,$page);
	my $status = 1;

    $page = readin($name);
	# Try for on-the-fly if not there
	if(! defined $page) {
		$page = fly_page($name);
		$name = $Vend::Cfg->{ItemLinkDir} . $name
			if $Vend::Cfg->{ItemLinkDir};
	}

    if (defined $page) {

		unless($check) {
		  open(BUILDPAGE, ">$dir/$name$Vend::Cfg->{StaticSuffix}")
			or die "Couldn't create file $dir/$name" .
					$Vend::Cfg->{StaticSuffix} . ": $!\n";
		}

		if(!$name and $Vend::Cfg->{StaticPath}) {
			$name = $Vend::Cfg->{StaticPath};
		}
		$page = cache_html($page);
		unless (defined $Vend::CachePage) {
			print "\cH" x 22 . "skipping, dynamic elements.\n";
			$status = 0;
		}
		elsif(! $check) {
			my @post = ();
			my $count = 0;
			my($search, $file);
			my $string = $Vend::Cfg->{VendURL} . "/scan/" ;
			while($page =~ s!$string([^?]+)[^"]+!"__POST_" . $count++ . "__"!e) {
				$search = $1;
				print do_msg "\n>> found search $search", 61;
				push @post, $string . $search;
				if ($search = fake_scan('', $search) ) {
					$file = "scan" . ++$Vend::ScanCount .
									$Vend::Cfg->{StaticSuffix};
					pop @post;
					push @post, "$Vend::Cfg->{StaticPath}/$file";
					Vend::Util::writefile(">$dir/$file", $search)
						or die "Couldn't write $dir/$file: $!\n";
					print "save.";
				}
				else {
					print "skip.";
				}
					
			}
			if(@post) {
				$page =~ s/__POST_(\d+)__/$post[$1]/g;
				print "\n";
			}
		}
				
		return $status if $check;
    	print BUILDPAGE $page;
		close BUILDPAGE;
    }
	else {
		print "\cH" x 20 . "skipping, page not found.\n";
		$status = 0;
	}
	$status;

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
	die "$catalog: no such catalog!\n"
		unless defined $g;
		
	my %build;
	my $build_list = 0;
	if(@Vend::BuildSpec) {
		%build = map { ($_,1) } @Vend::BuildSpec;
		$build_list = 1;
	}

	$spec = $Vend::BuildSpec || $Vend::Cfg->{StaticPattern} || '';
	CHECKSPEC: {
		my $test = 'NevVAIRBbe';
		eval { $test =~ s:^/tmp/whatever/$spec::; };
		die "Bad -files spec '$spec'\n" if $@;
	}
	$Vend::Cfg = $Global::Selector{$g};
	chdir $Vend::Cfg->{'VendRoot'} 
		or die "Couldn't change to $Vend::Cfg{'VendRoot'}: $!\n";
	$Vend::Cfg->{'ReadPermission'} = 'world';
	$Vend::Cfg->{'WritePermission'} = 'user';
	set_file_permissions();
	umask $Vend::Cfg->{'Umask'};

	my $all = $Vend::Cfg->{StaticAll};
	$build_list = 0 if $all;

	return unless ($all or scalar keys %{$Vend::Cfg->{StaticPage}});
	my $basedir = $Vend::Cfg->{'PageDir'};

	# do some basic checks to make sure we don't clobber
    # anything with a value of '/', and have an
	# absolute file path
	$outdir = $outdir || $Vend::Cfg->{StaticDir} || 'static';

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

	open_database();
	$Vend::SessionID = '';
	$Vend::SessionName = '';
	init_session();
	$Vend::Session->{'frames'} = 1;
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
						($File::Find::prune = 1, return)
							if defined $Vend::Cfg->{NoCache}->{$name};
						($File::Find::prune = 1, return)
							if defined $Vend::Cfg->{AdminPage}->{$name};
						return if -d "$outdir/$name";
						mkdir ("$outdir/$name", 0755)
							or die "Couldn't make dir $outdir/$name: $!\n";
						return;
					}
					return unless $name =~ s/$Vend::Cfg->{StaticSuffix}$//o;
					return if defined $Vend::Cfg->{NoCache}->{$name};

					if ($build_list) {
						return unless defined $build{$name};
					}

					return if $Vend::Cfg->{AdminPage}->{$name};

					push @files, $name;
			};
	print do_msg("Finding files...");
	File::Find::find($sub, $Vend::Cfg->{PageDir});
	print "done.\n";
	
	chdir $Vend::Cfg->{'VendRoot'} 
		or die "Couldn't change to $Vend::Cfg{'VendRoot'}: $!\n";

	$p = database_ref();
	$Vend::Session->{'pageCount'} = -1;
	my $save = $;
	$ = 0;

	my $static;

	foreach $key (@files) {
		print do_msg("Checking page $key ...");
		$Vend::Cfg->{StaticPage}->{$key} = 1 if $all;
		$static = build_page($key,$outdir, 1);
		unless ($static) {
			delete $Vend::Cfg->{StaticPage}->{$key};
			$key = '';
			next;
		}
		print "done.\n";
	}

	FLY: {
		last FLY unless $Vend::Cfg->{StaticFly};
		while( ($key,$val) = $p->each_record() ) {
			next if $build_list && ! defined $build{$key};
			next unless $key =~ m{^$spec}o;
			$Vend::Cfg->{StaticPage}->{$key} = 1 if $all;
			print do_msg("Checking part number $key ...");
			build_page($key,$outdir, 1)
				or (delete($Vend::Cfg->{StaticPage}->{$key}), next);
			print "done.\n";
		}
	}

	foreach $key (@files) {
		next unless $key;
		print do_msg("Building page $key ...");
		build_page($key,$outdir)
			or (delete($Vend::Cfg->{StaticPage}->{$key}), next);
		$Vend::Session->{'pageCount'} = -1;
		print "done.\n";
	}

	FLY: {
		last FLY unless $Vend::Cfg->{StaticFly};
		while( ($key,$val) = $p->each_record() ) {
			next unless defined $Vend::Cfg->{StaticPage}->{$key};
			print do_msg("Building part number $key ...");
			build_page($key,$outdir)
				or (delete($Vend::Cfg->{StaticPage}->{$key}), next);
			$Vend::Session->{'pageCount'} = -1;
			print "done.\n";
		}
	}
	open STATICPAGE, ">$basedir/.static"
		or die "Couldn't write static page file: $!\n";
	for(sort keys %{$Vend::Cfg->{StaticPage}}) {
		print STATICPAGE "$_\n";
	}
	close STATICPAGE;

	$ = $save;
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
	#
	# This is removed to guarantee that the user name is REMOTE_USER
	# Needed to guarantee security
    # $user = http()->Client_Ident
	#   unless (defined $user && $user ne '');
	#
    $user = '' unless defined $user;
    $CGI::user = $user;
    $CGI::useragent = http()->User_Agent;
    $CGI::cookie = http()->Cookie;

    #$CGI::content_length = http()->Content_Length;
    $CGI::content_type = http()->Content_Type;
    $CGI::reconfigure_catalog = http()->Reconfigure;
    $CGI::query_string = http()->Query;
    $CGI::referer = http()->Referer;
	unless ($Global::FullUrl) {
		$CGI::script_name = http()->Script;
	}
	else {
		$CGI::script_name = http()->URI;
	}

	$CGI::post_input = http()->read_entity_body(http());
	parse_post();
}

## DISPATCH

# Parse the invoking URL and dispatch to the handling subroutine.

sub dispatch {
	my($http, $socket, $debug) = @_;
	$H = $http;

#print Global::DEBUG "begin dispatch: ",  join " ", times(), "\n";
	map_cgi($H);

    my($sessionid, $argument, $path, $rest);
	my(@path);
	my($g, $action);

	unless (defined $Global::Standalone) {
		unless (defined $Global::Selector{$CGI::script_name}) {
			logGlobal("Call for undefined catalog from $CGI::script_name");
			return '';
		}
		$Vend::Cfg = $Global::Selector{$CGI::script_name};
		if (defined $Global::SelectorAlias{$CGI::script_name}) {
			my $real = $Global::SelectorAlias{$CGI::script_name};
			$Vend::Cfg->{VendURL} =~ s!$real!$CGI::script_name!;
			$Vend::Cfg->{SecureURL} =~ s!$real!$CGI::script_name!;
		}
	}
	else {
		$Vend::Cfg = $Global::Standalone;
	}

	if (defined $CGI::reconfigure_catalog) {

		my $build = $CGI::values{mv_build_static} ? 1 : '';
		return '' unless check_security(0, 1);

		logData("$Global::ConfDir/reconfig", $CGI::script_name, $build);
		logGlobal <<EOF;
Reconfiguring catalog on $CGI::script_name, INET mode:

	REMOTE_ADDR  $CGI::host
	REMOTE_USER  $CGI::user
	USER_AGENT   $CGI::useragent
	SCRIPT_NAME  $CGI::script_name
	PATH_INFO    $CGI::path_info
	BUILD        $CGI::reconfigure_catalog      

EOF
			
	}

	chdir $Vend::Cfg->{'VendRoot'} 
		or die "Couldn't change to $Vend::Cfg{'VendRoot'}: $!\n";
	set_file_permissions();
	umask $Vend::Cfg->{'Umask'};
	open_database();

    if (defined $CGI::query_string && $CGI::query_string ne '') {
		($sessionid, $argument, $rest) = split(/;/, $CGI::query_string);
		if ($CGI::cookie =~ /\bMV_SESSION_ID=(\w{8})
								: (
									(	\d{1,3}\.   # An IP ADDRESS
										\d{1,3}\.
										\d{1,3}\.
										\d{1,3})
									|	(\w+) )     # A user name
									
									\b/x) {
			$sessionid = $1 unless $rest eq 'RESET';
			$CGI::cookiehost = $3 || '';
			$CGI::cookieuser = $4 || '';
		}
		$Vend::Argument = $argument;
    }

	# Get a cookie if we have no session id (and its there)
    unless (defined $sessionid && $sessionid ne '') {
        if (defined $CGI::cookie and
			$CGI::cookie =~ /\bMV_SESSION_ID=(\w{8})
								: (
									(	\d{1,3}\.   # An IP ADDRESS
										\d{1,3}\.
										\d{1,3}\.
										\d{1,3})
									|	(\w+) )     # A user name
									\b/x)
		{
            $sessionid = $1;
            $CGI::cookiehost = $3 || '';
            $CGI::cookieuser = $4 || '';
        }
	}
#print("session='$sessionid' cookie='$CGI::cookie' chost='$CGI::cookiehost'\n") if $Global::DEBUG;

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
#print("session name='$Vend::SessionName'\n") if $Global::DEBUG;
	$Vend::Session->{id} = $Vend::SessionID;
	$Vend::Session->{arg} = $Vend::Argument;
	$Vend::Session->{source} = $rest if defined $rest && $rest =~ /[A-Za-z]/;
	$Vend::Session->{user} = $CGI::user;

    $path = $CGI::path_info;

    # If the cgi-bin program was invoked with no extra path info,
    # just display the catalog page.
    if (!defined $path || $path eq '' || $path eq '/') {
		do_catalog();
		release_session() if $Vend::HaveSession;
		close_database();
		undef $H;
		undef $Vend::Cfg;
		return 0;
    }

	$path =~ s:^/::;
    @path = split('/', $path, 2);
    $action = shift @path;

    if    ($action eq 'process')  { do_process();              }
    elsif ($action eq 'scan')     { do_scan($argument,@path);  } 
    elsif ($action eq 'search')   { do_search($argument);      } 
    elsif ($action eq 'order')    { do_order($argument,@path); }
    elsif ($action eq 'obtain')   {
									my($catalog,$page) = split '/', $path[0];
									do_order($argument,$page,$catalog);
								  } 
    else {
		# will try the on-the-fly page if it fails
		do_page($path, $argument);
    }

#print Global::DEBUG "end dispatch: ",  join " ", times(), "\n";
	release_session() if $Vend::HaveSession;
	close_database();
	undef $H;
	undef $Vend::Cfg;
#print Global::DEBUG "closed all: ",  join " ", times(), "\n";
	return 1;
}

## DEBUG

sub dontwarn {
	$Global::DBDtype +
	$Global::FullUrl +
	$Global::UserBuild +
	$Vend::ContentType +
	$Global::MailErrorTo +
	$File::Find::name +
	$File::Find::prune +

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
	return unless defined $CGI::post_input;
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
		} elsif (m/^-D(EBUG)?$/i) {
			$Global::DEBUG = 1;
		} elsif (m/^-s(erve)?$/i) {
			$Vend::mode = 'serve';
		} elsif (m/^-b(uild)?$/i) {
			$Vend::mode = 'build'
				unless $Vend::mode eq 'serve';
			die "-b(uild) requires argument\n" unless @ARGV;
			$Vend::CatalogToBuild{shift @ARGV} = 1;
		} elsif (m/^-f(iles)?$/i) {
			$Vend::BuildSpec = shift @ARGV;
			die "Missing file spec for -files option\n"
				if blank($Vend::BuildSpec);
		} elsif (m/^-o(utdir)?$/i) {
			$Vend::OutputDirectory = shift @ARGV;
			die "Missing file argument for -outdir option\n"
				if blank($Vend::OutputDirectory);
		} elsif (m/^-e(xclude)?$/i) {
			die "-e(xclude) requires argument\n" unless @ARGV;
			$Vend::CatalogToSkip{shift @ARGV} = 1;
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
		} elsif (m:^[^-]: and $Vend::mode eq 'build') {
			@Vend::BuildSpec = @ARGV;
			unshift @Vend::BuildSpec, $_;
			@ARGV = ();
		} else {
		    $? = 2;
			die "Unknown command line option: $_\n" .
				"(Use -help for a list).\n";
		}
	}
}

sub version {
	print "MiniVend version $VERSION Copyright 1995 Andrew M. Wilcox\n";
	print "                      Copyright 1996 Michael J. Heins\n";
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
     -exclude <name>  exclude catalog <name>
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

sub checkRegexSpeed {
	local($_) = 'x' x 10000;
	my $start = (times)[0];
	my $i;
	for($i = 0; $i < 5000; $i++) { }
	my $overhead = (times)[0] - $start;
	$start = (times)[0];
	for($i = 0; $i < 5000; $i++) { m/^/; }
	my $delta = (times)[0] - $start;
    my $naughty = $delta > $overhead * 10;
	#printf "It seems your code is %s (overhead=%.2f, delta=%.2f)\n",
    #        $naughty ? "contaminated":"clean", $overhead, $delta;
	if($naughty) {
		print q|It seems your code is contaminated by a library with $', $`, or $&.|;
		printf "\n (overhead=%.2f, delta=%.2f)", $overhead, $delta;
		print "\n";
		my $file;
		foreach $file (values %INC) {
			open CHECK, $file or die "open $file: $!\n";
			while (<CHECK>) {
				next unless /[^\$'+]\$['`&]/;
				print "\nHere is a possibly offending line in\n$file:\n\n";
				print;
			}
		}
		close CHECK;
		print <<EOF;

Try setting the environment variable PERL5LIB to the MiniVend directory
and see if it doesn't fix it:
	
	setenv PERL5LIB '$Global::VendRoot/lib'

	          or

	PERL5LIB='$Global::VendRoot/lib'; export PERL5LIB

Fixing this will improve the speed of MiniVend by a small percentage. If
you can't do it, don't worry about it.

EOF
	}
			
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

#print "\n##### DEBUG MODE ON #####\n" if $Global::DEBUG;

	umask 077;
	global_config();
	$| = 1;
	checkRegexSpeed;
	CATCONFIG: {
		my $i = 0;
		my ($g, $c);
		for (sort keys %Global::Catalog) {
			$g =  $Global::Catalog{$_};
			next if defined $Vend::CatalogToSkip{$g->{'name'}};
			print "Configuring catalog " . $g->{'name'} . '...';
			if (exists $Global::Selector{$g->{'script'}}) {
				warn "Two catalogs with same script name $g->{'script'}.\n";
				warn "Skipping catalog $g->{'name'}....\n\n";
				next;
			}
			
			eval {
			$c = config_named_catalog($g->{'script'}, " at server startup ($$)");
			};

			if ($@ or ! defined $c) {
				my $msg = $@;
				print "\n$msg\n\a$g->{'name'}: error in configuration. Skipping.\n";
				logGlobal
					"\n$msg\n\a$g->{'name'}: error in configuration. Skipping.\n";
				undef $Global::Selector{$g->{'script'}};
				next;
			}

			$Global::Selector{$g->{script}} = $c;

			# Set up aliases
			if (defined $g->{alias}) {
				for(@{$g->{alias}}) {
					if (exists $Global::Selector{$_}) {
						warn "Alias $_ used a second time, skipping.\n";
						next;
					}
					elsif (m![^\w-_:#/.]!) {
						warn "Bad alias $_, skipping.\n";
					}
					$Global::Selector{$_} = $c;
					$Global::SelectorAlias{$_} = $g->{'script'};
				}
			}
			
			if ($Vend::CatalogToBuild{$g->{name}}) {
				print <<EOF unless $c->{StaticDir};

Skipping static page build for $g->{name}, StaticDir not set.
EOF
				print "doing static page build\n";
				@Vend::BuildSpec = keys %{$c->{StaticPage}};
				$Vend::ScanCount = 0;

				$Vend::BuildingPages = 1;
				eval {
					build_all($g->{name});
				};
				undef $Vend::BuildingPages;

				if ($@) {
					my $msg = $@;
					print "\n$msg\n\a$g->{'name'}: error building pages. Skipping.\n";
					logGlobal
						"\n$msg\n$g->{'name'}: error building pages. Skipping.\n";
				}
			}
			print "done.\n";
		}
	}

	if ($Vend::mode eq 'serve') {
		# This should never return unless killed or an error
		# We set debug mode to -1 to communicate with the server
		# that no output is desired
		$0 = 'minivend';
		scrub_sockets();

        select STDERR; 
        $| = 1;
        select STDOUT;
        $| = 1;

        Vend::Server::run_server($Global::DEBUG);
	}
	elsif ($Vend::mode eq 'notify') {
		send_mail($Global::MailErrorTo, "MiniVend server not responding", <<EOF );
The MiniVend server serving the catalog named '$Vend::Cfg->{CatalogName}' did
not respond when called by the VLINK executable.

EOF
	}
	elsif ($Vend::mode eq 'build') {
				  # Empty, built in CATCONFIG
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

