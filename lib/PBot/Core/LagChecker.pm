# File: LagChecker.pm
#
# Purpose: sends PING command to IRC server and times duration for PONG reply in
# order to maintain lag history and average.

# SPDX-FileCopyrightText: 2011-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::LagChecker;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw(gettimeofday tv_interval);
use Time::Duration;

sub initialize($self, %conf) {
    # are we fully connected yet?
    $self->{welcomed} = 0;

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

    # enqueue repeating event  to send PINGs
    $self->{pbot}->{event_queue}->enqueue(
        sub { $self->send_ping },
        $self->{pbot}->{registry}->get_value('lagchecker', 'lag_history_interval'),
        'lag check'
    );

    # PONG IRC handler
    $self->{pbot}->{event_dispatcher}->register_handler('irc.pong', sub { $self->on_pong(@_) });

    # Don't send PING until fully connected
    $self->{pbot}->{event_dispatcher}->register_handler('irc.welcome', sub { $self->on_welcome(@_) });
}

# registry trigger fires when value changes
sub trigger_lag_history_interval($self, $section, $item, $newvalue) {
    $self->{pbot}->{event_queue}->update_interval('lag check', $newvalue);
}

sub send_ping($self) {
    return unless defined $self->{pbot}->{conn} && $self->{pbot}->{conn}->connected && $self->{welcomed};

    if (defined $self->{pong_received} && $self->{pong_received} == 0
        && gettimeofday - $self->{ping_send_time}[0] < 900) {
        return;
    }

    $self->{ping_send_time} = [gettimeofday];
    $self->{pong_received}  = 0;

    $self->{pbot}->{conn}->sl("PING :lagcheck");
}

sub on_welcome($self, $event_type, $event) {
    $self->{welcomed} = 1;
}

sub on_pong($self, $event_type, $event) {
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

sub lagging($self) {
    if (defined $self->{pong_received} and $self->{pong_received} == 0) {
        # a ping has been sent (pong_received is not undef) and no pong has been received yet
        my $elapsed = tv_interval($self->{ping_send_time});
        return $elapsed >= $self->{pbot}->{registry}->get_value('lagchecker', 'lag_threshold');
    }

    return 0 if not defined $self->{lag_average};
    return $self->{lag_average} >= $self->{pbot}->{registry}->get_value('lagchecker', 'lag_threshold');
}

sub lagstring($self) {
    return $self->{lag_string} || "initializing";
}

1;
