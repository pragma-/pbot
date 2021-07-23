# File: Class.pm
#
# Purpose: Base class for PBot classes. This prevents each PBot class from
# needing to define the new() constructor and other boilerplate.
#
# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Class;

use PBot::Imports;

our $quiet = 0;

sub import {
    my ($package, %opts) = @_;

    $quiet = $opts{quiet};
}

sub new {
    my ($class, %args) = @_;

    # ensure class was passed a PBot instance
    if (not exists $args{pbot}) {
        my ($package, $filename, $line) = caller(0);
        my (undef, undef, undef, $subroutine) = caller(1);
        Carp::croak("Missing pbot reference to " . $class . ", created by $subroutine at $filename:$line");
    }

    my $self = bless { pbot => $args{pbot} }, $class;

    $self->{pbot}->{logger}->log("Initializing $class\n") unless $quiet;
    $self->initialize(%args);

    return $self;
}

sub initialize {
    my ($package, $filename, $line) = caller(0);
    my (undef, undef, undef, $subroutine) = caller(1);
    Carp::croak("Missing initialize subroutine in $subroutine at $filename:$line");
}

1;
