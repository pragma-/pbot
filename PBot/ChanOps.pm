# File: ChanOps.pm
# Author: pragma_
#
# Purpose: Provides channel operator status tracking and commands.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::ChanOps;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use PBot::ChanOpCommands;
use Time::HiRes qw(gettimeofday);
use Time::Duration qw(concise duration);

sub initialize {
    my ($self, %conf) = @_;

    $self->{op_commands}  = {};
    $self->{is_opped}     = {};
    $self->{op_requested} = {};

    $self->{commands} = PBot::ChanOpCommands->new(pbot => $self->{pbot});

    $self->{pbot}->{registry}->add_default('text', 'general', 'deop_timeout', 300);

    $self->{pbot}->{timer}->register(sub { $self->check_opped_timeouts },  10, 'Check Opped Timeouts');
}

sub track_mode {
    my ($self, $source, $channel, $mode, $target) = @_;

    $channel = lc $channel;
    $target  = lc $target;

    if ($target eq lc $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
        if ($mode eq '+o') {
            $self->{pbot}->{logger}->log("$source opped me in $channel\n");
            my $timeout = $self->{pbot}->{registry}->get_value($channel, 'deop_timeout') // $self->{pbot}->{registry}->get_value('general', 'deop_timeout');
            $self->{is_opped}->{$channel}{timeout} = gettimeofday + $timeout;
            delete $self->{op_requested}->{$channel};
            $self->perform_op_commands($channel);
        } elsif ($mode eq '-o') {
            $self->{pbot}->{logger}->log("$source removed my ops in $channel\n");
            delete $self->{is_opped}->{$channel};
        } else {
            $self->{pbot}->{logger}->log("ChanOps: $source performed unhandled mode '$mode' on me\n");
        }
    }
}

sub can_gain_ops {
    my ($self, $channel) = @_;
    $channel = lc $channel;
    return
         $self->{pbot}->{channels}->{channels}->exists($channel)
      && $self->{pbot}->{channels}->{channels}->get_data($channel, 'chanop')
      && $self->{pbot}->{channels}->{channels}->get_data($channel, 'enabled');
}

sub gain_ops {
    my $self    = shift;
    my $channel = shift;
    $channel = lc $channel;

    return if exists $self->{op_requested}->{$channel};
    return if not $self->can_gain_ops($channel);

    my $op_nick = $self->{pbot}->{registry}->get_value($channel, 'op_nick') // $self->{pbot}->{registry}->get_value('general', 'op_nick') // 'chanserv';

    my $op_command = $self->{pbot}->{registry}->get_value($channel, 'op_command') // $self->{pbot}->{registry}->get_value('general', 'op_command') // "op $channel";

    $op_command =~ s/\$channel\b/$channel/g;

    if (not exists $self->{is_opped}->{$channel}) {
        $self->{pbot}->{conn}->privmsg($op_nick, $op_command);
        $self->{op_requested}->{$channel} = scalar gettimeofday;
    } else {
        $self->perform_op_commands($channel);
    }
}

sub lose_ops {
    my $self    = shift;
    my $channel = shift;
    $channel = lc $channel;
    $self->{pbot}->{conn}->mode($channel, '-o ' . $self->{pbot}->{registry}->get_value('irc', 'botnick'));
}

sub add_op_command {
    my ($self, $channel, $command) = @_;
    $channel = lc $channel;
    return if not $self->can_gain_ops($channel);
    push @{$self->{op_commands}->{$channel}}, $command;
}

sub perform_op_commands {
    my $self    = shift;
    my $channel = shift;
    $channel = lc $channel;
    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

    $self->{pbot}->{logger}->log("Performing op commands...\n");
    while (my $command = shift @{$self->{op_commands}->{$channel}}) {
        if ($command =~ /^mode (.*?) (.*)/i) {
            $self->{pbot}->{conn}->mode($1, $2);
            $self->{pbot}->{logger}->log("  executing mode $1 $2\n");
        } elsif ($command =~ /^kick (.*?) (.*?) (.*)/i) {
            $self->{pbot}->{conn}->kick($1, $2, $3) unless $1 =~ /^\Q$botnick\E$/i;
            $self->{pbot}->{logger}->log("  executing kick on $1 $2 $3\n");
        } elsif ($command =~ /^sl (.*)/i) {
            $self->{pbot}->{conn}->sl($1);
            $self->{pbot}->{logger}->log("  executing sl $1\n");
        }
    }
    $self->{pbot}->{logger}->log("Done.\n");
}

sub check_opped_timeouts {
    my $self = shift;
    my $now  = gettimeofday();
    foreach my $channel (keys %{$self->{is_opped}}) {
        if ($self->{is_opped}->{$channel}{timeout} < $now) {
            unless ($self->{pbot}->{channels}->{channels}->exists($channel) and $self->{pbot}->{channels}->{channels}->get_data($channel, 'permop')) { $self->lose_ops($channel); }
        }
    }

    foreach my $channel (keys %{$self->{op_requested}}) {
        if ($now - $self->{op_requested}->{$channel} > 60 * 5) {
            if ($self->{pbot}->{channels}->{channels}->exists($channel) and $self->{pbot}->{channels}->{channels}->get_data($channel, 'enabled')) {
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
