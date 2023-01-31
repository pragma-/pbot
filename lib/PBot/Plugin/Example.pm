# File: Example.pm
#
# Purpose: Example plugin boilerplate.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Example;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{event_dispatcher}->register_handler(
        'irc.public',
        sub { $self->on_public(@_) },
    );
}

sub unload {
    my $self = shift;

    # perform plugin clean-up here
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
}

sub on_public {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $msg) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->args,
    );

    if ($event->{interpreted}) {
        $self->{pbot}->{logger}->log("Message was already handled by the interpreter.\n");
        return 0; # event not handled by plugin
    }

    $self->{pbot}->{logger}->log("Example plugin: got message from $nick!$user\@$host: $msg\n");
    return 1;  # event handled by plugin
}

1;
