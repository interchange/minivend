# $Id: ValidCC.pm,v 1.3 1996/10/30 04:22:28 mike Exp $
#
# ValidCC.pm - validate credit card numbers
#
# Contributed by Bruce Albrecht, <bruce.albrecht@seag.fingerhut.com>
#
# Modified by Mike to make more forgiving in the parameters.

package Vend::ValidCC;
$VERSION = substr(q$Revision: 1.3 $, 10);
require 5.000;
require Exporter;
use Carp;

# AUTOLOAD
#use AutoLoader;
#@ISA = qw(Exporter Autoloader);
#*AUTOLOAD = \&AutoLoader::AUTOLOAD;
# END AUTOLOAD

# NOAUTO
@ISA = qw(Exporter);
# END NOAUTO

@EXPORT = qw(ValidCreditCard encrypt_cc encrypt_standard_cc);

=head1 NAME

ValidCreditCard - verify that a credit card number is valid and not expired

=head1 SYNOPSIS

	use ValidCreditCard;
	ValidCreditCard CreditCardType CreditCardNumber ExpirationDate

=head1 DESCRIPTION

CreditCardType is a string starting with one the following characters: 
A(merican Express), D(iscover), 
M(astercard), or V(isa). Lower case is acceptable. Any characters after the 
first are ignored.

CreditCardNumber is a 13-16 digit number with or without embedded spaces.
It will be assembled from chunks of numbers that dont include a / or 
a -.

Expiration date is string of the form MM/YY, where MM is a one or two 
digit string representing the month, and YY is a 1-4 digit string 
representing the year. Years 00-70 are assumed to be years 20xx, and
years 71-99 are assumed to be years 19xx.

ValidCardCard returns 1 if valid, 0 otherwise. A credit card is valid
if it passes a checksum algorithm and is not expired. It does not 
determine if the card has been issued, that the credit limit has not
been exceeded, etc.

=head1 AUTHOR

Bruce Albrecht (bruce@zuhause.mn.org)

=cut

# AUTOLOAD
#1;
#__END__
# END AUTOLOAD


sub ValidCreditCard
{
	my($mess) = join " ", @_;
	$mess =~ s:[^\sA-Za-z0-9/]::g ;
	my @tok = split /\s+/, $mess;
	my($card_type,$the_card,$expiration_date) = ('', '', '');
	for(@tok) {
		$card_type .= $_ if /^[A-Za-z]/;
		$the_card .= $_ if /^\d+$/;
		$expiration_date = $_ if m:/: ;
	}

	my ($index, $digit, $product);
	my ($month, $year, @now);
	my $multiplier = 2;        # multiplier is either 1 or 2
	my $the_sum = 0;

	return 0 if length($the_card) == 0;

	# check card type

	return 0 unless $card_type =~ /^[admv]/i;

	return 0 if ($card_type =~ /^v/i && substr($the_card, 0, 1) ne "4") ||
			($card_type =~ /^m/i && substr($the_card, 0, 1) ne "5") ||
				($card_type =~ /^d/i && substr($the_card, 0, 4) ne "6011") ||
					($card_type =~ /^a/i && substr($the_card, 0, 2) ne "34" && 
					 substr($the_card, 0, 2) ne "37");

	# check expiration date

	($month, $year) = split('/', $expiration_date);
	return 0 if $month !~ /^\d+$/ || $year !~ /^\d+$/;
	return 0 if $month <1 || $month > 12;
	$year += ($year < 70) ? 2000 : 1900 if $year < 1900;
	@now=localtime();
	$now[5] += 1900;
	return 0 if ($year < $now[5]) || ($year == $now[5] && $month <= $now[4]);

	# check for valid number of digits.

    $the_card =~ s/\s//g;    # strip out spaces
    return 0 if $the_card !~ /^\d+$/;

    $digit = substr($the_card, 0, 1);
    $index = length($the_card)-1;
    return 0 if ($digit == 3 && $index != 14) ||
        ($digit == 4 && $index != 12 && $index != 15) ||
            ($digit == 5 && $index != 15) ||
                ($digit == 6 && $index != 13 && $index != 15);

    # calculate checksum.
    for ($index--; $index >= 0; $index --)
    {
        $digit=substr($the_card, $index, 1);
        $product = $multiplier * $digit;
        $the_sum += $product > 9 ? $product - 9 : $product;
        $multiplier = 3 - $multiplier;
    }
    $the_sum %= 10;
    $the_sum = 10 - $the_sum if $the_sum;

    # return whether checksum matched.

    $the_sum == substr($the_card, -1);

}

