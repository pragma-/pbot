# File: Cap.pm
#
# Purpose: Handles IRCv3 CAP event.

# SPDX-FileCopyrightText: 2021-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::Cap;

use PBot::Imports;
use parent 'PBot::Core::Class';

use POSIX qw/EXIT_FAILURE/;

sub initialize($self, %conf) {
    # IRCv3 client capabilities
    $self->{pbot}->{event_dispatcher}->register_handler('irc.cap', sub { $self->on_cap(@_) });
}

# TODO: CAP NEW and CAP DEL

sub on_cap($self, $event_type, $event) {
    if ($event->{args}[0] eq 'LS') {
        my $capabilities;
        my $caps_listed = 0;

        if ($event->{args}[1] eq '*') {
            # more CAP LS messages coming
            $capabilities = $event->{args}[2];
        } else {
            # final CAP LS message
            $caps_listed    = 1;
            $capabilities = $event->{args}[1];
        }

        $self->{pbot}->{logger}->log("Client capabilities available: $capabilities\n");

        my @caps = split /\s+/, $capabilities;

        # store available capabilities
        foreach my $cap (@caps) {
            my $value;

            ($cap, $value) = split /=/, $cap;
            $value //= 1;

            $self->{pbot}->{irc_capabilities_available}->{$cap} = $value;
        }

        # all capabilities listed?
        if ($caps_listed) {
            # request desired capabilities
            $self->request_caps($event);
        }
    }
    elsif ($event->{args}[0] eq 'ACK') {
        $self->{pbot}->{logger}->log("Client capabilities granted: $event->{args}[1]\n");

        my @caps = split /\s+/, $event->{args}[1];

        foreach my $cap (@caps) {
            my ($key, $val) = split '=', $cap;
            $val //= 1;

            $self->{pbot}->{irc_capabilities}->{$key} = $val;

            if ($cap eq 'sasl') {
                # begin SASL authentication
                # TODO: for now we support only PLAIN
                $self->{pbot}->{logger}->log("Performing SASL authentication PLAIN\n");
                $event->{conn}->sl("AUTHENTICATE PLAIN");
            }
        }
    }
    elsif ($event->{args}[0] eq 'NAK') {
        $self->{pbot}->{logger}->log("Client capabilities rejected: $event->{args}[1]\n");
    }
    else {
        $self->{pbot}->{logger}->log("Unknown CAP event:\n");
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log(Dumper $event->{event});
    }

    return 1;
}

sub request_caps($self, $event) {
    # configure client capabilities that PBot currently supports
    my %desired_caps = (
        'account-notify' => 1,
        'account-tag'    => 1,
        'chghost'        => 1,
        'extended-join'  => 1,
        'message-tags'   => 1,
        'multi-prefix'   => 1,
        # sasl is gated by the irc.sasl registry entry instead

        # TODO: unsupported capabilities worth looking into
        'away-notify'    => 0,
        'identify-msg'   => 0,
    );

    foreach my $cap (keys $self->{pbot}->{irc_capabilities_available}->%*) {
        # request desired capabilities
        if ($desired_caps{$cap}) {
            $self->{pbot}->{logger}->log("Requesting client capability $cap\n");
            $event->{conn}->sl("CAP REQ :$cap");
        }
    }

    # request SASL capability if enabled, otherwise end cap negotiation
    if ($self->{pbot}->{registry}->get_value('irc', 'sasl')) {
        if (not exists $self->{pbot}->{irc_capabilities_available}->{sasl}) {
            $self->{pbot}->{logger}->log("SASL is not supported by this IRC server\n");
            $self->{pbot}->exit(EXIT_FAILURE);
        }

        $self->{pbot}->{logger}->log("Requesting client capability sasl\n");
        $event->{conn}->sl("CAP REQ :sasl");
    } else {
        $self->{pbot}->{logger}->log("Completed client capability negotiation\n");
        $event->{conn}->sl("CAP END");
    }
}

1;
