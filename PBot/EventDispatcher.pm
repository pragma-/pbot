# File: EventDispatcher.pm
#
# Purpose: Registers event handlers and dispatches events to them.
#
# Note: PBot::EventDispatcher has no relation to PBot::EventQueue.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::EventDispatcher;
use parent 'PBot::Class';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;

    # hash table of event handlers
    $self->{handlers} = {};
}

# add an event handler
sub register_handler {
    my ($self, $event_name, $subref) = @_;

    # get the package of the calling subroutine
    my ($package) = caller(0);

    # internal identifier to find calling package's event handler
    my $handler_id = "$package-$event_name";

    # add the event handler
    $self->{handlers}->{$event_name}->{$handler_id} = $subref;

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
        delete $self->{handlers}->{$event_name}->{$handler_id};

        # remove root event-name key if it has no more handlers
        if (not keys %{$self->{handlers}->{$event_name}}) {
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

    # event handler return value
    my $dispatch_result= undef;

    # if the event-name has handlers
    if (exists $self->{handlers}->{$event_name}) {
        # then dispatch the event to each one
        foreach my $handler_id (keys %{$self->{handlers}->{$event_name}}) {
            # event handler subref
            my $subref = $self->{handlers}->{$event_name}->{$handler_id};

            # debugging
            if ($debug) {
                $self->{pbot}->{logger}->log("Dispatching $event_name to handler $handler_id\n");
            }

            # invoke event handler
            my $handler_result = eval { $subref->($event_name, $event_data) };

            # update $dispatch_result only to a defined handler result because
            # we want to know if at least one handler handled the event. the
            # value of $dispatch_result will be undef if NONE of the handlers
            # have kicked in. in other words, an event handler may return
            # undef to indicate that they didn't handle the event after all.
            $dispatch_result = $handler_result if defined $handler_result;

            # check for error
            if (my $error = $@) {
                chomp $error;
                $self->{pbot}->{logger}->log("Error in event handler: $error\n");
            }
        }
    }

    # return dispatch result. if at least one event handler returned a defined
    # value, then this event is considered handled. if there were no handlers
    # or if all of the available handers returned undef then this value will
    # be undef.
    return $dispatch_result;
}

1;
