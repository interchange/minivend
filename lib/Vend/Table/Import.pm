# Table/Import.pm: import a table
#
# $Id: Import.pm,v 1.14 1998/05/02 03:07:56 mike Exp $
#
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

package Vend::Table::Import;
$VERSION = substr(q$Revision: 1.14 $, 10);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(import_csv import_quoted import_ascii_delimited);
use strict;
use Vend::Table::Quoted qw(read_quoted_fields);
use Vend::Util;

sub import_csv {
    my ($source, $create) = @_;

    die "The source file '$source' does not exist\n" unless -e $source;

    open(Vend::Table::Import::IN, "+<$source")
		or die "Can't open '$source' for reading: $!\n";
	lockfile(\*Vend::Table::Import::IN, 1, 1) or die "lock\n";
    my @columns = read_quoted_fields(\*IN);
    die "$source is empty\n" unless @columns;
    $Vend::FIRST_COLUMN_NAME = shift @columns;

    my $out = &$create(@columns);
    my (@fields,$key);
    while (@fields = read_quoted_fields(\*IN)) {
        $out->set_row(@fields);
    }
	unlockfile(\*Vend::Table::Import::IN) or die "unlock\n";
    close(Vend::Table::Import::IN);
	return $out;
}

sub import_quoted { return import_csv(@_) }

my %Sort = (

    ''  => sub { $a cmp $b              },
    none    => sub { $a cmp $b              },
    f   => sub { (lc $a) cmp (lc $b)    },
    fr  => sub { (lc $b) cmp (lc $a)    },
    n   => sub { $a <=> $b              },
    nr  => sub { $b <=> $a              },
    r   => sub { $b cmp $a              },
    rf  => sub { (lc $b) cmp (lc $a)    },
    rn  => sub { $b <=> $a              },
);

