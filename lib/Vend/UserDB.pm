#!/usr/bin/perl
#
# $Id: UserDB.pm,v 1.2 1998/03/21 12:07:46 mike Exp $
#
# Copyright 1997 by Michael J. Heins <mikeh@iac.net>
#
# **** ALL RIGHTS RESERVED ****

package Vend::UserDB;

$VERSION = substr(q$Revision: 1.2 $, 10);
$DEBUG = 0;

use vars qw! $VERSION $DEBUG @S_FIELDS @B_FIELDS @P_FIELDS %S_to_B %B_to_S!;

use lib '/a/lib';
use Carp;
use Vend::Data;
use Vend::Util;
use strict;

=head1 NAME

UserDB.pm -- MiniVend User Database Functions

=head1 SYNOPSIS

userdb $function, %options

=head1 DESCRIPTION

The MiniVend user database saves information for users, including shipping,
billing, and preference information.  It allows the user to return to a
previous session without the requirement for a "cookie" or other persistent
session information.

It is object-oriented and called via Perl subroutine. The main software 
is contained in a module, and is called from MiniVend with a GlobalSub.
The GlobalSub would take the form:

	GlobalSub <<EOF
	sub userdb {
		my($function, %options) = @_;
		use Vend::UserDB;
		$obj = new Vend::User->DB %options;
		$obj->$function
			or return $obj->{ERROR};
		return $obj->{MESSAGE};
	}

It restores and manipulates the form values normally stored in the user session
values -- the ones set in forms and read through the C<[value variable]> tags.
A special function allows saving of shopping cart contents.

The preference, billing, and shipping information is keyed so that different
sets of information may be saved, providing and "address_book" function that
can save more than one shipping and/or billing address. The set to restore
is selected by the form values C<s_nickname>, C<b_nickname>, and C<p_nickname>.

=cut

=head1 METHODS

User login:

    $obj->login();        # Form values are
                          # mv_username, mv_password

Create account:

    $obj->new_account();  # Form values are
                          # mv_username, mv_password, mv_verify

Change password:

    $obj->change_pass();  # Form values are
                          # mv_username, mv_password, mv_verify(new)

Get, set user information:

    $obj->get_values();
    $obj->set_values();

Save, restore filed user information:

    $obj->get_shipping();
    $obj->set_shipping();
 
    $obj->get_billing();
    $obj->set_billing();
 
    $obj->get_preferences();
    $obj->set_preferences();

    $obj->get_carts();
    $obj->set_carts();

=head2 Shipping Address Book

The shipping address book saves information relevant to shipping the
order. In its simplest form, this can be the only address book needed.
By default these form values are included:

	s_nickname
	name
	address
	city
	state
	zip
	country
	phone_day
	mv_shipmode

The values are saved with the $obj->set_shipping() method and restored 
with $obj->get_shipping. A list of the keys available is kept in the
form value C<address_book>, suitable for iteration in an HTML select
box or in a set of links.

=cut

@S_FIELDS = ( 
qw!	s_nickname	name		address		city		state		zip
	country		phone_day	mv_shipmode !
);

=head2 Accounts Book

The accounts book saves information relevant to billing the
order. By default these form values are included:

	b_nickname
	b_name
	b_address
	b_city
	b_state
	b_zip
	b_country
	b_phone
	mv_credit_card_type
	mv_credit_card_exp_month
	mv_credit_card_exp_year
	mv_credit_card_info

The values are saved with the $obj->set_billing() method and restored 
with $obj->get_billing. A list of the keys available is kept in the
form value C<accounts>, suitable for iteration in an HTML select
box or in a set of links.

=cut

@B_FIELDS = ( 
qw!	b_nickname	b_name		b_address	b_city		b_state		b_zip
	b_country	b_phone
	mv_credit_card_type	mv_credit_card_exp_month	mv_credit_card_exp_year
	mv_credit_card_info
	!
);

=head2 Preferences

Preferences are miscellaneous session information. They include
by default the fields C<email>, C<fax>, C<phone_night>,
and C<fax_order>. The field C<p_nickname> acts as a key to select
the preference set.

=cut

@P_FIELDS = qw ( p_nickname email fax phone_night fax_order );

%S_to_B = ( 
qw!
s_nickname	b_nickname
name		b_name
address		b_address
city		b_city
state		b_state
zip			b_zip
country		b_country
phone_day	b_phone
!
);

