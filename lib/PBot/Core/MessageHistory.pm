# File: MessageHistory.pm
#
# Purpose: Keeps track of who has said what and when, as well as their
# nickserv accounts and alter-hostmasks.
#
# Used in conjunction with AntiFlood and Quotegrabs for kick/ban on
# flood/ban-evasion and grabbing quotes, respectively.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::MessageHistory;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw(time tv_interval);

use PBot::Core::MessageHistory::Storage::SQLite;

sub initialize {
    my ($self, %conf) = @_;
    $self->{filename} = $conf{filename} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/message_history.sqlite3';

    $self->{database} = PBot::Core::MessageHistory::Storage::SQLite->new(
        pbot     => $self->{pbot},
        filename => $self->{filename}
    );

    $self->{database}->begin;
    $self->{database}->devalidate_all_channels;

    $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'max_recall_time', $conf{max_recall_time} // 0);

    $self->{pbot}->{atexit}->register(sub { $self->{database}->end(); return; });
}

sub get_message_account {
    my ($self, $nick, $user, $host) = @_;
    return $self->{database}->get_message_account($nick, $user, $host);
}

sub add_message {
    my ($self, $account, $mask, $channel, $text, $mode) = @_;
    $self->{database}->add_message($account, $mask, $channel, { timestamp => scalar time, msg => $text, mode => $mode });
}

1;
