# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Just a quick interface to test/play with PBot::Utils::ParseDate

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
