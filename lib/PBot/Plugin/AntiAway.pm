# File: AntiAway.pm
#
# Purpose: Kicks people that visibly auto-away with ACTIONs or nick-changes

# SPDX-FileCopyrightText: 2014-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::AntiAway;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize($self, %conf) {
    $self->{pbot}->{registry}->add_default('text', 'antiaway', 'bad_nicks',
        $conf{bad_nicks} // '(^zz+[[:punct:]]|[[:punct:]](afk|brb|bbl|away|a?sleep|nap|zz+|work|gone|study|out|home|busy|off)[[:punct:]]*$|afk$)'
    );

    $self->{pbot}->{registry}->add_default('text', 'antiaway', 'bad_actions', $conf{bad_actions} // '^/me (is (away|gone)|.*auto.?away)');
    $self->{pbot}->{registry}->add_default('text', 'antiaway', 'kick_msg',    'http://sackheads.org/~bnaylor/spew/away_msgs.html');

    $self->{pbot}->{event_dispatcher}->register_handler('irc.nick',    sub { $self->on_nickchange(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_action(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public(@_) });

    $self->{kick_counter} = {};
}

sub unload($self) {
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.nick');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
}

sub punish($self, $msg, $channel, $nick, $user, $host) {
    $self->{kick_counter}->{$channel}->{$nick}++;

    $self->{pbot}->{logger}->log("[anti-away] $nick!$user\@$host offense $self->{kick_counter}->{$channel}->{$nick}\n");

    if ($self->{kick_counter}->{$channel}->{$nick} == 2) {
        $msg .= ' (WARNING: next offense will result in a temp-ban)';
    } elsif ($self->{kick_counter}->{$channel}->{$nick} > 2) {
        $msg .= ' (temp ban for repeated offenses)';
    }

    $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $nick $msg");
    $self->{pbot}->{chanops}->gain_ops($channel);

    if ($self->{kick_counter}->{$channel}->{$nick} > 2) {
        my $botnick = $self->{pbot}->{conn}->nick;
        $self->{pbot}->{banlist}->ban_user_timed($channel, 'b', "*!*\@$host", 60 * 60 * 2, $botnick, 'anti-away');
    }
}

sub on_public($self, $event_type, $event) {
    my ($nick, $user, $host, $msg) = ($event->nick, $event->user, $event->host, $event->args);
    my $channel = $event->{to}[0];

    return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);

    my $u = $self->{pbot}->{users}->loggedin($channel, "$nick!$user\@$host");
    return 0 if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

    my $bad_nicks = $self->{pbot}->{registry}->get_value('antiaway', 'bad_nicks');

    if ($nick =~ m/$bad_nicks/i) {
        my $kick_msg = $self->{pbot}->{registry}->get_value('antiaway', 'kick_msg');
        $self->punish($kick_msg, $channel, $nick, $user, $host);
    }
    return 0;
}

sub on_nickchange($self, $event_type, $event) {
    my ($nick, $user, $host, $newnick) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->args
    );

    my $bad_nicks = $self->{pbot}->{registry}->get_value('antiaway', 'bad_nicks');

    if ($newnick =~ m/$bad_nicks/i) {
        my $kick_msg = $self->{pbot}->{registry}->get_value('antiaway', 'kick_msg');
        my $channels = $self->{pbot}->{nicklist}->get_channels($newnick);

        foreach my $chan (@$channels) {
            next if not $self->{pbot}->{chanops}->can_gain_ops($chan);

            my $u = $self->{pbot}->{users}->loggedin($chan, "$nick!$user\@$host");
            next if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

            $self->punish($kick_msg, $chan, $newnick, $user, $host);
        }
    }
    return 0;
}

sub on_action($self, $event_type, $event) {
    my ($nick, $user, $host, $msg, $channel) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->{args}[0],
        $event->{to}[0],
    );

    return 0 if $channel !~ /^#/;
    return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);

    my $u = $self->{pbot}->{users}->loggedin($channel, "$nick!$user\@$host");
    return 0 if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

    my $bad_actions = $self->{pbot}->{registry}->get_value('antiaway', 'bad_actions');

    if ($msg =~ m/$bad_actions/i) {
        $self->{pbot}->{logger}->log("$nick $msg matches bad away actions regex, kicking...\n");
        my $kick_msg = $self->{pbot}->{registry}->get_value('antiaway', 'kick_msg');
        $self->punish($kick_msg, $channel, $nick, $user, $host);
    }
    return 0;
}

1;
