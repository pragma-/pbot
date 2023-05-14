# File: Chat.pm
#
# Purpose: IRC handlers for chat/message events.

# SPDX-FileCopyrightText: 2001-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::Chat;

use PBot::Imports;
use parent 'PBot::Core::Class';

use PBot::Core::MessageHistory::Constants ':all';

sub initialize($self, %conf) {
    $self->{pbot}->{event_dispatcher}->register_handler('irc.notice',  sub { $self->on_notice (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_action (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.msg',     sub { $self->on_msg    (@_) });
}

sub on_notice($self, $event_type, $event) {
    my ($nick, $user, $host, $to, $text)  = (
        $event->nick,
        $event->user,
        $event->host,
        $event->to,
        $event->{args}[0],
    );

    # don't handle server NOTICE
    return undef if $to eq '*';

    # log notice
    $self->{pbot}->{logger}->log("NOTICE from $nick!$user\@$host to $to: $text\n");

    # handle NOTICE to channel (message history and anti-flood)
    if ($to =~ /^#/) {
        # add hostmask to user/message tracking database and get their account id
        my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);

        # add message to message history as a chat message
        $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $to, $text, MSG_CHAT);

        # look up channel-specific flood threshold settings from registry
        my $flood_threshold      = $self->{pbot}->{registry}->get_value($to, 'chat_flood_threshold');
        my $flood_time_threshold = $self->{pbot}->{registry}->get_value($to, 'chat_flood_time_threshold');

        # get general flood threshold settings if there are no channel-specific settings
        $flood_threshold       //= $self->{pbot}->{registry}->get_value('antiflood', 'chat_flood_threshold');
        $flood_time_threshold  //= $self->{pbot}->{registry}->get_value('antiflood', 'chat_flood_time_threshold');

        # perform anti-flood processing on this message
        $self->{pbot}->{antiflood}->check_flood(
            $to, $nick, $user, $host, $text,
            $flood_threshold, $flood_time_threshold,
            MSG_CHAT
        );
    }

    # nothing further to do with NOTICEs
    return 0;
}

sub on_public($self, $event_type, $event) {
    my ($from, $nick, $user, $host, $text, $tags) = (
        $event->{to}[0],
        $event->nick,
        $event->user,
        $event->host,
        $event->{args}[0],
        $event->{args}[1],
    );

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    # send text to be processed for bot commands, anti-flood enforcement, etc
    $event->{interpreted} = $self->{pbot}->{interpreter}->process_line($from, $nick, $user, $host, $text, $tags);

    return 1;
}

sub on_action($self, $event_type, $event) {
    # prepend "/me " to the message text
    $event->{args}[0] = "/me " . $event->{args}[0];

    # pass this along to on_public
    $self->on_public($event_type, $event);
    return 1;
}

sub on_msg($self, $event_type, $event) {
    my ($nick, $user, $host, $text, $tags) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->{args}[0],
        $event->{args}[1],
    );

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    # send text to be processed as a bot command, in "channel" $nick
    $event->{interpreted} = $self->{pbot}->{interpreter}->process_line($nick, $nick, $user, $host, $text, $tags, 1);

    return 1;
}

1;
