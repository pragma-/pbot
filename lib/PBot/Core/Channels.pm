# File: Channels.pm
#
# Purpose: Manages list of channels and auto-joins.

# SPDX-FileCopyrightText: 2010-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Channels;
use parent 'PBot::Core::Class';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;

    $self->{storage} = PBot::Core::Storage::HashObject->new(
        pbot     => $self->{pbot},
        name     => 'Channels',
        filename => $conf{filename}
    );

    $self->{storage}->load;

    # reset joined_channels flag when disconnected
    $self->{pbot}->{event_dispatcher}->register_handler(
        'pbot.disconnect',
        sub {
            $self->{pbot}->{joined_channels} = 0;
        }
    );
}

sub join {
    my ($self, $channels) = @_;

    return if not $channels;

    $self->{pbot}->{conn}->join($channels);

    foreach my $channel (split /,/, $channels) {
        $channel = lc $channel;
        $self->{pbot}->{event_dispatcher}->dispatch_event('pbot.join', { channel => $channel });
        $self->{pbot}->{conn}->mode($channel);
    }
}

sub part {
    my ($self, $channel) = @_;
    $channel = lc $channel;
    $self->{pbot}->{event_dispatcher}->dispatch_event('pbot.part', { channel => $channel });
    $self->{pbot}->{conn}->part($channel);
}

sub autojoin {
    my ($self) = @_;

    return if $self->{pbot}->{joined_channels};

    my $channels;
    foreach my $channel ($self->{storage}->get_keys) {
        if ($self->{storage}->get_data($channel, 'enabled')) {
            $channels .= $self->{storage}->get_key_name($channel) . ',';
        }
    }

    return if not $channels;

    $self->{pbot}->{logger}->log("Joining channels: $channels\n");
    $self->join($channels);

    $self->{pbot}->{joined_channels} = 1;
}

sub is_active {
    my ($self, $channel) = @_;
    # returns undef if channel doesn't exist; otherwise, the value of 'enabled'
    return $self->{storage}->get_data($channel, 'enabled');
}

sub is_active_op {
    my ($self, $channel) = @_;
    return $self->is_active($channel) && $self->{storage}->get_data($channel, 'chanop');
}

sub get_meta {
    my ($self, $channel, $key) = @_;
    return $self->{storage}->get_data($channel, $key);
}

1;
