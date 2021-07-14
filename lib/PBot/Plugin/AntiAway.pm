# File: AntiAway.pm
#
# Purpose: Kicks people that visibly auto-away with ACTIONs or nick-changes

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::AntiAway;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{registry}->add_default('text', 'antiaway', 'bad_nicks',
        $conf{bad_nicks} // '([[:punct:]](afk|brb|bbl|away|sleep|z+|work|gone|study|out|home|busy|off)[[:punct:]]*$|.+\[.*\]$)'
    );
    $self->{pbot}->{registry}->add_default('text', 'antiaway', 'bad_actions', $conf{bad_actions} // '^/me (is (away|gone)|.*auto.?away)');
    $self->{pbot}->{registry}->add_default('text', 'antiaway', 'kick_msg',    'http://sackheads.org/~bnaylor/spew/away_msgs.html');

    $self->{pbot}->{event_dispatcher}->register_handler('irc.nick',    sub { $self->on_nickchange(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_action(@_) });
}

sub unload {
    my ($self) = @_;
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.nick');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
}

sub on_nickchange {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $newnick) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);

    my $bad_nicks = $self->{pbot}->{registry}->get_value('antiaway', 'bad_nicks');
    if ($newnick =~ m/$bad_nicks/i) {
        my $kick_msg = $self->{pbot}->{registry}->get_value('antiaway', 'kick_msg');
        my $channels = $self->{pbot}->{nicklist}->get_channels($newnick);
        foreach my $chan (@$channels) {
            next if not $self->{pbot}->{chanops}->can_gain_ops($chan);

            my $u = $self->{pbot}->{users}->loggedin($chan, "$nick!$user\@$host");
            next if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

            $self->{pbot}->{logger}->log("$newnick matches bad away nick regex, kicking from $chan\n");
            $self->{pbot}->{chanops}->add_op_command($chan, "kick $chan $newnick $kick_msg");
            $self->{pbot}->{chanops}->gain_ops($chan);
        }
    }
    return 0;
}

sub on_action {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $msg, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->{args}[0], $event->{event}->{to}[0]);

    return 0 if $channel !~ /^#/;
    return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);

    my $u = $self->{pbot}->{users}->loggedin($channel, "$nick!$user\@$host");
    return 0 if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

    my $bad_actions = $self->{pbot}->{registry}->get_value('antiaway', 'bad_actions');
    if ($msg =~ m/$bad_actions/i) {
        $self->{pbot}->{logger}->log("$nick $msg matches bad away actions regex, kicking...\n");
        my $kick_msg = $self->{pbot}->{registry}->get_value('antiaway', 'kick_msg');
        $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $nick $kick_msg");
        $self->{pbot}->{chanops}->gain_ops($channel);
    }
    return 0;
}

1;
