# File: Plugin.pm
#
# Purpose: Base class for PBot plugins.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package Plugins::Plugin;

use PBot::Imports;

sub new {
    my ($class, %args) = @_;

    if (not exists $args{pbot}) {
        my ($package, $filename, $line) = caller(0);
        my (undef, undef, undef, $subroutine) = caller(1);
        Carp::croak("Missing pbot reference to " . $class . ", created by $subroutine at $filename:$line");
    }

    my $self  = bless {}, $class;
    $self->{pbot} = $args{pbot};
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my ($package, $filename, $line) = caller(0);
    my (undef, undef, undef, $subroutine) = caller(1);
    Carp::croak("Missing initialize subroutine in $subroutine at $filename:$line");
}

sub unload {
    my ($package, $filename, $line) = caller(0);
    my (undef, undef, undef, $subroutine) = caller(1);
    Carp::croak("Missing unload subroutine in $subroutine at $filename:$line");
}

1;
