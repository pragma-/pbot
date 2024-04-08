# File: ChanOps.pm
#
# Purpose: Tracks when PBot gains or loses OPs in a channel and invokes
# relevant actions. Handles OP-related actions when PBot joins or parts.

# SPDX-FileCopyrightText: 2005-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::ChanOps;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw(gettimeofday);

sub initialize($self, %conf) {
    $self->{pbot}->{event_dispatcher}->register_handler('pbot.join',    sub { $self->on_self_join(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('pbot.part',    sub { $self->on_self_part(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.modeflag', sub { $self->on_modeflag(@_) });
}

sub on_self_join($self, $event_type, $event) {
    my $channel = $event->{channel};

    delete $self->{pbot}->{chanops}->{is_opped}->{$channel};
    delete $self->{pbot}->{chanops}->{op_requested}->{$channel};

    if ($self->{pbot}->{channels}->{storage}->get_data($channel, 'permop')) {
        $self->{pbot}->{chanops}->gain_ops($channel);
    }

    return 1;
}

sub on_self_part($self, $event_type, $event) {
    my $channel = $event->{channel};
    delete $self->{pbot}->{chanops}->{is_opped}->{$channel};
    delete $self->{pbot}->{chanops}->{op_requested}->{$channel};
    return 1;
}

sub on_modeflag($self, $event_type, $event) {
    my ($source, $channel, $mode, $target) = (
        $event->{source},
        $event->{channel},
        $event->{mode},
        $event->{target},
    );

    $channel = defined $channel ? lc $channel : '';
    $target  = defined $target ? lc $target : '';

    if ($target eq lc $self->{pbot}->{conn}->nick) {
        if ($mode eq '+o') {
            $self->{pbot}->{logger}->log("$source opped me in $channel\n");

            my $timeout = $self->{pbot}->{registry}->get_value($channel, 'deop_timeout')
                // $self->{pbot}->{registry}->get_value('general', 'deop_timeout');

            $self->{pbot}->{chanops}->{is_opped}->{$channel}{timeout} = gettimeofday + $timeout;

            delete $self->{pbot}->{chanops}->{op_requested}->{$channel};

            $self->{pbot}->{chanops}->perform_op_commands($channel);
        }
        elsif ($mode eq '-o') {
            $self->{pbot}->{logger}->log("$source removed my ops in $channel\n");
            delete $self->{pbot}->{chanops}->{is_opped}->{$channel};
        }
        else {
            $self->{pbot}->{logger}->log("ChanOps: $source performed unhandled mode '$mode' on me\n");
        }
    }

    return 1;
}

1;
