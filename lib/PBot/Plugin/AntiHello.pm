# File: AntiHello.pm
#
# Purpose: Handles people that do stand-alone channel greetings without any
#          other meaningful content.
#          This plugin is opt-in only. Set #channel.nohello to 1 to enable.

# SPDX-FileCopyrightText: 2024 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::AntiHello;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize($self, %conf) {
    $self->{pbot}->{registry}->add_default('text', 'antihello', 'bad_greetings',
        $conf{bad_greetings} // '^\s*(?:[[:punct:]]|\p{Emoticons})*\s*(?:h*e+l+l+o+|h+e+y+a+|y+o+|h*e+n+l+o+|l+o+|h+i+|(?:g+o*d*\s*[[:punct:]]*\s*)*(d+a+y+|m+o+r+n+i*n*g*|e+v+e+n+i+n+g*|a+f+t+e+r+n+o+n+|n+o+n+)|w*a*s+u+p+|l+a+d+s*|b+r+o+s+|g+[[:punct:]]*d+a+y+|g+r+e+t+s*z*|g+r+e+t+i+n+g+s*|h*o+l+a+|o+i+|h*e+y+|h+a+y+|o*h+a+i+)\s*[[:punct:]]*\s*(?:\s+.{1,15})?\s*(?:[[:punct:]]|\p{Emoticons})*\s*$'
    );

    $self->{pbot}->{registry}->add_default('text', 'antihello', 'kick_msg', 'https://nohello.net/');

    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_action(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public(@_) });

    my $filename = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/antihello';

    $self->{storage} = PBot::Core::Storage::DualIndexHashObject->new(
        pbot     => $self->{pbot},
        name     => 'AntiHello',
        filename => $filename,
        save_queue_timeout => 15,
    );

    $self->{storage}->load;

    $self->{last_warning} = 0;
}

sub unload($self) {
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
}

sub punish($self, $msg, $channel, $nick, $user, $host) {
    my $data = $self->{storage}->get_data($channel, $nick);

    if (not defined $data) {
        $data = {
            offenses     => 0,
            last_offense => 0,
        };
    }

    $data->{offenses}++;
    $data->{last_offense} = time;

    $self->{storage}->add($channel, $nick, $data);

    $self->{pbot}->{logger}->log("[anti-hello] $nick!$user\@$host offense $data->{offenses}\n");

    if ($data->{offenses} == 1) {
        my $now = time;

        # send public message to channel with cooldown
        if ($now - $self->{last_warning} >= 60 * 60) {
            $self->{last_warning} = $now;
            $self->{pbot}->{conn}->privmsg($channel, "Please do not send stand-alone channel greeting messages; include your question/statement along with the greeting. For more info, see https://nohello.net/ (repeated offenses will result in an automatic ban)");
        }

        # always send private message to offender
        $self->{pbot}->{conn}->privmsg($nick, "$nick: ($channel) Please do not send stand-alone channel greeting messages; include your question/statement along with the greeting. For more info, see https://nohello.net/ (repeated offenses will result in an automatic ban)");

        return 0;
    } elsif ($data->{offenses} == 2) {
        $msg .= ' (2ND OFFENSE WARNING: next offense will result in a temp-ban)';
    } elsif ($data->{offenses} > 2) {
        $msg .= ' (temp ban for repeated offenses)';
    }

    $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $nick $msg");
    $self->{pbot}->{chanops}->gain_ops($channel);

    if ($data->{offenses} > 2) {
        my $botnick = $self->{pbot}->{conn}->nick;
        $self->{pbot}->{banlist}->ban_user_timed($channel, 'b', "*!*\@$host", 60 * 60 * 2, $botnick, 'anti-hello');
    }
}

sub on_public($self, $event_type, $event) {
    my ($nick, $user, $host, $msg) = ($event->nick, $event->user, $event->host, $event->args);
    my $channel = $event->{to}[0];

    return 0 if $channel !~ /^#/;
    return 0 if not $self->{pbot}->{registry}->get_value($channel, 'nohello');
    return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);

    my $u = $self->{pbot}->{users}->loggedin($channel, "$nick!$user\@$host");
    return 0 if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

    my $bad_greetings = $self->{pbot}->{registry}->get_value('antihello', 'bad_greetings');

    if ($msg =~ m/$bad_greetings/i) {
        my $kick_msg = $self->{pbot}->{registry}->get_value('antihello', 'kick_msg');
        $self->punish($kick_msg, $channel, $nick, $user, $host);
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
    return 0 if not $self->{pbot}->{registry}->get_value($channel, 'nohello');
    return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);

    my $u = $self->{pbot}->{users}->loggedin($channel, "$nick!$user\@$host");
    return 0 if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

    my $bad_actions = $self->{pbot}->{registry}->get_value('antihello', 'bad_greetings');

    if ($msg =~ m/$bad_actions/i) {
        my $kick_msg = $self->{pbot}->{registry}->get_value('antihello', 'kick_msg');
        $self->punish($kick_msg, $channel, $nick, $user, $host);
    }
    return 0;
}

1;
