#!/usr/bin/perl -w
#
# Cache.pm -- Tie a cache to a hash
#

package Vend::Cache;

$VERSION = substr(q$Revision: 1.1 $, 10);

use Fcntl;
use strict;

=head1 NAME

Tie::Cache.pm - tie a cache to a hash

=head1 SYNOPSIS

    use Tie::Cache;

	$entries = 64;
	$ob = tie %cache, 'Tie::Cache', $entries;

	$options = { entries => 128, signal_block => 1};
	tie %cache, 'Tie::Cache', $options ;

	tie %cached_dbm, 'Tie::Cache', $options, 'DBM_choice',
	         'file', $flags, $mode;

=head1 DESCRIPTION

The Tie::Cache module implements a fully associative cache tied
to an associative array. If an element is assigned to, it is written
to the cache. If referenced, it returns undef if not in the cache. Items
will not remain in the cache if $size items are more recently used.

Tie::Cache was originally designed to cache the results of searches -- using
an LRU cache limited by number of entries prevents runaway memory use, while
still allowing fast access to recent searches.

Tie::Cache does no entry size checks, so if you cache a large number of
large items memory use will potentially be very large.  A good rule of
thumb for determining memory use is:

	memory_used = number_of_entries * (128 + average_entry_size)

=head2 Options

The following options are available for use with Tie::Cache. The options
are set by passing an anonymous has with the options -- if a scalar is
passed instead of a reference, an integer I<entries> is assumed.

=over 4

=item entries
The number of items that will be cached. If I<overflow> is set, any
entries dropped through the LRU algorithm will be written to disk and
saved. If no overflow is done, or the cache is not re-tied to a DBM
file, entries that are dropped are lost forever.  Large numbers of items
will use LOTS of memory. A practical size for search caching might be
32-64 -- if small scalars are cached, 4096 might be a reasonable upper
limit, but YMMV.

=head1 Transparent Methods

Transparent methods are tied through normal hash access methods.
TIEHASH, DESTROY, EXISTS, DELETE, CLEAR, EACH, FIRSTKEY, NEXTKEY,
STORE are all supported.

=item TIEHASH

This is the constructor. Called for the tie, and accepts an initial
options anonymous hash (or a number of entries, if not a reference).
Additional parameters are assumed to be arguments to an underlying
tie -- they will be blindly used to re-tie the cache to another
hash. Returns the object, which can be used to set options with
virtual methods.

	$object = tie %cache, 'Tie::Cache', 32;

=item DESTROY

Called for an untie. Simply removes the cache from memory unless the
overflow mode is in effect.  If overflow is set, then any entries
in memory are written to the overflow file.  If you wish the cache
to be volatile while still in overflow mode, preventing the write
operation, call $object->option('overflow_file' => undef) before 
doing the untie.

	untie %cache;

=item FETCH

Called when referencing the cache. Returns the value of the
item if it is in the cache, undef if not.  If I<hide> is
set, will not return entries from underlying disk files.
Causes the item to become the most recently used item.

	$scalar = $cache{$key};

=item STORE

Called when assigning to a cache entry. If the assignment makes the
number of entries in the cache over flow the I<entries> option, the
least-recently used item is dropped from the cache (and written to disk
if appropriate).  Causes the item to become the most recently used item.

=item EXISTS

Returns true if the item is in the cache, the overflow file, or the re-tied
hash.

	print "exists\n" if exists $cache{$key};

=item FIRSTKEY, NEXTKEY

Called when iterating through the keys of the cache with I<keys> or I<each>.
Items are returned from most-recent to least-recent.

	@entries = keys %cache;

=item CLEAR

Invalidates all entries in the cache. If the I<clobber> option is set, also
deletes all items from disk.

	%cache = ();

=item DELETE

Invalidates the item from the cache. If the I<clobber> option is set, also
deletes the item from disk.

	delete $cache{$key};

=head1 BUGS

Needs to be validated for operation with signals and multiple processes.

