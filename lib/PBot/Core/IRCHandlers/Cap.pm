# File: Cap.pm
#
# Purpose: Handles IRCv3 CAP event.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::IRCHandlers::Cap;

use PBot::Imports;
use parent 'PBot::Core::Class';

sub initialize {
    my ($self, %conf) = @_;

    # IRCv3 client capabilities
    $self->{pbot}->{event_dispatcher}->register_handler('irc.cap', sub { $self->on_cap(@_) });
}

# TODO: CAP NEW and CAP DEL

sub on_cap {
    my ($self, $event_type, $event) = @_;

    # configure client capabilities that PBot currently supports
    my %desired_caps = (
        'account-notify' => 1,
        'extended-join'  => 1,

        # TODO: unsupported capabilities worth looking into
        'away-notify'    => 0,
        'chghost'        => 0,
        'identify-msg'   => 0,
        'multi-prefix'   => 0,
    );

    if ($event->{event}->{args}->[0] eq 'LS') {
        my $capabilities;
        my $caps_done = 0;

        if ($event->{event}->{args}->[1] eq '*') {
            # more CAP LS messages coming
            $capabilities = $event->{event}->{args}->[2];
        } else {
            # final CAP LS message
            $caps_done    = 1;
            $capabilities = $event->{event}->{args}->[1];
        }

        $self->{pbot}->{logger}->log("Client capabilities available: $capabilities\n");

        my @caps = split /\s+/, $capabilities;

        foreach my $cap (@caps) {
            my $value;

            if ($cap =~ /=/) {
                ($cap, $value) = split /=/, $cap;
            } else {
                $value = 1;
            }

            # store available capability
            $self->{pbot}->{irc_capabilities_available}->{$cap} = $value;

            # request desired capabilities
            if ($desired_caps{$cap}) {
                $self->{pbot}->{logger}->log("Requesting client capability $cap\n");
                $event->{conn}->sl("CAP REQ :$cap");
            }
        }

        # capability negotiation done
        # now we either start SASL authentication or we send CAP END
        if ($caps_done) {
            # start SASL authentication if enabled
            if ($self->{pbot}->{registry}->get_value('irc', 'sasl')) {
                $self->{pbot}->{logger}->log("Requesting client capability sasl\n");
                $event->{conn}->sl("CAP REQ :sasl");
            } else {
                $self->{pbot}->{logger}->log("Completed client capability negotiation\n");
                $event->{conn}->sl("CAP END");
            }
        }
    }
    elsif ($event->{event}->{args}->[0] eq 'ACK') {
        $self->{pbot}->{logger}->log("Client capabilities granted: $event->{event}->{args}->[1]\n");

        my @caps = split /\s+/, $event->{event}->{args}->[1];

        foreach my $cap (@caps) {
            $self->{pbot}->{irc_capabilities}->{$cap} = 1;

            if ($cap eq 'sasl') {
                # begin SASL authentication
                # TODO: for now we support only PLAIN
                $self->{pbot}->{logger}->log("Performing SASL authentication PLAIN\n");
                $event->{conn}->sl("AUTHENTICATE PLAIN");
            }
        }
    }
    elsif ($event->{event}->{args}->[0] eq 'NAK') {
        $self->{pbot}->{logger}->log("Client capabilities rejected: $event->{event}->{args}->[1]\n");
    }
    else {
        $self->{pbot}->{logger}->log("Unknown CAP event:\n");
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log(Dumper $event->{event});
    }

    return 1;
}

1;
