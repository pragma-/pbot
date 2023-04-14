# File: IgnoreList.pm
#
# Purpose: Manages ignore list.

# SPDX-FileCopyrightText: 2001-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::IgnoreList;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::Duration qw/duration/;

sub initialize($self, %conf) {
    $self->{filename} = $conf{filename};

    $self->{storage} = PBot::Core::Storage::DualIndexHashObject->new(
        pbot     => $self->{pbot},
        name     => 'IgnoreList',
        filename => $self->{filename}
    );

    $self->{storage}->load;
    $self->enqueue_ignores;
}

sub enqueue_ignores($self) {
    my $now    = time;

    foreach my $channel ($self->{storage}->get_keys) {
        foreach my $hostmask ($self->{storage}->get_keys($channel)) {
            my $timeout = $self->{storage}->get_data($channel, $hostmask, 'timeout');
            next if $timeout == -1; # permanent ignore

            my $interval = $timeout - $now;
            $interval = 0 if $interval < 0;

            $self->{pbot}->{event_queue}->enqueue_event(sub {
                    $self->remove($channel, $hostmask);
                }, $interval, "ignore_timeout $channel $hostmask"
            );
        }
    }
}

sub add($self, $channel, $hostmask, $length, $owner) {
    if ($hostmask !~ /!/) {
        $hostmask .= '!*@*';
    } elsif ($hostmask !~ /@/) {
        $hostmask .= '@*';
    }

    $channel = '.*' if $channel !~ /^#/;

    my $regex = quotemeta $hostmask;
    $regex =~ s/\\\*/.*?/g;
    $regex =~ s/\\\?/./g;

    my $data = {
        owner => $owner,
        created_on => time,
        regex => $regex,
    };

    if ($length < 0) {
        $data->{timeout} = -1;
    } else {
        $data->{timeout} = time + $length;
    }

    $self->{storage}->add($channel, $hostmask, $data);

    if ($length > 0) {
        $self->{pbot}->{event_queue}->dequeue_event("ignore_timeout $channel $hostmask");

        $self->{pbot}->{event_queue}->enqueue_event(sub {
                $self->remove($channel, $hostmask);
            }, $length, "ignore_timeout $channel $hostmask"
        );
    }

    my $duration = $data->{timeout} == -1 ? 'all eternity' : duration $length;
    return "$hostmask ignored for $duration";
}

sub remove($self, $channel, $hostmask) {
    if ($hostmask !~ /!/) {
        $hostmask .= '!*@*';
    } elsif ($hostmask !~ /@/) {
        $hostmask .= '@*';
    }

    $channel = '.*' if $channel !~ /^#/;

    $self->{pbot}->{event_queue}->dequeue_event("ignore_timeout $channel $hostmask");
    return $self->{storage}->remove($channel, $hostmask);
}

sub is_ignored($self, $channel, $hostmask) {
    return 0 if $self->{pbot}->{users}->loggedin_admin($channel, $hostmask);

    foreach my $chan ('.*', $channel) {
        foreach my $ignored ($self->{storage}->get_keys($chan)) {
            my $regex = $self->{storage}->get_data($chan, $ignored, 'regex');
            return 1 if $hostmask =~ /^$regex$/i;
        }
    }

    return 0;
}

1;
