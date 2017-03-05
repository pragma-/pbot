# File: Registerable.pm
# Author: pragma_
#
# Purpose: Provides functionality to register and execute one or more subroutines.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Registerable;

use warnings;
use strict;

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Registerable should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;
  my $self = bless {}, $class;
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

  if(not defined $ref) {
    Carp::croak("Missing reference parameter to Registerable::execute");
  }

  foreach my $func (@{ $self->{handlers} }) {
    if($ref == $func || $ref == $func->{subref}) {
      return &{ $func->{subref} }(@_);
    }
  }
  return undef;
}

sub register {
  my $self = shift;
  my $subref;

  if(@_) {
    $subref = shift;
  } else {
    Carp::croak("Must pass subroutine reference to register()");
  }

  my $ref = { subref => $subref };
  push @{ $self->{handlers} }, $ref;

  return $ref;
}

sub unregister {
  my $self = shift;
  my $ref;

  if(@_) {
    $ref = shift;
  } else {
    Carp::croak("Must pass subroutine reference to unregister()");
  }

  @{ $self->{handlers} } = grep { $_ != $ref && $_->{subref} != $ref } @{ $self->{handlers} };
}

1;
