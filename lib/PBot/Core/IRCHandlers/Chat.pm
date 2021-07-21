# File: Chat.pm
#
# Purpose: IRC handlers for chat/message events.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::IRCHandlers::Chat;

use PBot::Imports;

sub new {
    my ($class, %args) = @_;

    # ensure class was passed a PBot instance
    if (not exists $args{pbot}) {
        Carp::croak("Missing pbot reference to $class");
    }

    my $self = bless { pbot => $args{pbot} }, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{event_dispatcher}->register_handler('irc.notice',  sub { $self->on_notice (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_action (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.msg',     sub { $self->on_msg    (@_) });
}

sub on_notice {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $to, $text)  = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->to,
        $event->{event}->{args}->[0],
    );

    # don't handle non-chat NOTICE
    return undef if $to eq '*';

    # log notice
    $self->{pbot}->{logger}->log("NOTICE from $nick!$user\@$host to $to: $text\n");

    # if NOTICE is sent to the bot then replace the `to` field with the
    # sender's nick instead so when we pass it on to on_public ...
    if ($to eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
        $event->{event}->{to}->[0] = $nick;
    }

    # handle this NOTICE as a public message
    # (check for bot commands, anti-flooding, etc)
    $self->on_public($event_type, $event);

    return 1;
}

sub on_public {
    my ($self, $event_type, $event) = @_;

    my ($from, $nick, $user, $host, $text) = (
        $event->{event}->{to}->[0],
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->{args}->[0],
    );

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    # send text to be processed for bot commands, anti-flood enforcement, etc
    $event->{interpreted} = $self->{pbot}->{interpreter}->process_line($from, $nick, $user, $host, $text);

    return 1;
}

sub on_action {
    my ($self, $event_type, $event) = @_;

    # prepend "/me " to the message text
    $event->{event}->{args}->[0] = "/me " . $event->{event}->{args}->[0];

    # pass this along to on_public
    $self->on_public($event_type, $event);
    return 1;
}

sub on_msg {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $text) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->{args}->[0],
    );

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    # send text to be processed as a bot command, coming from $nick
    $event->{interpreted} = $self->{pbot}->{interpreter}->process_line($nick, $nick, $user, $host, $text, 1);

    return 1;
}

1;
