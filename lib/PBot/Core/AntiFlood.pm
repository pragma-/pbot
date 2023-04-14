# File: AntiFlood.pm
#
# Purpose: Tracks message and nickserv statistics to enforce anti-flooding and
# ban-evasion detection.
#
# The nickserv/ban-evasion stuff probably ought to be in BanTracker or some
# such suitable class.

# SPDX-FileCopyrightText: 2007-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::AntiFlood;
use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Core::MessageHistory::Constants ':all';

use Time::HiRes qw(gettimeofday tv_interval);
use Time::Duration;
use POSIX qw/strftime/;
use Text::CSV;

sub initialize($self, %conf) {
    # flags for 'validated' field
    use constant {
        NICKSERV_VALIDATED => (1 << 0),
        NEEDS_CHECKBAN     => (1 << 1),
    };

    $self->{channels}      = {};    # per-channel statistics, e.g. for optimized tracking of last spoken nick for enter-abuse detection, etc
    $self->{nickflood}     = {};    # statistics to track nickchange flooding
    $self->{whois_pending} = {};    # prevents multiple whois for nick joining multiple channels at once
    $self->{changinghost}  = {};    # tracks nicks changing hosts/identifying to strongly link them

    $self->{pbot}->{event_queue}->enqueue(sub { $self->adjust_offenses }, 60 * 60 * 1, 'Adjust anti-flood offenses');

    $self->{pbot}->{registry}->add_default('text', 'antiflood', 'enforce', $conf{enforce_antiflood} // 1);

    $self->{pbot}->{registry}->add_default('text',  'antiflood', 'join_flood_threshold',      $conf{join_flood_threshold}      // 4);
    $self->{pbot}->{registry}->add_default('text',  'antiflood', 'join_flood_time_threshold', $conf{join_flood_time_threshold} // 60 * 30);
    $self->{pbot}->{registry}->add_default('array', 'antiflood', 'join_flood_punishment',     $conf{join_flood_punishment}     // '28800,3600,86400,604800,2419200,14515200');

    $self->{pbot}->{registry}->add_default('text',  'antiflood', 'chat_flood_threshold',      $conf{chat_flood_threshold}      // 4);
    $self->{pbot}->{registry}->add_default('text',  'antiflood', 'chat_flood_time_threshold', $conf{chat_flood_time_threshold} // 10);
    $self->{pbot}->{registry}->add_default('array', 'antiflood', 'chat_flood_punishment',     $conf{chat_flood_punishment}     // '60,300,3600,86400,604800,2419200');

    $self->{pbot}->{registry}->add_default('text',  'antiflood', 'nick_flood_threshold',      $conf{nick_flood_threshold}      // 3);
    $self->{pbot}->{registry}->add_default('text',  'antiflood', 'nick_flood_time_threshold', $conf{nick_flood_time_threshold} // 60 * 30);
    $self->{pbot}->{registry}->add_default('array', 'antiflood', 'nick_flood_punishment',     $conf{nick_flood_punishment}     // '60,300,3600,86400,604800,2419200');

    $self->{pbot}->{registry}->add_default('text',  'antiflood', 'enter_abuse_threshold',      $conf{enter_abuse_threshold}      // 4);
    $self->{pbot}->{registry}->add_default('text',  'antiflood', 'enter_abuse_time_threshold', $conf{enter_abuse_time_threshold} // 20);
    $self->{pbot}->{registry}->add_default('array', 'antiflood', 'enter_abuse_punishment',     $conf{enter_abuse_punishment}     // '60,300,3600,86400,604800,2419200');
    $self->{pbot}->{registry}->add_default('text',  'antiflood', 'enter_abuse_max_offenses',   $conf{enter_abuse_max_offenses}   // 3);

    $self->{pbot}->{registry}->add_default('text', 'antiflood', 'debug_checkban', $conf{debug_checkban} // 0);

    $self->{pbot}->{event_dispatcher}->register_handler('irc.whoisaccount', sub { $self->on_whoisaccount(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.whoisuser',    sub { $self->on_whoisuser(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.endofwhois',   sub { $self->on_endofwhois(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.account',      sub { $self->on_accountnotify(@_) });
}

sub update_join_watch($self, $account, $channel, $text, $mode) {
    return if $channel =~ /[@!]/;    # ignore QUIT messages from nick!user@host channels

    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'join_watch');

    if ($mode == MSG_JOIN) {
        $channel_data->{join_watch}++;
        $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
    } elsif ($mode == MSG_DEPARTURE) {
        # PART or QUIT
        # check QUIT message for netsplits, and decrement joinwatch to allow a free rejoin
        if ($text =~ /^QUIT .*\.net .*\.split/) {
            if ($channel_data->{join_watch} > 0) {
                $channel_data->{join_watch}--;
                $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
            }
        }

        # check QUIT message for Ping timeout or Excess Flood
        elsif ($text =~ /^QUIT Excess Flood/ or $text =~ /^QUIT Max SendQ exceeded/ or $text =~ /^QUIT Ping timeout/) {
            # treat these as an extra join so they're snagged more quickly since these usually will keep flooding
            $channel_data->{join_watch}++;
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
        } else {
            # some other type of QUIT or PART
        }
    } elsif ($mode == MSG_CHAT) {
        # reset joinwatch if they send a message
        if ($channel_data->{join_watch} > 0) {
            $channel_data->{join_watch} = 0;
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
        }
    }
}

# TODO: break this gigantic function up into simple plugins
# e.g. PBot::Plugin::AntiAbuse::ChatFlood, ::JoinFlood, ::EnterAbuse, etc.
sub check_flood($self, $channel, $nick, $user, $host, $text, $max_messages, $max_time, $mode, $context = undef) {
    $channel = lc $channel;

    my $mask    = "$nick!$user\@$host";
    my $oldnick = $nick;
    my $account;

    # handle old-style pseudo-QUIT for changing-host if CHGHOST is not available
    if ($mode == MSG_JOIN and exists $self->{changinghost}->{$nick}) {
        $self->{pbot}->{logger}->log("Finalizing host change for $nick.\n");

        $account = delete $self->{changinghost}->{$nick};

        my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_id($mask);

        if (defined $id) {
            if ($id != $account) {
                $self->{pbot}->{logger}->log("Linking $mask [$id] to account $account\n");
                $self->{pbot}->{messagehistory}->{database}->link_alias($account, $id, LINK_STRONG, 1);
            } else {
                $self->{pbot}->{logger}->log("New hostmask already belongs to original account.\n");
            }
            $account = $id;
        } else {
            $self->{pbot}->{logger}->log("Adding $mask to account $account\n");
            $self->{pbot}->{messagehistory}->{database}->add_message_account($mask, $account, LINK_STRONG);
        }

        $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($account);
    } else {
        $account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);
    }

    $self->{pbot}->{messagehistory}->{database}->update_hostmask_data($mask, {last_seen => scalar gettimeofday});

    if ($mode == MSG_NICKCHANGE) {
        my ($newnick) = $text =~ m/NICKCHANGE (.*)/;

        $self->{pbot}->{logger}->log("[NICKCHANGE] ($account) $mask changed nick to $newnick\n");

        $mask    = "$newnick!$user\@$host";
        $account = $self->{pbot}->{messagehistory}->get_message_account($newnick, $user, $host);
        $nick    = $newnick;
        $self->{pbot}->{messagehistory}->{database}->update_hostmask_data($mask, {last_seen => scalar gettimeofday});
    } else {
        if ($mode == MSG_CHAT) {
            $self->{pbot}->{logger}->log("[MSG] $channel ($account) $mask => $text\n");
        } else {
            my $from = $channel eq lc $mask ? undef : $channel;
            $text =~ s/^(\w+) //;
            my $type = $1;
            $self->{pbot}->{logger}->log("[$type] " . (defined $from ? "$from " : '') . "($account) $mask => $text\n");
        }
    }

    # do not do flood processing for bot messages
    if ($nick eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
        $self->{channels}->{$channel}->{last_spoken_nick} = $nick;
        return;
    }

    # don't do flood processing for unidentified or banned users in +z channels
    return if defined $context and $context->{'chan-z'} and ($context->{'unidentified'} or $context->{'banned'});

    my $ancestor = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);
    $self->{pbot}->{logger}->log("Processing anti-flood account $account " . ($ancestor != $account ? "[ancestor $ancestor] " : '') . "for mask $mask\n")
      if $self->{pbot}->{registry}->get_value('antiflood', 'debug_account');

    if ($mode == MSG_NICKCHANGE) {
        $self->{nickflood}->{$ancestor}->{changes}++;
        $self->{pbot}->{logger}->log("account $ancestor has $self->{nickflood}->{$ancestor}->{changes} nickchanges\n");
    }

    # handle QUIT events
    # (these events come from $channel nick!user@host, not a specific channel or nick,
    # so they need to be dispatched to all channels the nick has been seen on)
    if ($mode == MSG_DEPARTURE and $text =~ /^QUIT/) {
        my $channels = $self->{pbot}->{nicklist}->get_channels($nick);

        foreach my $chan (@$channels) {
            next if $chan !~ m/^#/;
            $self->update_join_watch($account, $chan, $text, $mode);
        }

        $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($account);

        if ($text eq 'QUIT Changing host') {
            $self->{changinghost}->{$nick} = $account;
        }

        # don't do flood processing for QUIT events
        return;
    }

    my $needs_checkban = 0;

    if (defined $context && defined $context->{tags}) {
        my $tags = $self->{pbot}->{irc}->get_tags($context->{tags});

        if (defined $tags->{account}) {
            my $nickserv_account = $tags->{account};
            my $current_nickserv_account = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($account);

            if ($self->{pbot}->{registry}->get_value('irc', 'debug_tags')) {
                $self->{pbot}->{logger}->log("($account) $mask got account-tag $nickserv_account\n");
            }

            if ($current_nickserv_account ne $nickserv_account) {
                $self->{pbot}->{logger}->log("[MH] ($account) $mask updating NickServ to $nickserv_account\n");
                $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($account, $nickserv_account);
                $self->{pbot}->{messagehistory}->{database}->update_nickserv_account($account, $nickserv_account, scalar gettimeofday);
                $self->{pbot}->{messagehistory}->{database}->link_aliases($account, $mask, $nickserv_account);
                $needs_checkban = 1;
            }
        }
    }

    my $channels;
    if ($mode == MSG_NICKCHANGE) {
        $channels = $self->{pbot}->{nicklist}->get_channels($nick);
    } else {
        $self->update_join_watch($account, $channel, $text, $mode);
        push @$channels, $channel;
    }

    foreach my $chan (@$channels) {
        $chan = lc $chan;
        # do not do flood processing if channel is not in bot's channel list or bot is not set as chanop for the channel
        next if $chan =~ /^#/ and not $self->{pbot}->{chanops}->can_gain_ops($chan);
        my $u = $self->{pbot}->{users}->loggedin($chan, "$nick!$user\@$host");

        if ($chan =~ /^#/ and $mode == MSG_DEPARTURE) {
            # remove validation on PART or KICK so we check for ban-evasion when user returns at a later time
            my $chan_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $chan, 'validated');
            if ($chan_data->{validated} & NICKSERV_VALIDATED) {
                $chan_data->{validated} &= ~NICKSERV_VALIDATED;
                $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $chan, $chan_data);
            }
            next;
        }

        next if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

        $self->check_bans($account, $mask, $chan) if $needs_checkban;

        if ($max_messages > $self->{pbot}->{registry}->get_value('messagehistory', 'max_messages')) {
            $self->{pbot}->{logger}->log("Warning: max_messages greater than max_messages limit; truncating.\n");
            $max_messages = $self->{pbot}->{registry}->get_value('messagehistory', 'max_messages');
        }

        # check for ban evasion if channel begins with # (not private message) and hasn't yet been validated against ban evasion
        if ($chan =~ m/^#/) {
            my $validated = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $chan, 'validated')->{'validated'};

            if ($validated & NEEDS_CHECKBAN or not $validated & NICKSERV_VALIDATED) {
                if ($mode == MSG_DEPARTURE) {
                    # don't check for evasion on PART/KICK
                } elsif ($mode == MSG_NICKCHANGE) {
                    if (not exists $self->{whois_pending}->{$nick}) {
                        $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($account, '');
                        $self->{pbot}->{conn}->whois($nick);
                        $self->{whois_pending}->{$nick} = gettimeofday;
                    }
                } else {
                    if ($mode == MSG_JOIN && exists $self->{pbot}->{irc_capabilities}->{'extended-join'}) {
                        # don't WHOIS joins if extended-join capability is active
                    } elsif (not exists $self->{pbot}->{irc_capabilities}->{'account-notify'}) {
                        if (not exists $self->{whois_pending}->{$nick}) {
                            $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($account, '');
                            $self->{pbot}->{conn}->whois($nick);
                            $self->{whois_pending}->{$nick} = gettimeofday;
                        }
                    } else {
                        $self->check_bans($account, "$nick!$user\@$host", $chan);
                    }
                }
            }
        }

        # do not do flood enforcement for this event if bot is lagging
        if ($self->{pbot}->{lagchecker}->lagging) {
            $self->{pbot}->{logger}->log("Disregarding enforcement of anti-flood due to lag: " . $self->{pbot}->{lagchecker}->lagstring . "\n");
            $self->{channels}->{$chan}->{last_spoken_nick} = $nick;
            return;
        }

        # do not do flood enforcement for whitelisted users
        if ($self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted')) {
            $self->{channels}->{$chan}->{last_spoken_nick} = $nick;
            next;
        }

        # do not do flood enforcement for channels that do not want it
        if ($self->{pbot}->{registry}->get_value($chan, 'dont_enforce_antiflood')) {
            $self->{channels}->{$chan}->{last_spoken_nick} = $nick;
            next;
        }

        # check for chat/join/private message flooding
        if (    $max_messages > 0
            and $self->{pbot}->{messagehistory}->{database}->get_max_messages($account, $chan, $mode == MSG_NICKCHANGE ? $nick : undef) >=
            $max_messages)
        {
            my $msg;
            if ($mode == MSG_CHAT) {
                $msg = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($account, $chan, $max_messages - 1);
            } elsif ($mode == MSG_JOIN) {
                my $joins = $self->{pbot}->{messagehistory}->{database}->get_recent_messages($account, $chan, $max_messages, MSG_JOIN);
                $msg = $joins->[0];
            } elsif ($mode == MSG_NICKCHANGE) {
                my $nickchanges =
                  $self->{pbot}->{messagehistory}->{database}->get_recent_messages($ancestor, $chan, $max_messages, MSG_NICKCHANGE, $nick);
                $msg = $nickchanges->[0];
            } elsif ($mode == MSG_DEPARTURE) {
                # no flood checks to be done for departure events
                next;
            } else {
                $self->{pbot}->{logger}->log("Unknown flood mode [$mode] ... aborting flood enforcement.\n");
                return;
            }

            my $last;
            if ($mode == MSG_NICKCHANGE) {
                $last = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($ancestor, $chan, 0, undef, $nick);
            } else {
                $last = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($account, $chan, 0);
            }

            if ($last->{timestamp} - $msg->{timestamp} <= $max_time) {
                if ($mode == MSG_JOIN) {
                    my $chan_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $chan, 'offenses', 'last_offense', 'join_watch');

                    $self->{pbot}->{logger}->log("$account offenses $chan_data->{offenses}, join watch $chan_data->{join_watch}, max messages $max_messages\n");
                    if ($chan_data->{join_watch} >= $max_messages) {
                        $chan_data->{offenses}++;
                        $chan_data->{last_offense} = gettimeofday;

                        if ($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
                            my $timeout  = $self->{pbot}->{registry}->get_array_value('antiflood', 'join_flood_punishment', $chan_data->{offenses} - 1);
                            my $duration = duration($timeout);
                            my $banmask  = $self->address_to_mask($host);

                            my $join_flood_channel = $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_channel') // '#stop-join-flood';

                            if ($self->{pbot}->{channels}->is_active_op("${channel}-floodbans")) {
                                $self->{pbot}->{banlist}->ban_user_timed(
                                    $chan . '-floodbans',
                                    'b',
                                    "*!$user\@$banmask\$$join_flood_channel",
                                    $timeout,
                                    $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                                    'join flooding',
                                );

                                $self->{pbot}->{logger}->log("$nick!$user\@$banmask banned for $duration due to join flooding (offense #" . $chan_data->{offenses} . ").\n");
                                $self->{pbot}->{conn}->privmsg(
                                    $nick,
                                    "You have been banned from $chan due to join flooding.  If your connection issues have been fixed, or this was an accident, you may request an unban at any time by responding to this message with `unbanme`, otherwise you will be automatically unbanned in $duration."
                                );
                            } else {
                                $self->{pbot}->{logger}->log("[anti-flood] I am not an op for ${channel}-floodbans, disregarding join-flood.\n");
                            }
                        }
                        $chan_data->{join_watch} = $max_messages - 2;    # give them a chance to rejoin
                        $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $chan, $chan_data);
                    }
                } elsif ($mode == MSG_CHAT) {
                    if ($chan =~ /^#/) {                                #channel flood (opposed to private message or otherwise)
                        # don't increment offenses again if already banned
                        if ($self->{pbot}->{banlist}->has_ban_timeout($chan, "*!$user\@" . $self->address_to_mask($host))) {
                            $self->{pbot}->{logger}->log("$nick $chan flood offense disregarded due to existing ban\n");
                            next;
                        }

                        my $chan_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $chan, 'offenses', 'last_offense');
                        $chan_data->{offenses}++;
                        $chan_data->{last_offense} = gettimeofday;
                        $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $chan, $chan_data);

                        if ($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
                            my $length = $self->{pbot}->{registry}->get_array_value('antiflood', 'chat_flood_punishment', $chan_data->{offenses} - 1);

                            if ($self->{pbot}->{nicklist}->get_meta($chan, $nick, '+o')) {
                                $self->{pbot}->{logger}->log("Disregarding flood enforcement for opped user $nick in $chan.\n");
                                next;
                            }

                            if ($self->{pbot}->{nicklist}->get_meta($chan, $nick, '+v')) {
                                $self->{pbot}->{chanops}->add_op_command($chan, "mode $chan -v $nick");
                                $self->{pbot}->{chanops}->gain_ops($chan);
                            }

                            $self->{pbot}->{banlist}->ban_user_timed(
                                $chan,
                                'b',
                                "*!$user\@" . $self->address_to_mask($host),
                                $length,
                                $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                                'chat flooding',
                            );

                            $length = duration($length);
                            $self->{pbot}->{logger}->log("$nick $chan flood offense " . $chan_data->{offenses} . " earned $length ban\n");
                            $self->{pbot}->{conn}->privmsg(
                                $nick,
                                "You have been muted due to flooding.  Please use a web paste service such as http://codepad.org for lengthy pastes.  You will be allowed to speak again in approximately $length."
                            );
                        }
                        $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $chan, $chan_data);
                    } else {    # private message flood
                        my $hostmask = $self->address_to_mask($host);
                        next if $self->{pbot}->{ignorelist}->{storage}->exists($chan, "*!$user\@$hostmask");

                        my $chan_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $chan, 'offenses', 'last_offense');
                        $chan_data->{offenses}++;
                        $chan_data->{last_offense} = gettimeofday;
                        $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $chan, $chan_data);

                        my $length = $self->{pbot}->{registry}->get_array_value('antiflood', 'chat_flood_punishment', $chan_data->{offenses} - 1);

                        my $owner = $self->{pbot}->{registry}->get_value('irc', 'botnick');
                        $self->{pbot}->{ignorelist}->add($chan, "*!$user\@$hostmask", $length, $owner);
                        $length = duration($length);
                        $self->{pbot}->{logger}->log("$nick msg flood offense " . $chan_data->{offenses} . " earned $length ignore\n");
                        $self->{pbot}->{conn}->privmsg($nick, "You have used too many commands in too short a time period, you have been ignored for $length.");
                    }
                    next;
                } elsif ($mode == MSG_NICKCHANGE and $self->{nickflood}->{$ancestor}->{changes} >= $max_messages) {
                    next if $chan !~ /^#/;
                    ($nick) = $text =~ m/NICKCHANGE (.*)/;

                    $self->{nickflood}->{$ancestor}->{offenses}++;
                    $self->{nickflood}->{$ancestor}->{changes}   = $max_messages - 2;    # allow 1 more change (to go back to original nick)
                    $self->{nickflood}->{$ancestor}->{timestamp} = gettimeofday;

                    if ($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
                        my $length = $self->{pbot}->{registry}->get_array_value('antiflood', 'nick_flood_punishment', $self->{nickflood}->{$ancestor}->{offenses} - 1);

                        if ($self->{pbot}->{nicklist}->get_meta($chan, $nick, '+o')) {
                            $self->{pbot}->{logger}->log("Disregarding flood enforcement for opped user $nick in $chan.\n");
                            next;
                        }

                        if ($self->{pbot}->{nicklist}->get_meta($chan, $nick, '+v')) {
                            $self->{pbot}->{chanops}->add_op_command($chan, "mode $chan -v $nick");
                            $self->{pbot}->{chanops}->gain_ops($chan);
                        }

                        $self->{pbot}->{banlist}->ban_user_timed(
                            $chan,
                            'b',
                            "*!$user\@" . $self->address_to_mask($host),
                            $length,
                            $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                            'nick flooding',
                        );

                        $length = duration($length);
                        $self->{pbot}->{logger}->log("$nick nickchange flood offense " . $self->{nickflood}->{$ancestor}->{offenses} . " earned $length ban\n");
                        $self->{pbot}->{conn}->privmsg($nick, "You have been temporarily banned due to nick-change flooding.  You will be unbanned in $length.");
                    }
                }
            }
        }

        # check for enter abuse
        if ($mode == MSG_CHAT and $chan =~ m/^#/) {
            my $chan_data         = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $chan, 'enter_abuse', 'enter_abuses', 'offenses');
            my $other_offenses    = delete $chan_data->{offenses};
            my $debug_enter_abuse = $self->{pbot}->{registry}->get_value('antiflood', 'debug_enter_abuse');

            if (defined $self->{channels}->{$chan}->{last_spoken_nick} and $nick eq $self->{channels}->{$chan}->{last_spoken_nick}) {
                my $messages = $self->{pbot}->{messagehistory}->{database}->get_recent_messages($account, $chan, 2, MSG_CHAT);

                my $enter_abuse_threshold      = $self->{pbot}->{registry}->get_value($chan, 'enter_abuse_threshold');
                my $enter_abuse_time_threshold = $self->{pbot}->{registry}->get_value($chan, 'enter_abuse_time_threshold');
                my $enter_abuse_max_offenses   = $self->{pbot}->{registry}->get_value($chan, 'enter_abuse_max_offenses');

                $enter_abuse_threshold      = $self->{pbot}->{registry}->get_value('antiflood', 'enter_abuse_threshold')      if not defined $enter_abuse_threshold;
                $enter_abuse_time_threshold = $self->{pbot}->{registry}->get_value('antiflood', 'enter_abuse_time_threshold') if not defined $enter_abuse_time_threshold;
                $enter_abuse_max_offenses   = $self->{pbot}->{registry}->get_value('antiflood', 'enter_abuse_max_offenses')   if not defined $enter_abuse_max_offenses;

                if ($messages->[1]->{timestamp} - $messages->[0]->{timestamp} <= $enter_abuse_time_threshold) {
                    if (++$chan_data->{enter_abuse} >= $enter_abuse_threshold - 1) {
                        $chan_data->{enter_abuse} = $enter_abuse_threshold / 2 - 1;
                        $chan_data->{enter_abuses}++;
                        if ($chan_data->{enter_abuses} >= $enter_abuse_max_offenses) {
                            if ($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
                                if ($self->{pbot}->{nicklist}->get_meta($chan, $nick, '+o')) {
                                    $self->{pbot}->{logger}->log("Disregarding flood enforcement for opped user $nick in $chan.\n");
                                    next;
                                }

                                if ($self->{pbot}->{nicklist}->get_meta($chan, $nick, '+v')) {
                                    $self->{pbot}->{chanops}->add_op_command($chan, "mode $chan -v $nick");
                                    $self->{pbot}->{chanops}->gain_ops($chan);
                                }

                                if ($self->{pbot}->{banlist}->has_ban_timeout($chan, "*!$user\@" . $self->address_to_mask($host))) {
                                    $self->{pbot}->{logger}->log("$nick $chan enter abuse offense disregarded due to existing ban\n");
                                    next;
                                }

                                my $offenses   = $chan_data->{enter_abuses} - $enter_abuse_max_offenses + 1 + $other_offenses;
                                my $ban_length = $self->{pbot}->{registry}->get_array_value('antiflood', 'enter_abuse_punishment', $offenses - 1);

                                $self->{pbot}->{banlist}->ban_user_timed(
                                    $chan,
                                    'b',
                                    "*!$user\@" . $self->address_to_mask($host),
                                    $ban_length,
                                    $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                                    'enter abuse',
                                );

                                $ban_length = duration($ban_length);
                                $self->{pbot}->{logger}->log("$nick $chan enter abuse offense " . $chan_data->{enter_abuses} . " earned $ban_length ban\n");

                                $self->{pbot}->{conn}->privmsg(
                                    $nick,
                                    "You have been muted due to abusing the enter key.  Please do not split your sentences over multiple messages.  You will be allowed to speak again in approximately $ban_length."
                                );

                                $chan_data->{last_offense} = gettimeofday;
                                $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $chan, $chan_data);
                                next;
                            }
                        } else {
                            $self->{pbot}->{logger}->log("$nick $chan enter abuses counter incremented to " . $chan_data->{enter_abuses} . "\n") if $debug_enter_abuse;
                            if ($chan_data->{enter_abuses} == $enter_abuse_max_offenses - 1 && $chan_data->{enter_abuse} == $enter_abuse_threshold / 2 - 1) {
                                if ($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
                                    $self->{pbot}->{conn}->privmsg(
                                        $chan,
                                        "$nick: Please stop abusing the enter key. Feel free to type longer messages and to take a moment to think of anything else to say before you hit that enter key."
                                    );
                                }
                            }
                        }
                    } else {
                        $self->{pbot}->{logger}->log("$nick $chan enter abuse counter incremented to " . $chan_data->{enter_abuse} . "\n") if $debug_enter_abuse;
                    }
                    $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $chan, $chan_data);
                } else {
                    if ($chan_data->{enter_abuse} > 0) {
                        $self->{pbot}->{logger}->log("$nick $chan more than $enter_abuse_time_threshold seconds since last message, enter abuse counter reset\n") if $debug_enter_abuse;
                        $chan_data->{enter_abuse} = 0;
                        $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $chan, $chan_data);
                    }
                }
            } else {
                $self->{channels}->{$chan}->{last_spoken_nick} = $nick;
                $self->{pbot}->{logger}->log("last spoken nick set to $nick\n") if $debug_enter_abuse;
                if ($chan_data->{enter_abuse} > 0) {
                    $self->{pbot}->{logger}->log("$nick $chan enter abuse counter reset\n") if $debug_enter_abuse;
                    $chan_data->{enter_abuse} = 0;
                    $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $chan, $chan_data);
                }
            }
        }
    }

    $self->{channels}->{$channel}->{last_spoken_nick} = $nick if $mode == MSG_CHAT;
}

sub address_to_mask($self, $address) {
    my $banmask;

    if ($address =~ m/^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/) {
        my ($a, $b, $c, $d) = ($1, $2, $3, $4);
        given ($a) {
            when ($_ <= 127) { $banmask = "$a.*"; }
            when ($_ <= 191) { $banmask = "$a.$b.*"; }
            default          { $banmask = "$a.$b.$c.*"; }
        }
    } elsif ($address =~ m{^gateway/([^/]+)/([^/]+)/}) {
        $banmask = "gateway/$1/$2/*";
    } elsif ($address =~ m{^nat/([^/]+)/}) {
        $banmask = "nat/$1/*";
    } elsif ($address =~ m/^([^:]+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)$/) {
        $banmask = "$1:$2:*";
    } elsif ($address =~ m/[^.]+\.([^.]+\.[a-zA-Z]+)$/) {
        $banmask = "*.$1";
    } else {
        $banmask = $address;
    }

    return $banmask;
}

# remove validation on accounts in $channel that match a ban/quiet $mask
sub devalidate_accounts($self, $mask, $channel) {
    my @message_accounts;

    #$self->{pbot}->{logger}->log("Devalidating accounts for $mask in $channel\n");

    if ($mask =~ m/^\$a:(.*)/) {
        my $ban_account = lc $1;
        @message_accounts = $self->{pbot}->{messagehistory}->{database}->find_message_accounts_by_nickserv($ban_account);
    } else {
        @message_accounts = $self->{pbot}->{messagehistory}->{database}->find_message_accounts_by_mask($mask);
    }

    foreach my $account (@message_accounts) {
        my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'validated');
        if (defined $channel_data and $channel_data->{validated} & NICKSERV_VALIDATED) {
            $channel_data->{validated} &= ~NICKSERV_VALIDATED;

            #$self->{pbot}->{logger}->log("Devalidating account $account\n");
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
        }
    }
}

sub check_bans($self, $message_account, $mask, $channel, $dry_run = 0) {
    $channel = lc $channel;

    return if not $self->{pbot}->{chanops}->can_gain_ops($channel);
    my $user = $self->{pbot}->{users}->loggedin($channel, $mask);
    return if $self->{pbot}->{capabilities}->userhas($user, 'botowner');

    my $debug_checkban = $self->{pbot}->{registry}->get_value('antiflood', 'debug_checkban');

    my $current_nickserv_account = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($message_account);

    $self->{pbot}->{logger}->log("anti-flood: [check-bans] checking for bans on ($message_account) $mask "
          . (defined $current_nickserv_account and length $current_nickserv_account ? "[$current_nickserv_account] " : "")
          . "in $channel\n");

    my ($do_not_validate, $bans);

    if (defined $current_nickserv_account and length $current_nickserv_account) {
        $self->{pbot}->{logger}->log("anti-flood: [check-bans] current nickserv [$current_nickserv_account] found for $mask\n") if $debug_checkban >= 2;
        my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
        if ($channel_data->{validated} & NEEDS_CHECKBAN) {
            $channel_data->{validated} &= ~NEEDS_CHECKBAN;
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
        }
    } else {
        if (not exists $self->{pbot}->{irc_capabilities}->{'account-notify'}) {
            # mark this account as needing check-bans when nickserv account is identified
            my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
            if (not $channel_data->{validated} & NEEDS_CHECKBAN) {
                $channel_data->{validated} |= NEEDS_CHECKBAN;
                $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
            }
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] no account for $mask; marking for later validation\n") if $debug_checkban >= 1;
        } else {
            $do_not_validate = 1;
        }
    }

    my ($nick) = $mask =~ m/^([^!]+)/;
    my %aliases = $self->{pbot}->{messagehistory}->{database}->get_also_known_as($nick);

    my $csv = Text::CSV->new({binary => 1});

    foreach my $alias (keys %aliases) {
        next if $alias =~ /^Guest\d+(?:!.*)?$/;

        $self->{pbot}->{logger}->log("[after aka] processing $alias\n") if $debug_checkban >= 1;

        if ($aliases{$alias}->{type} == LINK_WEAK) {
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] skipping WEAK alias $alias in channel $channel\n") if $debug_checkban >= 2;
            next;
        }

        my @nickservs;

        if (exists $aliases{$alias}->{nickserv}) { @nickservs = split /,/, $aliases{$alias}->{nickserv}; }
        else                                     { @nickservs = (undef); }

        foreach my $nickserv (@nickservs) {
            my @gecoses;
            if (exists $aliases{$alias}->{gecos}) {
                $csv->parse($aliases{$alias}->{gecos});
                @gecoses = $csv->fields;
            } else {
                @gecoses = (undef);
            }

            foreach my $gecos (@gecoses) {
                my $tgecos    = defined $gecos    ? $gecos    : "[undefined]";
                my $tnickserv = defined $nickserv ? $nickserv : "[undefined]";
                $self->{pbot}->{logger}->log("anti-flood: [check-bans] checking blacklist for $alias in channel $channel using gecos '$tgecos' and nickserv '$tnickserv'\n")
                  if $debug_checkban >= 5;
                if ($self->{pbot}->{blacklist}->is_blacklisted($alias, $channel, $nickserv, $gecos)) {
                    my $u = $self->{pbot}->{users}->loggedin($channel, $mask);
                    if ($self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted')) {
                        $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask [$alias] blacklisted in $channel, but allowed through whitelist\n");
                        next;
                    }

                    my $baninfo = {};
                    $baninfo->{mask} = $alias;
                    $baninfo->{channel} = $channel;
                    $baninfo->{owner}   = 'blacklist';
                    $baninfo->{when}    = 0;
                    $baninfo->{type}    = 'blacklist';
                    push @$bans, $baninfo;
                    next;
                }
            }

            $self->{pbot}->{logger}->log("anti-flood: [check-bans] checking for bans in $channel on $alias using nickserv " . (defined $nickserv ? $nickserv : "[undefined]") . "\n")
              if $debug_checkban >= 2;
            my $baninfos = $self->{pbot}->{banlist}->get_baninfo($channel, $alias, $nickserv);

            if (defined $baninfos) {
                foreach my $baninfo (@$baninfos) {
                    if (time - $baninfo->{when} < 5) {
                        $self->{pbot}->{logger}
                          ->log("anti-flood: [check-bans] $mask [$alias] evaded $baninfo->{mask} in $baninfo->{channel}, but within 5 seconds of establishing ban; giving another chance\n");
                        my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
                        if ($channel_data->{validated} & NICKSERV_VALIDATED) {
                            $channel_data->{validated} &= ~NICKSERV_VALIDATED;
                            $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
                        }
                        $do_not_validate = 1;
                        next;
                    }

                    my $u           = $self->{pbot}->{users}->loggedin($baninfo->{channel}, $mask);
                    my $whitelisted = $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

                    if ($self->{pbot}->{banlist}->is_ban_exempted($baninfo->{channel}, $baninfo->{mask}) || $whitelisted) {
                        #$self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask [$alias] evaded $baninfo->{mask} in $baninfo->{channel}, but allowed through whitelist\n");
                        next;
                    }

                    # special case for twkm clone bans
                    if ($baninfo->{mask} =~ m/\?\*!\*@\*$/) {
                        $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask [$alias] evaded $baninfo->{mask} in $baninfo->{channel}, but disregarded due to clone ban\n");
                        next;
                    }

                    my $banmask_regex = quotemeta $baninfo->{mask};
                    $banmask_regex =~ s/\\\*/.*/g;
                    $banmask_regex =~ s/\\\?/./g;

                    if ($mask =~ /^$banmask_regex$/i) {
                        $self->{pbot}->{logger}->log("anti-flood: [check-bans] Hostmask ($mask) matches $baninfo->{type} banmask ($banmask_regex), disregarding\n");
                        next;
                    }

                    if (defined $nickserv and $baninfo->{type} eq 'q' and $baninfo->{mask} =~ /^\$a:(.*)/ and lc $1 eq $nickserv and $nickserv eq $current_nickserv_account) {
                        $self->{pbot}->{logger}->log("anti-flood: [check-bans] Hostmask ($mask) matches quiet on account ($nickserv), disregarding\n");
                        next;
                    }

                    if (not defined $bans) { $bans = []; }

                    $self->{pbot}->{logger}
                      ->log("anti-flood: [check-bans] Hostmask ($mask [$alias" . (defined $nickserv ? "/$nickserv" : "") . "]) matches $baninfo->{type} $baninfo->{mask}, adding ban\n");
                    push @$bans, $baninfo;
                    goto GOT_BAN;
                }
            }
        }
    }

  GOT_BAN:
    if (defined $bans) {
        foreach my $baninfo (@$bans) {
            my $banmask;

            my ($user, $host) = $mask =~ m/[^!]+!([^@]+)@(.*)/;
            if ($host =~ m{^([^/]+)/.+} and $1 ne 'gateway' and $1 ne 'nat') { $banmask = "*!*\@$host"; }
            elsif ( $current_nickserv_account
                and $baninfo->{mask} !~ m/^\$a:/i
                and not $self->{pbot}->{banlist}->{banlist}->exists($baninfo->{channel}, "\$a:$current_nickserv_account"))
            {
                $banmask = "\$a:$current_nickserv_account";
            } else {
                if    ($host =~ m{\.irccloud.com$}) { $banmask = "*!$user\@*.irccloud.com"; }
                elsif ($host =~ m{^nat/([^/]+)/})              { $banmask = "*!$user\@nat/$1/*"; }
                else {
                    $banmask = "*!*\@$host";
                    #$banmask = "*!$user@" . $self->address_to_mask($host);
                }
            }

            $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask evaded $baninfo->{mask} banned in $baninfo->{channel} by $baninfo->{owner}, banning $banmask\n");
            my ($bannick) = $mask =~ m/^([^!]+)/;
            if ($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
                if ($self->{pbot}->{banlist}->has_ban_timeout($baninfo->{channel}, $banmask)) {
                    $self->{pbot}->{logger}->log("anti-flood: [check-bans] $banmask already banned in $channel, disregarding\n");
                    return;
                }

                my $ancestor = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($message_account);
                if (exists $self->{nickflood}->{$ancestor} and $self->{nickflood}->{$ancestor}->{offenses} > 0 and $baninfo->{type} ne 'blacklist') {
                    if (gettimeofday - $self->{nickflood}->{$ancestor}->{timestamp} < 60 * 15) {
                        $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask evading nick-flood ban, disregarding\n");
                        return;
                    }
                }

                if (defined $dry_run && $dry_run != 0) {
                    $self->{pbot}->{logger}->log("Skipping ban due to dry-run.\n");
                    return;
                }

                if ($baninfo->{type} eq 'blacklist') {
                    $self->{pbot}->{chanops}->add_op_command($baninfo->{channel}, "kick $baninfo->{channel} $bannick I don't think so");
                } else {
                    my $owner = $baninfo->{owner};
                    $owner =~ s/!.*$//;
                    $self->{pbot}->{chanops}->add_op_command($baninfo->{channel}, "kick $baninfo->{channel} $bannick Evaded $baninfo->{mask} set by $owner");
                }

                $self->{pbot}->{banlist}->ban_user_timed(
                    $baninfo->{channel},
                    'b',
                    $banmask,
                    60 * 60 * 24 * 14,
                    $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                    $baninfo->{type} eq 'blacklist' ? 'blacklisted' : 'ban evasion',
                );
            }
            my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
            if ($channel_data->{validated} & NICKSERV_VALIDATED) {
                $channel_data->{validated} &= ~NICKSERV_VALIDATED;
                $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
            }
            return;
        }
    }

    unless ($do_not_validate) {
        my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
        if (not $channel_data->{validated} & NICKSERV_VALIDATED) {
            $channel_data->{validated} |= NICKSERV_VALIDATED;
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
        }
    }
}

