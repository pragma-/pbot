# File: Channel.pm
#
# Purpose: Handlers for general channel-related IRC events that aren't handled
# by any specialized Handler modules.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::Channel;
use parent 'PBot::Core::Class';

use PBot::Imports;
use PBot::Core::MessageHistory::Constants ':all';

use Data::Dumper;
use Encode;
use MIME::Base64;
use Time::HiRes qw/time/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{event_dispatcher}->register_handler('irc.mode',          sub { $self->on_mode          (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.join',          sub { $self->on_join          (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.part',          sub { $self->on_departure     (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',          sub { $self->on_kick          (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.invite',        sub { $self->on_invite        (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.channelmodeis', sub { $self->on_channelmodeis (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.topic',         sub { $self->on_topic         (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.topicinfo',     sub { $self->on_topicinfo     (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.channelcreate', sub { $self->on_channelcreate (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.modeflag',      sub { $self->on_modeflag      (@_) });
}

sub on_mode {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $mode_string, $channel) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->{args}->[0],
        lc $event->{event}->{to}->[0],
    );

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    my $i = 0;
    my ($modifier, $flag, $mode, $target);

    my $source = "$nick!$user\@$host";

    # split combined modes
    while ($mode_string =~ m/(.)/g) {
        $flag = $1;

        if ($flag eq '-' or $flag eq '+') {
            $modifier = $flag;
            next;
        }

        $mode   = $modifier . $flag;
        $target = $event->{event}->{args}->[++$i];

        $self->{pbot}->{logger}->log("[MODE] $channel $mode" . (length $target ? " $target" : '') . " by $source\n");

        # dispatch a single mode flag event
        $self->{pbot}->{event_dispatcher}->dispatch_event(
            'irc.modeflag',
            {
                source  => $source,
                channel => $channel,
                mode    => $mode,
                target  => $target,
            },
        );
    }

    return 1;
}

sub on_modeflag {
    my ($self, $event_type, $event) = @_;

    my ($source, $channel, $mode, $target) = (
        $event->{source},
        $event->{channel},
        $event->{mode},
        $event->{target},
    );

    # disregard mode set on user instead of channel
    return if defined $target and length $target;

    my ($modifier, $flag) = split //, $mode;

    my $modes = $self->{pbot}->{channels}->get_meta($channel, 'MODE') // '';

    if ($modifier eq '+') {
        $modes = '+' if not length $modes;
        $modes .= $flag if $modes !~ /\Q$flag/;
    } else {
        $modes =~ s/\Q$flag//g;
        $modes = '' if $modes eq '+';
    }

    $self->{pbot}->{channels}->{storage}->set($channel, 'MODE', $modes, 1);
    return 1;
}

sub on_join {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $channel) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        lc $event->{event}->{to}->[0],
    );

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);

    $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "JOIN", MSG_JOIN);

    $self->{pbot}->{messagehistory}->{database}->devalidate_channel($message_account, $channel);

    my $msg = 'JOIN';

    # IRCv3 extended-join capability provides more details about user
    if (exists $self->{pbot}->{irc_capabilities}->{'extended-join'}) {
        my ($nickserv, $gecos) = (
            $event->{event}->{args}->[0],
            $event->{event}->{args}->[1],
        );

        $msg .= " $nickserv :$gecos";

        $self->{pbot}->{messagehistory}->{database}->update_gecos($message_account, $gecos, scalar time);

        if ($nickserv ne '*') {
            $self->{pbot}->{messagehistory}->{database}->link_aliases($message_account, undef, $nickserv);
            $self->{pbot}->{messagehistory}->{database}->update_nickserv_account($message_account, $nickserv, scalar time);
            $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($message_account, $nickserv);
        } else {
            $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($message_account, '');
        }

        $self->{pbot}->{antiflood}->check_bans($message_account, $event->{event}->from, $channel);
    }

    $self->{pbot}->{antiflood}->check_flood(
        $channel, $nick, $user, $host, $msg,
        $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_threshold'),
        $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_time_threshold'),
        MSG_JOIN,
    );

    return 1;
}

sub on_invite {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $target, $channel) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->to,
        lc $event->{event}->{args}->[0]
    );

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    $self->{pbot}->{logger}->log("$nick!$user\@$host invited $target to $channel!\n");

    # if invited to a channel on our channel list, go ahead and join it
    if ($target eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
        if ($self->{pbot}->{channels}->is_active($channel)) {
            $self->{pbot}->{interpreter}->add_botcmd_to_command_queue($channel, "join $channel", 0);
        }
    }

    return 1;
}

sub on_kick {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $target, $channel, $reason) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->to,
        lc $event->{event}->{args}->[0],
        $event->{event}->{args}->[1]
    );

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    $self->{pbot}->{logger}->log("$nick!$user\@$host kicked $target from $channel ($reason)\n");

    # hostmask of the person being kicked
    my $target_hostmask;

    # look up message history account for person being kicked
    my ($message_account) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($target);

    if (defined $message_account) {
        # update target hostmask
        $target_hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($message_account);

        # add "KICKED by" to kicked person's message history
        my $text = "KICKED by $nick!$user\@$host ($reason)";

        $self->{pbot}->{messagehistory}->add_message($message_account, $target_hostmask, $channel, $text, MSG_DEPARTURE);

        # do stuff that happens in check_flood
        my ($target_nick, $target_user, $target_host) = $target_hostmask =~ m/^([^!]+)!([^@]+)@(.*)/;

        $self->{pbot}->{antiflood}->check_flood(
            $channel, $target_nick, $target_user, $target_host, $text,
            $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_threshold'),
            $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_time_threshold'),
            MSG_DEPARTURE,
        );
    }

    # look up message history account for person doing the kicking
    $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account_id("$nick!$user\@$host");

    if (defined $message_account) {
        # replace target nick with target hostmask if available
        if (defined $target_hostmask) {
            $target = $target_hostmask;
        }

        # add "KICKED $target" to kicker's message history
        my $text = "KICKED $target from $channel ($reason)";
        $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, $text, MSG_CHAT);
    }

    return 1;
}

