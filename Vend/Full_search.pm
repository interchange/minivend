package Vend::Full_search;

use strict;
use Vend::Application;
use Vend::Page;

sub setup {
    my $C = app_config();

    my $fn = $C->{'Bin_directory'} . "/make_index";
    print "Creating $fn\n";
    open(OUT, ">$fn") or die "Can't create '$fn': $!\n";
    print OUT <<"END";
#!$C->{'Perl_program'} -w

use lib '$C->{'Vend_lib'}';
use Vend::Setup;

\$ENV{'PATH'} = '/bin:/usr/bin';
\$ENV{'SHELL'} = '/bin/sh';
\$ENV{'IFS'} = '';
srand(\$\$ ^ time());
umask 077;
chdir '$C->{'App_directory'}';

require '$C->{'Config_file'}';
initialize_modules();

Vend::Full_search::make_index();
exit 0;
END

    close(OUT);
    chmod 0700, $fn or die "Can't chmod '$fn': $!\n";
}

my ($Html, $Stripped_directory, %Directory);

sub write_stripped_pages {
    ($Stripped_directory, $Html) = @_;

    `rm -rf $Stripped_directory`;
    mkdir $Stripped_directory, 0700
        or die "Can't create '$Stripped_directory': $\n";

    %Directory = ();
    page_iterate(\&write_stripped_page);
}

sub write_stripped_page {
    my ($filename, $page_name) = @_;

    my $out = join('/', map(escape_to_filename($_), split(/\//, $page_name)));
 print "$out\n";

    my ($base) = ($out =~ m,^(.*?)/,);
    if (defined $base and not defined $Directory{$base}) {
        my $dir = "$Stripped_directory/$base";
        die "$dir is not a directory\n" if -e $dir and not -d $dir;
        if (! -e $dir) {
            print "Creating $dir\n";
            mkdir $dir, 0700 or die "Can't create directory '$dir': $!\n";
        }
        $Directory{$base} = 1;
    }

    my $out_fn = "$Stripped_directory/$out$Html";
    open(OUT, ">$out_fn") or die "Can't create '$out_fn': $!\n";
    print OUT strip_page($page_name);
    close(OUT);
}

1;
