# File: Channels.pm
#
# Purpose: Commands to manage list of channels, and channel metadata.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::Channels;

use PBot::Imports;
use parent 'PBot::Core::Class';

sub initialize {
    my ($self, %conf) = @_;

    # register commands
    $self->{pbot}->{commands}->register(sub { $self->cmd_join(@_) },   "join",      1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_part(@_) },   "part",      1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_set(@_) },    "chanset",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unset(@_) },  "chanunset", 1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_add(@_) },    "chanadd",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_remove(@_) }, "chanrem",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_list(@_) },   "chanlist",  1);

    # add capabilities to admin group
    $self->{pbot}->{capabilities}->add('admin', 'can-join',     1);
    $self->{pbot}->{capabilities}->add('admin', 'can-part',     1);
    $self->{pbot}->{capabilities}->add('admin', 'can-chanlist', 1);
}

sub cmd_join {
    my ($self, $context) = @_;
    foreach my $channel (split /[\s+,]/, $context->{arguments}) {
        $self->{pbot}->{logger}->log("$context->{hostmask} made me join $channel\n");
        $self->{pbot}->{channels}->join($channel);
    }
    return "/msg $context->{nick} Joining $context->{arguments}";
}

sub cmd_part {
    my ($self, $context) = @_;
    $context->{arguments} = $context->{from} if not $context->{arguments};
    foreach my $channel (split /[\s+,]/, $context->{arguments}) {
        $self->{pbot}->{logger}->log("$context->{hostmask} made me part $channel\n");
        $self->{pbot}->{channels}->part($channel);
    }
    return "/msg $context->{nick} Parting $context->{arguments}";
}

sub cmd_set {
    my ($self, $context) = @_;
    my ($channel, $key, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);
    return "Usage: chanset <channel> [key [value]]" if not defined $channel;
    return $self->{pbot}->{channels}->{storage}->set($channel, $key, $value);
}

sub cmd_unset {
    my ($self, $context) = @_;
    my ($channel, $key) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
    return "Usage: chanunset <channel> <key>" if not defined $channel or not defined $key;
    return $self->{pbot}->{channels}->{storage}->unset($channel, $key);
}

sub cmd_add {
    my ($self, $context) = @_;
    return "Usage: chanadd <channel>" if not length $context->{arguments};

    my $data = {
        enabled => 1,
        chanop  => 0,
        permop  => 0
    };

    return $self->{pbot}->{channels}->{storage}->add($context->{arguments}, $data);
}

sub cmd_remove {
    my ($self, $context) = @_;
    return "Usage: chanrem <channel>" if not length $context->{arguments};

    # clear banlists
    $self->{pbot}->{banlist}->{banlist}->remove($context->{arguments});
    $self->{pbot}->{banlist}->{quietlist}->remove($context->{arguments});
    $self->{pbot}->{event_queue}->dequeue_event("unban $context->{arguments} .*");
    $self->{pbot}->{event_queue}->dequeue_event("unmute $context->{arguments} .*");

    # TODO: ignores, etc?
    return $self->{storage}->remove($context->{arguments});
}

sub cmd_list {
    my ($self, $context) = @_;
    my $result;
    foreach my $channel (sort $self->{pbot}->{channels}->{storage}->get_keys) {
        $result .= $self->{pbot}->{channels}->{storage}->get_key_name($channel) . ': {';
        my $comma = ' ';
        foreach my $key (sort $self->{pbot}->{channels}->{storage}->get_keys($channel)) {
            $result .= "$comma$key => " . $self->{pbot}->{channels}->{storage}->get_data($channel, $key);
            $comma = ', ';
        }
        $result .= " }\n";
    }
    return $result;
}

1;