sub on_departure {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $channel, $args) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        lc $event->{event}->{to}->[0],
        $event->{event}->args
    );

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    my $text = uc ($event->{event}->type) . ' ' . $args;

    my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);

    if ($text =~ m/^QUIT/) {
        # QUIT messages must be added to the mesasge history of each channel the user is on
        my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
        foreach my $chan (@$channels) {
            next if $chan !~ m/^#/;
            $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $chan, $text, MSG_DEPARTURE);
        }
    } else {
        $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, $text, MSG_DEPARTURE);
    }

    $self->{pbot}->{antiflood}->check_flood(
        $channel, $nick, $user, $host, $text,
        $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_threshold'),
        $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_time_threshold'),
        MSG_DEPARTURE,
    );

    my $u = $self->{pbot}->{users}->find_user($channel, "$nick!$user\@$host");

    # log user out if logged in and not stayloggedin
    # TODO: this should probably be in Users.pm with its own part/quit/kick handler
    if (defined $u and $u->{loggedin} and not $u->{stayloggedin}) {
        $self->{pbot}->{logger}->log("Logged out $nick.\n");
        delete $u->{loggedin};
        $self->{pbot}->{users}->save;
    }

    return 1;
}

sub on_channelmodeis {
    my ($self, $event_type, $event) = @_;

    my (undef, $channel, $modes) = $event->{event}->args;

    $self->{pbot}->{logger}->log("Channel $channel modes: $modes\n");

    $self->{pbot}->{channels}->{storage}->set($channel, 'MODE', $modes, 1);
    return 1;
}

sub on_channelcreate {
    my ($self,  $event_type, $event) = @_;

    my ($owner, $channel, $timestamp) = $event->{event}->args;

    $self->{pbot}->{logger}->log("Channel $channel created by $owner on " . localtime($timestamp) . "\n");

    $self->{pbot}->{channels}->{storage}->set($channel, 'CREATED_BY', $owner,     1);
    $self->{pbot}->{channels}->{storage}->set($channel, 'CREATED_ON', $timestamp, 1);
    return 1;
}

sub on_topic {
    my ($self, $event_type, $event) = @_;

    if (not length $event->{event}->{to}->[0]) {
        # on join
        my (undef, $channel, $topic) = $event->{event}->args;
        $self->{pbot}->{logger}->log("Topic for $channel: $topic\n");
        $self->{pbot}->{channels}->{storage}->set($channel, 'TOPIC', $topic, 1);
    } else {
        # user changing topic
        my ($nick, $user, $host) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);
        my $channel = $event->{event}->{to}->[0];
        my $topic   = $event->{event}->{args}->[0];

        $self->{pbot}->{logger}->log("$nick!$user\@$host changed topic for $channel to: $topic\n");
        $self->{pbot}->{channels}->{storage}->set($channel, 'TOPIC',        $topic,               1);
        $self->{pbot}->{channels}->{storage}->set($channel, 'TOPIC_SET_BY', "$nick!$user\@$host", 1);
        $self->{pbot}->{channels}->{storage}->set($channel, 'TOPIC_SET_ON', time);
    }

    return 1;
}

sub on_topicinfo {
    my ($self, $event_type, $event) = @_;
    my (undef, $channel, $by, $timestamp) = $event->{event}->args;
    $self->{pbot}->{logger}->log("Topic for $channel set by $by on " . localtime($timestamp) . "\n");
    $self->{pbot}->{channels}->{storage}->set($channel, 'TOPIC_SET_BY', $by,        1);
    $self->{pbot}->{channels}->{storage}->set($channel, 'TOPIC_SET_ON', $timestamp, 1);
    return 1;
}

1;
