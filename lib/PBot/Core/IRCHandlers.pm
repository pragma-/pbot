# File: IRCHandlers.pm
#
# Purpose: Pipes the PBot::Core::IRC default handler through PBot::Core::EventDispatcher,
# and loads all the packages in the IRCHandlers directory.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::IRCHandlers;
use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Utils::LoadPackages;

use Data::Dumper;

sub initialize {
    my ($self, %conf) = @_;

    # register all the IRC handlers in the IRCHandlers directory
    $self->register_handlers(%conf);
}

# registers handlers with a PBot::Core::IRC connection

sub add_handlers {
    my ($self) = @_;

    # set up handlers for the IRC engine
    $self->{pbot}->{conn}->add_default_handler(
        sub { $self->default_handler(@_) }, 1);

    # send these events to on_init()
    $self->{pbot}->{conn}->add_handler([251, 252, 253, 254, 255, 302],
        sub { $self->{packages}->{Server}->on_init(@_) });

    # ignore these events
    $self->{pbot}->{conn}->add_handler(
        [
            'myinfo',
            'whoisserver',
            'whoiscountry',
            'whoischannels',
            'whoisidle',
            'motdstart',
            'endofmotd',
            'away',
        ],
        sub { }
    );
}

# registers all the IRC handler files in the IRCHandlers directory

sub register_handlers {
    my ($self, %conf) = @_;

    $self->{pbot}->{logger}->log("Registering IRC handlers:\n");
    load_packages($self, 'PBot::Core::IRCHandlers');
}

# this default handler prepends 'irc.' to the event-type and then dispatches
# the event to the rest of PBot via PBot::Core::EventDispatcher.

sub default_handler {
    my ($self, $conn, $event) = @_;

    my $result = $self->{pbot}->{event_dispatcher}->dispatch_event(
        "irc.$event->{type}",
        {
            conn => $conn,
            event => $event
        }
    );

    # log event if it was not handled and logging is requested
    if (not defined $result and $self->{pbot}->{registry}->get_value('irc', 'log_default_handler')) {
        $Data::Dumper::Sortkeys = 1;
        $Data::Dumper::Indent   = 2;
        $Data::Dumper::Useqq    = 1;
        $self->{pbot}->{logger}->log(Dumper $event);
    }
}

# replace randomized gibberish in certain hostmasks with identifying information

sub normalize_hostmask {
    my ($self, $nick, $user, $host) = @_;

    if ($host =~ m{^(gateway|nat)/(.*)/x-[^/]+$}) {
        $host = "$1/$2/x-$user";
    }

    $host =~ s{/session$}{/x-$user};

    return ($nick, $user, $host);
}

1;
