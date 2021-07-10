# File: EventQueue.pm
#
# Purpose: Provides functionality to manage event subroutines which are invoked
# at a future time, optionally recurring.
#
# Note: PBot::EventQueue has no relation to PBot::EventDispatcher.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::EventQueue;
use parent 'PBot::Class';

use PBot::Imports;

use Time::HiRes qw/time/;
use Time::Duration;

sub initialize {
    my ($self, %conf) = @_;

    # array of pending events
    $self->{event_queue} = [];

    # register `eventqueue` bot command
    $self->{pbot}->{commands}->register(sub { $self->cmd_eventqueue(@_) }, 'eventqueue', 1);

    # add `can-eventqueue` capability to admin group
    $self->{pbot}->{capabilities}->add('admin', 'can-eventqueue', 1);
}

# eventqueue bot command
sub cmd_eventqueue {
    my ($self, $context) = @_;

    my $usage = "Usage: eventqueue list [filter regex] | add <relative time> <command> [-repeat] | remove <regex>";

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

                my $duration = $event->{timeout} - time;

                if ($duration < 0) {
                    # current time has passed an event's time but the
                    # event hasn't left the queue yet. we'll show these
                    # as, e.g., "pending 5s ago"
                    $duration = 'pending ' . concise ago -$duration;
                } else {
                    $duration = 'in ' . concise duration $duration;
                }

                $text .= "  $i) $duration: $event->{id}";
                $text .= ' [R]' if $event->{repeating};
                $text .= ";\n";
            }

            return "No events found." if $events == 0;

            return $text . "$events events.\n";
        };

        if (my $error = $@) {
            # strip source information to prettify error for non-developer consumption
            $error =~ s/ at PBot.*//;
            return "Bad regex: $error";
        }

        return $result;
    }

    if ($command eq 'add') {
        my ($duration, $command) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

        if (not defined $duration or not defined $command) {
            return "Usage: eventqueue add <relative time> <command> [-repeat]";
        }

        # convert text like "5 minutes" or "1 week" or "next tuesday" to seconds
        my ($seconds, $error) = $self->{pbot}->{parsedate}->parsedate($duration);
        return $error if defined $error;

        # check for `-repeating` at front or end of command
        my $repeating = $command =~ s/^-repeat\s+|\s+-repeat$//g;

        my $cmd = {
            nick     => $context->{nick},
            user     => $context->{user},
            host     => $context->{host},
            hostmask => $context->{hostmask},
            command  => $command,
        };

        $self->{pbot}->{interpreter}->add_to_command_queue($context->{from}, $cmd, $seconds, $repeating);

        return "Command added to event queue.";
    }

    if ($command eq 'remove') {
        my ($regex) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 1);
        return "Usage: eventqueue remove <regex>" if not defined $regex;
        $regex =~ s/(?<!\.)\*/.*?/g;
        return $self->dequeue_event($regex);
    }

    return "Unknown command '$command'. $usage";
}

# returns seconds until upcoming event.
sub duration_until_next_event {
    my ($self) = @_;
    return 0 if not @{$self->{event_queue}};
    return $self->{event_queue}->[0]->{timeout} - time;
}

# invokes any current events and then returns seconds until upcoming event.
sub do_events {
    my ($self) = @_;

    # early-return if no events available
    return 0 if not @{$self->{event_queue}};

    my $debug = $self->{pbot}->{registry}->get_value('eventqueue', 'debug') // 0;

    # repeating events to re-enqueue
    my @enqueue;

    for (my $i = 0; $i < @{$self->{event_queue}}; $i++) {
        # we call time for a fresh time, instead of using a stale $now that
        # could be in the past depending on a previous event's duration
        if (time >= $self->{event_queue}->[$i]->{timeout}) {
            my $event = $self->{event_queue}->[$i];

            $self->{pbot}->{logger}->log("Processing event $i: $event->{id}\n") if $debug > 1;

            # call event's subref, passing event as argument
            $event->{subref}->($event);

            # remove event from queue
            splice @{$self->{event_queue}}, $i--, 1;

            # add event to re-enqueue queue if repeating
            push @enqueue, $event if $event->{repeating};
        } else {
            # no more events ready at this time
            if ($debug > 2) {
                $self->{pbot}->{logger}->log("Event not ready yet: $self->{event_queue}->[$i]->{id} (timeout=$self->{event_queue}->[$i]->{timeout})\n");
            }

            last;
        }
    }

    # re-enqueue repeating events
    foreach my $event (@enqueue) {
        $self->enqueue_event($event->{subref}, $event->{interval}, $event->{id}, 1);
    }

    return $self->duration_until_next_event;
}

# check if an event is in the event queue.
sub exists {
    my ($self, $id) = @_;
    return scalar grep { $_->{id} eq $id } @{$self->{event_queue}};
}

# quickly and efficiently find the best position in the event
# queue array for a given time value
sub find_enqueue_position {
    my ($self, $time) = @_;

    # no events in queue yet, early-return first position
    return 0 if not @{$self->{event_queue}};

    # early-return first position if event's time is less
    # than first position's
    if ($time < $self->{event_queue}->[0]->{timeout}) {
        return 0;
    }

    # early-return last position if event's time is greater
    if ($time > $self->{event_queue}->[@{$self->{event_queue}} - 1]->{timeout}) {
        return scalar @{$self->{event_queue}};
    }

    # binary search to find enqueue position

    my $lo = 0;
    my $hi = scalar @{$self->{event_queue}} - 1;

    while ($lo <= $hi) {
        my $mid = int (($hi + $lo) / 2);

        if ($time < $self->{event_queue}->[$mid]->{timeout}) {
            $hi = $mid - 1;
        } elsif ($time > $self->{event_queue}->[$mid]->{timeout}) {
            $lo = $mid + 1;
        } else {
            while ($mid < @{$self->{event_queue}} and $self->{event_queue}->[$mid]->{timeout} == $time) {
                # found a slot with the same time. we "slide" down the array
                # to append this event to the end of this region of same-times.
                $mid++;
            }
            return $mid;
        }
    }

    return $lo;
}

