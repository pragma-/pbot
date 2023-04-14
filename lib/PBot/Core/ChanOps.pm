# File: ChanOps.pm
#
# Purpose: Manages channel operator status and command queues.
#
# Unless the `permop` metadata is set, PBot remains unopped until an OP-related
# command is queued. When a command is queued, PBot will request OP status.
# Until PBot gains Op status, new OP commands will be added to the queue. Once
# PBot gains OP status, all queued commands are invoked and then after a
# timeout PBot will remove its OP status.

# SPDX-FileCopyrightText: 2010-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::ChanOps;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes    qw(gettimeofday);
use Time::Duration qw(concise duration);

sub initialize($self, %conf) {
    $self->{op_commands}  = {}; # OP command queue
    $self->{op_requested} = {}; # channels PBot has requested OP
    $self->{is_opped}     = {}; # channels PBot is currently OP

    # default de-OP timeout
    $self->{pbot}->{registry}->add_default('text', 'general', 'deop_timeout', 300);

    # TODO: enqueue OP events as needed instead of naively checking every 10 seconds
    $self->{pbot}->{event_queue}->enqueue(sub { $self->check_opped_timeouts },  10, 'Check opped timeouts');
}

# returns true if PBot can gain OP status in $channel
sub can_gain_ops($self, $channel) {
    return
         $self->{pbot}->{channels}->{storage}->exists($channel)
      && $self->{pbot}->{channels}->{storage}->get_data($channel, 'chanop')
      && $self->{pbot}->{channels}->{storage}->get_data($channel, 'enabled');
}

# sends request to gain OP status in $channel
sub gain_ops($self, $channel) {
    $channel = lc $channel;

    return if exists $self->{op_requested}->{$channel};
    return if not $self->can_gain_ops($channel);

    if (not exists $self->{is_opped}->{$channel}) {
        # not opped in channel, send request for ops
        my $op_nick = $self->{pbot}->{registry}->get_value($channel, 'op_nick')
            // $self->{pbot}->{registry}->get_value('general', 'op_nick')
            // 'chanserv';

        my $op_command = $self->{pbot}->{registry}->get_value($channel, 'op_command')
            // $self->{pbot}->{registry}->get_value('general', 'op_command')
            // "op $channel";

        $op_command =~ s/\$channel\b/$channel/g;

        $self->{pbot}->{conn}->privmsg($op_nick, $op_command);
        $self->{op_requested}->{$channel} = scalar gettimeofday;
    } else {
        # already opped, invoke op commands
        $self->perform_op_commands($channel);
    }
}

# removes OP status in $channel
sub lose_ops($self, $channel) {
    $channel = lc $channel;
    $self->{pbot}->{conn}->mode($channel, '-o ' . $self->{pbot}->{registry}->get_value('irc', 'botnick'));
}

# adds a command to the OP command queue
sub add_op_command($self, $channel, $command) {
    return if not $self->can_gain_ops($channel);
    push @{$self->{op_commands}->{lc $channel}}, $command;
}

# invokes commands in OP command queue
sub perform_op_commands($self, $channel) {
    $channel = lc $channel;

    $self->{pbot}->{logger}->log("Performing op commands in $channel:\n");

    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

    while (my $command = shift @{$self->{op_commands}->{$channel}}) {
        if ($command =~ /^mode (.*?) (.*)/i) {
            $self->{pbot}->{logger}->log("  executing mode $1 $2\n");
            $self->{pbot}->{conn}->mode($1, $2);
        }
        elsif ($command =~ /^kick (.*?) (.*?) (.*)/i) {
            $self->{pbot}->{logger}->log("  executing kick on $1 $2 $3\n");
            $self->{pbot}->{conn}->kick($1, $2, $3) unless $1 =~ /^\Q$botnick\E$/i;
        }
        elsif ($command =~ /^sl (.*)/i) {
            $self->{pbot}->{logger}->log("  executing sl $1\n");
            $self->{pbot}->{conn}->sl($1);
        }
    }

    $self->{pbot}->{logger}->log("Done.\n");
}

# manages OP-related timeouts
sub check_opped_timeouts($self) {
    my $now  = gettimeofday();
    foreach my $channel (keys %{$self->{is_opped}}) {
        if ($self->{is_opped}->{$channel}{timeout} < $now) {
            unless ($self->{pbot}->{channels}->{storage}->exists($channel) and $self->{pbot}->{channels}->{storage}->get_data($channel, 'permop')) { $self->lose_ops($channel); }
        }
    }

    foreach my $channel (keys %{$self->{op_requested}}) {
        if ($now - $self->{op_requested}->{$channel} > 60 * 5) {
            if ($self->{pbot}->{channels}->{storage}->exists($channel) and $self->{pbot}->{channels}->{storage}->get_data($channel, 'enabled')) {
                $self->{pbot}->{logger}->log("5 minutes since OP request for $channel and no OP yet; trying again ...\n");
                delete $self->{op_requested}->{$channel};
                $self->gain_ops($channel);
            } else {
                $self->{pbot}->{logger}->log("Disregarding OP request for $channel (channel is disabled)\n");
                delete $self->{op_requested}->{$channel};
            }
        }
    }
}

1;
