# File: EventQueue.pm
#
# Purpose: Provides functionality to manage event subroutines which are invoked
# at a future time, optionally recurring.
#
# Note: PBot::Core::EventQueue has no relation to PBot::Core::EventDispatcher.

# SPDX-FileCopyrightText: 2021-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::EventQueue;
use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Core::Utils::PriorityQueue;

use Time::HiRes qw/time/;

sub initialize($self, %conf) {
    $self->{event_queue} = PBot::Core::Utils::PriorityQueue->new(pbot => $self->{pbot});
}

# returns seconds until upcoming event.
sub duration_until_next_event($self) {
    return 0 if not $self->{event_queue}->count;
    return $self->{event_queue}->get_priority(0) - time;
}

# invokes any current events and then returns seconds until upcoming event.
sub do_events($self) {
    # early-return if no events available
    return 0 if not $self->{event_queue}->count;

    my $debug = $self->{pbot}->{registry}->get_value('eventqueue', 'debug') // 0;

    # repeating events to re-enqueue
    my @enqueue;

    for (my $i = 0; $i < $self->{event_queue}->entries; $i++) {
        # we call time for a fresh time, instead of using a stale $now that
        # could be in the past depending on a previous event's duration
        if (time >= $self->{event_queue}->get_priority($i)) {
            my $event = $self->{event_queue}->get($i);

            $self->{pbot}->{logger}->log("Processing event $i: $event->{id}\n") if $debug > 1;

            # call event's subref, passing event as argument
            $event->{subref}->($event);

            # remove event from queue
            $self->{event_queue}->remove($i--);

            # add event to re-enqueue queue if repeating
            push @enqueue, $event if $event->{repeating};
        } else {
            # no more events ready at this time
            if ($debug > 2) {
                my $event = $self->{event_queue}->get($i);
                $self->{pbot}->{logger}->log("Event not ready yet: $event->{id} (timeout=$event->{priority})\n");
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
sub exists($self, $id) {
    return scalar grep { $_->{id} eq $id } $self->{event_queue}->entries;
}

# adds an event to the event queue, optionally repeating
sub enqueue_event($self, $subref, $interval = 0, $id = "unamed (${interval}s $subref)", $repeating = 0) {
    # create event structure
    my $event = {
        id        => $id,
        subref    => $subref,
        interval  => $interval,
        priority  => time + $interval,
        repeating => $repeating,
    };

    # add the event to the priority queue
    my $position = $self->{event_queue}->add($event);

    # debugging noise
    my $debug = $self->{pbot}->{registry}->get_value('eventqueue', 'debug') // 0;
    if ($debug > 1) {
        $self->{pbot}->{logger}->log("Enqueued new event $id at position $position: timeout=$event->{priority} interval=$interval repeating=$repeating\n");
    }
}

# convenient alias to add an event with repeating defaulted to enabled.
sub enqueue($self, $subref, $interval = undef, $id = undef, $repeating = 1) {
    $self->enqueue_event($subref, $interval, $id, $repeating);
}

# removes an event from the event queue, optionally invoking it.
# `id` can contain `.*` and `.*?` for wildcard-matching/globbing.
sub dequeue_event($self, $id, $execute = 0) {
    my $result = eval {
        # escape special characters
        $id = quotemeta $id;

        # unescape .* and .*?
        $id =~ s/\\\.\\\*\\\?/.*?/g;
        $id =~ s/\\\.\\\*/.*/g;

        # compile regex
        my $regex = qr/^$id$/i;

        # count total events before removal
        my $count = $self->{event_queue}->count;

        # collect events to be removed
        my @removed = grep { $_->{id} =~ /$regex/i; } $self->{event_queue}->entries;

        # remove events from event queue
        @{$self->{event_queue}->queue} = grep { $_->{id} !~ /$regex/i; } $self->{event_queue}->entries;

        # set count to total events removed
        $count -= $self->{event_queue}->count;

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
sub dequeue($self, $id) {
    $self->dequeue_event($id);
}

# invoke and remove all events matching `id`, which can
# contain `.*` and `.*?` for wildcard-matching/globbing.
sub execute_and_dequeue_event($self, $id) {
    return $self->dequeue_event($id, 1);
}

# replace code subrefs for matching events. if no events
# were found, then add the event to the event queue.
sub replace_subref_or_enqueue_event($self, $subref, $interval, $id, $repeating = 0) {
    # find events matching id
    my @events = grep { $_->{id} eq $id } $self->{event_queue}->entries;

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
sub replace_or_enqueue_event($self, $subref, $interval, $id, $repeating = 0) {
    # remove event if it exists
    $self->dequeue_event($id) if $self->exists($id);

    # enqueue new event
    $self->enqueue_event($subref, $interval, $id, $repeating);
}

# add event unless it already had been added.
sub enqueue_event_unless_exists($self, $subref, $interval, $id, $repeating = 0) {
    # event already exists, bail out
    return if $self->exists($id);

    # enqueue new event
    $self->enqueue_event($subref, $interval, $id, $repeating);
}

# update the `repeating` flag for all events matching `id`.
sub update_repeating($self, $id, $repeating) {
    foreach my $event ($self->{event_queue}->entries) {
        if ($event->{id} eq $id) {
            $event->{repeating} = $repeating;
        }
    }
}

# update the `interval` value for all events matching `id`.
sub update_interval($self, $id, $interval, $dont_enqueue = 0) {
    for (my $i = 0; $i < $self->{event_queue}->count; $i++) {
        my $event = $self->{event_queue}->get($i);

        if ($event->{id} eq $id) {
            if ($dont_enqueue) {
                # update interval in-place without moving event to new place in queue
                # (allows event to fire at expected time, then updates to new timeout afterwards)
                $event->{interval} = $interval;
            } else {
                # remove and add event in new position in queue
                $self->{event_queue}->remove($i);
                $self->enqueue_event($event->{subref}, $interval, $id, $event->{repeating});
            }
        }
    }
}

sub count($self) {
    return $self->{event_queue}->count;
}

sub entries($self) {
    return $self->{event_queue}->entries;
}

1;
