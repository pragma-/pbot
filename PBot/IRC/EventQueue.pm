package PBot::IRC::EventQueue;    # pragma_ 2011/21/01

use feature 'unicode_strings';

use PBot::IRC::EventQueue::Entry;    # pragma_ 2011/21/01

use strict;

sub new {
    my $class = shift;

    my $self = {
        'queue' => {},
    };

    bless $self, $class;
}

sub queue {
    my $self = shift;
    return $self->{'queue'};
}

sub enqueue {
    my $self    = shift;
    my $time    = shift;
    my $content = shift;

    my $entry = new PBot::IRC::EventQueue::Entry($time, $content);    # pragma_ 2011/21/01
    $self->queue->{$entry->id} = $entry;
    return $entry->id;
}

sub dequeue {
    my $self  = shift;
    my $event = shift;
    my $result;

    if (!$event) {                                                    # we got passed nothing, so return the first event
        $event = $self->head();
        delete $self->queue->{$event->id};
        $result = $event;
    } elsif (!ref($event)) {                                          # we got passed an id
        $result = $self->queue->{$event};
        delete $self->queue->{$event};
    } else {                                                          # we got passed an actual event object
        ref($event) eq 'PBot::IRC::EventQueue::Entry'                 # pragma_ 2011/21/01
          or die "Cannot delete event type of " . ref($event) . "!";

        $result = $self->queue->{$event->id};
        delete $self->queue->{$event->id};
    }

    return $result;
}

sub head {
    my $self = shift;

    return undef if $self->is_empty;

    no warnings;    # because we want to numerically sort strings...
    my $headkey = (sort { $a <=> $b } (keys(%{$self->queue})))[0];
    use warnings;

    return $self->queue->{$headkey};
}

sub is_empty {
    my $self = shift;

    return keys(%{$self->queue}) ? 0 : 1;
}

1;