sub on_endofwhois($self, $event_type, $event) {
    my $nick = $event->{args}[1];

    delete $self->{whois_pending}->{$nick};

    my ($id, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick);

    # $self->{pbot}->{logger}->log("endofwhois: Found [$id][$hostmask] for [$nick]\n");
    $self->{pbot}->{messagehistory}->{database}->link_aliases($id, $hostmask) if $id;

    # check to see if any channels need check-ban validation
    my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
    foreach my $channel (@$channels) {
        next unless $channel =~ /^#/;
        my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($id, $channel, 'validated');
        if ($channel_data->{validated} & NEEDS_CHECKBAN or not $channel_data->{validated} & NICKSERV_VALIDATED) {
            $self->check_bans($id, $hostmask, $channel);
        }
    }

    return 0;
}

sub on_whoisuser($self, $event_type, $event) {
    my $nick  = $event->{args}[1];
    my $gecos = lc $event->{args}[5];

    my ($id) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick);

    if ($self->{pbot}->{registry}->get_value('antiflood', 'debug_checkban') >= 2) { $self->{pbot}->{logger}->log("Got gecos for $nick ($id): '$gecos'\n"); }

    $self->{pbot}->{messagehistory}->{database}->update_gecos($id, $gecos, scalar gettimeofday);
}

