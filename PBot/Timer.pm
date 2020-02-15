# File: Timer.pm
# Author: pragma_
#
# Purpose: Provides functionality to register and execute one or more subroutines every X seconds.
#
# Caveats: Uses ALARM signal and all its issues.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Timer;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

our $min_timeout = 1;
our $max_seconds = 1000000;
our $seconds     = 0;
our @timer_funcs;

$SIG{ALRM} = sub {
    $seconds += $min_timeout;
    alarm $min_timeout;

    # call timer func subroutines
    foreach my $func (@timer_funcs) { &$func; }

    # prevent $seconds over-flow
    $seconds -= $max_seconds if $seconds > $max_seconds;
};

sub initialize {
    my ($self, %conf) = @_;
    my $timeout = $conf{timeout} // 10;
    $min_timeout      = $timeout if $timeout < $min_timeout;
    $self->{name}     = $conf{name} // "Unnamed $timeout Second Timer";
    $self->{handlers} = [];
    $self->{enabled}  = 0;

    # alarm signal handler (poor-man's timer)
    $self->{timer_func} = sub { on_tick_handler($self) };
    return $self;
}

sub start {
    my $self = shift;
    $self->{enabled} = 1;
    push @timer_funcs, $self->{timer_func};
    alarm $min_timeout;
}

sub stop {
    my $self = shift;
    $self->{enabled} = 0;
    @timer_funcs = grep { $_ != $self->{timer_func} } @timer_funcs;
}

sub on_tick_handler {
    my $self    = shift;
    my $elapsed = 0;

    if ($self->{enabled}) {
        if ($#{$self->{handlers}} > -1) {
            # call handlers supplied via register() if timeout for each has elapsed
            foreach my $func (@{$self->{handlers}}) {
                if (defined $func->{last}) {
                    $func->{last} -= $max_seconds if $seconds < $func->{last};    # handle wrap-around of $seconds

                    if ($seconds - $func->{last} >= $func->{timeout}) {
                        $func->{last} = $seconds;
                        $elapsed = 1;
                    }
                } else {
                    $func->{last} = $seconds;
                    $elapsed = 1;
                }

                if ($elapsed) {
                    &{$func->{subref}}($self);
                    $elapsed = 0;
                }
            }
        } else {
            # call default overridable handler if timeout has elapsed
            if (defined $self->{last}) {
                $self->{last} -= $max_seconds if $seconds < $self->{last};    # handle wrap-around

                if ($seconds - $self->{last} >= $self->{timeout}) {
                    $elapsed = 1;
                    $self->{last} = $seconds;
                }
            } else {
                $elapsed = 1;
                $self->{last} = $seconds;
            }

            if ($elapsed) {
                $self->on_tick();
                $elapsed = 0;
            }
        }
    }
}

# overridable method, executed whenever timeout is triggered
sub on_tick {
    my $self = shift;
    print "Tick! $self->{name} $self->{timeout} $self->{last} $seconds\n";
}

sub register {
    my $self = shift;
    my ($ref, $timeout, $id) = @_;

    Carp::croak("Must pass subroutine reference to register()") if not defined $ref;

    # TODO: Check if subref already exists in handlers?
    $timeout = 300     if not defined $timeout;    # set default value of 5 minutes if not defined
    $id      = 'timer' if not defined $id;

    my $h = {subref => $ref, timeout => $timeout, id => $id};
    push @{$self->{handlers}}, $h;

    if ($timeout < $min_timeout) { $min_timeout = $timeout; }

    if ($self->{enabled}) { alarm $min_timeout; }
}

sub unregister {
    my ($self, $id) = @_;
    Carp::croak("Must pass timer id to unregister()") if not defined $id;
    @{$self->{handlers}} = grep { $_->{id} ne $id } @{$self->{handlers}};
}

sub update_interval {
    my ($self, $id, $interval) = @_;

    foreach my $h (@{$self->{handlers}}) {
        if ($h->{id} eq $id) {
            $h->{timeout} = $interval;
            last;
        }
    }
}

1;
