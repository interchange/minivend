package Vend::Option_1;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(options combine defaults);

sub options {
    my ($package, @hashes, $directive, $hash, @result);

    $package = shift @_ if !defined($_[0]) and !ref($_[0]);
    $package = (caller)[0] unless defined $package;

    while (@_) {
        shift @_, next unless defined $_[0];
        last unless ref $_[0];
        push @hashes, shift @_;
    }

    DIRECTIVE: foreach $directive (@_) {
        foreach $hash (@hashes) {
            if (exists $hash->{$package . '::' . $directive}) {
                push @result, $hash->{$package . '::' . $directive};
                next DIRECTIVE;
            }
            if (exists $hash->{$directive}) {
                push @result, $hash->{$directive};
                next DIRECTIVE;
            }
        }
        push @result, undef;
    }

    return @result;
}


sub combine {
    my ($package, @hashes, $directive, $hash, $result);

    $package = shift @_ if !defined($_[0]) and !ref($_[0]);
    $package = (caller)[0] unless defined $package;

    while (@_) {
        shift @_, next unless defined $_[0];
        last unless ref $_[0];
        push @hashes, shift @_;
    }

    $result = {};
    DIRECTIVE: foreach $directive (@_) {
        foreach $hash (@hashes) {
            if (exists $hash->{$package . '::' . $directive}) {
                $result->{$directive} = $hash->{$package . '::' . $directive};
                next DIRECTIVE;
            }
            if (exists $hash->{$directive}) {
                $result->{$directive} = $hash->{$directive};
                next DIRECTIVE;
            }
        }
    }

    return $result;
}


sub defaults {
    my ($hash, $directive, $default);
    $hash = shift @_;

    while ($directive = shift @_) {
        $default = shift @_;
        unless (defined $hash->{$directive}) {
            $hash->{$directive} = $default;
        }
    }
    return $hash;
}

1;
