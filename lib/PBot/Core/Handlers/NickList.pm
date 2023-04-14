# File: NickList.pm
#
# Purpose: Maintains lists of nicks currently present in channels.

# SPDX-FileCopyrightText: 2010-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::NickList;

use PBot::Imports;
use parent 'PBot::Core::Class';

use Time::HiRes qw/gettimeofday/;

sub initialize($self, %conf) {
    # handlers for various IRC events (0 is highest priority, 100 is lowest priority)

    # highest priority so these get handled by NickList before any other handlers
    # (all other handlers should be given a priority > 0)
    $self->{pbot}->{event_dispatcher}->register_handler('irc.namreply', sub { $self->on_namreply(@_) },   0);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.join',     sub { $self->on_join(@_) },       0);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',   sub { $self->on_activity(@_) },   0);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction',  sub { $self->on_activity(@_) },   0);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.modeflag', sub { $self->on_modeflag(@_) },   0);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.nick',     sub { $self->on_nickchange(@_) }, 0);

    # lowest priority so these get handled by NickList after all other handlers
    # (all other handlers should be given a priority < 100)
    $self->{pbot}->{event_dispatcher}->register_handler('irc.part',     sub { $self->on_part(@_) },       100);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',     sub { $self->on_quit(@_) },       100);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',     sub { $self->on_kick(@_) },       100);

    # handlers for the bot itself joining/leaving channels (highest priority)
    $self->{pbot}->{event_dispatcher}->register_handler('pbot.join', sub { $self->on_self_join(@_) },  0);
    $self->{pbot}->{event_dispatcher}->register_handler('pbot.part', sub { $self->on_self_part(@_) },  0);
}

sub on_namreply($self, $event_type, $event) {
    my ($channel, $nicks) = ($event->{args}[2], $event->{args}[3]);

    foreach my $nick (split ' ', $nicks) {
        my $stripped_nick = $nick;

        $stripped_nick =~ s/^[@+%]//g;    # remove OP/Voice/etc indicator from nick

        $self->{pbot}->{nicklist}->add_nick($channel, $stripped_nick);

        my ($account_id, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($stripped_nick);

        if (defined $hostmask) {
            my ($user, $host) = $hostmask =~ m/[^!]+!([^@]+)@(.*)/;
            $self->{pbot}->{nicklist}->set_meta($channel, $stripped_nick, 'hostmask', $hostmask);
            $self->{pbot}->{nicklist}->set_meta($channel, $stripped_nick, 'user',     $user);
            $self->{pbot}->{nicklist}->set_meta($channel, $stripped_nick, 'host',     $host);
        }

        if ($nick =~ m/\@/) { $self->{pbot}->{nicklist}->set_meta($channel, $stripped_nick, '+o', 1); }

        if ($nick =~ m/\+/) { $self->{pbot}->{nicklist}->set_meta($channel, $stripped_nick, '+v', 1); }

        if ($nick =~ m/\%/) { $self->{pbot}->{nicklist}->set_meta($channel, $stripped_nick, '+h', 1); }
    }

    return 1;
}

sub on_activity($self, $event_type, $event) {
    my ($nick, $user, $host, $channel) = ($event->nick, $event->user, $event->host, $event->{to}[0]);

    $self->{pbot}->{nicklist}->update_timestamp($channel, $nick);

    return 1;
}

sub on_join($self, $event_type, $event) {
    my ($nick, $user, $host, $channel) = ($event->nick, $event->user, $event->host, $event->to);

    $self->{pbot}->{nicklist}->add_nick($channel, $nick);

    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'hostmask', "$nick!$user\@$host");
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'user',     $user);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'host',     $host);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'join',     scalar gettimeofday);

    return 1;
}

sub on_part($self, $event_type, $event) {
    my ($nick, $user, $host, $channel) = ($event->nick, $event->user, $event->host, $event->to);

    $self->{pbot}->{nicklist}->remove_nick($channel, $nick);

    return 1;
}

sub on_quit($self, $event_type, $event) {
    my ($nick, $user, $host)  = ($event->nick, $event->user, $event->host);

    foreach my $channel (keys %{$self->{pbot}->{nicklist}->{nicklist}}) {
        if ($self->{pbot}->{nicklist}->is_present($channel, $nick)) {
            $self->{pbot}->{nicklist}->remove_nick($channel, $nick);
        }
    }

    return 1;
}

sub on_kick($self, $event_type, $event) {
    my ($nick, $channel) = ($event->to, $event->{args}[0]);

    $self->{pbot}->{nicklist}->remove_nick($channel, $nick);

    return 1;
}

sub on_nickchange($self, $event_type, $event) {
    my ($nick, $user, $host, $newnick) = ($event->nick, $event->user, $event->host, $event->args);

    foreach my $channel (keys %{$self->{pbot}->{nicklist}->{nicklist}}) {
        if ($self->{pbot}->{nicklist}->is_present($channel, $nick)) {
            my $meta = delete $self->{pbot}->{nicklist}->{nicklist}->{$channel}->{lc $nick};

            $meta->{nick}      = $newnick;
            $meta->{timestamp} = gettimeofday;

            $self->{pbot}->{nicklist}->{nicklist}->{$channel}->{lc $newnick} = $meta;
        }
    }

    return 1;
}

sub on_modeflag($self, $event_type, $event) {
    my ($source, $channel, $mode, $target) = (
        $event->{source},
        $event->{channel},
        $event->{mode},
        $event->{target},
    );

    # disregard mode set on channel
    return if not defined $target or not length $target;

    my ($modifier, $char) = split //, $mode;

    if ($modifier eq '-') {
        $self->{pbot}->{nicklist}->delete_meta($channel, $target, "+$char");
    } else {
        $self->{pbot}->{nicklist}->set_meta($channel, $target, $mode, 1);
    }

    return 1;
}

sub on_self_join($self, $event_type, $event) {
    # clear nicklist to remove any stale nicks before repopulating with namreplies
    $self->{pbot}->{nicklist}->remove_channel($event->{channel});
    return 1;
}

sub on_self_part($self, $event_type, $event) {
    $self->{pbot}->{nicklist}->remove_channel($event->{channel});
    return 1;
}

1;