sub import_ascii_delimited {
    my ($infile, $delimiter, $create) = @_;
	my ($options, $format);

	if(ref $delimiter) {
		$options = $delimiter;
		$delimiter = quotemeta($options->{'delimiter'});
		$format = uc ($options->{CONTINUE} || 'NONE');
	}
	else {
		$delimiter = quotemeta($delimiter);
		$format = 'NONE';
	}

    open(Vend::Table::Import::IN, "+<$infile")
		or die "Couldn't open '$infile': $!\n";
	lockfile(\*Vend::Table::Import::IN, 1, 1) or die "lock\n";

    my $field_names = <IN>;
    chomp $field_names;
	$field_names =~ s/\s+$//;
    my @field_names = split(/$delimiter/, $field_names);
	my $field_count = scalar @field_names;

	my $field_hash;
	my $para_sep;
	my $codere = '[\w-_#/.]+';
	my $idx = 0;

	if($format eq 'NOTES') {
		$field_hash = {};
		for(@field_names) {
			s/:.*//;	
			if(/\S\s+/) {
				die "Only one notes field allowed in NOTES format.\n"
					if $para_sep;
				$para_sep = $_;
				$_ = '';
			}
			else {
				$field_hash->{$_} = $idx++;
			}
		}
		@field_names = grep $_, @field_names;
		$para_sep =~ s/($codere)[\t ]*(.)/$2/;
		push(@field_names, ($1 || 'notes_field'));
		if ($para_sep) {
			$para_sep =~ s/[ \t\r\n].*//;
			my $msg;
			$msg = length($para_sep) != 1	? "'$para_sep'"
											: sprintf '0x%02x', ord $para_sep;
			::logError("notes_field='$field_names[$idx]' delimiter: $msg");
		}
		else {
			$para_sep = "\f";
		}

	}
	local($/) = "\n" . $para_sep ."\n"
		if $para_sep;

	# HACK!
    $Vend::FIRST_COLUMN_NAME = shift @field_names;

    my $out = &$create(@field_names);
	my $fields;
    my (@fields, $key);
	my @addl;
	my $excel = '';
	my $excel_addl = '';

	if($options->{EXCEL}) {
		$excel = <<'EndOfExcel';
			if(/"[^\t]*,/) {
				for (@fields) {
					next unless /,/;
					s/^"//;
					s/"$//;
				}
			}
EndOfExcel
		$excel_addl = <<'EndOfExcel';
			if(/"[^\t]*,/) {
				for (@addl) {
					next unless /,/;
					s/^"//;
					s/"$//;
				}
			}
EndOfExcel
	}
	
	my $index = '';
	my @fh; # Array of file handles for sort
	my @i;  # Array of field names for sort
	my @o;  # Array of sort options
	if($options->{INDEX}) {
		my @f; my $f;
		my @n;
		my $i;
		@f = split /[\s,]+/, $options->{INDEX};
		foreach $f (@f) {
			my $found = 0;
			$i = 1;
			if( $f =~ s/:(.*)//) {
				push @o, $1;
			}
			else {
				push @o, '';
			}
			for(@field_names) {
				if($_ eq $f) {
					$found++;
					push(@i, $i);
					push(@n, $f);
					last;
				}
				$i++;
			}
			pop(@o) unless $found;
		}
		if(@i) {
			require IO::File;
			my $fh;
			my $f_string = join ",", @i;
			@f = ();
			for($i = 0; $i < @i; $i++) {
				my $fnum = $i[$i];
				$fh = new IO::File "> $infile.$i[$i]";
				eval {
					unlink "$infile.$n[$i]" if -l "$infile.$n[$i]";
					symlink "$infile.$i[$i]", "$infile.$n[$i]"; 
				};
				die "Couldn't create $infile.$i[$i]: $!\n"
					unless defined $fh;
				push(@fh, $fh);
				$index .= <<EndOfIndex;
			print { \$fh[$i] } "\$fields[$fnum]\\t\$fields[0]\\n";
EndOfIndex
			}
		}
	}

my %format = (

	NOTES => <<EndOfRoutine,
        while (<IN>) {
            chomp;
			\@fields = ();
			s/\\r?\\n\\r?\\n([\\000-\\377]*)//
				and \$fields[$idx] = \$1;

		while(s!($codere):\\s*(.*)\\n?!!) {
			next unless defined \$field_hash->{\$1};
			\$fields[\$field_hash->{\$1}] = \$2;
		}
			$index
            \$key = shift \@fields;
            \$out->set_row(\$key, \@fields);
        }
EndOfRoutine

	LINE => <<EndOfRoutine,
        while (<IN>) {
            chomp;
			\$fields = \@fields = split(/$delimiter/, \$_, $field_count);
			$index
			push (\@fields, '') until \$fields++ >= $field_count;
            \$key = shift \@fields;
            \$out->set_row(\$key, \@fields);
        }
EndOfRoutine

	NONE => <<EndOfRoutine,
        while (<IN>) {
            chomp;
            \$fields = \@fields = split(/$delimiter/, \$_, 99999);
			$excel
			$index
            push (\@fields, '') until \$fields++ >= $field_count;
            \$key = shift \@fields;
            \$out->set_row(\$key, \@fields);
        }
EndOfRoutine

	UNIX => <<EndOfRoutine,
        while (<IN>) {
            chomp;
			if(s/\\\\\$//) {
				\$_ .= <IN>;
				redo;
			}
            \$fields = \@fields = split(/$delimiter/, \$_, 99999);
			$excel
			$index
            push (\@fields, '') until \$fields++ >= $field_count;
            \$key = shift \@fields;
            \$out->set_row(\$key, \@fields);
        }
EndOfRoutine

	DITTO => <<EndOfRoutine,
        while (<IN>) {
            chomp;
			if(/^$delimiter/) {
				\$fields = \@addl = split /$delimiter/, \$_, 99999;
				shift \@addl;
				$excel_addl
				my \$i;
				for(\$i = 0; \$i < \@addl; \$i++) {
					\$fields[\$i] .= "\n\$addl[\$i]"
						if \$addl[\$i] ne '';
				}
			}
			else {
				\$fields = \@fields = split(/$delimiter/, \$_, 99999);
				$excel
				$index
				push (\@fields, '') until \$fields++ >= $field_count;
				\$key = shift \@fields;
			}
            \$out->set_row(\$key, \@fields);
        }
EndOfRoutine

);

    eval $format{$format};
    die $@ if $@;
	if(@fh) {
		my $no_sort;
		my $sort_sub;
		my $cmd = 'echo junk | sort -f -n';
		system $cmd;
		$no_sort = 1 if $?;
		
		my $fh;
		my $i;
		for ($i = 0; $i < @fh; $i++) {
			close $fh[$i] or die "close: $!";
			unless ($no_sort) {
				$o[$i] = "-$o[$i]" if $o[$i];
				$cmd = "sort $o[$i] -o $infile.$i[$i] $infile.$i[$i]";
				system $cmd;
			}
			else {
				$fh = new IO::File "$infile.$i[$i]";
				my (@lines) = <$fh>;
				close $fh or die "close: $!";
				my $option = $o[$i] || 'none';
				@lines = sort { &{$Sort{$option}} } @lines;
				$fh = new IO::File ">$infile.$i[$i]";
				print $fh @lines;
				close $fh or die "close: $!";
			}
		}
	}
	unlockfile(\*Vend::Table::Import::IN) or die "unlock\n";
    close(Vend::Table::Import::IN);
    return $out;
}

sub version { $Vend::Table::Import::VERSION }

1;
