# File: Class.pm
#
# Purpose: Base class for PBot classes. This prevents each PBot class from
# needing to define the new() constructor and other boilerplate.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
