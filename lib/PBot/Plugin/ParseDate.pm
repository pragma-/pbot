# File: ParseDate.pm
#
# Purpose: Just a simple interface to test/play with PBot::Core::Utils::ParseDate
# and make sure it's working properly.
#
# SPDX-FileCopyrightText: 2017-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::ParseDate;
use parent 'PBot::Plugin::Base';

use  PBot::Imports;

use Time::Duration qw/duration/;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->add(
        name   => 'pd',
        help   => 'Simple command to test ParseDate interface',
        subref =>sub { return $self->cmd_parsedate(@_) },
    );
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->remove('pd');
}

sub cmd_parsedate {
    my ($self, $context) = @_;
    my ($seconds, $error) = $self->{pbot}->{parsedate}->parsedate($context->{arguments});
    return $error if defined $error;
    return duration $seconds;
}

1;
