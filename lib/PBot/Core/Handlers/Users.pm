# File: Users.pm
#
# Purpose: Handles IRC events related to PBot user accounts and user metadata.

# SPDX-FileCopyrightText: 2010-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::Users;

use PBot::Imports;
use parent 'PBot::Core::Class';

sub initialize($self, %conf) {
    $self->{pbot}->{event_dispatcher}->register_handler('irc.join',  sub { $self->on_join      (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.part',  sub { $self->on_departure (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',  sub { $self->on_departure (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',  sub { $self->on_kick      (@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('pbot.part', sub { $self->on_self_part (@_) });
}

sub on_join($self, $event_type, $event) {
    my ($nick, $user, $host, $channel) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->to
    );

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    my ($u, $name) = $self->{pbot}->{users}->find_user($channel, "$nick!$user\@$host");

    if (defined $u) {
        if ($self->{pbot}->{chanops}->can_gain_ops($channel)) {
            my $modes   = '+';
            my $targets = '';

            if ($u->{autoop}) {
                $self->{pbot}->{logger}->log("$nick!$user\@$host autoop in $channel\n");
                $modes   .= 'o';
                $targets .= "$nick ";
            }

            if ($u->{autovoice}) {
                $self->{pbot}->{logger}->log("$nick!$user\@$host autovoice in $channel\n");
                $modes   .= 'v';
                $targets .= "$nick ";
            }

            if (length $modes > 1) {
                $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $modes $targets");
                $self->{pbot}->{chanops}->gain_ops($channel);
            }
        }

        if ($u->{autologin}) {
            $self->{pbot}->{logger}->log("$nick!$user\@$host autologin to $name for $channel\n");
            $u->{loggedin} = 1;
        }
    }

    return 1;
}

sub on_departure($self, $event_type, $event) {
    my ($nick, $user, $host, $channel) = ($event->nick, $event->user, $event->host, $event->to);
    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);
    $self->{pbot}->{users}->decache_user($channel, "$nick!$user\@$host");
    return 1;
}

sub on_kick($self, $event_type, $event) {
    my ($nick, $user, $host, $channel) = ($event->nick, $event->user, $event->host, $event->{args}[0]);
    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);
    $self->{pbot}->{users}->decache_user($channel, "$nick!$user\@$host");
    return 1;
}

sub on_self_part($self, $event_type, $event) {
    delete $self->{pbot}->{users}->{user_cache}->{lc $event->{channel}};
    return 1;
}

1;
