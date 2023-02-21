# File: BanList.pm
#
# Purpose: Implements functions related to maintaining and tracking channel
# bans/mutes. Maintains ban/mute queues and timeouts.

# SPDX-FileCopyrightText: 2015-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::BanList;

use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Core::MessageHistory::Constants ':all';

use Time::HiRes qw/gettimeofday/;
use Time::Duration;
use POSIX qw/strftime/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{registry}->add_default('text', 'banlist', 'chanserv_ban_timeout', '604800');
    $self->{pbot}->{registry}->add_default('text', 'banlist', 'mute_timeout',         '604800');
    $self->{pbot}->{registry}->add_default('text', 'banlist', 'debug',                '0');
    $self->{pbot}->{registry}->add_default('text', 'banlist', 'mute_mode_char',       'q');

    my $data_dir = $self->{pbot}->{registry}->get_value('general', 'data_dir');

    $self->{'ban-exemptions'} = PBot::Core::Storage::DualIndexHashObject->new(
        pbot => $self->{pbot},
        name => 'Ban exemptions',
        filename => "$data_dir/ban-exemptions",
    );

    $self->{banlist} = PBot::Core::Storage::DualIndexHashObject->new(
        pbot     => $self->{pbot},
        name     => 'Ban List',
        filename => "$data_dir/banlist",
        save_queue_timeout => 15,
    );

    $self->{quietlist} = PBot::Core::Storage::DualIndexHashObject->new(
        pbot     => $self->{pbot},
        name     => 'Quiet List',
        filename => "$data_dir/quietlist",
        save_queue_timeout => 15,
    );

    $self->{'ban-exemptions'}->load;
    $self->{banlist}->load;
    $self->{quietlist}->load;

    $self->enqueue_timeouts($self->{banlist}, 'b');
    $self->enqueue_timeouts($self->{quietlist}, $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char'));

    $self->{ban_queue}   = {};
    $self->{unban_queue} = {};

    $self->{pbot}->{event_queue}->enqueue(sub { $self->flush_unban_queue }, 30, 'Flush unban queue');
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

    if (exists $data->{timeout} and $data->{timeout} > 0) {
        my $duration = concise duration($data->{timeout} - gettimeofday);
        $result .= "($duration remaining)";
    }

    return $result;
}

sub is_ban_exempted {
    my ($self, $channel, $hostmask) = @_;
    return 1 if $self->{'ban-exemptions'}->exists(lc $channel, lc $hostmask);
    return 0;
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
                my $u           = $self->{pbot}->{users}->loggedin($baninfo->{channel}, "$nick!$user\@$host");
                my $whitelisted = $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

                if ($self->is_ban_exempted($baninfo->{channel}, $baninfo->{mask}) || $whitelisted) {
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
        $self->{banlist}->remove($channel, $mask, 'timeout');
        $self->{banlist}->add($channel, $mask, $data);
    } elsif ($mode eq $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char')) {
        $self->{quietlist}->remove($channel, $mask, 'timeout');
        $self->{quietlist}->add($channel, $mask, $data);
    }

    my $method = $mode eq 'b' ? 'unban' : 'unmute';
    $self->{pbot}->{event_queue}->dequeue_event("$method $channel $mask");

    if ($length > 0) {
        $self->enqueue_unban($channel, $mode, $mask, $length);
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
        next if $akas{$aka}->{type} == LINK_WEAK;
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

    my $is_irccloud = $host =~ m{\.irccloud.com$};
    my $irccloud_uid;

    if ($is_irccloud) {
        ($irccloud_uid) = $user =~ /id(\d+)$/;
    }

    foreach my $entry (@lists) {
        my ($mode, $list) = @$entry;
        foreach my $banmask ($list->get_keys($channel)) {
            if ($banmask =~ m/^\$a:(.*)/) {
                $ban_nickserv = lc $1;
            } else {
                $ban_nickserv = '';
            }

            my $banmask_regex = quotemeta $banmask;
            $banmask_regex =~ s/\\\*/.*?/g;
            $banmask_regex =~ s/\\\?/./g;

            my $banned;
            $banned = 1 if defined $nickserv and $nickserv eq $ban_nickserv;
            $banned = 1 if $mask =~ m/^$banmask_regex$/i;

            # irccloud hosts are disambiguated by the user field which can be uid{N}+ or sid{N}+
            # where {N}+ are 1 or more integer digits
            if ($is_irccloud && $banmask =~ m{\@.*\.irccloud.com$}) {
                my ($bannick, $banuser, $banhost) = $banmask =~ m/([^!]+)!([^@]+)@(.*)/;
                my ($banuid) = $banuser =~ /id(\d+)$/;
                $banned = $1 if $irccloud_uid == $banuid;
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

    # $a:account, etc, don't need wildcards appended
    if ($mask =~ /^\$/) {
        return $mask;
    }

    # ensure $mask is a complete hostmask by appending missing bits with wildcards
    if ($mask !~ /!/) {
        $mask .= '!*@*';
    } elsif ($mask !~ /@/) {
        $mask =~ s/\*?$/*@*/;
    } else {
        # TODO find out if/where this weird case happens and why...
        $mask =~ s/\@$/@*/;
    }

    return $mask;
}

sub add_to_ban_queue {
    my ($self, $channel, $mode, $mask) = @_;
    if (not grep { $_ eq $mask } @{$self->{ban_queue}->{$channel}->{$mode}}) {
        push @{$self->{ban_queue}->{$channel}->{$mode}}, $mask;
        $self->{pbot}->{logger}->log("Added +$mode $mask for $channel to ban queue.\n");
    }
}

sub add_to_unban_queue {
    my ($self, $channel, $mode, $mask) = @_;
    if (not grep { $_ eq $mask } @{$self->{unban_queue}->{$channel}->{$mode}}) {
        push @{$self->{unban_queue}->{$channel}->{$mode}}, $mask;
        $self->{pbot}->{logger}->log("Added -$mode $mask for $channel to unban queue.\n");
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
                    last if ++$count >= $self->{pbot}->{isupport}->{MODES} // 1;
                }

                if (not @{$self->{ban_queue}->{$channel}->{$mode}}) {
                    delete $self->{ban_queue}->{$channel}->{$mode};
                }

                last if $count >= $self->{pbot}->{isupport}->{MODES} // 1;
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
                    last if ++$count >= $self->{pbot}->{isupport}->{MODES} // 1;
                }

                if (not @{$self->{unban_queue}->{$channel}->{$mode}}) {
                    delete $self->{unban_queue}->{$channel}->{$mode};
                }

                last if $count >= $self->{pbot}->{isupport}->{MODES} // 1;
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

    $self->{pbot}->{event_queue}->enqueue_event(
        sub {
            $self->{pbot}->{event_queue}->update_interval("$method $channel $hostmask", 60 * 5, 1); # try again in 5 minutes
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

1;