# Encrypts a credit card number with DES or the like
# Prefers internal Des module, if was included
sub encrypt_cc {
	my($enclair) = @_;
	my($encrypted, $status, $cmd);
	my $firstline = 0;
	my $infile    = 0;

	$cmd = $Vend::Cfg->{'EncryptProgram'};

	# This is the internal function, will return the value
	# only if it was found. Takes the IVEC from the first
	# eight characters of the encrypted password
	if (defined @Des::EXPORT and $cmd =~ /^internal/i ) {
		my($password) = $Vend::Cfg->{'Password'} || return undef;
		my($ivec) = $Vend::Cfg->{'Pw_Ivec'} || return undef;
		my $key = string_to_key($password);
		my $sched = set_key($key);
		$encrypted = pcbc_encrypt($enclair,undef,$sched,$ivec);
		return $encrypted;
	}

	#Substitute the password
	unless ($cmd =~ /\bpgp\b/ or $cmd =~ s/%p/$password/ ) {
		$firstline = 1;
	}

	my $tempfile = $Vend::SessionID . '.cry';

	#Substitute the filename
	if ($cmd =~ s/%f/$tempfile/) {
		$infile = 1;
	}

	# Want the whole file
	local($/) = undef;

	# Send the CC to a tempfile if incoming
	if($infile) {
		open(CARD, ">$tempfile") ||
			die "Couldn't write $tempfile: $!\n";
		# Put the cardnumber there, and maybe password first
		print CARD "$password\n" if $firstline;
		print CARD $enclair;
		close CARD;

		# Encrypt the string, but key on arg line will be exposed
		# to ps(1) for systems that allow it
		open(CRYPT, "$cmd |") || die "Couldn't fork: $!\n";
		chomp($encrypted = <CRYPT>);
		close CRYPT;
		$status = $?;
	}
	else {
		open(CRYPT, "| $cmd >$tempfile ") || die "Couldn't fork: $!\n";
		print CRYPT $enclair;
		close CRYPT;
		$status = $?;

		open(CARD, $tempfile) || warn "open $tempfile: $!\n";
		$encrypted = <CARD>;
		close CARD;
	}

	unlink $tempfile;

	# This means encryption failed
	if( $status != 0 ) {
		::logGlobal("Encryption error: $!");
		return undef;
	}

	$encrypted;
}

# Takes a reference to a hash (usually %CGI::values) that contains
# the following:
# 
#    mv_credit_card_number      The actual credit card number
#    mv_credit_card_exp_all     A combined expiration MM/YY
#    mv_credit_card_exp_month   Month only, used if _all not present
#    mv_credit_card_exp_year    Year only, used if _all not present
#    mv_credit_card_type        A = Amex, D = Discover, etc. Attempts
#                               to guess from number if not there

sub encrypt_standard_cc {
	my($ref) = @_;
	my($valid, $info);

	my $month	= $ref->{mv_credit_card_exp_month}	|| '';
	my $type	= $ref->{mv_credit_card_type}		|| '';
	my $num		= $ref->{mv_credit_card_number}		|| '';
	my $year	= $ref->{mv_credit_card_exp_year}	|| '';
	my $all		= $ref->{mv_credit_card_exp_all}	|| '';

	for ( qw (	mv_credit_card_type		mv_credit_card_number
				mv_credit_card_exp_year	mv_credit_card_exp_month
				mv_credit_card_exp_all  ))
	{
		next unless defined $ref->{$_};
		delete $ref->{$_};
	}

	# remove unwanted chars from card number
	#$num =~ tr/0-9//cd;

	# error will be pushed on this if present
	@return = (
				0,			# 0- Whether it is valid
				'',			# 1- Encrypted credit card information
				'',			# 2- Month
				'',			# 3- Year
				'',			# 4- Month/year
				'',         # 5- type
	);

	# Get the type
	unless ( $type ) {
		($num =~ /^3/) and $type = 'amex';
		($num =~ /^4/) and $type = 'visa';
		($num =~ /^5/) and $type = 'mc';
		($num =~ /^6/) and $type = 'discover';
	}

	if ($type) {
		$return[5] = $type;
	}
	else {
		push @return, "Can't figure out credit card type.";
		return @return;
	}

	# Get the expiration
	if ($all =~ m!(\d\d?)[-/](\d\d)(\d\d)?! ){
		$month = $1;
		$year  = "$2$3";
	}
	elsif ($month >= 1  and $month <= 12 and $year) 
	{
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
		push @return, "Can't figure out credit card expiration.";
		return @return;
	}

	#$num =~ tr/\d//cd;

	unless ($valid = ValidCreditCard ($type,$num,$all) ) {
		push @return, "Credit card number, type, or expiration not valid.";
		return @return;
	}

	$return[0] = $valid;

	$info = encrypt_cc "$type $num $all\n";

	unless (defined $info) {
		push @return, "Credit card encryption failed.";
		$return[0] = 0;
		return @return;
	}
	$return[1] = $info;

	return @return;

}

sub version {
	$Vend::ValidCC::VERSION;
}

1;