@B_to_S{values %S_to_B} = keys %S_to_B;

sub new {

	my ($class, %options) = @_;

	my $values = $options{'values'} || $Vend::Session->{'values'};

	my $self = {
			USERNAME  	=> $options{username}	|| $CGI::values{mv_username} || '',
			PASSWORD  	=> $options{password}	|| $CGI::values{mv_password} || '',
			VERIFY  	=> $options{verify}		|| $CGI::values{mv_verify}	 || '',
			NICKNAME   	=> $options{nickname}	|| '',
			LAST   		=> '',
			VALUES		=>	$values,
			CARTS		=>	$Vend::Session->{carts},
			PRESENT		=>	{ },
			DB_ID		=>	$options{database} || 'userdb',
			LOCATION	=>	{
						USERNAME	=> $options{bill_field} || 'user',
						BILLING		=> $options{bill_field} || 'accounts',
						SHIPPING	=> $options{addr_field} || 'address_book',
						PREFERENCES	=> $options{pref_field} || 'preferences',
						CARTS		=> $options{cart_field} || 'carts',
						PASSWORD	=> $options{pass_field} || 'password',
						LAST		=> $options{time_field} || 'time',
							},
			STATUS		=>		0,
			ERROR		=>		'',
		};

	bless $self;

	return $self if $options{no_open};

	set_db($self) or croak "user database $self->{DB_ID} does not exist.\n";

	return $self;
}

sub create_db {
	my(%options) = @_;
	my $user = new Vend::UserDB no_open => 1, %options;

	my(@out);
	push @out, $user->{LOCATION}{USERNAME};
	push @out, $user->{LOCATION}{PASSWORD};
	push @out, $user->{LOCATION}{LAST};
	push @out, @S_FIELDS, @B_FIELDS, @P_FIELDS;
	push @out, $user->{LOCATION}{SHIPPING};
	push @out, $user->{LOCATION}{BILLING};
	push @out, $user->{LOCATION}{PREFERENCES};

	my $csv = 0;
	my $delimiter = $options{delimiter} || "\t";
	if($delimiter =~ /csv|comma/i) {
		$csv = 1;
		$delimiter = '","';
	}
	my $separator = $options{separator} || "\n";

	print '"' if $csv;
	print join $delimiter, @out;
	print '"' if $csv;
	print $separator;
	if ($options{verbose}) {
		my $msg;
		$msg = "Delimiter=";
		if(length $delimiter == 1) {
			$msg .= sprintf '\0%o', ord($delimiter);
		}
		else {
			$msg .= $delimiter;
		}
		$msg .= " ";
		$msg .= "Separator=";
		if(length $separator == 1) {
			$msg .= sprintf '\0%o', ord($separator);
		}
		else {
			$msg .= $separator;
		}
		$msg .= "\nNicknames: ";
		$msg .= "SHIPPING=$S_FIELDS[0] ";
		$msg .= "BILLING=$B_FIELDS[0] ";
		$msg .= "PREFERENCES=$P_FIELDS[0] ";
		$msg .= "\nFields:\n";
		$msg .= join "\n", @out;
		$msg .= "\n\n";
		my $type;
		my $ext = '.txt';
		SWITCH: {
			$type = 4, $ext = '.csv', last SWITCH if $csv;
			$type = 6, last SWITCH if $delimiter eq "\t";
			$type = 5, last SWITCH if $delimiter eq "|";
			$type = 3, last SWITCH
				if $delimiter eq "\n%%\n" && $separator eq "\n%%%\n";
			$type = 2, last SWITCH
				if $delimiter eq "\n" && $separator eq "\n\n";
			$type = '?';
		}

		my $id = $user->{DB_ID};
		$msg .= "Database line in catalog.cfg should be:\n\n";
		$msg .= "Database $id $id.txt $type";
		warn "$msg\n";
	}
	1;
}
	
	

sub set_db {
	my($self, $database) = @_;

	$database = $self->{DB_ID}		unless $database;

	$Vend::WriteDatabase{$database} = 1;

	my $db = database_exists_ref($database);
	return undef unless defined $db;

	$db = $db->ref();
	my @fields = $db->columns();
	my %ignore;

	my @final;

	for(values %{$self->{LOCATION}}) {
		$ignore{$_} = 1;
	}

	for(@fields) {
		if(defined $ignore{$_}) {
			$self->{PRESENT}->{$_} = 1;
			next;
		}
		push @final, $_;
	}

	$self->{DB_FIELDS} = \@final;
	$self->{DB} = $db;
}

