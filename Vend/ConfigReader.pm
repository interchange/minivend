# ConfigReader.pm: read a configuration file
#
# $Id: ConfigReader.pm,v 1.4 1995/10/30 19:51:30 amw Exp $
#
package Vend::ConfigReader;

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

require 5.001;
use strict;
use Carp;

sub new {
    my ($class, $error_callback, $warn_callback, @options) = @_;
    my ($caller_package) = caller;

    my $self = {};

    if (defined $error_callback) {
        $self->{error_callback} =
            _resolve_code($error_callback, $caller_package,
                          'specified for error callback');
    }
    if (defined $warn_callback) {
        $self->{warn_callback} =
            _resolve_code($warn_callback, $caller_package,
                          'specified for warning callback');
    }

    my $option;
    foreach $option (@options) {
        if ($option eq 'ignore_unknown_directives') {
            $self->{ignore_unknown_directives} = 1;
        }
        else {
            croak "Unknown option '$option'";
        }
    }

    bless $self, $class;
}

# Allows the user to specify code to run in several different ways.
# Returns a code ref that will run the desired code.
#    'func'               calls subroutine 'func' in caller's package
#    'pkg::func'          calls subroutine 'pkg::func'
#    'new URI::URL'       calls static method 'new' in class 'URI::URL'
#    $coderef             calls the code ref
#    [new => 'URI::URL']  calls new URI::URL
#    [parse => $obj]      calls $obj->parse()

sub _resolve_code {
    my ($sub, $default_package, $purpose) = @_;
    my ($r, $class, $static_method, $function);

    $r = ref($sub);
    if (not $r) {
        if (($static_method, $class) = ($sub =~ m/^(\w+)\s+([\w:]+)$/)) {
            return sub {
                $class->$static_method(@_);
            };
        }
        elsif (($function) = ($sub =~ m/^(\w+)::(\w+)$/)) {
            croak "Undefined subroutine &$function $purpose"
                unless defined &{"$function"};
            return \&{$function};
        }
        elsif (($function) = ($sub =~ m/^(\w+)$/)) {
            $function = $default_package . '::' . $function;
            croak "Undefined subroutine &$function $purpose"
                unless defined &{"$function"};
            return \&{$function};
        }
        else {
            croak "Syntax error in function name '$sub' $purpose";
        }
    }
    elsif ($r eq 'CODE') {
        return $sub;
    }
    elsif ($r eq 'ARRAY') {
        my ($method, $class_or_obj) = @$sub;
        croak "Empty array used to $purpose" unless defined $method;
        croak "Class or object not specified in array used to $purpose"
            unless defined $class_or_obj;
        return sub {
            $class_or_obj->$method(@_);
        };
    }
    else {
        croak "Unknown object $purpose";
    }
}

sub _for_lookup {
    my ($directive) = @_;

    $directive = lc($directive);
    $directive =~ s/[\-\_]//g;
    $directive;
}

sub on {
    my ($self, $name, $default, $parser) = @_;
    my ($caller_package) = caller;
    my ($directive, $name_part, $directive_part);

    if (($name_part, $directive_part) = ($name =~ m/^(\w+):\s*(\S+)$/)) {
        $name = $name_part;
        $directive = $directive_part;
    }
    elsif (($name_part) = ($name =~ m/^(\w+)$/)) {
        $name = $name_part;
        $directive = $name_part;
    }
    else {
        croak "Syntax error in name specification '$name'";
    }

    $parser = _resolve_code($parser, $caller_package, 'specified as parser')
        if defined $parser;

    push @{$self->{names}}, $name;
    $self->{name_of_directive}{_for_lookup($directive)} = $name;
    $self->{directives}{$name} = 1;
    $self->{directive}{$name} = $directive;
    $self->{default}{$name} = $default;
    $self->{parser}{$name} = $parser;
}

sub predefine {
    my ($self, $name, $value) = @_;

    push @{$self->{names}}, $name;
    $self->{'directives'}{$name} = 1;
    $self->{'predefined'}{$name} = 1;
    _set $self $name, $value;
}

sub ignore {
    my ($self, $directive) = @_;

    $self->{'ignore'}{_for_lookup($directive)} = 1;
}

sub load {
    my ($self, $file, $untaint_input) = @_;
    my ($package, $filename, $linenum) = caller;

    $self->{untaint} = $untaint_input;
    $self->{seen} = {};
    $self->{value_set} = {};

    $self->_load_from_file($file);
    undef $self->{line};

    my $the_config_file = "in the configuration file '$file'";
    my $the_source_code = "as the default value specified in $filename " .
                          "at line $linenum";
    $self->_assign_defaults($the_config_file, $the_source_code);

    $self->{where} = undef;
}

sub _assign_defaults {
    my ($self, $the_config_file, $the_source_code) = @_;
    my ($name);

    foreach $name (@{$self->{names}}) {
        $self->_assign_default($name, $the_config_file, $the_source_code)
            unless $self->{value_set}{$name} or $self->{'predefined'}{$name};
    }
}

