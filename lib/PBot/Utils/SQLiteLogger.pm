# File: SQLiteLogger
#
# Purpose: Logs SQLite trace messages to Logger.pm with profiling of elapsed
# time between messages.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Utils::SQLiteLogger;

use PBot::Imports;

use Time::HiRes qw(gettimeofday);

sub new {
    my ($class, %args) = @_;

    my $self = {
        pbot      => $args{pbot},
        buf       => '',
        timestamp => scalar gettimeofday,
    };

    return bless $self, $class;
}

sub log {
    my $self = shift;

    $self->{buf} .= shift;

    # DBI feeds us pieces at a time, so accumulate a complete line
    # before outputing
    if ($self->{buf} =~ tr/\n//) {
        $self->log_message;
        $self->{buf} = '';
    }
}

sub log_message {
    my ($self) = @_;

    my $now     = gettimeofday;
    my $elapsed = $now - $self->{timestamp};

    # log SQL statements that take more than 100ms since the last log
    if ($elapsed >= 0.100) { $self->{pbot}->{logger}->log("^^^ SLOW SQL ^^^\n"); }

    # log SQL statement and elapsed duration since last statement
    $elapsed = sprintf '%10.3f', $elapsed;
    $self->{pbot}->{logger}->log("$elapsed : $self->{buf}");

    # update timestamp
    $self->{timestamp} = $now;
}

sub close {
    my ($self) = @_;

    # log anything left in buf when closing
    if ($self->{buf}) {
        $self->log_message;
        $self->{buf} = '';
    }
}

1;
