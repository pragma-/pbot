# File: AntiNickSpam.pm
#
# Purpose: Temporarily mutes $~a in channel if too many nicks were
#          mentioned within a time period; used to combat botnet spam

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::AntiNickSpam;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use Time::Duration qw/duration/;
use Time::HiRes qw/gettimeofday/;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_action(@_) });
    $self->{nicks} = {};
}

sub unload {
    my ($self) = @_;
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
}

sub on_action {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $msg) = ($event->nick, $event->user, $event->host, $event->args);
    my $channel = $event->{to}[0];
    return 0 if $event->{interpreted};
    $self->check_flood($nick, $user, $host, $channel, $msg);
    return 0;
}

sub on_public {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $msg) = ($event->nick, $event->user, $event->host, $event->args);
    my $channel = $event->{to}[0];
    return 0 if $event->{interpreted};
    $self->check_flood($nick, $user, $host, $channel, $msg);
    return 0;
}

sub check_flood {
    my ($self, $nick, $user, $host, $channel, $msg) = @_;
    return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);

    $channel = lc $channel;
    my @words = split /\s+/, $msg;
    my @nicks;

    foreach my $word (@words) {
        $word =~ s/[:;\+,\.!?\@\%\$]+$//g;
        if ($self->{pbot}->{nicklist}->is_present($channel, $word) and not grep { $_ eq $word } @nicks) {
            push @{$self->{nicks}->{$channel}}, [scalar gettimeofday, $word];
            push @nicks, $word;
        }
    }

    $self->clear_old_nicks($channel);

    if (exists $self->{nicks}->{$channel} and @{$self->{nicks}->{$channel}} >= 10) {
        $self->{pbot}->{logger}->log("Nick spam flood detected in $channel\n");
        $self->{pbot}->{banlist}->ban_user_timed(
            $channel,
            'q',
            '$~a',
            60 * 15,
            $self->{pbot}->{registry}->get_value('irc', 'botnick'),
            'nick spam flooding',
        );
    }
}

sub clear_old_nicks {
    my ($self, $channel) = @_;
    my $now = gettimeofday;
    return if not exists $self->{nicks}->{$channel};

    while (1) {
        if   (@{$self->{nicks}->{$channel}} and $self->{nicks}->{$channel}->[0]->[0] <= $now - 15) {
            shift @{$self->{nicks}->{$channel}};
        } else {
            last;
        }
    }

    delete $self->{nicks}->{$channel} if not @{$self->{nicks}->{$channel}};
}

1;
