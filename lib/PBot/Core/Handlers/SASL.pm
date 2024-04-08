# File: SASL.pm
#
# Purpose: Handles IRCv3 SASL events. Currently only PLAIN is supported.

# SPDX-FileCopyrightText: 2021-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::SASL;

use PBot::Imports;
use parent 'PBot::Core::Class';

use POSIX qw/EXIT_FAILURE/;
use Encode;
use MIME::Base64;

sub initialize($self, %conf) {
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

sub on_sasl_authenticate($self, $event_type, $event) {
    my $nick     = $self->{pbot}->{registry}->get_value('irc', 'identify_nick'); # try identify_nick
       $nick   //= $self->{pbot}->{registry}->get_value('irc', 'botnick');       # fallback to botnick
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

sub on_rpl_loggedin($self, $event_type, $event) {
    $self->{pbot}->{logger}->log($event->{args}[3] . "\n");
    $self->{pbot}->{hostmask} = $event->{args}[1];
    $self->{pbot}->{logger}->log("Set hostmask to $event->{args}[1]\n");
    return 1;
}

sub on_rpl_loggedout($self, $event_type, $event) {
    $self->{pbot}->{logger}->log($event->{args}[1] . "\n");
    return 1;
}

sub on_err_nicklocked($self, $event_type, $event) {
    $self->{pbot}->{logger}->log($event->{args}[1] . "\n");
    $self->{pbot}->exit(EXIT_FAILURE);
}

sub on_rpl_saslsuccess($self, $event_type, $event) {
    $self->{pbot}->{logger}->log($event->{args}[1] . "\n");
    $event->{conn}->sl("CAP END");
    return 1;
}

sub on_err_saslfail($self, $event_type, $event) {
    $self->{pbot}->{logger}->log($event->{args}[1] . "\n");
    $self->{pbot}->exit(EXIT_FAILURE);
}

sub on_err_sasltoolong($self, $event_type, $event) {
    $self->{pbot}->{logger}->log($event->{args}[1] . "\n");
    $self->{pbot}->exit(EXIT_FAILURE);
}

sub on_err_saslaborted($self, $event_type, $event) {
    $self->{pbot}->{logger}->log($event->{args}[1] . "\n");
    $self->{pbot}->exit(EXIT_FAILURE);
}

sub on_err_saslalready($self, $event_type, $event) {
    $self->{pbot}->{logger}->log($event->{args}[1] . "\n");
    return 1;
}

sub on_rpl_saslmechs($self, $event_type, $event) {
    $self->{pbot}->{logger}->log("SASL mechanism not available.\n");
    $self->{pbot}->{logger}->log("Available mechanisms are: $event->{args}[1]\n");
    $self->{pbot}->exit(EXIT_FAILURE);
}

1;
