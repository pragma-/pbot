# File: Server.pm
#
# Purpose: Handles server-related IRC events.

# SPDX-FileCopyrightText: 2021-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::Server;

use PBot::Imports;
use parent 'PBot::Core::Class';

use PBot::Core::MessageHistory::Constants ':all';

use Time::HiRes qw/time/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{event_dispatcher}->register_handler('irc.welcome',       sub { $self->on_welcome       (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.disconnect',    sub { $self->on_disconnect    (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.motd',          sub { $self->on_motd          (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.notice',        sub { $self->on_notice        (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.nick',          sub { $self->on_nickchange    (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.isupport',      sub { $self->on_isupport      (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.yourhost',      sub { $self->log_first_arg    (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.created',       sub { $self->log_first_arg    (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.luserconns',    sub { $self->log_first_arg    (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.notregistered', sub { $self->log_first_arg    (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.n_local',       sub { $self->log_third_arg    (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.n_global',      sub { $self->log_third_arg    (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.nononreg',      sub { $self->on_nononreg      (@_) });
}

sub on_init {
    my ($self, $conn, $event) = @_;
    my (@args) = ($event->args);
    shift @args;
    $self->{pbot}->{logger}->log("*** @args\n");
    return 1;
}

sub on_welcome {
    my ($self, $event_type, $event) = @_;

    $self->{pbot}->{logger}->log("Welcome!\n");

    if ($self->{pbot}->{irc_capabilities}->{sasl}) {
        # using SASL; go ahead and auto-join channels now
        $self->{pbot}->{logger}->log("Autojoining channels.\n");
        $self->{pbot}->{channels}->autojoin;
    }

    return 1;
}

sub on_disconnect {
    my ($self, $event_type, $event) = @_;

    $self->{pbot}->{logger}->log("Disconnected...\n");
    $self->{pbot}->{conn} = undef;

    # send pbot.disconnect to notify PBot internals
    $self->{pbot}->{event_dispatcher}->dispatch_event(
        'pbot.disconnect', undef
    );

    # attempt to reconnect to server
    # TODO: maybe add a registry entry to control whether the bot auto-reconnects
    $self->{pbot}->connect;

    return 1;
}

sub on_motd {
    my ($self, $event_type, $event) = @_;

    if ($self->{pbot}->{registry}->get_value('irc', 'show_motd')) {
        my $from = $event->{from};
        my $msg  = $event->{args}[1];
        $self->{pbot}->{logger}->log("MOTD from $from :: $msg\n");
    }

    return 1;
}

sub on_notice {
    my ($self, $event_type, $event) = @_;

    my ($server, $to, $text) = (
        $event->nick,
        $event->to,
        $event->{args}[0],
    );

    # don't handle non-server NOTICE
    return undef if $to ne '*';

    # log notice
    $self->{pbot}->{logger}->log("NOTICE from $server: $text\n");

    return 1;
}

sub on_isupport {
    my ($self, $event_type, $event) = @_;

    # remove and discard first and last arguments
    # (first arg is botnick, last arg is "are supported by this server")
    shift @{$event->{args}};
    pop   @{$event->{args}};

    my $logmsg = "$event->{from} supports:";

    foreach my $arg (@{$event->{args}}) {
        my ($key, $value) = split /=/, $arg;

        if ($key =~ s/^-//) {
            # server removed suppport for this key
            delete $self->{pbot}->{isupport}->{$key};
        } else {
            $self->{pbot}->{isupport}->{$key} = $value // 1;
        }

        $logmsg .= defined $value ? " $key=$value" : " $key";
    }

    $self->{pbot}->{logger}->log("$logmsg\n");

    return 1;
}

sub on_nickchange {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $newnick) = ($event->nick, $event->user, $event->host, $event->args);

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    $self->{pbot}->{logger}->log("[NICKCHANGE] $nick!$user\@$host changed nick to $newnick\n");

    if ($newnick eq $self->{pbot}->{registry}->get_value('irc', 'botnick') and not $self->{pbot}->{joined_channels}) {
        $self->{pbot}->{channels}->autojoin;
        return 1;
    }

    my $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
    $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($message_account, $self->{pbot}->{antiflood}->{NEEDS_CHECKBAN});
    my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
    foreach my $channel (@$channels) {
        next if $channel !~ m/^#/;
        $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "NICKCHANGE $newnick", MSG_NICKCHANGE);
    }
    $self->{pbot}->{messagehistory}->{database}->update_hostmask_data("$nick!$user\@$host", {last_seen => scalar time});

    my $newnick_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($newnick, $user, $host, $nick);
    $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($newnick_account, $self->{pbot}->{antiflood}->{NEEDS_CHECKBAN});
    $self->{pbot}->{messagehistory}->{database}->update_hostmask_data("$newnick!$user\@$host", {last_seen => scalar time});

    $self->{pbot}->{antiflood}->check_flood(
        "$nick!$user\@$host", $nick, $user, $host, "NICKCHANGE $newnick",
        $self->{pbot}->{registry}->get_value('antiflood', 'nick_flood_threshold'),
        $self->{pbot}->{registry}->get_value('antiflood', 'nick_flood_time_threshold'),
        MSG_NICKCHANGE,
    );

    return 1;
}

sub on_nononreg {
    my ($self, $event_type, $event) = @_;

    my $target = $event->{args}[1];

    $self->{pbot}->{logger}->log("Cannot send private /msg to $target; they are blocking unidentified /msgs.\n");

    return 1;
}

sub log_first_arg {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log("$event->{args}[1]\n");
    return 1;
}

sub log_third_arg {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log("$event->{args}[3]\n");
    return 1;
}

1;
