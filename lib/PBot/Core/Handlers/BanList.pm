# File: BanList.pm
#
# Purpose: Populates and maintains channel banlists by checking mode +b/+q
# when joining channels and by tracking modes +b/+q and -b/-q in channels.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::BanList;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw(gettimeofday);
use Time::Duration;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{event_dispatcher}->register_handler('irc.endofnames',     sub { $self->get_banlist(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.banlist',        sub { $self->on_banlist_entry(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quietlist',      sub { $self->on_quietlist_entry(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.endofbanlist',   sub { $self->compare_banlist(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.endofquietlist', sub { $self->compare_quietlist(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.modeflag',       sub { $self->on_modeflag(@_) });

    $self->{mute_char} = $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char');
}

# irc.endofnames
sub get_banlist {
    my ($self, $event_type, $event) = @_;

    my $channel = lc $event->{event}->{args}[1];

    $self->{pbot}->{logger}->log("Retrieving banlist for $channel.\n");

    delete $self->{temp_banlist};

    my $mute_char = $self->{mute_char};

    if ($mute_char eq 'b') {
        $event->{conn}->sl("mode $channel +b");
    } else {
        $event->{conn}->sl("mode $channel +b$mute_char");
    }

    return 1;
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
    return 1;
}

sub on_quietlist_entry {
    my ($self, $event_type, $event) = @_;

    my $channel   = lc $event->{event}->{args}[1];
    my $target    = lc $event->{event}->{args}[3];
    my $source    = lc $event->{event}->{args}[4];
    my $timestamp =    $event->{event}->{args}[5];

    my $ago = concise ago(gettimeofday - $timestamp);
    $self->{pbot}->{logger}->log("Ban List: [quietlist entry] $channel: $target quieted by $source $ago.\n");
    my $mute_char = $self->{mute_char};
    $self->{temp_banlist}->{$channel}->{"+$mute_char"}->{$target} = [$source, $timestamp];
    return 1;
}

# irc.endofbanlist
sub compare_banlist {
    my ($self, $event_type, $event) = @_;
    my $channel = lc $event->{event}->{args}[1];

    # first check for saved bans no longer in channel
    foreach my $mask ($self->{pbot}->{banlist}->{banlist}->get_keys($channel)) {
        if (not exists $self->{temp_banlist}->{$channel}->{'+b'}->{$mask}) {
            $self->{pbot}->{logger}->log("BanList: Saved ban +b $mask no longer exists in $channel.\n");
            # TODO option to restore ban
            $self->{pbot}->{banlist}->{banlist}->remove($channel, $mask, undef, 1);
            $self->{pbot}->{event_queue}->dequeue_event("unban $channel $mask");
        }
    }

    # add channel bans to saved bans
    foreach my $mask (keys %{$self->{temp_banlist}->{$channel}->{'+b'}}) {
        my $data = $self->{pbot}->{banlist}->{banlist}->get_data($channel, $mask);
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
                    $self->{pbot}->{banlist}->enqueue_unban($channel, 'b', $mask, $timeout);
                }
            }
        }

        $self->{pbot}->{banlist}->{banlist}->add($channel, $mask, $data, 1);
    }

    $self->{pbot}->{banlist}->{banlist}->save if keys %{$self->{temp_banlist}->{$channel}->{'+b'}};
    delete $self->{temp_banlist}->{$channel}->{'+b'};
    return 1;
}

# irc.endofquietlist
sub compare_quietlist {
    my ($self, $event_type, $event) = @_;
    my $channel = lc $event->{event}->{args}[1];

    my $mute_char = $self->{mute_char};

    # first check for saved quiets no longer in channel
    foreach my $mask ($self->{pbot}->{banlist}->{quietlist}->get_keys($channel)) {
        if (not exists $self->{temp_banlist}->{$channel}->{"+$mute_char"}->{$mask}) {
            $self->{pbot}->{logger}->log("BanList: Saved quiet +q $mask no longer exists in $channel.\n");
            # TODO option to restore quiet
            $self->{pbot}->{banlist}->{quietlist}->remove($channel, $mask, undef, 1);
            $self->{pbot}->{event_queue}->dequeue_event("unmute $channel $mask");
        }
    }

    # add channel bans to saved bans
    foreach my $mask (keys %{$self->{temp_banlist}->{$channel}->{"+$mute_char"}}) {
        my $data = $self->{pbot}->{banlist}->{quietlist}->get_data($channel, $mask);
        $data->{owner}     = $self->{temp_banlist}->{$channel}->{"+$mute_char"}->{$mask}->[0];
        $data->{timestamp} = $self->{temp_banlist}->{$channel}->{"+$mute_char"}->{$mask}->[1];
        $self->{pbot}->{banlist}->{quietlist}->add($channel, $mask, $data, 1);
    }

    $self->{pbot}->{banlist}->{quietlist}->save if keys %{$self->{temp_banlist}->{$channel}->{"+$mute_char"}};
    delete $self->{temp_banlist}->{$channel}->{"+$mute_char"};
    return 1;
}

sub on_modeflag {
    my ($self, $event_type, $event) = @_;

    my ($source, $channel, $mode, $mask) = (
        $event->{source},
        $event->{channel},
        $event->{mode},
        $event->{target},
    );

    my ($nick) = $source =~ /(^[^!]+)/;
    $channel = defined $channel ? lc $channel : '';
    $mask    = defined $mask ? lc $mask : '';

    my $mute_char = $self->{mute_char};

    if ($mode eq "+b" or $mode eq "+$mute_char") {
        $self->{pbot}->{logger}->log("Ban List: $mask " . ($mode eq '+b' ? 'banned' : 'muted') . " by $source in $channel.\n");

        my $data = {
            owner => $source,
            timestamp => scalar gettimeofday,
        };

        if ($mode eq "+b") {
            $self->{pbot}->{banlist}->{banlist}->add($channel, $mask, $data);
        } elsif ($mode eq "+$mute_char") {
            $self->{pbot}->{banlist}->{quietlist}->add($channel, $mask, $data);
        }

        $self->{pbot}->{antiflood}->devalidate_accounts($mask, $channel);
    } elsif ($mode eq "-b" or $mode eq "-$mute_char") {
        $self->{pbot}->{logger}->log("Ban List: $mask " . ($mode eq '-b' ? 'unbanned' : 'unmuted') . " by $source in $channel.\n");

        if ($mode eq "-b") {
            $self->{pbot}->{banlist}->{banlist}->remove($channel, $mask);
            $self->{pbot}->{event_queue}->dequeue_event("unban $channel $mask");

            # freenode strips channel forwards from unban result if no ban exists with a channel forward
            my $join_flood_channel = $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_channel') // '#stop-join-flood';
            $self->{pbot}->{banlist}->{banlist}->remove($channel, "$mask\$$join_flood_channel");
            $self->{pbot}->{event_queue}->dequeue_event(lc "unban $channel $mask\$$join_flood_channel");
        } elsif ($mode eq "-$mute_char") {
            $self->{pbot}->{banlist}->{quietlist}->remove($channel, $mask);
            $self->{pbot}->{event_queue}->dequeue_event("unmute $channel $mask");
        }
    }

    return if not $self->{pbot}->{chanops}->can_gain_ops($channel);

    if ($mode eq "+b") {
        if ($nick eq "ChanServ" or $mask =~ m/##fix_your_connection$/i) {
            if ($self->{pbot}->{banlist}->{banlist}->exists($channel, $mask)) {
                $self->{pbot}->{banlist}->{banlist}->set($channel, $mask, 'timeout', gettimeofday + $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'));
                $self->{pbot}->{event_queue}->update_interval("unban $channel $mask", $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'));
            } else {
                my $data = {
                    reason    => 'Temp ban for banned-by-ChanServ or mask is *!*@*##fix_your_connection',
                    owner     => $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                    timeout   => gettimeofday + $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'),
                    timestamp => gettimeofday,
                };
                $self->{pbot}->{banlist}->{banlist}->add($channel, $mask, $data);
                $self->{pbot}->{banlist}->enqueue_unban($channel, 'b', $mask, $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'));
            }
        } elsif ($mask =~ m/^\*!\*@/ or $mask =~ m/^\*!.*\@gateway\/web/i) {
            my $timeout = 60 * 60 * 24 * 7;

            if ($mask =~ m/\// and $mask !~ m/\@gateway/) {
                $timeout = 0;    # permanent bans for cloaks that aren't gateway
            }

            if ($timeout) {
                if (not $self->{pbot}->{banlist}->{banlist}->exists($channel, $mask)) {
                    $self->{pbot}->{logger}->log("Temp ban for $mask in $channel.\n");
                    my $data = {
                        reason    => 'Temp ban for *!*@host',
                        timeout   => gettimeofday + $timeout,
                        owner     => $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                        timestamp => gettimeofday,
                    };
                    $self->{pbot}->{banlist}->{banlist}->add($channel, $mask, $data);
                    $self->{pbot}->{banlist}->enqueue_unban($channel, 'b', $mask, $timeout);
                }
            }
        }
    } elsif ($mode eq "+$mute_char") {
        if (lc $nick ne lc $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
            $self->{pbot}->{logger}->log("WEIRD MUTE THING $nick...\n");
            if ($self->{pbot}->{banlist}->{quietlist}->exists($channel, $mask)) {
                $self->{pbot}->{banlist}->{quietlist}->set($channel, $mask, 'timeout', gettimeofday + $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'));
                $self->{pbot}->{event_queue}->update_interval("unmute $channel $mask", $self->{pbot}->{registry}->get_value('banlist', 'chanserv_ban_timeout'));
            } else {
                my $data = {
                    reason    => 'Temp mute',
                    owner     => $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                    timeout   => gettimeofday + $self->{pbot}->{registry}->get_value('banlist', 'mute_timeout'),
                    timestamp => gettimeofday,
                };
                $self->{pbot}->{banlist}->{quietlist}->add($channel, $mask, $data);
                $self->{pbot}->{banlist}->enqueue_unban($channel, $self->{mute_char}, $mask, $self->{pbot}->{registry}->get_value('banlist', 'mute_timeout'));
            }
        }
    }

    return 1;
}

1;
