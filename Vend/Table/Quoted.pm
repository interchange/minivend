# $Id: Quoted.pm,v 1.1 1996/08/09 22:21:11 mike Exp $
#
# From and presumably copyright 1996 Andrew M. Wilcox
#
# $Log: Quoted.pm,v $
# Revision 1.1  1996/08/09 22:21:11  mike
# Initial revision
#
# Revision 1.1  1996/04/22 05:24:17  mike
# Initial revision
#
#
package Vend::Table::Quoted;
$VERSION = substr(q$Revision: 1.1 $, 10);
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(read_quoted_fields);

use strict;

my $white = ' \t';

sub read_quoted_fields {
    my ($filehandle) = @_;
    local ($_, $.);

    while(<$filehandle>) {
        chomp;
        s/[\000\r\cZ]+//g;           # ms-dos cruft
        next if m/^[$white]*$/o;     # skip blank lines
        return parse($_, $.);
    }
    return ();
}

sub parse {
    local $_ = $_[0];
    my $linenum = $_[1];

    my $expect = 1;
    my @a = ();
    my $x;
    while ($_ ne '') {
        if    (m# \A ([$white]+) (.*) #ox) { }
        elsif (m# \A (,[$white]*) (.*) #ox) {
            push @a, '' if $expect;
            $expect = 1;
        }
        elsif (m# \A ([^",$white] (?:[$white]* [^,$white]+)*) (.*) #ox) {
            push @a, $1;
            $expect = 0;
        }
        elsif (m# \A " ((?:[^"] | (?:""))*) " (?!") (.*) #x) {
            ($x = $1) =~ s/""/"/g;
            push @a, $x;
            $expect = 0;
        }
        elsif (m# \A " #x) {
            die "Unterminated quote at line $linenum\n";
        }
        else { die "Can't happen: '$_'" }
        $_ = $2;
    }
    $expect and push @a, '';
    return @a;
}

sub version { $Vend::Table::Quoted::VERSION }

eval join('',<DATA>) || die $@ unless caller();
1;

__DATA__

my @tests =
  (
   '' => [''],
   ',' => ['', ''],
   'a' => ['a'],
   ',a' => ['', 'a'],
   'a,' => ['a', ''],
   ',,' => ['', '', ''],
   ' a , b , c ' => ['a', 'b', 'c'],
   '""' => [''],
   '" a , b "' => [' a , b '],
   "1,\t2, 3 " => ['1', '2', '3'],
   ' a b c , d e f ' => ['a b c', 'd e f'],
   ' " a"",b ",c' => [' a",b ', 'c'],
   );

my $errors = 0;
my ($in, $out, @a, @b);
while (($in, $out) = splice(@tests, 0, 2)) {
    @a = @$out;
    @b = parse($in);
    if (@a != @b or grep($_ ne shift @a, @b)) {
        print "'$in' parsed as ",
              join(' ',map("<$_>",@b)),
              " instead of the expected ",
              join(' ',map("<$_>",@$out)), "\n";
        ++$errors;
    }
}
print "All tests successful\n" unless $errors;
1;
