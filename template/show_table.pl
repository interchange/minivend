#!@@Perl_program@@
# show_table: display contents of Vend GDBM tables
#
# $Id: show_table.pl,v 1.2 1995/12/15 20:00:08 amw Exp $

use lib '@@Vend_lib@@';
use Getopt::Long;
use strict;
use Vend::Table::GDBM;

GetOptions("keys") or exit 1;
my ($file, $key) = @ARGV;
die <<'END' unless defined $file;
Usage: show_table <table>          show all records in table
       show_table <table> <key>    show the record for 'key'
       show_table -keys <table>    list all the keys in the table
END

if (! -f "$file.columns") {
    $file = "@@Data_directory@@/$file";
    die "I'm sorry, but I couldn't find '$file'\n" unless -f "$file.columns";
}

my $db = Vend::Table::GDBM->open_table($file);
my @columns = $db->columns();

if ($main::opt_keys) {
    while (($key) = $db->each_record()) {
        print "$key\n";
    }
}
elsif (defined $key) {
    if ($db->record_exists($key)) {
        show_record($key, $db->row($key));
    }
    else {
        print "There is no record with key '$key' in the table.\n";
    }
}
else {
    my @all;
    while (@all = $db->each_record()) {
        show_record(@all);
    }
}

sub show_record {
    my ($key, @fields) = @_;
    print "key: $key\n";
    my $i;
    for $i (0 .. $#columns) {
        print $columns[$i], ": ", $fields[$i], "\n";
    }
    print "\n";
}
