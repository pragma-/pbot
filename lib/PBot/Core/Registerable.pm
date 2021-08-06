# File: Registerable.pm
#
# Purpose: Provides functionality to register and execute one or more subroutines.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Registerable;

use PBot::Imports;

sub new {
    my ($class, %args) = @_;
    my $self  = bless {}, $class;
    Carp::croak("Missing pbot reference to " . __FILE__) unless exists $args{pbot};
    $self->{pbot} = delete $args{pbot};
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my $self = shift;
    $self->{handlers} = [];
}

sub execute_all {
    my $self = shift;
    foreach my $func (@{$self->{handlers}}) {
        $func->{subref}->(@_);
    }
}

sub execute {
    my $self = shift;
    my $ref  = shift;
    Carp::croak("Missing reference parameter to Registerable::execute") if not defined $ref;
    foreach my $func (@{$self->{handlers}}) {
        if ($ref == $func || $ref == $func->{subref}) { return $func->{subref}->(@_); }
    }
    return undef;
}

sub register {
    my ($self, $subref) = @_;
    Carp::croak("Must pass subroutine reference to register()") if not defined $subref;
    my $ref = {subref => $subref};
    push @{$self->{handlers}}, $ref;
    return $ref;
}

sub register_front {
    my ($self, $subref) = @_;
    Carp::croak("Must pass subroutine reference to register_front()") if not defined $subref;
    my $ref = {subref => $subref};
    unshift @{$self->{handlers}}, $ref;
    return $ref;
}

sub unregister {
    my ($self, $ref) = @_;
    Carp::croak("Must pass reference to unregister()") if not defined $ref;
    @{$self->{handlers}} = grep { $_ != $ref } @{$self->{handlers}};
}

sub unregister_all {
    my ($self) = @_;
    $self->{handlers} = [];
}

1;
