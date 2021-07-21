# File: NickList.pm
#
# Purpose: Maintains lists of nicks currently present in channels.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::IRCHandlers::NickList;

use PBot::Imports;

use Time::HiRes qw/gettimeofday/;

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

    # handlers for various IRC events (0 is highest priority, 100 is lowest priority)

    # highest priority so these get handled by NickList before any other handlers
    # (all other handlers should be given a priority > 0)
    $self->{pbot}->{event_dispatcher}->register_handler('irc.namreply', sub { $self->on_namreply(@_) },   0);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.join',     sub { $self->on_join(@_) },       0);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',   sub { $self->on_activity(@_) },   0);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction',  sub { $self->on_activity(@_) },   0);

    # lowest priority so these get handled by NickList after all other handlers
    # (all other handlers should be given a priority < 100)
    $self->{pbot}->{event_dispatcher}->register_handler('irc.part',     sub { $self->on_part(@_) },       100);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',     sub { $self->on_quit(@_) },       100);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',     sub { $self->on_kick(@_) },       100);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.nick',     sub { $self->on_nickchange(@_) }, 100);

    # handlers for the bot itself joining/leaving channels (highest priority)
    $self->{pbot}->{event_dispatcher}->register_handler('pbot.join', sub { $self->on_self_join(@_) },  0);
    $self->{pbot}->{event_dispatcher}->register_handler('pbot.part', sub { $self->on_self_part(@_) },  0);
}

sub on_namreply {
    my ($self, $event_type, $event) = @_;
    my ($channel, $nicks) = ($event->{event}->{args}[2], $event->{event}->{args}[3]);

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

    return 0;
}

sub on_activity {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->{to}[0]);

    $self->{pbot}->{nicklist}->update_timestamp($channel, $nick);

    return 0;
}

sub on_join {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);

    $self->{pbot}->{nicklist}->add_nick($channel, $nick);

    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'hostmask', "$nick!$user\@$host");
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'user',     $user);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'host',     $host);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'join',     gettimeofday);

    return 0;
}

sub on_part {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);

    $self->{pbot}->{nicklist}->remove_nick($channel, $nick);

    return 0;
}

sub on_quit {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host)  = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);

    foreach my $channel (keys %{$self->{pbot}->{nicklist}->{nicklist}}) {
        if ($self->{pbot}->{nicklist}->is_present($channel, $nick)) {
            $self->{pbot}->{nicklist}->remove_nick($channel, $nick);
        }
    }

    return 0;
}

sub on_kick {
    my ($self, $event_type, $event) = @_;

    my ($nick, $channel) = ($event->{event}->to, $event->{event}->{args}[0]);

    $self->{pbot}->{nicklist}->remove_nick($channel, $nick);

    return 0;
}

sub on_nickchange {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $newnick) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);

    foreach my $channel (keys %{$self->{pbot}->{nicklist}->{nicklist}}) {
        if ($self->{pbot}->{nicklist}->is_present($channel, $nick)) {
            my $meta = delete $self->{pbot}->{nicklist}->{nicklist}->{$channel}->{lc $nick};

            $meta->{nick}      = $newnick;
            $meta->{timestamp} = gettimeofday;

            $self->{pbot}->{nicklist}->{nicklist}->{$channel}->{lc $newnick} = $meta;
        }
    }

    return 0;
}

sub on_self_join {
    my ($self, $event_type, $event) = @_;
    # clear nicklist to remove any stale nicks before repopulating with namreplies
    $self->{pbot}->{nicklist}->remove_channel($event->{channel});
    return 0;
}

sub on_self_part {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{nicklist}->remove_channel($event->{channel});
    return 0;
}

1;
