# File: ParseDate.pm
#
# Purpose: Just a simple interface to test/play with PBot::Utils::ParseDate
# and make sure it's working properly.
#
# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package Plugins::ParseDate;
use parent 'Plugins::Plugin';

use  PBot::Imports;

use Time::Duration qw/duration/;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { return $self->cmd_parsedate(@_) }, "pd", 0);
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister("pd");
}

sub cmd_parsedate {
    my ($self, $context) = @_;
    my ($seconds, $error) = $self->{pbot}->{parsedate}->parsedate($context->{arguments});
    return $error if defined $error;
    return duration $seconds;
}

1;
