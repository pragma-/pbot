# File: Channels.pm
#
# Purpose: Manages list of channels and auto-joins.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Channels;
use parent 'PBot::Class';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;
    $self->{channels} = PBot::HashObject->new(pbot => $self->{pbot}, name => 'Channels', filename => $conf{filename});
    $self->{channels}->load;

    $self->{pbot}->{commands}->register(sub { $self->cmd_join(@_) },   "join",      1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_part(@_) },   "part",      1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_set(@_) },    "chanset",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unset(@_) },  "chanunset", 1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_add(@_) },    "chanadd",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_remove(@_) }, "chanrem",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_list(@_) },   "chanlist",  1);

    $self->{pbot}->{capabilities}->add('admin', 'can-join',     1);
    $self->{pbot}->{capabilities}->add('admin', 'can-part',     1);
    $self->{pbot}->{capabilities}->add('admin', 'can-chanlist', 1);
}

sub cmd_join {
    my ($self, $context) = @_;
    foreach my $channel (split /[\s+,]/, $context->{arguments}) {
        $self->{pbot}->{logger}->log("$context->{hostmask} made me join $channel\n");
        $self->join($channel);
    }
    return "/msg $context->{nick} Joining $context->{arguments}";
}

sub cmd_part {
    my ($self, $context) = @_;
    $context->{arguments} = $context->{from} if not $context->{arguments};
    foreach my $channel (split /[\s+,]/, $context->{arguments}) {
        $self->{pbot}->{logger}->log("$context->{hostmask} made me part $channel\n");
        $self->part($channel);
    }
    return "/msg $context->{nick} Parting $context->{arguments}";
}

sub cmd_set {
    my ($self, $context) = @_;
    my ($channel, $key, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);
    return "Usage: chanset <channel> [key [value]]" if not defined $channel;
    return $self->{channels}->set($channel, $key, $value);
}

sub cmd_unset {
    my ($self, $context) = @_;
    my ($channel, $key) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
    return "Usage: chanunset <channel> <key>" if not defined $channel or not defined $key;
    return $self->{channels}->unset($channel, $key);
}

sub cmd_add {
    my ($self, $context) = @_;
    return "Usage: chanadd <channel>" if not length $context->{arguments};

    my $data = {
        enabled => 1,
        chanop  => 0,
        permop  => 0
    };

    return $self->{channels}->add($context->{arguments}, $data);
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
    return $self->{channels}->remove($context->{arguments});
}

sub cmd_list {
    my ($self, $context) = @_;
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
            $self->{pbot}->{chanops}->gain_ops($channel);
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
