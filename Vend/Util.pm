# $Id: Util.pm,v 1.6 1996/01/30 23:30:56 amw Exp $

package Vend::Util;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(combine blank wrap fill_table file_modification_time);

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


=head2 C<wrap($str, $width)>

Wraps the passed string to fit the specified maximum width.  An array
of lines, each $width or less, is returned.  The line is wrapped at a
space if one exists in the string.

(The function could also wrap on other characters, such as a dash, but
currently does not).

=cut

sub wrap {
    my ($str, $width) = @_;
    my @a = ();
    my ($l, $b);

    for (;;) {
        $str =~ s/^ +//;
        $l = length($str);
        last if $l == 0;
        if ($l <= $width) {
            push @a, $str;
            last;
        }
        $b = rindex($str, " ", $width - 1);
        if ($b == -1) {
            push @a, substr($str, 0, $width);
            $str = substr($str, $width);
        }
        else {
            push @a, substr($str, 0, $b);
            $str = substr($str, $b + 1);
        }
    }
    return @a;
}


sub fill_table {
    my ($widths, $aligns, $strs, $prefix, $separator, $postfix, $push_down) = @_;
    my ($x, @text, $y, $align, $cell, $l, $width);

    my $last_x = $#$widths;
    my $last_y = -1;
    my $texts = [];

    for $x (0 .. $#$widths) {
        die "Width value not specified: $widths->[$x]\n"
            unless $widths->[$x] > 0;
        @text = wrap($strs->[$x], $widths->[$x]);
        $last_y = $#text if $#text > $last_y;
        $texts->[$x] = [@text];
    }


    my ($column, $this_height, $fill, $i);
    if ($push_down) {
        for $x (0 .. $last_x) {
            $column = $texts->[$x];
            $this_height = $#$column;
            $fill = ' ' x $widths->[$x];
            for $i (1 .. $last_y - $this_height) {
                unshift @$column, $fill;
            }
        }
    }

    for $y (0 .. $last_y) {
        for $x (0 .. $last_x) {
            $width = $widths->[$x];
            if ($y > $#{$texts->[$x]}) {
                $cell = ' ' x $width;
            }
            else {
                $align = $aligns->[$x];
                $cell = $texts->[$x][$y];
                $cell =~ s/^ +//;
                $cell =~ s/ +$//;
                $l = length($cell);
                if ($l < $width) {
                    if ($align eq '<') {
                        $cell .= ' ' x ($width - $l);
                    }
                    elsif ($align eq '|') {
                        $l = length($cell);
                        $cell = ' ' x (($width - $l) / 2) . $cell;
                        $cell .= ' ' x ($width - length($cell));
                    }
                    elsif ($align eq '>') {
                        $cell = ' ' x ($width - $l) . $cell;
                    }
                    else { die "Unknown alignment specified: $align" }
                }
            }
            $texts->[$x][$y] = $cell;
        }
    }

    my $r = '';
    for $y (0 .. $last_y) {
        $r .= $prefix;
        for $x (0 .. $last_x - 1) {
            $r .= $texts->[$x][$y] . $separator;
        }
        $r .= $texts->[$last_x][$y] . $postfix;
    }
    return $r;
}

sub file_modification_time {
    my ($fn) = @_;
    my @s = stat($fn) or die "Can't stat '$fn': $!\n";
    return $s[9];
}

1;
