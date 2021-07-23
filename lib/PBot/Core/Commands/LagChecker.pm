# File: LagChecker.pm
#
# Purpose: Registers command to query lag history.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::LagChecker;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::Duration qw/concise ago/;
use Time::HiRes qw/gettimeofday/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->register(sub { $self->cmd_lagcheck(@_) }, "lagcheck", 0);
}

sub cmd_lagcheck {
    my ($self, $context) = @_;

    if (defined $self->{pbot}->{lagchecker}->{pong_received} and $self->{pbot}->{lagchecker}->{pong_received} == 0) {
        # a ping has been sent (pong_received is not undef) and no pong has been received yet
        my $elapsed   = tv_interval($self->{pbot}->{lagchecker}->{ping_send_time});
        my $lag_total = $elapsed;
        my $len       = @{$self->{pbot}->{lagchecker}->{lag_history}};

        my @entries;

        foreach my $entry (@{$self->{pbot}->{lagchecker}->{lag_history}}) {
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

    return "My lag: " . $self->{pbot}->{lagchecker}->lagstring;
}


1;
