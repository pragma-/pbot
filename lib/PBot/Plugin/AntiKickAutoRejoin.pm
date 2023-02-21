# File: AntiKickAutoRejoin.pm
#
# Purpose: Temporarily bans people who immediately auto-rejoin after a kick.

# SPDX-FileCopyrightText: 2014-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::AntiKickAutoRejoin;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use Time::HiRes qw/gettimeofday/;
use Time::Duration;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{registry}->add_default('array', 'antikickautorejoin', 'punishment', '30,90,180,300,28800');
    $self->{pbot}->{registry}->add_default('text',  'antikickautorejoin', 'threshold',  '2');

    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick', sub { $self->on_kick(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.join', sub { $self->on_join(@_) });
    $self->{kicks} = {};
}

sub unload {
    my ($self) = @_;
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.kick');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.join');
}

sub on_kick {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host) = ($event->nick, $event->user, $event->host);
    my ($target, $channel, $reason) = ($event->to, $event->{args}[0], $event->{args}[1]);

    $channel = lc $channel;
    return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);
    return 0 if $reason eq '*BANG!*'; # roulette

    if (not exists $self->{kicks}->{$channel} or not exists $self->{kicks}->{$channel}->{$target}) {
        $self->{kicks}->{$channel}->{$target}->{rejoins} = 0;
    }

    $self->{kicks}->{$channel}->{$target}->{last_kick} = gettimeofday;
    return 0;
}

sub on_join {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $channel) = ($event->nick, $event->user, $event->host, $event->to);

    $channel = lc $channel;
    return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);

    my $u = $self->{pbot}->{users}->loggedin($channel, "$nick!$user\@$host");
    return 0 if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

    if (exists $self->{kicks}->{$channel} and exists $self->{kicks}->{$channel}->{$nick}) {
        my $now = gettimeofday;

        if ($now - $self->{kicks}->{$channel}->{$nick}->{last_kick} <= $self->{pbot}->{registry}->get_value('antikickautorejoin', 'threshold')) {
            my $timeout  = $self->{pbot}->{registry}->get_array_value('antikickautorejoin', 'punishment', $self->{kicks}->{$channel}->{$nick}->{rejoins});
            my $duration = duration($timeout);
            $duration =~ s/s$//;    # hours -> hour, minutes -> minute

            $self->{pbot}->{banlist}->ban_user_timed(
                $channel,
                'b',
                "*!$user\@$host",
                $timeout,
                $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                'autorejoining after kick',
            );
            $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $nick $duration ban for auto-rejoining after kick; use this time to think about why you were kicked");
            $self->{pbot}->{chanops}->gain_ops($channel);
            $self->{kicks}->{$channel}->{$nick}->{rejoins}++;
        }
    }

    return 0;
}

1;
