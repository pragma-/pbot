# File: AutoRejoin.pm
#
# Purpose: Auto-rejoin channels after kick or whatever.

# SPDX-FileCopyrightText: 2016-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::AutoRejoin;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use Time::HiRes qw/gettimeofday/;
use Time::Duration;

sub initialize($self, %conf) {
    $self->{pbot}->{registry}->add_default('array', 'autorejoin', 'rejoin_delay', '900,1800,3600');
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick', sub { $self->on_kick(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.part', sub { $self->on_part(@_) });
    $self->{rejoins} = {};
}

sub unload($self) {
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.kick');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.part');
}

sub rejoin_channel($self, $channel) {
    if (not exists $self->{rejoins}->{$channel}) {
        $self->{rejoins}->{$channel}->{rejoins} = 0;
    }

    my $delay = $self->{pbot}->{registry}->get_array_value($channel, 'rejoin_delay', $self->{rejoins}->{$channel}->{rejoins});

    if (not defined $delay) {
        $delay = $self->{pbot}->{registry}->get_array_value('autorejoin', 'rejoin_delay', $self->{rejoins}->{$channel}->{rejoins});
    }

    $self->{pbot}->{interpreter}->add_botcmd_to_command_queue($channel, "join $channel", $delay);

    $delay = duration $delay;
    $self->{pbot}->{logger}->log("Rejoining $channel in $delay.\n");
    $self->{rejoins}->{$channel}->{last_rejoin} = gettimeofday;
}

sub on_kick($self, $event_type, $event) {
    my ($nick, $user, $host, $target, $channel, $reason) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->to,
        $event->{args}[0],
        $event->{args}[1],
    );

    return 0 if not $self->{pbot}->{channels}->is_active($channel);
    return 0 if $self->{pbot}->{channels}->{storage}->get_data($channel, 'noautorejoin');

    if ($target eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
        $self->rejoin_channel($channel);
    }

    return 1;
}

sub on_part($self, $event_type, $event) {
    my ($nick, $user, $host, $channel) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->to,
    );

    return 0 if not $self->{pbot}->{channels}->is_active($channel);
    return 0 if $self->{pbot}->{channels}->{storage}->get_data($channel, 'noautorejoin');

    if ($nick eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
        $self->rejoin_channel($channel);
    }

    return 1;
}

1;
