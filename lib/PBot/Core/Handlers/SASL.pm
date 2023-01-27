# File: SASL.pm
#
# Purpose: Handles IRCv3 SASL events. Currently only PLAIN is supported.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::SASL;

use PBot::Imports;
use parent 'PBot::Core::Class';

use POSIX qw/EXIT_FAILURE/;
use Encode;
use MIME::Base64;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{event_dispatcher}->register_handler('irc.authenticate',    sub { $self->on_sasl_authenticate (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.rpl_loggedin',    sub { $self->on_rpl_loggedin      (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.rpl_loggedout',   sub { $self->on_rpl_loggedout     (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.err_nicklocked',  sub { $self->on_err_nicklocked    (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.rpl_saslsuccess', sub { $self->on_rpl_saslsuccess   (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.err_saslfail',    sub { $self->on_err_saslfail      (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.err_sasltoolong', sub { $self->on_err_sasltoolong   (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.err_saslaborted', sub { $self->on_err_saslaborted   (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.err_saslalready', sub { $self->on_err_saslalready   (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.rpl_saslmechs',   sub { $self->on_rpl_saslmechs     (@_) });
}

sub on_sasl_authenticate {
    my ($self, $event_type, $event) = @_;

    my $nick     = $self->{pbot}->{registry}->get_value('irc', 'botnick');
    my $password = $self->{pbot}->{registry}->get_value('irc', 'identify_password');

    if (not defined $password or not length $password) {
        $self->{pbot}->{logger}->log("Error: Registry entry irc.identify_password is not set.\n");
        $self->{pbot}->exit(EXIT_FAILURE);
    }

    $password = encode('UTF-8', "$nick\0$nick\0$password");

    $password = encode_base64($password, '');

    my @chunks = unpack('(A400)*', $password);

    foreach my $chunk (@chunks) {
        $event->{conn}->sl("AUTHENTICATE $chunk");
    }

    # must send final AUTHENTICATE + if last chunk was exactly 400 bytes
    if (length $chunks[$#chunks] == 400) {
        $event->{conn}->sl("AUTHENTICATE +");
    }

    return 1;
}

sub on_rpl_loggedin {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[3] . "\n");
    return 1;
}

sub on_rpl_loggedout {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    return 1;
}

sub on_err_nicklocked {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    $self->{pbot}->exit(EXIT_FAILURE);
}

sub on_rpl_saslsuccess {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    $event->{conn}->sl("CAP END");
    return 1;
}

sub on_err_saslfail {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    $self->{pbot}->exit(EXIT_FAILURE);
}

sub on_err_sasltoolong {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    $self->{pbot}->exit(EXIT_FAILURE);
}

sub on_err_saslaborted {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    $self->{pbot}->exit(EXIT_FAILURE);
}

sub on_err_saslalready {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    return 1;
}

sub on_rpl_saslmechs {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log("SASL mechanism not available.\n");
    $self->{pbot}->{logger}->log("Available mechanisms are: $event->{event}->{args}->[1]\n");
    $self->{pbot}->exit(EXIT_FAILURE);
}

1;
