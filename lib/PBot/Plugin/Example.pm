# File: Example.pm
#
# Purpose: Example plugin boilerplate.

# SPDX-FileCopyrightText: 2015-2025 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Example;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize($self, %conf) {
    # an event handler
    $self->{pbot}->{event_dispatcher}->register_handler(
        'irc.public',
        sub { $self->on_public(@_) },
    );

    # a command
    $self->{pbot}->{commands}->add(
        name => 'thing',
        help => 'Does a thing!',
        subref => sub { $self->cmd_thing(@_) },
    );

    # a recurring enqueued event
    $self->{pbot}->{event_queue}->enqueue(sub { $self->recurring_event }, 60, 'Recurring event');
}

sub unload($self) {
    # perform plugin clean-up here
    $self->{pbot}->{commands}->remove('thing');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
    $self->{pbot}->{event_queue}->dequeue('Recurring event');
}

sub on_public($self, $event_type, $event) {
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

sub cmd_thing($self, $context) {
    my @args = $self->{pbot}->{interpreter}->split_line($context->{arguments});
    # do some command with @args here
}

sub recurring_event($self) {
    # do some event here
}

1;