# Sets location map, returns old value
sub map_field {
	my ($self, $location, $field) = @_;
	if(! defined $field) {
		return $self->{LOCATION}->{$location};
	}
	else {
		my $old = $self->{LOCATION}->{$field};
		$self->{LOCATION}->{$location} = $field;
		return $old;
	}
}

sub get_values {
	my($self, @fields) = @_;

	if(! @fields) {
		@fields = $self->{DB}->columns();
	}

	unless ( $self->{DB}->record_exists($self->{USERNAME}) ) {
		$self->{ERROR} = "username $self->{USERNAME} does not exist.";
		return undef;
	}

	my %ignore;

	for(values %{$self->{LOCATION}}) {
		$ignore{$_} = 1;
	}

	for(@fields) {
		if($ignore{$_}) {
			$self->{PRESENT}->{$_} = 1;
			next;
		}
		$self->{VALUES}->{$_} = $self->{DB}->field($self->{USERNAME}, $_);	
	}

	for(qw!SHIPPING BILLING PREFERENCES CARTS!) {
		my $f = $self->{LOCATION}->{$_};
		if ($self->{PRESENT}->{$f}) {
			my $s = eval $self->{DB}->field($self->{USERNAME}, $f);
			$self->{VALUES}->{$f} = join " ", sort keys %$s;
		}
	}
	
	1;
}

sub set_values {
	my($self, @fields) = @_;

	my $user = $self->{USERNAME};

	unless ( $self->{DB}->record_exists($self->{USERNAME}) ) {
		$self->{ERROR} = "username $self->{USERNAME} does not exist.";
		return undef;
	}
	for( @{$self->{DB_FIELDS}} ) {
# DEBUG
#Vend::Util::logDebug
#("saving $_ as $self->{VALUES}->{$_}\n")
#	if ::debug(0x1);
# END DEBUG
		$self->{DB}->set_field($user, $_, $self->{VALUES}->{$_})
			if defined $self->{VALUES}->{$_};	
	}
	1;
}

sub set_billing {
	my($self) = @_;
	my @fields = @B_FIELDS;
	$self->set_hash('BILLING', @B_FIELDS );
}

sub set_shipping {
	my($self) = @_;
	my @fields = @S_FIELDS;
	$self->set_hash('SHIPPING', @S_FIELDS );
}

sub set_preferences {
	my($self) = @_;
	$self->set_hash('PREFERENCES', @P_FIELDS );
}

sub get_billing {
	my($self) = @_;
	my @fields = @B_FIELDS;
	$self->get_hash('BILLING', @B_FIELDS );
}

sub get_shipping {
	my($self) = @_;
	my @fields = @S_FIELDS;
	$self->get_hash('SHIPPING', @S_FIELDS );
}

sub get_preferences {
	my($self) = @_;
	$self->get_hash('PREFERENCES', @P_FIELDS );
}

sub set_hash {
	my($self, $name, @fields) = @_;

	die "no fields?" unless @fields;
	die "no name?" unless $name;

	$self->get_hash($name) unless ref $self->{$name};

	my $nick_field = shift @fields;
	my $nick = $self->{NICKNAME} || $self->{VALUES}->{$nick_field};

	die "no nickname?" unless $nick;


	$self->{$name}{$nick} = {} unless defined $self->{$name}{$nick};

	for(@fields) {
		$self->{$name}{$nick}{$_} = $self->{VALUES}->{$_};
	}

	my $field_name = $self->{LOCATION}->{$name};
	unless($self->{PRESENT}->{$field_name}) {
		$self->{ERROR} = '$field_name field not present to set $name';
		return undef;
	}

	my $s = uneval $self->{$name};

	Vend::Data::set_field( $self->{DB}, $self->{USERNAME}, $field_name, $s);

	return $s;
}

