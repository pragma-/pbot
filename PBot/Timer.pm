# File: Timer.pm
# Author: pragma_
#
# Purpose: Provides functionality to register subroutines/events to be invoked
# at a future time, optionally recurring.
#
# If no subroutines/events are registered/enqueued, the default on_tick()
# method, which can be overridden, is invoked.
#
# Uses own internal seconds counter and relative-intervals to avoid
# timeout desyncs due to system clock changes.
#
# Note: Uses ALARM signal.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Timer;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use Time::Duration qw/concise duration/;

our $seconds ||= 0;
our $waitfor ||= 1;
our @timer_funcs;

# alarm signal handler (poor-man's timer)
$SIG{ALRM} = sub {
    $seconds += $waitfor;
    foreach my $func (@timer_funcs) { &$func; }
};

sub initialize {
    my ($self, %conf) = @_;
    my $timeout          = $conf{timeout} // 10;
    $self->{name}        = $conf{name} // "Unnamed ${timeout}s Timer";
    $self->{enabled}     = 0;
    $self->{event_queue} = [];
    $self->{last}        = $seconds;
    $self->{timeout}     = $timeout;

    $self->{pbot}->{commands}->register(sub { $self->cmd_eventqueue(@_) },  'eventqueue', 1);
    $self->{pbot}->{capabilities}->add('admin', 'can-eventqueue', 1);

    $self->{timer_func} = sub { $self->on_tick_handler(@_) };
}

sub cmd_eventqueue {
    my ($self, $context) = @_;

    my $usage = "Usage: eventqueue list [filter regex] | add <relative time> <command> [-repeat] | remove <event>";

    my $command = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    if (not defined $command) {
        return $usage;
    }

    if ($command eq 'list') {
        return "No events queued." if not @{$self->{event_queue}};

        my $result = eval {
            my $text = "Queued events:\n";
            my ($regex) = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

            my $i = 0;
            my $events = 0;
            foreach my $event (@{$self->{event_queue}}) {
                $i++;

                if ($regex) {
                    next unless $event->{id} =~ /$regex/i;
                }

                $events++;

                my $duration = concise duration $event->{timeout} - $seconds;
                $text .= "  $i) in $duration: $event->{id}";
                $text .= ' [R]' if $event->{repeating};
                $text .= ";\n";
            }

            return "No events found." if $events == 0;

            return $text;
        };

        if ($@) {
            my $error = $@;
            $error =~ s/ at PBot.*//;
            return "Bad regex: $error";
        }

        return $result;
    }

    if ($command eq 'add') {
        my ($duration, $command) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
        return "Usage: eventqueue add <relative time> <command> [-repeat]" if not defined $duration or not defined $command;

        my ($delay, $error) = $self->{pbot}->{parsedate}->parsedate($duration);
        return $error if defined $error;

        my $repeating = 0;
        $repeating = 1 if $command =~ s/^-repeat\s+|\s+-repeat$//g;

        my $cmd = {
            nick => $context->{nick},
            user => $context->{user},
            host => $context->{host},
            command => $command,
        };

        $self->{pbot}->{interpreter}->add_to_command_queue($context->{from}, $cmd, $delay, $repeating);
        return "Command added to event queue.";
    }

    if ($command eq 'remove') {
        my ($regex) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 1);
        return "Usage: eventqueue remove <event>" if not defined $regex;
        $regex =~ s/\*/.*?/g;
        return $self->dequeue_event($regex);
    }

    return "Unknown command '$command'. $usage";
}

sub start {
    my $self = shift;
    $self->{enabled} = 1;
    push @timer_funcs, $self->{timer_func};
    alarm 1;
}

sub stop {
    my $self = shift;
    $self->{enabled} = 0;
    @timer_funcs = grep { $_ != $self->{timer_func} } @timer_funcs;
}

sub find_enqueue_position {
    my ($self, $value) = @_;

    return 0 if not @{$self->{event_queue}};

    if ($value < $self->{event_queue}->[0]->{timeout}) {
        return 0;
    }

    if ($value > $self->{event_queue}->[@{$self->{event_queue}} - 1]->{timeout}) {
        return scalar @{$self->{event_queue}};
    }

    my $lo = 0;
    my $hi = scalar @{$self->{event_queue}} - 1;

    while ($lo <= $hi) {
        my $mid = int (($hi + $lo) / 2);

        if ($value < $self->{event_queue}->[$mid]->{timeout}) {
            $hi = $mid - 1;
        } elsif ($value > $self->{event_queue}->[$mid]->{timeout}) {
            $lo = $mid + 1;
        } else {
            while ($mid < @{$self->{event_queue}} and $self->{event_queue}->[$mid]->{timeout} == $value) {
                $mid++;
            }
            return $mid;
        }
    }

    return $lo;
}

