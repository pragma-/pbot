# File: Class.pm
#
# Purpose: Base class for PBot classes. This prevents each PBot class from
# needing to define the new() constructor and other boilerplate.
#
# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Class;

use PBot::Imports;

sub new {
    my ($class, %args) = @_;

    my $self  = bless {}, $class;

    # ensure class was passed a PBot instance
    if (not exists $args{pbot}) {
        my ($package, $filename, $line) = caller(0);
        my (undef, undef, undef, $subroutine) = caller(1);
        Carp::croak("Missing pbot reference to " . $class . ", created by $subroutine at $filename:$line");
    }

    $self->{pbot} = $args{pbot};

    $self->{pbot}->{logger}->log("Initializing $class\n");
    $self->initialize(%args);

    return $self;
}

sub initialize {
    my ($package, $filename, $line) = caller(0);
    my (undef, undef, undef, $subroutine) = caller(1);
    Carp::croak("Missing initialize subroutine in $subroutine at $filename:$line");
}

1;
