#$self = {
#	INSTALLPRIVLIB => '/usr/local/minivend/lib',
#	INSTALLARCHLIB => '/usr/local/minivend',
#};

use Config;
require 'scripts/initp.pl';

sub doit {
	my ($key) = @_;
	return $MV::Self->{$key} unless $key =~ /[a-z]/;
	return $Config{$key};
}

DOIT: {
	local ($/);
	local($_) = <<'_EoP_';
#!/usr/bin/perl
##!~_~perlpath~_~
#
# expireall - Expire all minivend catalogs
#

use lib '/usr/local/minivend/lib';
#use lib '~_~INSTALLPRIVLIB~_~';
use lib '/usr/local/minivend';
#use lib '~_~INSTALLARCHLIB~_~';

use Getopt::Std;

$VendRoot = $VendRoot || '/usr/local/minivend';
#$VendRoot = $VendRoot || '~_~INSTALLARCHLIB~_~';

## END CONFIGURABLE VARIABLES

BEGIN {
    ($VendRoot = $ENV{MINIVEND_ROOT})
        if defined $ENV{MINIVEND_ROOT};
}

my $query;

$USAGE = <<EOF;
Expire all listed MiniVend catalogs. Will read information from
either:

	$VendRoot/minivend.cfg
	$VendRoot/catalogs.list

usage: expireall [-r]

	-r    Use reorganize parameter in command

EOF

getopts('r') or die "$@\n$USAGE\n";

if ($opt_r) {
	$flag = '-r';
}

# Parse the minivend.cfg file to look for script/catalog info
PARSECFG: {
	my $file;
	my @cfglines;

	$file = "$VendRoot/minivend.cfg";
	open(MVCFG, $file) or die "Couldn't read $file: $!\n";
	while(<MVCFG>) { push(@cfglines, $_) if /^\s*catalog\s+/i }
	close MVCFG;

	eval {
		$file = "$VendRoot/catalogs.list";
		open(MVCFG, $file) or die "Couldn't read $file: $!\n";
		while(<MVCFG>) { push(@cfglines, $_) if /^\s*catalog\s+/i }
		close MVCFG;
	};
	eval {
		$file = "$VendRoot/active.catalogs";
		open(MVCFG, $file) or die "Couldn't read $file: $!\n";
		while(<MVCFG>) { push(@cfglines, $_) if /^\s*catalog\s+/i }
		close MVCFG;
		rename $file, "$file.bak";
	};
	my %seen;
	@cfglines = grep !$seen{$_}++, @cfglines;

	for(@cfglines) {
		next unless /^\s*catalog\s+([-\w_]+)/i;
		push @cats, $1;
	}

}

for(@cats) {
	system "$VendRoot/bin/expire $flag -c $_";
}

=head1 NAME

expireall -- Run Minivend expire on all catalogs

=head1 VERSION

$Id: expireall,v 1.2 2000/01/03 18:31:40 mike Exp $

=head1 DESCRIPTION

Skeleton POD to avoid make errors.

=cut
_EoP_
	s{.*\n(#(.*)~_~(\w+)~_~(.*))}{$2 . doit($3) . "$4\n$1"}eg;
	my $file = $0;
	$file =~ s/\.PL$//;
	open(OUT, ">$file") 
		or die "Create $file: $!\n";
	print OUT $_;
}
