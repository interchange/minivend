
package POSIX;
require Exporter;
@ISA = qw(Exporter);
@EXPORT		= qw( strftime ceil );

@EXPORT_OK	= qw( setsid localeconv LC_ALL setlocale );


use strict;

my @wday = ( qw! Sun Mon Tue Wed Thu Fri Sat Sun !);
my @weekday = ( qw! Sunday Monday Tuesday Wednesday
					Thursday Friday Saturday Sunday !);
my @mon = ( qw! Jan Feb Mar Apr May Jun
				Jul Aug Sep Oct Nov Dec !);
my @month = ( qw! January February March April May June
				July August September October November December !);

sub strftime {
	my ($fmt,$sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= @_;
	my %strf = (
			'%'	=> sub { "%" },
			a	=> sub { $wday[$wday] },
			A	=> sub { $weekday[$wday] },
			b	=> sub { $mon[$mon] },
			B	=> sub { $month[$mon] },
			c	=> sub { printf "%s %s %2s %02d:%02d:%02d %04d",
						 $wday[$wday], $mon[$mon], $mday,
						 $hour, $min, $sec, $year+1900 },
			d	=> sub { sprintf "%02d", $mday },
			H	=> sub { sprintf "%02d", $hour},
			I	=> sub { my $h;
						if ($hour == 0) {
							$h = 12;
						} elsif ( $hour > 12 ) {
							$h = $hour - 12;
						} else {
							$h = $hour;
						}
						sprintf "%02d", $h; },
			j	=> sub { sprintf "%03d", $yday + 1 },
			m	=> sub { sprintf "%02d", $mday },
			M	=> sub { sprintf "%02d", $min },
			p	=> sub { $hour > 11 ? "pm" : "am" },
			S	=> sub { sprintf "%02d", $sec },
			w	=> sub { $wday },
			x	=> sub { sprintf "%02d %s %04d",
							$mday, $mon[$mon], $year + 1900 },
			X	=> sub { sprintf "%02d:%02d:%02d", $hour, $min, $sec },
			y	=> sub { substr($year,-2) },
			Y	=> sub { sprintf "%04d", $year + 1900 },
	);
	$fmt =~ s/%(.)/&{$strf{$1}}() || "%$1"/eg;
	return $fmt;
}

sub ceil { 
	my ($num) = @_;
	return int($num) if int($num) == $num;
	return int($num) + 1;
}

sub LC_ALL {}

sub setlocale {}

sub localeconv {}

1;
