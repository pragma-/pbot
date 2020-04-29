# File: Channels.pm
# Author: pragma_
#
# Purpose: Manages list of channels and auto-joins.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Channels;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

sub initialize {
    my ($self, %conf) = @_;
    $self->{channels} = PBot::HashObject->new(pbot => $self->{pbot}, name => 'Channels', filename => $conf{filename});
    $self->{channels}->load;

    $self->{pbot}->{commands}->register(sub { $self->join_cmd(@_) }, "join",      1);
    $self->{pbot}->{commands}->register(sub { $self->part_cmd(@_) }, "part",      1);
    $self->{pbot}->{commands}->register(sub { $self->set(@_) },      "chanset",   1);
    $self->{pbot}->{commands}->register(sub { $self->unset(@_) },    "chanunset", 1);
    $self->{pbot}->{commands}->register(sub { $self->add(@_) },      "chanadd",   1);
    $self->{pbot}->{commands}->register(sub { $self->remove(@_) },   "chanrem",   1);
    $self->{pbot}->{commands}->register(sub { $self->list(@_) },     "chanlist",  1);

    $self->{pbot}->{capabilities}->add('admin', 'can-join',     1);
    $self->{pbot}->{capabilities}->add('admin', 'can-part',     1);
    $self->{pbot}->{capabilities}->add('admin', 'can-chanlist', 1);
}

sub join_cmd {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;
    foreach my $channel (split /[\s+,]/, $arguments) {
        $self->{pbot}->{logger}->log("$nick!$user\@$host made me join $channel\n");
        $self->join($channel);
    }
    return "/msg $nick Joining $arguments";
}

sub part_cmd {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;
    $arguments = $from if not $arguments;
    foreach my $channel (split /[\s+,]/, $arguments) {
        $self->{pbot}->{logger}->log("$nick!$user\@$host made me part $channel\n");
        $self->part($channel);
    }
    return "/msg $nick Parting $arguments";
}

sub set {
    my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
    my ($channel, $key, $value) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);
    return "Usage: chanset <channel> [key [value]]" if not defined $channel;
    return $self->{channels}->set($channel, $key, $value);
}

sub unset {
    my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
    my ($channel, $key) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);
    return "Usage: chanunset <channel> <key>" if not defined $channel or not defined $key;
    return $self->{channels}->unset($channel, $key);
}

sub add {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;
    return "Usage: chanadd <channel>" if not defined $arguments or not length $arguments;

    my $data = {
        enabled => 1,
        chanop  => 0,
        permop  => 0
    };

    return $self->{channels}->add($arguments, $data);
}

sub remove {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;
    return "Usage: chanrem <channel>" if not defined $arguments or not length $arguments;

    # clear banlists
    $self->{pbot}->{banlist}->remove($arguments);
    $self->{pbot}->{quietlist}->remove($arguments);
    $self->{pbot}->{timer}->dequeue_event("unban $arguments .*");
    $self->{pbot}->{timer}->dequeue_event("unmute $arguments .*");

    # TODO: ignores, etc?
    return $self->{channels}->remove($arguments);
}

sub list {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;
    my $result;
    foreach my $channel (sort $self->{channels}->get_keys) {
        $result .= $self->{channels}->get_key_name($channel) . ': {';
        my $comma = ' ';
        foreach my $key (sort $self->{channels}->get_keys($channel)) {
            $result .= "$comma$key => " . $self->{channels}->get_data($channel, $key);
            $comma = ', ';
        }
        $result .= " }\n";
    }
    return $result;
}

sub join {
    my ($self, $channels) = @_;

    $self->{pbot}->{conn}->join($channels);

    foreach my $channel (split /,/, $channels) {
        $channel = lc $channel;
        $self->{pbot}->{event_dispatcher}->dispatch_event('pbot.join', {channel => $channel});

        delete $self->{pbot}->{chanops}->{is_opped}->{$channel};
        delete $self->{pbot}->{chanops}->{op_requested}->{$channel};

        if ($self->{channels}->exists($channel) and $self->{channels}->get_data($channel, 'permop')) {
            $self->gain_ops($channel);
        }

        $self->{pbot}->{conn}->mode($channel);
    }
}

sub part {
    my ($self, $channel) = @_;
    $channel = lc $channel;
    $self->{pbot}->{event_dispatcher}->dispatch_event('pbot.part', {channel => $channel});
    $self->{pbot}->{conn}->part($channel);
    delete $self->{pbot}->{chanops}->{is_opped}->{$channel};
    delete $self->{pbot}->{chanops}->{op_requested}->{$channel};
}

sub autojoin {
    my ($self) = @_;
    return if $self->{pbot}->{joined_channels};
    my $channels;
    foreach my $channel ($self->{channels}->get_keys) {
        if ($self->{channels}->get_data($channel, 'enabled')) {
            $channels .= $self->{channels}->get_key_name($channel) . ',';
        }
    }
    $self->{pbot}->{logger}->log("Joining channels: $channels\n");
    $self->join($channels);
    $self->{pbot}->{joined_channels} = 1;
}

sub is_active {
    my ($self, $channel) = @_;
    # returns undef if channel doesn't exist; otherwise, the value of 'enabled'
    return $self->{channels}->get_data($channel, 'enabled');
}

sub is_active_op {
    my ($self, $channel) = @_;
    return $self->is_active($channel) && $self->{channels}->get_data($channel, 'chanop');
}

sub get_meta {
    my ($self, $channel, $key) = @_;
    return $self->{channels}->get_data($channel, $key);
}

1;
