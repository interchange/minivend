# Form.pm:  html form handling
#
# $Id: Form.pm,v 1.7 1995/10/30 19:55:44 amw Exp $
#
package Vend::Form;

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

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(specify_form form_fields);

use Carp;
use strict;
use Vend::Directive qw(Dump_request);
use Vend::Dispatch;
use Vend::Log;


sub unhexify {
    my($s) = @_;

    $s =~ s/%(..)/chr(hex($1))/ge;
    $s;
}

sub parse_form_input {
    my ($input) = @_;
    my ($pair, $key, $value, $aref);

    # From Tim Bunce's Base.pm read_entity_body():
    # Convert posted query string back into canonical form.
    # We have to deal with browsers which use CRLF, CR or LF.
    $input =~ s/\r?[\n\r]/&/mg;

    my $values = {};
    foreach $pair (split(/&/, $input)) {
	($key, $value) = ($pair =~ m/([^=]+)=(.*)/)
	    or die "Syntax error in post input:\n$pair\n";
	$key = unhexify($key);
	$value =~ s/\+/ /g;
	$value = unhexify($value);
        # from Tim Bunce's Request.pm
        $aref = $values->{$key} || ($values->{$key} = []);
	push @$aref, $value;
    }
    $values;
}

sub read_form_input {
    my ($http) = @_;

    if ($http->Method eq 'GET') {
        my $query = $http->Query;
        if (defined $query and $query ne '') {
            return $query;
        }
        else {
            die "No form input available\n";
        }
    }
    elsif ($http->Method eq 'POST') {
        if ($http->has_Entity) {
            return $http->read_entity_body();
        }
        else {
            die "No entity data for form input included with POST request\n";
        }
    }
    return undef;
}


# Check that a form is being submitted.

sub expect_form {
    if (http()->Method ne 'POST') {
        interaction_error("Request method for form submission is not POST\n");
        return 0;
    }

    if (http()->Content_Type ne 'application/x-www-form-urlencoded') {
        interaction_error("Content type for form submission is not\n" .
                          "application/x-www-form-urlencoded\n");
        return 0;
    }

    return 1;
}



my %Form_callback;

sub specify_form {
    my ($name, $callback) = @_;

    $Form_callback{$name} = $callback;
    specify_action $name, \&form_handler;
}


sub form_handler {
    my ($name, $path, $args) = @_;

    expect_form();
    my $input = parse_form_input(read_form_input(http()));
    show_input($name, $input) if Dump_request;
    my $callback = $Form_callback{$name};
    die "No action defined for form '$name'" if not defined $callback;
    &$callback($name, $path, $args, $input);
}

sub show_input {
    my ($name, $input) = @_;

    my $r = "Form input for '$name':\n";
    my ($field, $values);
    while (($field, $values) = each %$input) {
        $r .= "   $field = " . join(', ', map(fieldval($_), @$values)) . "\n";
    }
    report_error($r);
}

sub fieldval {
    my ($v) = @_;
    $v =~ s/[\x00-\x1F\'\"\\\x7F-\xFF]/sprintf('\\x%02X', org($&))/eg;
    '"' . $v . '"';
}


##

# value \$zip_code 'zip-code'
# dotted \%hash 'q'
# submit \$which [
#     'submit', 'foo'
#     'image', \$x, \$y, 'Do'
#     ]
# checkbox \$value 'credit-card'

sub form_fields {
    my ($input, $field_spec) = @_;

    my $dotted = {};
    my ($field_name, $values, $first, $second);
    while (($field_name, $values) = each %$input) {
        if (($first, $second) = ($field_name =~ m/^ ([^\.]+) \. (.*) $/x)) {
            if (@$values > 1) {
                report_error("More than one value passed for dotted form value '$field_name' (using the first)\n");
            }
            $dotted->{$first}{$second} = $values->[0];
        }
    }
        
    my ($spec, @p, $t, $var, $field_name, $which, $x, $y, $r, $submit);
    my ($v);

    foreach $spec (@$field_spec) {
        my @p = @$spec;
        my $t = shift @p;
        if    ($t eq 'value' and ($var, $field_name) = @p) {
            if (defined($v = $input->{$field_name})) {
                if (@$v > 1) {
                    report_error("More than one value passed for form variable '$field_name' (using the first)\n");
                }
                $$var = $v->[0];
            }
            else {
                $$var = undef;
            }
        }
        elsif ($t eq 'dotted' and ($var, $field_name) = @p) {
            # log_error "dotted = " . uneval($dotted) . "\n";
            # log_error "field_name = $field_name\n";
            %$var = %{ $dotted->{$field_name} }
                if defined $dotted->{$field_name};
        }
        elsif ($t eq 'submit' and $which = shift @p) {
            foreach $submit (@p) {
                my @q = @$submit;
                my $r = shift @q;
                if ($r eq 'submit' and $field_name = shift @q) {
                    $$which = $field_name if $input->{$field_name};
                }
                elsif ($r eq 'image' and ($x, $y, $field_name) = @q) {
                    if (defined $input->{"$field_name.x"}) {
                        $$which = $field_name;
                        $$x = $input->{"$field_name.x"};
                        $$y = $input->{"$field_name.y"};
                    }
                }
                else { croak "Unrecognized submit type '$r'"; }
            }
        }
        elsif ($t eq 'checkbox' and ($var, $field_name) = @p) {
            $$var = defined($input->{$field_name});
        }
        else { croak "Unrecognized spec type '$t'"; }
    }
}

1;