sub get_hash {
	my($self, $name, @fields) = @_;

	my $field_name = $self->{LOCATION}->{$name};
	my ($nick, $s);

	eval {
		die "no name?"					unless $name;
		die "$field_name field not present to get $name\n"
										unless $self->{PRESENT}->{$field_name};

		$s = $self->{DB}->field( $self->{USERNAME}, $field_name);

		if($s) {
			$self->{$name} = eval $s;
		}
		else {
			$self->{$name} = {};
		}

		die "eval failed?"				unless ref $self->{$name};
	};

	if($@) {
		$self->{ERROR} = $@;
		return undef;
	}

	return unless @fields;

	eval {
		my $nick_field = shift @fields;
		$nick = $self->{NICKNAME} || $self->{VALUES}->{$nick_field};
		die "no nickname?" unless $nick;
	};

	if($@) {
		$self->{ERROR} = $@;
		return undef;
	}


	$self->{$name}->{$nick} = {} unless defined $self->{$name}{$nick};

	for(@fields) {
		$self->{VALUES}{$_} = $self->{$name}{$nick}{$_} || '';
	}
	return $self->{$name}{$nick};
}

sub login {
	my $self;

	$self = shift
		if ref $_[0];

	my(%options) = @_;
	
	eval {
		unless($self) {
			$self = new Vend::UserDB %options;
		}

		die "Username does not exist.\n"
			unless $self->{DB}->record_exists($self->{USERNAME});
		my $db_pass = $self->{DB}->field(
						$self->{USERNAME},
						$self->{LOCATION}{PASSWORD},
						);
		die "Password mismatch.\n"
			unless $self->{PASSWORD} eq $db_pass;

		$self->get_values();
	};

	if($@) {
		if(defined $self) {
			$self->{ERROR} = $@;
		}
		else {
			logError "Vend::UserDB error: $@\n";
		}
		return undef;
	}
	
	1;
}

sub new_account {

	my $self;

	$self = shift
		if ref $_[0];

	my(%options) = @_;
	
	eval {
		unless($self) {
			$self = new Vend::UserDB %options;
		}

		die "Bad object.\n" unless defined $self;

		die "Username already exists.\n"
			if $self->{DB}->record_exists($self->{USERNAME});
		die "Must enter at least 4 characters for password.\n"
			unless length($self->{PASSWORD}) > 3;
		die "Password and check value don't match.\n"
			unless $self->{PASSWORD} eq $self->{VERIFY};
		my $pass = Vend::Data::set_field(
						$self->{DB},
						$self->{USERNAME},
						$self->{LOCATION}{PASSWORD},
						$self->{PASSWORD}
						);
		die "Database access error.\n" unless defined $pass;
		$self->set_values();
	};

	if($@) {
		if(defined $self) {
			$self->{ERROR} = $@;
		}
		else {
			logError "Vend::UserDB error: $@\n";
		}
		return undef;
	}
	
	1;
}

sub get_cart {
	my($self, $from, $to) = @_;

	my $field_name = $self->{LOCATION}->{CARTS};
	my ($cart,$d);

	eval {
		die "no from cart name?"				unless $from;
		die "no to cart name?"					unless $to;
		die "$field_name field not present to get $from\n"
										unless $self->{PRESENT}->{$field_name};

		my $s = $self->{DB}->field( $self->{USERNAME}, $field_name);

		die "no value in source cart." unless $s;

		$d = eval $s;

		die "eval failed?"				unless ref $d;
	};

	if($@) {
		$self->{ERROR} = $@;
		return undef;
	}


	$self->{CARTS}->{$to} = $d->{$from};

}

sub set_cart {
	my($self, $from, $to) = @_;

	my $field_name = $self->{LOCATION}->{CARTS};
	my ($cart,$s,$d);

	eval {
		die "no from cart name?"				unless $from;
		die "no to cart name?"					unless $to;
		die "$field_name field not present to save $from\n"
										unless $self->{PRESENT}->{$field_name};

		$s = eval $self->{DB}->field( $self->{USERNAME}, $field_name);

		if($s) {
			$d = eval $s;
		}
		else {
			$d = {};
		}

		die "eval failed?"				unless ref $d;

		$d->{$to} = $self->{CARTS}->{$from};

		$s = uneval $d;

	};

	if($@) {
		$self->{ERROR} = $@;
		return undef;
	}

	Vend::Interpolate::set_field( $self->{DB}, $self->{USERNAME}, $field_name, $s);

}

1;
