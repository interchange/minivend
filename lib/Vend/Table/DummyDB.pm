# Table/DummyDB.pm: Autoloader for MiniVend Databases
#
# $Id: DummyDB.pm,v 1.8 1997/08/18 18:39:47 mike Exp $
#
#
# Copyright 1996, 1997 by Mike Heins <mikeh@iac.net>
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

package Vend::Table::DummyDB;

use Vend::Data qw(import_database update_productbase);

sub new {
	my ($class, $obj) = @_;
	my $self = { %$obj };
	return bless $self;
}

sub close_table { 1; }

sub database_key_exists {
    my ($self,$key) = @_;
	my $db = $self->import_db();
	return $db->record_exists($key);
}

sub record_exists {
    my ($self,$key) = @_;
	my $db = $self->import_db();
	my $result = $db->record_exists($key);
	wantarray ? ($result, $db) : $result;
}

sub import_db {
	my($self) = @_;
	my $db = Vend::Data::import_database(
			$self->{file}, $self->{type}, $self->{name});
	$Vend::Database{$self->{name}} = $db;
	Vend::Data::update_productbase($self->{name});
	return $db;
}

sub field {
    my ($self, $key, $field_name) = @_;

	my $db = $self->import_db();

	return '' unless $db->record_exists($key);
	return '' unless defined $db->test_column($field_name);
	return $db->field($key, $field_name);
}

sub ref {
    my ($self) = @_;
	return $self->import_db();
}

sub test_column {
    my ($self, $field_name) = @_;
	my $db = $self->import_db();
    return $db->test_column($field_name);
}

1;