Should implement all DBM styles for re-tying.

=head1 AUTHOR

Mike Heins, <mikeh@iac.net>

=cut

use Carp;

sub TIEHASH	{

	my $class = shift;
	my $entries = shift || 32;

	my $s = {};

	$s->{DATA} = {};
	$s->{NEXT} = {};
	$s->{PREV} = {};
	$s->{MRU} = '';
	$s->{ENTRIES} = $entries;

	return bless $s, $class;
	
}

sub FIRSTKEY {
    my $s = shift;
    my $next;
    if($next = $s->{MRU}) {
        my $k = $s->{KEYS} = [$next];
        my $n = $s->{NEXT};
        $ = 0;
        while($next = $n->{$next}) {
            push @$k, $next;
        }
        $ = 1;
        return shift @$k;
    }
    else {  return undef }
}

sub _lru {

	my $s = shift;
	my $n = $s->{NEXT};
	my ($key, $next) = each %{$s->{DATA}};
    while ($next = $n->{$key}) {
        $key = $next;
    }
    return $key;
}
	

sub NEXTKEY {
	shift @{$_[0]->{KEYS}};
}

sub EXISTS {
	exists $_[0]->{DATA}->{$_[1]};
}

sub STORE {
	my $s = shift;
	my $key = shift;
	my $d = $s->{DATA};

	if (exists $d->{$key}) {
		$s->invalidate($key);
	}

	$d->{$key} = $_[0];
	$s->_mru($key);
	if(scalar keys %{$d} > $s->{ENTRIES}) {
		my $k = $s->_lru();
		delete $d->{$k};
	}
	return $_[0];
}

sub FETCH { 
	my ($s,$key) = @_;
	return undef unless exists $s->{DATA}->{$key};
	$s->_mru($key);
	${$s->{DATA}}{$key};
}

sub invalidate {

	my ($s,@keys) = @_;
	my ($key);

	my $n = $s->{NEXT};
	my $p = $s->{PREV};
	my ($next, $prev);

	unless(@keys) {
		@keys = keys %{$s->{DATA}};
		$s->{DATA} = {};
		$s->{NEXT} = {};
		$s->{PREV} = {};
		$s->{MRU} = '';
		return @keys;
	}
	
	foreach $key (@keys) {
		croak "Tie::Cache: invalidating bad key $key\n"
			unless exists $s->{DATA}->{$key};

		# Call ourself to delete all if we are the only key

        $next = $n->{$key};

		if ($prev = $p->{$key}) {
			$n->{$prev} = $next;
		}
		else {
			$s->{MRU} = $next;
		}

		if ($next = $n->{$key}) {
			$p->{$next} = $prev;
		}

		croak "Vend::Cache: linked list error while invalidating $key DATA\n"
			unless defined delete ${$s->{DATA}}{$key};
		croak "Vend::Cache: linked list error while invalidating $key NEXT\n"
			unless defined delete ${$s->{NEXT}}{$key};
		croak "Vend::Cache: linked list error while invalidating $key PREV\n"
			unless defined delete ${$s->{PREV}}{$key};
	}

	@keys;
}

sub _mru {

	my($s,$key) = @_;

	return if $s->{MRU} eq $key;

	my $n = $s->{NEXT};
	my $p = $s->{PREV};
	my $prev = $p->{$key};
	my $next = $n->{$key};

	if (defined $n->{$key}) {
		$n->{$prev} = $next;
		$p->{$next} = $prev if $next;
	}

 	if ($s->{MRU}) {
		$n->{$key} = $s->{MRU};
		$p->{$s->{MRU}} = $key;
	}
	else {
		$n->{$key} = '';
	}

	$p->{$key} = '';
	$s->{MRU} = $key;
}

sub version { $Vend::Cache::VERSION }
#sub version { $Cache::VERSION }

sub new	{ 

	my $pack = shift(@_);
	$pack->TIEHASH(@_);

}

