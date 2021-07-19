# File: PriorityQueue.pm
#
# Purpose: Bare-bones lightweight implementation of a priority queue.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Utils::PriorityQueue;
use parent 'PBot::Class';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;

    $self->{queue} = [];
}

sub queue {
    my ($self) = @_;
    return $self->{queue};
}

sub entries {
    my ($self) = @_;
    return @{$self->{queue}};
}

sub count {
    my ($self) = @_;
    return scalar @{$self->{queue}};
}

sub get_entry {
    my ($self, $position) = @_;
    return $self->{queue}->[$position];
}

sub get_priority {
    my ($self, $position) = @_;
    return $self->{queue}->[$position]->{priority};
}

sub remove {
    my ($self, $position) = @_;
    return splice @{$self->{queue}}, $position, 1;
}

# quickly and efficiently find the best position in the entry
# queue array for a given priority value
sub find_enqueue_position {
    my ($self, $priority) = @_;

    # no entries in queue yet, early-return first position
    return 0 if not @{$self->{queue}};

    # early-return first position if entry's priority is less
    # than first position's
    if ($priority < $self->{queue}->[0]->{priority}) {
        return 0;
    }

    # early-return last position if entry's priority is greater
    if ($priority > $self->{queue}->[@{$self->{queue}} - 1]->{priority}) {
        return scalar @{$self->{queue}};
    }

    # binary search to find enqueue position

    my $lo = 0;
    my $hi = scalar @{$self->{queue}} - 1;

    while ($lo <= $hi) {
        my $mid = int (($hi + $lo) / 2);

        if ($priority < $self->{queue}->[$mid]->{priority}) {
            $hi = $mid - 1;
        } elsif ($priority > $self->{queue}->[$mid]->{priority}) {
            $lo = $mid + 1;
        } else {
            # found a slot with the same priority. we "slide" down the array
            # to append this entry to the end of this region of same-priorities
            # and then return the final slot
            while ($mid < @{$self->{queue}} and $self->{queue}->[$mid]->{priority} == $priority) {
                $mid++;
            }
            return $mid;
        }
    }

    return $lo;
}

sub add {
    my ($self, $entry) = @_;
    my $position = $self->find_enqueue_position($entry->{priority});
    splice @{$self->{queue}}, $position, 0, $entry;
    return $position;
}

1;
