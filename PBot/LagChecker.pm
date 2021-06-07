# File: LagChecker.pm
# Author: pragma_
#
# Purpose: sends PING command to IRC server and times duration for PONG reply in
# order to maintain lag history and average.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::LagChecker;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';
use utf8;

use Time::HiRes qw(gettimeofday tv_interval);
use Time::Duration;

sub initialize {
    my ($self, %conf) = @_;

    # average of entries in lag history, in seconds
    $self->{lag_average} = undef;

    # string representation of lag history and lag average
    $self->{lag_string} = undef;

    # history of previous PING/PONG timings
    $self->{lag_history} = [];

    # tracks pong replies; undef if no ping sent; 0 if ping sent but no pong reply yet; 1 if ping/pong completed
    $self->{pong_received} = undef;

    # when last ping was sent
    $self->{ping_send_time} = undef;

    # maximum number of lag history entries to retain
    $self->{pbot}->{registry}->add_default('text', 'lagchecker', 'lag_history_max', $conf{lag_history_max} // 3);

    # lagging is true if lag_average reaches or exceeds this threshold, in milliseconds
    $self->{pbot}->{registry}->add_default('text', 'lagchecker', 'lag_threshold', $conf{lag_threshhold} // 2000);

    # how often to send PING, in seconds
    $self->{pbot}->{registry}->add_default('text', 'lagchecker', 'lag_history_interval', $conf{lag_history_interval} // 10);

    # registry trigger for lag_history_interval changes
    $self->{pbot}->{registry}->add_trigger('lagchecker', 'lag_history_interval', sub { $self->trigger_lag_history_interval(@_) });

    # timer to send PINGs
    $self->{pbot}->{timer}->register(
        sub { $self->send_ping },
        $self->{pbot}->{registry}->get_value('lagchecker', 'lag_history_interval'),
        'lag check'
    );

    # lagcheck bot command
    $self->{pbot}->{commands}->register(sub { $self->cmd_lagcheck(@_) }, "lagcheck", 0);

    # PONG IRC handler
    $self->{pbot}->{event_dispatcher}->register_handler('irc.pong', sub { $self->on_pong(@_) });
}

# registry trigger fires when value changes
sub trigger_lag_history_interval {
    my ($self, $section, $item, $newvalue) = @_;
    $self->{pbot}->{timer}->update_interval('lag check', $newvalue);
}

# lagcheck bot command
sub cmd_lagcheck {
    my ($self, $context) = @_;

    if (defined $self->{pong_received} and $self->{pong_received} == 0) {
        # a ping has been sent (pong_received is not undef) and no pong has been received yet
        my $elapsed   = tv_interval($self->{ping_send_time});
        my $lag_total = $elapsed;
        my $len       = @{$self->{lag_history}};

        my @entries;

        foreach my $entry (@{$self->{lag_history}}) {
            my ($send_time, $lag_result) = @$entry;

            $lag_total += $lag_result;

            my $ago = concise ago(gettimeofday - $send_time);

            push @entries, "[$ago] " . sprintf "%.1f ms", $lag_result;
        }

        push @entries, "[waiting for pong] $elapsed";

        my $lagstring = join '; ', @entries;

        my $average = $lag_total / ($len + 1);

        $lagstring .= "; average: " . sprintf "%.1f ms", $average;

        return $lagstring;
    }

    return "My lag: " . $self->lagstring;
}


sub send_ping {
    my $self = shift;

    return unless defined $self->{pbot}->{conn};

    $self->{ping_send_time} = [gettimeofday];
    $self->{pong_received}  = 0;

    $self->{pbot}->{conn}->sl("PING :lagcheck");
}

sub on_pong {
    my $self = shift;

    $self->{pong_received} = 1;

    my $elapsed = tv_interval($self->{ping_send_time});

    push @{$self->{lag_history}}, [$self->{ping_send_time}[0], $elapsed * 1000];

    my $len = @{$self->{lag_history}};

    my $lag_history_max = $self->{pbot}->{registry}->get_value('lagchecker', 'lag_history_max');

    while ($len > $lag_history_max) {
        shift @{$self->{lag_history}};
        $len--;
    }

    $self->{lag_string} = '';

    my @entries;
    my $lag_total = 0;

    foreach my $entry (@{$self->{lag_history}}) {
        my ($send_time, $lag_result) = @$entry;

        $lag_total += $lag_result;

        my $ago = concise ago(gettimeofday - $send_time);

        push @entries, "[$ago] " . sprintf "%.1f ms", $lag_result;
    }

    $self->{lag_string} = join '; ', @entries;

    $self->{lag_average} = $lag_total / $len;

    $self->{lag_string} .= "; average: " . sprintf "%.1f ms", $self->{lag_average};

    return 0;
}

sub lagging {
    my ($self) = @_;

    if (defined $self->{pong_received} and $self->{pong_received} == 0) {
        # a ping has been sent (pong_received is not undef) and no pong has been received yet
        my $elapsed = tv_interval($self->{ping_send_time});

        return $elapsed >= $self->{pbot}->{registry}->get_value('lagchecker', 'lag_threshold');
    }

    return 0 if not defined $self->{lag_average};

    return $self->{lag_average} >= $self->{pbot}->{registry}->get_value('lagchecker', 'lag_threshold');
}

sub lagstring {
    my ($self) = @_;

    my $lag = $self->{lag_string} || "initializing";

    return $lag;
}

1;
