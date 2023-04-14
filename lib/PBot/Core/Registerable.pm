# File: Registerable.pm
#
# Purpose: Provides functionality to register and execute one or more subroutines.

# SPDX-FileCopyrightText: 2010-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Registerable;

use PBot::Imports;

sub new($class, %args) {
    my $self  = bless {}, $class;
    Carp::croak("Missing pbot reference to " . __FILE__) unless exists $args{pbot};
    $self->{pbot} = delete $args{pbot};
    $self->initialize(%args);
    return $self;
}

sub initialize($self, %args) {
    $self->{handlers} = [];
}

sub execute_all($self) {
    foreach my $func (@{$self->{handlers}}) {
        $func->{subref}->(@_);
    }
}

sub execute($self, $ref) {
    foreach my $func (@{$self->{handlers}}) {
        if ($ref == $func || $ref == $func->{subref}) { return $func->{subref}->(@_); }
    }
    return undef;
}

sub register($self, $subref) {
    my $ref = {subref => $subref};
    push @{$self->{handlers}}, $ref;
    return $ref;
}

sub register_front($self, $subref) {
    my $ref = {subref => $subref};
    unshift @{$self->{handlers}}, $ref;
    return $ref;
}

sub unregister($self, $ref) {
    @{$self->{handlers}} = grep { $_ != $ref } @{$self->{handlers}};
}

sub unregister_all($self) {
    $self->{handlers} = [];
}

1;
