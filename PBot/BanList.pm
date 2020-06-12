# File: BanList.pm
# Author: pragma_
#
# Purpose: Populates and maintains channel banlists by checking mode +b/+q on
# joining channels and by tracking modes +b/+q and -b/-q in channels. Keeps
# track of remaining duration for timed bans/quiets. Handles ban/unban queue.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::BanList;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use Time::HiRes qw/gettimeofday/;
use Time::Duration;
use Data::Dumper;
use POSIX qw/strftime/;

$Data::Dumper::Sortkeys = 1;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{registry}->add_default('text', 'banlist', 'chanserv_ban_timeout', '604800');
    $self->{pbot}->{registry}->add_default('text', 'banlist', 'mute_timeout',         '604800');
    $self->{pbot}->{registry}->add_default('text', 'banlist', 'debug',                '0');
    $self->{pbot}->{registry}->add_default('text', 'banlist', 'mute_mode_char',       'q');

    $self->{pbot}->{commands}->register(sub { $self->cmd_banlist(@_) },   "banlist",   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_checkban(@_) },  "checkban",  0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_checkmute(@_) }, "checkmute", 0);

    $self->{pbot}->{event_dispatcher}->register_handler('irc.endofnames',     sub { $self->get_banlist(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.banlist',        sub { $self->on_banlist_entry(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quietlist',      sub { $self->on_quietlist_entry(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.endofbanlist',   sub { $self->compare_banlist(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.endofquietlist', sub { $self->compare_quietlist(@_) });

    $self->{banlist} = PBot::DualIndexHashObject->new(
        pbot     => $self->{pbot},
        name     => 'Ban List',
        filename => $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/banlist',
        save_queue_timeout => 15,
    );

    $self->{quietlist} = PBot::DualIndexHashObject->new(
        pbot     => $self->{pbot},
        name     => 'Quiet List',
        filename => $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/quietlist',
        save_queue_timeout => 15,
    );

    $self->{banlist}->load;
    $self->{quietlist}->load;

    $self->enqueue_timeouts($self->{banlist},   'b');
    $self->enqueue_timeouts($self->{quietlist}, $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char'));

    $self->{ban_queue}   = {};
    $self->{unban_queue} = {};

    $self->{pbot}->{timer}->register(sub { $self->flush_unban_queue }, 30, 'Unban Queue');
}

sub cmd_banlist {
    my ($self, $context) = @_;

    if (not length $context->{arguments}) {
        return "Usage: banlist <channel>";
    }

    my $result = "Ban list for $context->{arguments}:\n";

    if ($self->{banlist}->exists($context->{arguments})) {
        my $count = $self->{banlist}->get_keys($context->{arguments});
        $result .= "$count ban" . ($count == 1 ? '' : 's') . ":\n";
        foreach my $mask ($self->{banlist}->get_keys($context->{arguments})) {
            my $data = $self->{banlist}->get_data($context->{arguments}, $mask);
            $result .= "  $mask banned ";

            if (defined $data->{timestamp}) {
                my $date = strftime "%a %b %e %H:%M:%S %Y %Z", localtime $data->{timestamp};
                my $ago = concise ago (time - $data->{timestamp});
                $result .= "on $date ($ago) ";
            }

            $result .= "by $data->{owner} "   if defined $data->{owner};
            $result .= "for $data->{reason} " if defined $data->{reason};
            if (defined $data->{timeout} and $data->{timeout} > 0) {
                my $duration = concise duration($data->{timeout} - gettimeofday);
                $result .= "($duration remaining)";
            }
            $result .= ";\n";
        }
    } else {
        $result .= "bans: none;\n";
    }

    if ($self->{quietlist}->exists($context->{arguments})) {
        my $count = $self->{quietlist}->get_keys($context->{arguments});
        $result .= "$count mute" . ($count == 1 ? '' : 's') . ":\n";
        foreach my $mask ($self->{quietlist}->get_keys($context->{arguments})) {
            my $data = $self->{quietlist}->get_data($context->{arguments}, $mask);
            $result .= "  $mask muted ";

            if (defined $data->{timestamp}) {
                my $date = strftime "%a %b %e %H:%M:%S %Y %Z", localtime $data->{timestamp};
                my $ago = concise ago (time - $data->{timestamp});
                $result .= "on $date ($ago) ";
            }

            $result .= "by $data->{owner} "   if defined $data->{owner};
            $result .= "for $data->{reason} " if defined $data->{reason};
            if (defined $data->{timeout} and $data->{timeout} > 0) {
                my $duration = concise duration($data->{timeout} - gettimeofday);
                $result .= "($duration remaining)";
            }
            $result .= ";\n";
        }
    } else {
        $result .= "quiets: none\n";
    }

    $result =~ s/ ;/;/g;
    return $result;
}

sub cmd_checkban {
    my ($self, $context) = @_;
    my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    return "Usage: checkban <mask> [channel]" if not defined $target;
    $channel = $context->{from} if not defined $channel;

    return "Please specify a channel." if $channel !~ /^#/;
    return $self->checkban($channel, 'b', $target);
}

sub cmd_checkmute {
    my ($self, $context) = @_;
    my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    return "Usage: checkmute <mask> [channel]" if not defined $target;
    $channel = $context->{from} if not defined $channel;

    return "Please specify a channel." if $channel !~ /^#/;
    return $self->checkban($channel, $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char'), $target);
}

sub get_banlist {
    my ($self, $event_type, $event) = @_;
    my $channel = lc $event->{event}->{args}[1];
    $self->{pbot}->{logger}->log("Retrieving banlist for $channel.\n");
    delete $self->{temp_banlist};

    my $mute_char = $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char');

    if ($mute_char eq 'b') {
        $event->{conn}->sl("mode $channel +b");
    } else {
        $event->{conn}->sl("mode $channel +b$mute_char");
    }

    return 0;
}

sub on_banlist_entry {
    my ($self, $event_type, $event) = @_;

    my $channel   = lc $event->{event}->{args}[1];
    my $target    = lc $event->{event}->{args}[2];
    my $source    = lc $event->{event}->{args}[3];
    my $timestamp =    $event->{event}->{args}[4];

    my $ago = concise ago(gettimeofday - $timestamp);
    $self->{pbot}->{logger}->log("Ban List: [banlist entry] $channel: $target banned by $source $ago.\n");
    $self->{temp_banlist}->{$channel}->{'+b'}->{$target} = [$source, $timestamp];
    return 0;
}

sub on_quietlist_entry {
    my ($self, $event_type, $event) = @_;

    my $channel   = lc $event->{event}->{args}[1];
    my $target    = lc $event->{event}->{args}[3];
    my $source    = lc $event->{event}->{args}[4];
    my $timestamp =    $event->{event}->{args}[5];

    my $ago = concise ago(gettimeofday - $timestamp);
    $self->{pbot}->{logger}->log("Ban List: [quietlist entry] $channel: $target quieted by $source $ago.\n");
    my $mute_char = $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char');
    $self->{temp_banlist}->{$channel}->{"+$mute_char"}->{$target} = [$source, $timestamp];
    return 0;
}

sub compare_banlist {
    my ($self, $event_type, $event) = @_;
    my $channel = lc $event->{event}->{args}[1];

    $self->{pbot}->{logger}->log("Finalizing Ban List for $channel\n");

    # first check for saved bans no longer in channel
    foreach my $mask ($self->{banlist}->get_keys($channel)) {
        if (not exists $self->{temp_banlist}->{$channel}->{'+b'}->{$mask}) {
            $self->{pbot}->{logger}->log("BanList: Saved ban +b $mask no longer exists in $channel.\n");
            # TODO option to restore ban
            $self->{banlist}->remove($channel, $mask, undef, 1);
            $self->{pbot}->{timer}->dequeue_event("unban $channel $mask");
        }
    }

    # add channel bans to saved bans
    foreach my $mask (keys %{$self->{temp_banlist}->{$channel}->{'+b'}}) {
        my $data = $self->{banlist}->get_data($channel, $mask);
        $data->{owner}     = $self->{temp_banlist}->{$channel}->{'+b'}->{$mask}->[0];
        $data->{timestamp} = $self->{temp_banlist}->{$channel}->{'+b'}->{$mask}->[1];

        # make some special-case bans temporary
        if (not defined $data->{timeout} and $self->{pbot}->{chanops}->can_gain_ops($channel)) {
            if ($mask =~ m/^\*!\*@/ or $mask =~ m/^\*!.*\@gateway\/web/i) {
                my $timeout = 60 * 60 * 24 * 7;

                # permanent bans for cloaks that aren't gateway
                $timeout = 0 if $mask =~ m/\// and $mask !~ m/\@gateway/;

                if ($timeout) {
                    $self->{pbot}->{logger}->log("Temp ban for $mask in $channel.\n");
                    $data->{timeout} = gettimeofday + $timeout;
                    $self->{pbot}->{chanops}->enqueue_unban($channel, 'b', $mask, $timeout);
                }
            }
        }

        $self->{banlist}->add($channel, $mask, $data, 1);
    }

    $self->{banlist}->save if keys %{$self->{temp_banlist}->{$channel}->{'+b'}};
    delete $self->{temp_banlist}->{$channel}->{'+b'};
}

sub compare_quietlist {
    my ($self, $event_type, $event) = @_;
    my $channel = lc $event->{event}->{args}[1];

    $self->{pbot}->{logger}->log("Finalizing quiet list for $channel\n");
    my $mute_char = $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char');

    # first check for saved quiets no longer in channel
    foreach my $mask ($self->{quietlist}->get_keys($channel)) {
        if (not exists $self->{temp_banlist}->{$channel}->{"+$mute_char"}->{$mask}) {
            $self->{pbot}->{logger}->log("BanList: Saved quiet +q $mask no longer exists in $channel.\n");
            # TODO option to restore quiet
            $self->{quietlist}->remove($channel, $mask, undef, 1);
            $self->{pbot}->{timer}->dequeue_event("unmute $channel $mask");
        }
    }

    # add channel bans to saved bans
    foreach my $mask (keys %{$self->{temp_banlist}->{$channel}->{"+$mute_char"}}) {
        my $data = $self->{quietlist}->get_data($channel, $mask);
        $data->{owner}     = $self->{temp_banlist}->{$channel}->{"+$mute_char"}->{$mask}->[0];
        $data->{timestamp} = $self->{temp_banlist}->{$channel}->{"+$mute_char"}->{$mask}->[1];
        $self->{quietlist}->add($channel, $mask, $data, 1);
    }

    $self->{quietlist}->save if keys %{$self->{temp_banlist}->{$channel}->{"+$mute_char"}};
    delete $self->{temp_banlist}->{$channel}->{"+$mute_char"};
}

sub track_mode {
    my $self = shift;
    my ($source, $channel, $mode, $mask) = @_;

    my ($nick) = $source =~ /(^[^!]+)/;
    $channel = defined $channel ? lc $channel : '';
    $mask    = defined $mask ? lc $mask : '';

    my $mute_char = $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char');

    if ($mode eq "+b" or $mode eq "+$mute_char") {
        $self->{pbot}->{logger}->log("Ban List: $mask " . ($mode eq '+b' ? 'banned' : 'muted') . " by $source in $channel.\n");

        my $data = {
            owner => $source,
            timestamp => scalar gettimeofday,
        };

        if ($mode eq "+b") {
            $self->{banlist}->add($channel, $mask, $data);
        } elsif ($mode eq "+$mute_char") {
            $self->{quietlist}->add($channel, $mask, $data);
        }

        $self->{pbot}->{antiflood}->devalidate_accounts($mask, $channel);
    } elsif ($mode eq "-b" or $mode eq "-$mute_char") {
        $self->{pbot}->{logger}->log("Ban List: $mask " . ($mode eq '-b' ? 'unbanned' : 'unmuted') . " by $source in $channel.\n");

        if ($mode eq "-b") {
            $self->{banlist}->remove($channel, $mask);
            $self->{pbot}->{timer}->dequeue_event("unban $channel $mask");

            # freenode strips channel forwards from unban result if no ban exists with a channel forward
            $self->{banlist}->remove($channel, "$mask\$##stop_join_flood");
            $self->{pbot}->{timer}->dequeue_event(lc "unban $channel $mask\$##stop_join_flood");
        } elsif ($mode eq "-$mute_char") {
            $self->{quietlist}->remove($channel, $mask);
            $self->{pbot}->{timer}->dequeue_event("unmute $channel $mask");
        }
    }

    return if not $self->{pbot}->{chanops}->can_gain_ops($channel);

    if ($mode eq "+b") {
        if ($nick eq "ChanServ" or $mask =~ m/##fix_your_connection$/i) {
            if ($self->{banlist}->exists($channel, $mask)) {
                $self->{banlist}->set($channel, $mask, 'timeout', gettimeofday + $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'));
                $self->{pbot}->{timer}->update_interval("unban $channel $mask", $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'));
            } else {
                my $data = {
                    reason    => 'Temp ban for banned-by-ChanServ or mask is *!*@*##fix_your_connection',
                    owner     => $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                    timeout   => gettimeofday + $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'),
                    timestamp => gettimeofday,
                };
                $self->{banlist}->add($channel, $mask, $data);
                $self->enqueue_unban($channel, 'b', $mask, $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'));
            }
        } elsif ($mask =~ m/^\*!\*@/ or $mask =~ m/^\*!.*\@gateway\/web/i) {
            my $timeout = 60 * 60 * 24 * 7;

            if ($mask =~ m/\// and $mask !~ m/\@gateway/) {
                $timeout = 0;    # permanent bans for cloaks that aren't gateway
            }

            if ($timeout) {
                if (not $self->{banlist}->exists($channel, $mask)) {
                    $self->{pbot}->{logger}->log("Temp ban for $mask in $channel.\n");
                    my $data = {
                        reason    => 'Temp ban for *!*@host',
                        timeout   => gettimeofday + $timeout,
                        owner     => $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                        timestamp => gettimeofday,
                    };
                    $self->{banlist}->add($channel, $mask, $data);
                    $self->enqueue_unban($channel, 'b', $mask, $timeout);
                }
            }
        }
    } elsif ($mode eq "+$mute_char") {
        if (lc $nick ne lc $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
            $self->{pbot}->{logger}->log("WEIRD MUTE THING $nick...\n");
            if ($self->{quietlist}->exists($channel, $mask)) {
                $self->{quietlist}->set($channel, $mask, 'timeout', gettimeofday + $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'));
                $self->{pbot}->{timer}->update_interval("unmute $channel $mask", $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'));
            } else {
                my $data = {
                    reason    => 'Temp mute',
                    owner     => $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                    timeout   => gettimeofday + $self->{pbot}->{registry}->get_value('banlist', 'mute_timeout'),
                    timestamp => gettimeofday,
                };
                $self->{quietlist}->add($channel, $mask, $data);
                $self->enqueue_unban($channel, $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char'), $mask, $self->{pbot}->{registry}->get_value('banlist', 'mute_timeout'));
            }
        }
    }
}

sub ban_user {
    my ($self, $channel, $mode, $mask, $immediately) = @_;
    $mode ||= 'b';
    $self->{pbot}->{logger}->log("Banning $channel +$mode $mask\n");
    $self->add_to_ban_queue($channel, $mode, $mask);
    if (not defined $immediately or $immediately != 0) {
        $self->flush_ban_queue;
    }
}

sub unban_user {
    my ($self, $channel, $mode, $mask, $immediately) = @_;
    $mask    = lc $mask;
    $channel = lc $channel;
    $mode ||= 'b';
    $self->{pbot}->{logger}->log("Unbanning $channel -$mode $mask\n");
    $self->unmode_user($channel, $mode, $mask, $immediately);
}

sub unmode_user {
    my ($self, $channel, $mode, $mask, $immediately) = @_;

    $mask    = lc $mask;
    $channel = lc $channel;
    $self->{pbot}->{logger}->log("Removing mode $mode from $mask in $channel\n");

    my $bans = $self->get_bans($channel, $mask);
    my %unbanned;

    if (not defined $bans) {
        push @$bans, { mask => $mask, type => $mode };
    }

    foreach my $ban (@$bans) {
        next if $ban->{type} ne $mode;
        next if exists $unbanned{$ban->{mask}};
        $unbanned{$ban->{mask}} = 1;
        $self->add_to_unban_queue($channel, $mode, $ban->{mask});
    }

    $self->flush_unban_queue if $immediately;
}

sub get_bans {
    my ($self, $channel, $mask) = @_;

    my $masks;
    my ($message_account, $hostmask);

    if ($mask !~ m/[!@]/) {
        ($message_account, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($mask);
        $hostmask = $mask if not defined $message_account;
    } else {
        $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account_id($mask);
        $hostmask = $mask;
    }

    if (defined $message_account) {
        my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($message_account);
        $masks = $self->get_baninfo($channel, $hostmask, $nickserv);
    }

    my %akas = $self->{pbot}->{messagehistory}->{database}->get_also_known_as($hostmask);

    foreach my $aka (keys %akas) {
        next if $akas{$aka}->{type} == $self->{pbot}->{messagehistory}->{database}->{alias_type}->{WEAK};
        next if $akas{$aka}->{nickchange} == 1;

        my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($akas{$aka}->{id});

        my $b = $self->get_baninfo($channel, $aka, $nickserv);
        if (defined $b) {
            push @$masks, @$b;
        }
    }

    return $masks;
}

sub get_baninfo {
    my ($self, $channel, $mask, $nickserv) = @_;
    my ($bans, $ban_nickserv);

    $nickserv = undef        if not length $nickserv;
    $nickserv = lc $nickserv if defined $nickserv;

    if ($self->{pbot}->{registry}->get_value('banlist', 'debug')) {
        my $ns = defined $nickserv ? $nickserv : "[undefined]";
        $self->{pbot}->{logger}->log("[get-baninfo] Getting baninfo for $mask in $channel using nickserv $ns\n");
    }

    my ($nick, $user, $host) = $mask =~ m/([^!]+)!([^@]+)@(.*)/;

    my @lists = (
        [ 'b', $self->{banlist} ],
        [ $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char'), $self->{quietlist} ],
    );

    foreach my $entry (@lists) {
        my ($mode, $list) = @$entry;
        foreach my $banmask ($list->get_keys($channel)) {
            if   ($banmask =~ m/^\$a:(.*)/) { $ban_nickserv = lc $1; }
            else                            { $ban_nickserv = ""; }

            my $banmask_regex = quotemeta $banmask;
            $banmask_regex =~ s/\\\*/.*?/g;
            $banmask_regex =~ s/\\\?/./g;

            my $banned;
            $banned = 1 if defined $nickserv and $nickserv eq $ban_nickserv;
            $banned = 1 if $mask =~ m/^$banmask_regex$/i;

            if ($banmask =~ m{\@gateway/web/irccloud.com} and $host =~ m{^gateway/web/irccloud.com}) {
                my ($bannick, $banuser, $banhost) = $banmask =~ m/([^!]+)!([^@]+)@(.*)/;
                $banned = $1 if lc $user eq lc $banuser;
            }

            if ($banned) {
                my $data = $list->get_data($channel, $banmask);
                my $baninfo = {
                    mask    => $banmask,
                    channel => $channel,
                    owner   => $data->{owner},
                    when    => $data->{timestamp},
                    type    => $mode,
                    reason  => $data->{reason},
                    timeout => $data->{timeout},
                };
                push @$bans, $baninfo;
            }
        }
    }

    return $bans;
}

sub nick_to_banmask {
    my ($self, $mask) = @_;

    if ($mask !~ m/[!@\$]/) {
        my ($message_account, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($mask);
        if (defined $hostmask) {
            my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($message_account);
            if (defined $nickserv && length $nickserv) { $mask = '$a:' . $nickserv; }
            else {
                my ($nick, $user, $host) = $hostmask =~ m/([^!]+)!([^@]+)@(.*)/;
                $mask = "*!$user\@" . $self->{pbot}->{antiflood}->address_to_mask($host);
            }
        } else {
            $mask .= '!*@*';
        }
    }

    return $mask;
}

sub ban_user_timed {
    my ($self, $channel, $mode, $mask, $length, $owner, $reason, $immediately) = @_;

    $channel = lc $channel;
    $mask    = lc $mask;

    $mask = $self->nick_to_banmask($mask);
    $self->ban_user($channel, $mode, $mask, $immediately);

    my $data = {
        timeout   => $length > 0 ? gettimeofday + $length : -1,
        owner     => $owner,
        reason    => $reason,
        timestamp => time,
    };

    if ($mode eq 'b') {
        $self->{banlist}->add($channel, $mask, $data);
    } elsif ($mode eq $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char')) {
        $self->{quietlist}->add($channel, $mask, $data);
    }

    my $method = $mode eq 'b' ? 'unban' : 'unmute';
    $self->{pbot}->{timer}->dequeue_event("$method $channel $mask");

    if ($length > 0) {
        $self->enqueue_unban($channel, $mode, $mask, $length);
    }
}

sub checkban {
    my ($self, $channel, $mode, $mask) = @_;
    $mask = $self->nick_to_banmask($mask);

    my $data;

    if ($mode eq 'b') {
        $data = $self->{banlist}->get_data($channel, $mask);
    } elsif ($mode eq $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char')) {
        $data = $self->{quietlist}->get_data($channel, $mask);
    }

    if (not defined $data) {
        return "$mask is not " . ($mode eq 'b' ? 'banned' : 'muted') . ".";
    }

    my $result = "$mask " . ($mode eq 'b' ? 'banned' : 'quieted') . " in $channel ";

    if (defined $data->{timestamp}) {
        my $date = strftime "%a %b %e %H:%M:%S %Y %Z", localtime $data->{timestamp};
        my $ago = concise ago (time - $data->{timestamp});
        $result .= "on $date ($ago) ";
    }

    $result .= "by $data->{owner} "   if defined $data->{owner};
    $result .= "for $data->{reason} " if defined $data->{reason};
    if ($data->{timeout} > 0) {
        my $duration = concise duration($data->{timeout} - gettimeofday);
        $result .= "($duration remaining)";
    }
    return $result;
}

sub add_to_ban_queue {
    my ($self, $channel, $mode, $mask) = @_;
    if (not grep { $_ eq $mask } @{$self->{ban_queue}->{$channel}->{$mode}}) {
        push @{$self->{ban_queue}->{$channel}->{$mode}}, $mask;
        $self->{pbot}->{logger}->log("Added +$mode $mask for $channel to ban queue.\n");
    }
}

sub flush_ban_queue {
    my $self = shift;

    my $MAX_COMMANDS = 4;
    my $commands     = 0;

    foreach my $channel (keys %{$self->{ban_queue}}) {
        my $done = 0;
        while (not $done) {
            my ($list, $count, $modes);
            $list  = '';
            $modes = '+';
            $count = 0;

            foreach my $mode (keys %{$self->{ban_queue}->{$channel}}) {
                while (@{$self->{ban_queue}->{$channel}->{$mode}}) {
                    my $target = pop @{$self->{ban_queue}->{$channel}->{$mode}};
                    $list  .= " $target";
                    $modes .= $mode;
                    last if ++$count >= $self->{pbot}->{ircd}->{MODES};
                }

                if (not @{$self->{ban_queue}->{$channel}->{$mode}}) {
                    delete $self->{ban_queue}->{$channel}->{$mode};
                }

                last if $count >= $self->{pbot}->{ircd}->{MODES};
            }

            if (not keys %{$self->{ban_queue}->{$channel}}) {
                delete $self->{ban_queue}->{$channel};
                $done = 1;
            }

            if ($count) {
                $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $modes $list");
                $self->{pbot}->{chanops}->gain_ops($channel);
                return if ++$commands >= $MAX_COMMANDS;
            }
        }
    }
}

sub add_to_unban_queue {
    my ($self, $channel, $mode, $mask) = @_;
    if (not grep { $_ eq $mask } @{$self->{unban_queue}->{$channel}->{$mode}}) {
        push @{$self->{unban_queue}->{$channel}->{$mode}}, $mask;
        $self->{pbot}->{logger}->log("Added -$mode $mask for $channel to unban queue.\n");
    }
}

sub flush_unban_queue {
    my $self = shift;

    my $MAX_COMMANDS = 4;
    my $commands     = 0;

    foreach my $channel (keys %{$self->{unban_queue}}) {
        my $done = 0;
        while (not $done) {
            my ($list, $count, $modes);
            $list  = '';
            $modes = '-';
            $count = 0;

            foreach my $mode (keys %{$self->{unban_queue}->{$channel}}) {
                while (@{$self->{unban_queue}->{$channel}->{$mode}}) {
                    my $target = pop @{$self->{unban_queue}->{$channel}->{$mode}};
                    $list  .= " $target";
                    $modes .= $mode;
                    last if ++$count >= $self->{pbot}->{ircd}->{MODES};
                }

                if (not @{$self->{unban_queue}->{$channel}->{$mode}}) {
                    delete $self->{unban_queue}->{$channel}->{$mode};
                }

                last if $count >= $self->{pbot}->{ircd}->{MODES};
            }

            if (not keys %{$self->{unban_queue}->{$channel}}) {
                delete $self->{unban_queue}->{$channel};
                $done = 1;
            }

            if ($count) {
                $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $modes $list");
                $self->{pbot}->{chanops}->gain_ops($channel);
                return if ++$commands >= $MAX_COMMANDS;
            }
        }
    }
}

sub enqueue_unban {
    my ($self, $channel, $mode, $hostmask, $interval) = @_;

    my $method = $mode eq 'b' ? 'unban' : 'unmute';

    $self->{pbot}->{timer}->enqueue_event(
        sub {
            $self->{pbot}->{timer}->update_interval("$method $channel $hostmask", 60 * 15, 1); # try again in 15 minutes
            return if not $self->{pbot}->{joined_channels};
            $self->unban_user($channel, $mode, $hostmask);
        }, $interval, "$method $channel $hostmask", 1
    );
}

sub enqueue_timeouts {
    my ($self, $list, $mode) = @_;
    my $now = time;

    foreach my $channel ($list->get_keys) {
        foreach my $mask ($list->get_keys($channel)) {
            my $timeout = $list->get_data($channel, $mask, 'timeout');
            next if defined $timeout and $timeout <= 0;
            next if not defined $timeout;
            my $interval = $timeout - $now;
            $interval = 10 if $interval < 10;
            $self->enqueue_unban($channel, $mode, $mask, $interval);
        }
    }
}

sub has_ban_timeout {
    my ($self, $channel, $mask, $mode) = @_;
    $mode ||= 'b';

    my $list = $mode eq 'b' ? $self->{banlist} : $self->{quietlist};

    my $data = $list->get_data($channel, $mask);

    if (defined $data && $data->{timeout} > 0) {
        return 1;
    } else {
        return 0;
    }
}

sub is_banned {
    my ($self, $channel, $nick, $user, $host) = @_;

    my $message_account   = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
    my @nickserv_accounts = $self->{pbot}->{messagehistory}->{database}->get_nickserv_accounts($message_account);
    push @nickserv_accounts, undef;

    my $banned = undef;

    foreach my $nickserv_account (@nickserv_accounts) {
        my $baninfos = $self->get_baninfo($channel, "$nick!$user\@$host", $nickserv_account);

        if (defined $baninfos) {
            foreach my $baninfo (@$baninfos) {
                my $u           = $self->{pbot}->{users}->loggedin($channel, "$nick!$user\@$host");
                my $whitelisted = $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');
                if ($self->{pbot}->{antiflood}->ban_exempted($baninfo->{channel}, $baninfo->{mask}) || $whitelisted) {
                    $self->{pbot}->{logger}->log("[BanList] is_banned: $nick!$user\@$host banned as $baninfo->{mask} in $baninfo->{channel}, but allowed through whitelist\n");
                } else {
                    if ($channel eq lc $baninfo->{channel}) {
                        my $mode = $baninfo->{type} eq 'b' ? "banned" : "quieted";
                        $self->{pbot}->{logger}->log("[BanList] is_banned: $nick!$user\@$host $mode as $baninfo->{mask} in $baninfo->{channel} by $baninfo->{owner}\n");
                        $banned = $baninfo;
                        last;
                    }
                }
            }
        }
    }

    return $banned;
}

1;
