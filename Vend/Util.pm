# $Id: Util.pm,v 1.5 1995/11/28 18:35:09 amw Exp $

package Vend::Util;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(combine blank);

use strict;

# # from Larry
# sub tainted {
#     ! eval { join('',@_), kill 0; 1; };
# }
 
sub combine {
    my $r;

    if (@_ == 1) {
	$_[0];
    } elsif (@_ == 2) {
	"$_[0] and $_[1]";
    } else {
	$r = $_[0];
	foreach (1 .. $#_ - 1) {
	    $r .= ", $_[$_]";
	}
	$r .= ", and " . $_[$#_];
	$r;
    }
}

sub blank {
    my ($x) = @_;
    return (!defined($x) or $x eq '');
}

1;