sub on_whoisaccount($self, $event_type, $event) {
    my $nick    = $event->{args}[1];
    my $account = lc $event->{args}[2];

    $self->{pbot}->{logger}->log("[MH] $nick is using NickServ account [$account]\n");

    my ($id, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick);

    if ($id) {
        $self->{pbot}->{messagehistory}->{database}->link_aliases($id, undef, $account);
        $self->{pbot}->{messagehistory}->{database}->update_nickserv_account($id, $account, scalar gettimeofday);
        $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($id, $account);
    } else {
        $self->{pbot}->{logger}->log("[MH] No message account found for $nick [$account]; cannot update database.\n");
    }

    return 0;
}

sub on_accountnotify($self, $event_type, $event) {
    my $mask = $event->{from};
    my ($nick, $user, $host) = $mask =~ m/^([^!]+)!([^@]+)@(.*)/;
    my $account = $event->{args}[0];
    my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

    $self->{pbot}->{messagehistory}->{database}->update_hostmask_data($mask, {last_seen => scalar gettimeofday});

    if ($account eq '*') {
        $self->{pbot}->{logger}->log("[MH] ($id) $mask logged out of NickServ\n");
        $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($id, '');
    } else {
        $self->{pbot}->{logger}->log("[MH] ($id) $mask logged into NickServ account $account\n");

        $self->{pbot}->{messagehistory}->{database}->link_aliases($id, undef, $account);
        $self->{pbot}->{messagehistory}->{database}->update_nickserv_account($id, $account, scalar gettimeofday);
        $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($id, $account);

        $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($id);

        my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
        foreach my $channel (@$channels) {
            next unless $channel =~ /^#/;
            $self->check_bans($id, $mask, $channel);
        }
    }

    return 0;
}

