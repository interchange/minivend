# $Id: ValidCC.pm,v 1.1 1996/08/09 22:20:51 mike Exp $
#
# ValidCC.pm - validate credit card numbers
#
# $Log: ValidCC.pm,v $
# Revision 1.1  1996/08/09 22:20:51  mike
# Initial revision
#
# Revision 1.4  1996/05/24 07:58:52  mike
# Tested and works with [if validcc ] tag
#
# Revision 1.2  1996/05/09 18:54:52  mike
# minor change ( 1; at end)
#
# Revision 1.1  1996/05/08 22:10:15  mike
# Initial revision
#
#
#
#
# Contributed by Bruce Albrecht, <bruce.albrecht@seag.fingerhut.com>
#
# Modified by Mike to make more forgiving in the parameters.

package Vend::ValidCC;
$VERSION = substr(q$Revision: 1.1 $, 10);
require 5.000;
require Exporter;
use Carp;

@ISA = qw(Exporter);
@EXPORT = qw(ValidCreditCard);

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

sub version {
	$Vend::ValidCC::VERSION;
}

1;

