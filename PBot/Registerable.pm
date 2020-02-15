# File: Registerable.pm
# Author: pragma_
#
# Purpose: Provides functionality to register and execute one or more subroutines.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Registerable;

use warnings; use strict;
use feature 'unicode_strings';

sub new {
  my ($proto, %conf) = @_;
  my $class = ref($proto) || $proto;
  my $self = bless {}, $class;
  Carp::croak("Missing pbot reference to " . __FILE__) unless exists $conf{pbot};
  $self->{pbot} = $conf{pbot};
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my $self = shift;
  $self->{handlers} = [];
}

sub execute_all {
  my $self = shift;
  foreach my $func (@{ $self->{handlers} }) {
    my $result = &{ $func->{subref} }(@_);
    return $result if defined $result;
  }
  return undef;
}

sub execute {
  my $self = shift;
  my $ref = shift;
  Carp::croak("Missing reference parameter to Registerable::execute") if not defined $ref;
  foreach my $func (@{ $self->{handlers} }) {
    if ($ref == $func || $ref == $func->{subref}) {
      return &{ $func->{subref} }(@_);
    }
  }
  return undef;
}

sub register {
  my ($self, $subref) = @_;
  Carp::croak("Must pass subroutine reference to register()") if not defined $subref;
  my $ref = { subref => $subref };
  push @{ $self->{handlers} }, $ref;
  return $ref;
}

sub unregister {
  my ($self, $ref) = @_;
  Carp::croak("Must pass reference to unregister()") if not defined $ref;
  @{ $self->{handlers} } = grep { $_ != $ref } @{ $self->{handlers} };
}

sub unregister_all {
  my ($self) = @_;
  $self->{handlers} = [];
}

1;
