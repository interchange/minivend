# Form.pm:  html form handling
#
# $Id: Form.pm,v 1.8 1996/02/26 21:33:16 amw Exp $
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

=head1 NAME

Vend::Form - html form handling

=cut

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(form_fields get_field get_required_field get_field_values
             register_form specify_form);

use Carp;
use strict;
# use Vend::Directive qw(Dump_request);
use Vend::Dispatch;


sub unhexify {
    my ($s) = @_;

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
    }
    if (http()->Content_Type ne 'application/x-www-form-urlencoded') {
        interaction_error("Content type for form submission is not\n" .
                          "application/x-www-form-urlencoded\n");
    }
}



my %Form_callback;

=head2 C<register_form($form_name, $code_ref)>

Registers $form_name as an action to handle a form submittal.  When
the form is submitted, the $code_ref is called with four arguments:
$form_name, $path (any remaining components in the URL after the
action name), $args (a hash ref of additional arguments passed in the
URL), and $input (the form field values).  The $input is a hash ref,
with the form field names as keys.  The value for each name is an
array ref of all the values returned for that input field.

=cut

sub register_form {
    my ($name, $callback) = @_;

    $Form_callback{$name} = $callback;
    specify_action $name, \&form_handler;
}

sub specify_form { register_form(@_) }


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


=head2 C<get_field($input, $field_name)>

Call get_field() for form fields which return only one value.  (Pretty
much everything except select tags).  Returns the value of the
$field_name from the form $input.  Returns undef if the field was not
passed in from the form.

=cut

sub get_field {
    my ($input, $field_name) = @_;

    my $value_list = $input->{$field_name};
    return undef unless defined $value_list;
    report("More than one value passed for form variable '$field_name'")
        if (@$value_list > 1);
    return $value_list->[0];
}


=head2 C<get_required_field($input, $field_name)>

Returns the value of the $field_name from the form $input, for fields
which return only one value.  Raises an error if the field was not
passed in from the form.

=cut

sub get_required_field {
    my ($input, $field_name) = @_;
    my $value = get_field($input, $field_name);
    interaction_error("Missing form field '$field_name'")
        unless defined $value;
    return $value;
}


=head2 C<get_field_values($input, $field_name)>

Returns an array of the values of the $field_name, for form fields
which return multiple values like the select tag.  Returns the empty
array () if the field was not passed in from the form, or if it did
not return any values.

=cut

sub get_field_values {
    my ($input, $field_name) = @_;
    my $value_list = $input->{$field_name};
    return () unless defined $value_list;
    return @$value_list;
}


# Depreciated.

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