# adds an event to the event queue, optionally repeating
sub enqueue_event {
    my ($self, $subref, $interval, $id, $repeating) = @_;

    # default values
    $id        //= "unnamed (${interval}s $subref)";
    $repeating //= 0;
    $interval  //= 0;

    # create event structure
    my $event = {
        id        => $id,
        subref    => $subref,
        interval  => $interval,
        timeout   => time + $interval,
        repeating => $repeating,
    };

    # find position to add event
    my $i = $self->find_enqueue_position($event->{timeout});

    # add the event to the event queue array
    splice @{$self->{event_queue}}, $i, 0, $event;

    # debugging noise
    my $debug = $self->{pbot}->{registry}->get_value('eventqueue', 'debug') // 0;
    if ($debug > 1) {
        $self->{pbot}->{logger}->log("Enqueued new event $id at position $i: timeout=$event->{timeout} interval=$interval repeating=$repeating\n");
    }
}

# convenient alias to add an event with repeating defaulted to enabled.
sub enqueue {
    my ($self, $subref, $interval, $id, $repeating) = @_;
    $self->enqueue_event($subref, $interval, $id, $repeating // 1);
}

# removes an event from the event queue, optionally invoking it.
# `id` can contain `.*` and `.*?` for wildcard-matching/globbing.
sub dequeue_event {
    my ($self, $id, $execute) = @_;

    my $result = eval {
        # escape special characters
        $id = quotemeta $id;

        # unescape .* and .*?
        $id =~ s/\\\.\\\*\\\?/.*?/g;
        $id =~ s/\\\.\\\*/.*/g;

        # compile regex
        my $regex = qr/^$id$/i;

        # count total events before removal
        my $count = @{$self->{event_queue}};

        # collect events to be removed
        my @removed = grep { $_->{id} =~ /$regex/i; } @{$self->{event_queue}};

        # remove events from event queue
        @{$self->{event_queue}} = grep { $_->{id} !~ /$regex/i; } @{$self->{event_queue}};

        # set count to total events removed
        $count -= @{$self->{event_queue}};

        # invoke removed events, if requested
        if ($execute) {
            foreach my $event (@removed) {
                $event->{subref}->($event);
            }
        }

        # nothing removed
        return "No matching events." if not $count;


        # list all removed events
        my $removed = "Removed $count event" . ($count == 1 ? '' : 's') . ': ' . join(', ', map { $_->{id} } @removed);
        $self->{pbot}->{logger}->log("EventQueue: dequeued $removed\n");
        return $removed;
    };

    if ($@) {
        my $error = $@;
        $self->{pbot}->{logger}->log("Error in dequeue_event: $error\n");
        $error =~ s/ at PBot.*//;
        return "$error";
    }

    return $result;
}

# alias to dequeue_event, for consistency.
sub dequeue {
    my ($self, $id) = @_;
    $self->dequeue_event($id);
}

# invoke and remove all events matching `id`, which can
# contain `.*` and `.*?` for wildcard-matching/globbing.
sub execute_and_dequeue_event {
    my ($self, $id) = @_;
    return $self->dequeue_event($id, 1);
}

# replace code subrefs for matching events. if no events
# were found, then add the event to the event queue.
sub replace_subref_or_enqueue_event {
    my ($self, $subref, $interval, $id, $repeating) = @_;

    # find events matching id
    my @events = grep { $_->{id} eq $id } @{$self->{event_queue}};

    # no events found, enqueue new event
    if (not @events) {
        $self->enqueue_event($subref, $interval, $id, $repeating);
        return;
    }

    # otherwise update existing events
    foreach my $event (@events) {
        $event->{subref} = $subref;
    }
}

# remove existing events of this id then enqueue new event.
sub replace_or_enqueue_event {
    my ($self, $subref, $interval, $id, $repeating) = @_;

    # remove event if it exists
    $self->dequeue_event($id) if $self->exists($id);

    # enqueue new event
    $self->enqueue_event($subref, $interval, $id, $repeating);
}

# add event unless it already had been added.
sub enqueue_event_unless_exists {
    my ($self, $subref, $interval, $id, $repeating) = @_;

    # event already exists, bail out
    return if $self->exists($id);

    # enqueue new event
    $self->enqueue_event($subref, $interval, $id, $repeating);
}

# update the `repeating` flag for all events matching `id`.
sub update_repeating {
    my ($self, $id, $repeating) = @_;

    for (my $i = 0; $i < @{$self->{event_queue}}; $i++) {
        if ($self->{event_queue}->[$i]->{id} eq $id) {
            $self->{event_queue}->[$i]->{repeating} = $repeating;
        }
    }
}

# update the `interval` value for all events matching `id`.
sub update_interval {
    my ($self, $id, $interval, $dont_enqueue) = @_;

    for (my $i = 0; $i < @{$self->{event_queue}}; $i++) {
        if ($self->{event_queue}->[$i]->{id} eq $id) {
            if ($dont_enqueue) {
                # update interval in-place without moving event to new place in queue
                # (allows event to fire at expected time, then updates to new timeout afterwards)
                $self->{event_queue}->[$i]->{interval} = $interval;
            } else {
                # remove and add event in new position in queue
                my $event = splice(@{$self->{event_queue}}, $i, 1);
                $self->enqueue_event($event->{subref}, $interval, $id, $event->{repeating});
            }
        }
    }
}

1;
