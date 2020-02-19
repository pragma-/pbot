# File: SQLiteLogger
# Author: pragma_
#
# Purpose: Logs SQLite trace messages to Logger.pm with profiling of elapsed
# time between messages.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::SQLiteLogger;

use strict; use warnings;
use feature 'unicode_strings';

use Time::HiRes qw(gettimeofday);

sub new {
    my ($class, %conf) = @_;
    my $self = {};
    $self->{buf}       = '';
    $self->{timestamp} = gettimeofday;
    $self->{pbot}      = $conf{pbot};
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
    my $self    = shift;
    my $now     = gettimeofday;
    my $elapsed = $now - $self->{timestamp};
    if ($elapsed >= 0.100) { $self->{pbot}->{logger}->log("^^^ SLOW SQL ^^^\n"); }
    $elapsed = sprintf '%10.3f', $elapsed;
    $self->{pbot}->{logger}->log("$elapsed : $self->{buf}");
    $self->{timestamp} = $now;
}

sub close {
    my $self = shift;
    if ($self->{buf}) {
        $self->log_message;
        $self->{buf} = '';
    }
}

1;
