# File: BanTracker.pm
# Author: pragma_
#
# Purpose: Populates and maintains channel banlists by checking mode +b on
# joining channels and by tracking modes +b and -b in channels.
#
# Does NOT do banning or unbanning.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::BanTracker;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use Time::HiRes qw/gettimeofday/;
use Time::Duration;
use Data::Dumper;

$Data::Dumper::Sortkeys = 1;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{registry}->add_default('text', 'bantracker', 'chanserv_ban_timeout', '604800');
    $self->{pbot}->{registry}->add_default('text', 'bantracker', 'mute_timeout',         '604800');
    $self->{pbot}->{registry}->add_default('text', 'bantracker', 'debug',                '0');

    $self->{pbot}->{commands}->register(sub { $self->dumpbans(@_) }, "dumpbans", 1);

    $self->{pbot}->{event_dispatcher}->register_handler('irc.endofnames', sub { $self->get_banlist(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.banlist',    sub { $self->on_banlist_entry(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quietlist',  sub { $self->on_quietlist_entry(@_) });

    $self->{banlist} = {};
}

sub dumpbans {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;
    my $bans = Dumper($self->{banlist});
    return $bans;
}

sub get_banlist {
    my ($self, $event_type, $event) = @_;
    my $channel = lc $event->{event}->{args}[1];
    return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);
    delete $self->{banlist}->{$channel};
    $self->{pbot}->{logger}->log("Retrieving banlist for $channel.\n");
    $event->{conn}->sl("mode $channel +bq");
    return 0;
}

sub on_banlist_entry {

    my ($self, $event_type, $event) = @_;

    my $channel   = lc $event->{event}->{args}[1];
    my $target    = lc $event->{event}->{args}[2];
    my $source    = lc $event->{event}->{args}[3];
    my $timestamp = $event->{event}->{args}[4];

    my $ago = ago(gettimeofday - $timestamp);

    $self->{pbot}->{logger}->log("ban-tracker: [banlist entry] $channel: $target banned by $source $ago.\n");
    $self->{banlist}->{$channel}->{'+b'}->{$target} = [$source, $timestamp];

    if ($target =~ m/^\*!\*@/ or $target =~ m/^\*!.*\@gateway\/web/i) {
        my $timeout = 60 * 60 * 24 * 7;

        if ($target =~ m/\// and $target !~ m/\@gateway/) {
            $timeout = 0;    # permanent bans for cloaks that aren't gateway
        }

        if ($timeout && $self->{pbot}->{chanops}->can_gain_ops($channel)) {
            if (not $self->{pbot}->{chanops}->{unban_timeout}->exists($channel, $target)) {
                $self->{pbot}->{logger}->log("Temp ban for $target in $channel.\n");
                my $data = {
                    timeout => gettimeofday + $timeout,
                    owner   => $source,
                    reason  => 'Temp ban on *!*@... or *!...@gateway/web'
                };
                $self->{pbot}->{chanops}->{unban_timeout}->add($channel, $target, $data);
            }
        }
    }
    return 0;
}

sub on_quietlist_entry {

    my ($self, $event_type, $event) = @_;

    my $channel   = lc $event->{event}->{args}[1];
    my $target    = lc $event->{event}->{args}[3];
    my $source    = lc $event->{event}->{args}[4];
    my $timestamp = $event->{event}->{args}[5];

    my $ago = ago(gettimeofday - $timestamp);

    $self->{pbot}->{logger}->log("ban-tracker: [quietlist entry] $channel: $target quieted by $source $ago.\n");
    $self->{banlist}->{$channel}->{'+q'}->{$target} = [$source, $timestamp];
    return 0;
}

