# $Id: Util.pm,v 1.8 1996/03/12 16:19:34 amw Exp $

package Vend::Util;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(combine blank wrap fill_table file_modification_time);
@EXPORT_OK = qw(append_field_data append_to_file csv field_line random_string
                tabbed);

use strict;

# # from Larry
# sub tainted {
#     ! eval { join('',@_), kill 0; 1; };
# }
 
## random_string

# leaving out 0, O and 1, l
my $random_chars = "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

# Return a string of random characters.

sub random_string {
    my ($len) = @_;
    $len = 8 unless $len;
    my ($r, $i);

    $r = '';
    for ($i = 0;  $i < $len;  ++$i) {
	$r .= substr($random_chars, int(rand(length($random_chars))), 1);
    }
    $r;
}


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


# Returns its arguments as a string of tab-separated fields.  Tabs in the
# argument values are converted to spaces.

sub tabbed {        
    return join("\t", map { $_ = '' unless defined $_;
                            s/\t/ /g;
                            $_;
                          } @_);
}


# Returns its arguments as a string of comma separated and quoted
# fields.  Double quotes in the argument values are converted to
# two double quotes.

sub csv {
    return join(',', map { $_ = '' unless defined $_;
                           s/\"/\"\"/g;
                           '"'. $_ .'"';
                         } @_);
}


# Appends the string $value to the end of $filename.  The file is opened
# in append mode, and the string is written in a single system write
# operation, so this function is safe in a multiuser environment even
# without locking.

sub append_to_file {
    my ($filename, $value) = @_;

    open(OUT, ">>$filename") or die "Can't append to '$filename': $!\n";
    syswrite(OUT, $value, length($value))
        == length($value) or die "Can't write to '$filename': $!\n";
    close(OUT);
}

# Converts the passed field values into a single line in Ascii delimited
# format.  Two formats are available, selected by $format:
# "comma_separated_values" and "tab_separated".

sub field_line {
    my $format = shift;

    return csv(@_) . "\n"    if $format eq 'comma_separated_values';
    return tabbed(@_) . "\n" if $format eq 'tab_separated';

    die "Unknown format: $format\n";
}

# Appends the passed field values onto the end of $filename in a single
# system operation.

sub append_field_data {
    my $filename = shift;
    my $format = shift;

    append_to_file($filename, field_line($format, @_));
}
    
1;