sub adjust_offenses($self) {
    # decrease offenses counter if 24 hours have elapsed since latest offense
    my $channel_datas = $self->{pbot}->{messagehistory}->{database}->get_channel_datas_where_last_offense_older_than(gettimeofday - 60 * 60 * 24);
    foreach my $channel_data (@$channel_datas) {
        my $id      = delete $channel_data->{id};
        my $channel = delete $channel_data->{channel};
        my $update  = 0;

        if ($channel_data->{offenses} > 0) {
            $channel_data->{offenses}--;
            $update = 1;
        }

        if (defined $channel_data->{unbanmes} and $channel_data->{unbanmes} > 0) {
            $channel_data->{unbanmes}--;
            $update = 1;
        }

        if ($update) {
            $channel_data->{last_offense} = gettimeofday;
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($id, $channel, $channel_data);
        }
    }

    $channel_datas = $self->{pbot}->{messagehistory}->{database}->get_channel_datas_with_enter_abuses();
    foreach my $channel_data (@$channel_datas) {
        my $id           = delete $channel_data->{id};
        my $channel      = delete $channel_data->{channel};
        my $last_offense = delete $channel_data->{last_offense};
        if (gettimeofday - $last_offense >= 60 * 60 * 3) {
            $channel_data->{enter_abuses}--;

            #$self->{pbot}->{logger}->log("[adjust-offenses] [$id][$channel] decreasing enter abuse offenses to $channel_data->{enter_abuses}\n");
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($id, $channel, $channel_data);
        }
    }

    foreach my $account (keys %{$self->{nickflood}}) {
        if ($self->{nickflood}->{$account}->{offenses} and gettimeofday - $self->{nickflood}->{$account}->{timestamp} >= 60 * 60) {
            $self->{nickflood}->{$account}->{offenses}--;

            if ($self->{nickflood}->{$account}->{offenses} <= 0) {
                delete $self->{nickflood}->{$account};
            } else {
                $self->{nickflood}->{$account}->{timestamp} = gettimeofday;
            }
        }
    }
}

1;