sub get_baninfo {
    my ($self, $mask, $channel, $account) = @_;
    my ($bans, $ban_account);

    $account = undef       if not length $account;
    $account = lc $account if defined $account;

    if ($self->{pbot}->{registry}->get_value('bantracker', 'debug')) {
        $self->{pbot}->{logger}->log("[get-baninfo] Getting baninfo for $mask in $channel using account " . (defined $account ? $account : "[undefined]") . "\n");
    }

    my ($nick, $user, $host) = $mask =~ m/([^!]+)!([^@]+)@(.*)/;

    foreach my $mode (keys %{$self->{banlist}->{$channel}}) {
        foreach my $banmask (keys %{$self->{banlist}->{$channel}->{$mode}}) {
            if   ($banmask =~ m/^\$a:(.*)/) { $ban_account = lc $1; }
            else                            { $ban_account = ""; }

            my $banmask_key = $banmask;
            $banmask = quotemeta $banmask;
            $banmask =~ s/\\\*/.*?/g;
            $banmask =~ s/\\\?/./g;

            my $banned;

            $banned = 1 if defined $account and $account eq $ban_account;
            $banned = 1 if $mask =~ m/^$banmask$/i;

            if ($banmask_key =~ m{\@gateway/web/irccloud.com} and $host =~ m{^gateway/web/irccloud.com}) {
                my ($bannick, $banuser, $banhost) = $banmask_key =~ m/([^!]+)!([^@]+)@(.*)/;

                if (lc $user eq lc $banuser) { $banned = 1; }
            }

            if ($banned) {
                if (not defined $bans) { $bans = []; }

                my $baninfo = {};
                $baninfo->{banmask} = $banmask_key;
                $baninfo->{channel} = $channel;
                $baninfo->{owner}   = $self->{banlist}->{$channel}->{$mode}->{$banmask_key}->[0];
                $baninfo->{when}    = $self->{banlist}->{$channel}->{$mode}->{$banmask_key}->[1];
                $baninfo->{type}    = $mode;
                push @$bans, $baninfo;
            }
        }
    }

    return $bans;
}

sub is_banned {
    my ($self, $nick, $user, $host, $channel) = @_;

    my $message_account   = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
    my @nickserv_accounts = $self->{pbot}->{messagehistory}->{database}->get_nickserv_accounts($message_account);
    push @nickserv_accounts, undef;

    my $banned = undef;

    foreach my $nickserv_account (@nickserv_accounts) {
        my $baninfos = $self->get_baninfo("$nick!$user\@$host", $channel, $nickserv_account);

        if (defined $baninfos) {
            foreach my $baninfo (@$baninfos) {
                my $u           = $self->{pbot}->{users}->loggedin($channel, "$nick!$user\@$host");
                my $whitelisted = $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');
                if ($self->{pbot}->{antiflood}->ban_exempted($baninfo->{channel}, $baninfo->{banmask}) || $whitelisted) {
                    $self->{pbot}->{logger}->log("[BanTracker] is_banned: $nick!$user\@$host banned as $baninfo->{banmask} in $baninfo->{channel}, but allowed through whitelist\n");
                } else {
                    if ($channel eq lc $baninfo->{channel}) {
                        my $mode = $baninfo->{type} eq "+b" ? "banned" : "quieted";
                        $self->{pbot}->{logger}->log("[BanTracker] is_banned: $nick!$user\@$host $mode as $baninfo->{banmask} in $baninfo->{channel} by $baninfo->{owner}\n");
                        $banned = $baninfo;
                        last;
                    }
                }
            }
        }
    }
    return $banned;
}

sub track_mode {
    my $self = shift;
    my ($source, $mode, $target, $channel) = @_;

    $mode    = lc $mode;
    $target  = lc $target;
    $channel = lc $channel;

    if ($mode eq "+b" or $mode eq "+q") {
        $self->{pbot}->{logger}->log("ban-tracker: $target " . ($mode eq '+b' ? 'banned' : 'quieted') . " by $source in $channel.\n");
        $self->{banlist}->{$channel}->{$mode}->{$target} = [$source, gettimeofday];
        $self->{pbot}->{antiflood}->devalidate_accounts($target, $channel);
    } elsif ($mode eq "-b" or $mode eq "-q") {
        $self->{pbot}->{logger}->log("ban-tracker: $target " . ($mode eq '-b' ? 'unbanned' : 'unquieted') . " by $source in $channel.\n");
        delete $self->{banlist}->{$channel}->{$mode eq "-b" ? "+b" : "+q"}->{$target};

        if ($mode eq "-b") {
            if ($self->{pbot}->{chanops}->{unban_timeout}->exists($channel, $target)) { $self->{pbot}->{chanops}->{unban_timeout}->remove($channel, $target); }
            elsif ($self->{pbot}->{chanops}->{unban_timeout}->exists($channel, "$target\$##stop_join_flood")) {
                # freenode strips channel forwards from unban result if no ban exists with a channel forward
                $self->{pbot}->{chanops}->{unban_timeout}->remove($channel, "$target\$##stop_join_flood");
            }
        } elsif ($mode eq "-q") {
            if ($self->{pbot}->{chanops}->{unmute_timeout}->exists($channel, $target)) { $self->{pbot}->{chanops}->{unmute_timeout}->remove($channel, $target); }
        }
    } else {
        $self->{pbot}->{logger}->log("BanTracker: Unknown mode '$mode'\n");
    }
}

1;