sub _assign_default {
    my ($self, $name, $the_config_file, $the_source_code) = @_;

    my $directive = $self->{directive}{$name};
    my $default = $self->{default}{$name};

    if (not defined $default) {
        $self->{where} = $the_config_file;
        $self->error("Please specify the '$directive' directive");
    }

    $self->{where} = $the_source_code;
    if (not ref $default) {
        _parse $self $name, $directive, $default;
    }
    elsif (ref($default) eq 'CODE') {
        _set $self $name, &$default();
    }
    else {
        _set $self $name, $default;
    }
}


sub _load_from_file {
    my ($self, $file) = @_;
    local ($/) = "\n";
    local ($_, $., $!);

    open(ConfigReader::FILE, $file)
        or croak "Could not read configuration file '$file': $!";
    while (<ConfigReader::FILE>) {
        $self->{where} = "in line $. of the configuration file '$file'";
        $self->_process($_);
    }
    close(ConfigReader::FILE);
    $self->{where} = undef;
}


sub _process {
    my ($self, $line) = @_;
    my ($directive, $name, $value);

    $line =~ s/[\r\n]+$//;      # zap trailing newline and/or CR,
    my $eline = $line;
    $line =~ s/#.*//;           #   comments,
    $line =~ s/\s+$//;          #   trailing spaces
    $line =~ s/^\s+//;          #   leading spaces
    return if $line eq '';

    $self->{line} = $eline;     # save for error or warning messages

    if ($self->{untaint}) {
        $line =~ /^([\w\-]+)\s+(.*)/ or $self->error("Syntax error");
        $directive = $1;
        $value = $2;
    }
    else {
        (($directive, $value) = ($line =~ m/([\w\-]+)\s+(.*)/))
            or $self->error("Syntax error");
    }
    
    return if $self->{'ignore'}{_for_lookup($directive)};

    $name = $self->{name_of_directive}{_for_lookup($directive)};

    if (not defined $name) {
        if ($self->{ignore_unknown_directives}) {
            return;
        }
        else {
            $self->error("Unknown directive '$directive'");
        }
    }

    $self->error("Duplicate directive '$directive'")
        if $self->{seen}{$name};
    ++$self->{seen}{$name};

    $value = substr($value, 1, length($value) - 2)
        if ($value =~ m/^".*"$/ or $value =~ m/^'.*'$/);

    $self->_parse($name, $directive, $value); # if defined $parser;
    $self->{line} = undef;
}

sub _parse {
    my ($self, $name, $directive, $string) = @_;
    my ($value, $error_msg);

    my $parser = $self->{parser}{$name};
    if (not defined $parser) {
        _set $self $name, $string;
    }
    else {
        $self->{directive_being_parsed} = $directive;
        # on_complaint sub { $value = &$parser($self, $string) },
        #             \$error_msg,
        #             sub { $self->warning($_[0]) };
        # $value = $self->error($error_msg) if (defined $error_msg);
        $value = &$parser($self, $string);
        undef $self->{directive_being_parsed};
        _set $self $name, $value;
    }
}

sub _set {
    my ($self, $name, $value) = @_;
    $self->{value}{$name} = $value;
    $self->{value_set}{$name} = 1;
}

sub values {
    my ($self) = @_;

    $self->{value};
}

sub directive {
    my ($self) = @_;

    croak "directive() was not called from inside of a parsing function"
        unless defined $self->{directive_being_parsed};

    $self->{directive_being_parsed};
}

sub _message {
    my ($self, $msg) = @_;

    my $where = $self->{where};
    my $line = $self->{line};

    $msg .= " $where" if (defined $where);
    $msg .= ":\n$line" if (defined $line);
    $msg .= "\n";
    $msg;
}


sub error {
    my ($self, $msg) = @_;

    my $errorcall = $self->{error_callback};
    if (defined $errorcall) {
        return &$errorcall($msg, $self->{where}, $self->{line});
    }
    else {
        die $self->_message($msg);
    }
}

sub warning {
    my ($self, $msg) = @_;

    my $warncall = $self->{warn_callback};
    if (defined $warncall) {
        &$warncall($msg, $self->{where}, $self->{line});
    }
    else {
        warn $self->_message($msg);
    }
}


sub value {
    my ($self, $name) = @_;

    croak "'$name' has not been defined as a configuration directive name"
        if not $self->{'directives'}{$name};
    croak "'$name' has no value because the configuration file has not ".
          "been read yet"
        unless $self->{value_set}{$name} or $self->{predefined}{$name};

    $self->{value}{$name};
}

sub directives {
    my ($self) = @_;

    @{$self->{names}};
}

sub make_accessor {
    my ($self, $name) = @_;

    my $sub = sub { $self->value($name) };
    $sub;
}

sub make_accessors {
    my ($self, @names) = @_;
    @names = $self->{names} if @names == 0;

    my $name;
    my $subs = {};
    foreach $name (@names) {
        $subs->{$name} = $self->make_accessor($name);
    }
    $subs;
}

sub define_accessor {
    my ($self, $name, $package) = @_;
    ($package) = caller unless defined $package;
    
    {
        no strict 'refs';
        *{ $package . "::" . $name } = $self->make_accessor($name);
    }
    $name;
}

sub define_accessors {
    my ($self, $package, @names) = @_;
    @names = @{$self->{names}} if @names == 0;
    # ($package) = caller unless defined $package;

    my @subs = ();
    my $name;
    foreach $name (@names) {
        push @subs, $self->define_accessor($name, $package);
    }
    @subs;
}

1;
