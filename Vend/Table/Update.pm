package Vend::Table::Update;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw();

use strict;
use Vend::Table::GDBM;
use Vend::Table::Quoted;
use Vend::Util;

sub import_table {
    my ($source, $table) = @_;

    die "The source file '$source' does not exist\n" unless -e $source;

    return if -e $table
              and file_modification_time($source) <=
                  file_modification_time($table);

    print "Importing product table '$source'\n";
    open(IN, $source) or die "Can't open '$source' for reading: $!\n";
    my @columns = read_quoted_fields(\*IN);
    die "$source is empty\n" unless @columns;

    my $new_table = "$table.new";
    my $db = Vend::Table::GDBM->create({Fast_write => 1},
                                       $new_table,
                                       [@columns]);
    my @fields;
    while (@fields = read_quoted_fields(\*IN)) {
        $db->set_row(@fields);
    }
    close(IN);

    rename($new_table, $table)
        or die "Can't move '$new_table' to '$table': $!\n";
}

1;