sub enqueue_event {
    my ($self, $ref, $interval, $id, $repeating) = @_;

    $id        ||= 'anonymous event';
    $repeating ||= 0;

    my $event = {
        id        => $id,
        subref    => $ref,
        interval  => $interval,
        timeout   => $seconds + $interval,
        repeating => $repeating,
    };

    my $i = $self->find_enqueue_position($event->{timeout});
    splice @{$self->{event_queue}}, $i, 0, $event;

    if ($interval < $waitfor) {
        $self->waitfor($interval);
    }

    my $debug = $self->{pbot}->{registry}->get_value('timer', 'debug') // 0;
    if ($debug > 1) {
        $self->{pbot}->{logger}->log("Enqueued new timer event $id at position $i: timeout=$event->{timeout} interval=$interval repeating=$repeating\n");
    }
}

sub dequeue_event {
    my ($self, $id) = @_;

    my $result = eval {
        $id = quotemeta $id;
        $id =~ s/\\\.\\\*\\\?/.*?/g;
        $id =~ s/\\\.\\\*/.*/g;
        my $regex = qr/^$id$/i;
        my $count = @{$self->{event_queue}};
        my @removed = grep { $_->{id} =~ /$regex/i; } @{$self->{event_queue}};
        @{$self->{event_queue}} = grep { $_->{id} !~ /$regex/i; } @{$self->{event_queue}};
        $count -= @{$self->{event_queue}};
        return "No matching events." if not $count;
        return "Removed $count event" . ($count == 1 ? '' : 's') . ': ' . join(', ', map { $_->{id} } @removed);
    };

    if ($@) {
        my $error = $@;
        $self->{pbot}->{logger}->log("Error in dequeue_event: $error\n");
        $error =~ s/ at PBot.*//;
        return "$error";
    }

    return $result;
}

sub register {
    my ($self, $ref, $interval, $id) = @_;
    $self->enqueue_event($ref, $interval, $id, 1);
}

sub unregister {
    my ($self, $id) = @_;
    $self->dequeue_event($id);
}

sub update_repeating {
    my ($self, $id, $repeating) = @_;

    for (my $i = 0; $i < @{$self->{event_queue}}; $i++) {
        if ($self->{event_queue}->[$i]->{id} eq $id) {
            $self->{event_queue}->[$i]->{repeating} = $repeating;
            last;
        }
    }
}

sub update_interval {
    my ($self, $id, $interval, $dont_enqueue) = @_;

    for (my $i = 0; $i < @{$self->{event_queue}}; $i++) {
        if ($self->{event_queue}->[$i]->{id} eq $id) {
            if ($dont_enqueue) {
                $self->{event_queue}->[$i]->{interval} = $interval;
            } else {
                my $event = splice(@{$self->{event_queue}}, $i, 1);
                $self->enqueue_event($event->{subref}, $interval, $id, $event->{repeating});
            }
            last;
        }
    }
}

sub waitfor {
    my ($self, $duration) = @_;
    $duration = 1 if $duration < 1;
    alarm $duration;
    $waitfor = $duration;
}

sub on_tick_handler {
    my ($self) = @_;
    return if not $self->{enabled};

    my $debug = $self->{pbot}->{registry}->get_value('timer', 'debug') // 0;
    $self->{pbot}->{logger}->log("$self->{name} tick $seconds\n") if $debug;

    if (@{$self->{event_queue}}) {
        my $next_tick = 1;
        my @enqueue = ();
        for (my $i = 0; $i < @{$self->{event_queue}}; $i++) {
            if ($seconds >= $self->{event_queue}->[$i]->{timeout}) {
                my $event = $self->{event_queue}->[$i];
                $self->{pbot}->{logger}->log("Processing timer event $i: $event->{id}\n") if $debug > 1;
                $event->{subref}->($event);
                splice @{$self->{event_queue}}, $i--, 1;
                push @enqueue, $event if $event->{repeating};
            } else {
                if ($debug > 2) {
                    $self->{pbot}->{logger}->log("Event not ready yet: $self->{event_queue}->[$i]->{id} (timeout=$self->{event_queue}->[$i]->{timeout})\n");
                }

                $next_tick = $self->{event_queue}->[$i]->{timeout} - $seconds;
                last;
            }
        }

        $self->waitfor($next_tick);

        foreach my $event (@enqueue) {
            $self->enqueue_event($event->{subref}, $event->{interval}, $event->{id}, 1);
        }
    } else {
        # no queued events, call default overridable on_tick() method if timeout has elapsed
        if ($seconds - $self->{last} >= $self->{timeout}) {
            $self->{last} = $seconds;
            $self->on_tick;
        }

        $self->waitfor($self->{timeout} - $seconds - $self->{last});
    }
}

# default overridable handler, executed whenever timeout is triggered
sub on_tick {
    my ($self) = @_;
    $self->{pbot}->{logger}->log("Tick! $self->{name} $self->{timeout} $self->{last} $seconds\n");
}

1;
