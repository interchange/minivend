# $Id: Value_tie.pm,v 1.3 1995/10/31 14:19:49 amw Exp $

package Vend::Value_tie;
use strict;
use Vend::Session;

sub TIESCALAR {
    my ($class, $value_name) = @_;
    bless \$value_name, $class;
}

sub DESTROY {}

sub FETCH {
    my ($value_name, $key) = @_;
    Value->{$$value_name};
}

sub STORE {
    my ($value_name, $key, $value) = @_;
    Value->{$$value_name} = $value;
}

1;
