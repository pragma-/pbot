# File: PriorityQueue.pm
#
# Purpose: Bare-bones lightweight implementation of a priority queue.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Utils::PriorityQueue;

use PBot::Imports;

sub new($class, %args) {
    return bless {
        # list of entries; each entry is expected to have a `priority` and an `id` field
        queue => [],
    }, $class;
}

sub queue($self) {
    return $self->{queue};
}

sub entries($self) {
    return @{$self->{queue}};
}

sub count($self) {
    return scalar @{$self->{queue}};
}

sub get($self, $position) {
    return $self->{queue}->[$position];
}

sub get_priority($self, $position) {
    return $self->{queue}->[$position]->{priority};
}

sub remove($self, $position) {
    return splice @{$self->{queue}}, $position, 1;
}

# quickly and efficiently find the best position in the entry
# queue array for a given priority value
sub find_enqueue_position($self, $priority = 0) {
    # shorter alias
    my $queue = $self->{queue};

    # no entries in queue yet, early-return first position
    return 0 if not @$queue;

    # early-return first position if entry's priority is less
    # than first position's
    if ($priority < $queue->[0]->{priority}) {
        return 0;
    }

    # early-return last position if entry's priority is greater
    if ($priority > $queue->[@$queue - 1]->{priority}) {
        return scalar @$queue;
    }

    # binary search to find enqueue position

    my $lo = 0;
    my $hi = scalar @$queue - 1;

    while ($lo <= $hi) {
        my $mid = int (($hi + $lo) / 2);

        if ($priority < $queue->[$mid]->{priority}) {
            $hi = $mid - 1;
        } elsif ($priority > $queue->[$mid]->{priority}) {
            $lo = $mid + 1;
        } else {
            # found a slot with the same priority. we "slide" down the array
            # to append this entry to the end of this region of same-priorities
            # and then return the final slot
            while ($mid < @$queue and $queue->[$mid]->{priority} == $priority) {
                $mid++;
            }
            return $mid;
        }
    }

    return $lo;
}

sub add($self, $entry) {
    my $position = $self->find_enqueue_position($entry->{priority});
    splice @{$self->{queue}}, $position, 0, $entry;
    return $position;
}

sub update_priority($self, $id, $priority) {
    my @entries = grep { $_->{id} eq $id } @{$self->{queue}};
    map { $_->{priority} = $priority } @entries;
    $self->{queue} = [ sort { $a->{priority} <=> $b->{priority} } @{$self->{queue}} ];
}

1;
