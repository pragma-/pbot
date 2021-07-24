# File: EventDispatcher.pm
#
# Purpose: Registers event handlers and dispatches events to them.
#
# Note: PBot::Core::EventDispatcher has no relation to PBot::Core::EventQueue.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::EventDispatcher;
use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Core::Utils::PriorityQueue;

sub initialize {
    my ($self, %conf) = @_;

    # hash table of event handlers
    $self->{handlers} = {};
}

# add an event handler
#
# priority ranges from 0 to 100. 0 is the highest priority, i.e. an handler with
# priority 0 will handle events first. 100 is the lowest priority and will handle
# events last. priority defaults to 50 if omitted.
#
# NickList reserves 0 and 100 to ensure its list is populated by JOINs, etc,
# before any handlers need to consult its list, or depopulated by PARTs, QUITs,
# KICKs, etc, after any other handlers need to consult its list.
sub register_handler {
    my ($self, $event_name, $subref, $priority) = @_;

    # get the package of the calling subroutine
    my ($package) = caller(0);

    # internal identifier to find calling package's event handler
    my $handler_id = "$package-$event_name";

    my $entry = {
        priority => $priority // 50,
        id       => $handler_id,
        subref   => $subref,
    };

    # create new priority-queue for event-name if one doesn't exist
    if (not exists $self->{handlers}->{$event_name}) {
        $self->{handlers}->{$event_name} = PBot::Core::Utils::PriorityQueue->new(pbot => $self->{pbot});
    }

    # add the event handler
    $self->{handlers}->{$event_name}->add($entry);

    # debugging
    if ($self->{pbot}->{registry}->get_value('eventdispatcher', 'debug')) {
        $self->{pbot}->{logger}->log("EventDispatcher: Add handler: $handler_id\n");
    }
}

# remove an event handler
sub remove_handler {
    my ($self, $event_name) = @_;

    # get the package of the calling subroutine
    my ($package) = caller(0);

    # internal identifier to find calling package's event handler
    my $handler_id = "$package-$event_name";

    # remove the event handler
    if (exists $self->{handlers}->{$event_name}) {
        my $handlers = $self->{handlers}->{$event_name};

        for (my $i = 0; $i < $handlers->count; $i++) {
            my $handler = $handlers->get($i);

            if ($handler->{id} eq $handler_id) {
                $handlers->remove($i--);
            }
        }

        # remove root event-name key if it has no more handlers
        if (not $self->{handlers}->{$event_name}->count) {
            delete $self->{handlers}->{$event_name};
        }
    }

    # debugging
    if ($self->{pbot}->{registry}->get_value('eventdispatcher', 'debug')) {
        $self->{pbot}->{logger}->log("EventDispatcher: Remove handler: $handler_id\n");
    }
}

# send an event to its handlers
sub dispatch_event {
    my ($self, $event_name, $event_data) = @_;

    # debugging flag
    my $debug = $self->{pbot}->{registry}->get_value('eventdispatcher', 'debug') // 0;

    # undef means no handlers have handled this event
    my $dispatch_result= undef;

    # if the event-name has handlers
    if (exists $self->{handlers}->{$event_name}) {
        # then dispatch the event to each one
        foreach my $handler ($self->{handlers}->{$event_name}->entries) {
            # debugging
            if ($debug) {
                $self->{pbot}->{logger}->log("Dispatching $event_name to handler $handler->{id}\n");
            }

            # invoke an event handler. a handler may return undef to indicate
            # that it decided not to handle this event.
            my $handler_result = eval { $handler->{subref}->($event_name, $event_data) };

            # check for exception
            if (my $exception = $@) {
                $self->{pbot}->{logger}->log("Exception in event handler: $exception");
            } else {
                # update $dispatch_result only when handler result is a defined
                # value so we remember if any handlers have handled this event.
                $dispatch_result = $handler_result if defined $handler_result;
            }
        }
    }

    # return undef if no handlers have handled this event; otherwise the return
    # value of the last event handler to handle this event.
    return $dispatch_result;
}

1;
