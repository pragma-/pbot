# File: IRCHandlers.pm
#
# Purpose: Subroutines to handle IRC events. Note that various PBot packages
# can in turn register their own IRC event handlers as well. There can be
# multiple handlers for PRIVMSG spread throughout the bot and its plugins,
# for example.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::IRCHandlers;
use parent 'PBot::Class';

use PBot::Imports;

use Time::HiRes qw/time/;
use Data::Dumper;

use MIME::Base64;
use Encode;

sub initialize {
    my ($self, %conf) = @_;

    # convenient alias so the following lines aren't so long
    my $ed = $self->{pbot}->{event_dispatcher};

    # various IRC events (note that other PBot packages and plugins can
    # also register additional IRC event handlers, including handlers for
    # the events listed here. any duplicate events will be chained.)
    $ed->register_handler('irc.welcome',       sub { $self->on_connect       (@_) });
    $ed->register_handler('irc.disconnect',    sub { $self->on_disconnect    (@_) });
    $ed->register_handler('irc.motd',          sub { $self->on_motd          (@_) });
    $ed->register_handler('irc.notice',        sub { $self->on_notice        (@_) });
    $ed->register_handler('irc.public',        sub { $self->on_public        (@_) });
    $ed->register_handler('irc.caction',       sub { $self->on_action        (@_) });
    $ed->register_handler('irc.msg',           sub { $self->on_msg           (@_) });
    $ed->register_handler('irc.mode',          sub { $self->on_mode          (@_) });
    $ed->register_handler('irc.part',          sub { $self->on_departure     (@_) });
    $ed->register_handler('irc.join',          sub { $self->on_join          (@_) });
    $ed->register_handler('irc.kick',          sub { $self->on_kick          (@_) });
    $ed->register_handler('irc.quit',          sub { $self->on_departure     (@_) });
    $ed->register_handler('irc.nick',          sub { $self->on_nickchange    (@_) });
    $ed->register_handler('irc.nicknameinuse', sub { $self->on_nicknameinuse (@_) });
    $ed->register_handler('irc.invite',        sub { $self->on_invite        (@_) });
    $ed->register_handler('irc.isupport',      sub { $self->on_isupport      (@_) });
    $ed->register_handler('irc.channelmodeis', sub { $self->on_channelmodeis (@_) });
    $ed->register_handler('irc.topic',         sub { $self->on_topic         (@_) });
    $ed->register_handler('irc.topicinfo',     sub { $self->on_topicinfo     (@_) });
    $ed->register_handler('irc.channelcreate', sub { $self->on_channelcreate (@_) });
    $ed->register_handler('irc.yourhost',      sub { $self->log_first_arg    (@_) });
    $ed->register_handler('irc.created',       sub { $self->log_first_arg    (@_) });
    $ed->register_handler('irc.luserconns',    sub { $self->log_first_arg    (@_) });
    $ed->register_handler('irc.notregistered', sub { $self->log_first_arg    (@_) });
    $ed->register_handler('irc.n_local',       sub { $self->log_third_arg    (@_) });
    $ed->register_handler('irc.n_global',      sub { $self->log_third_arg    (@_) });
    $ed->register_handler('irc.nononreg',      sub { $self->on_nononreg      (@_) });
    $ed->register_handler('irc.whoreply',      sub { $self->on_whoreply      (@_) });
    $ed->register_handler('irc.whospcrpl',     sub { $self->on_whospcrpl     (@_) });
    $ed->register_handler('irc.endofwho',      sub { $self->on_endofwho      (@_) });

    # IRCv3 client capabilities
    $ed->register_handler('irc.cap', sub { $self->on_cap(@_) });

    # IRCv3 SASL
    $ed->register_handler('irc.authenticate',    sub { $self->on_sasl_authenticate (@_) });
    $ed->register_handler('irc.rpl_loggedin',    sub { $self->on_rpl_loggedin      (@_) });
    $ed->register_handler('irc.rpl_loggedout',   sub { $self->on_rpl_loggedout     (@_) });
    $ed->register_handler('irc.err_nicklocked',  sub { $self->on_err_nicklocked    (@_) });
    $ed->register_handler('irc.rpl_saslsuccess', sub { $self->on_rpl_saslsuccess   (@_) });
    $ed->register_handler('irc.err_saslfail',    sub { $self->on_err_saslfail      (@_) });
    $ed->register_handler('irc.err_sasltoolong', sub { $self->on_err_sasltoolong   (@_) });
    $ed->register_handler('irc.err_saslaborted', sub { $self->on_err_saslaborted   (@_) });
    $ed->register_handler('irc.err_saslalready', sub { $self->on_err_saslalready   (@_) });
    $ed->register_handler('irc.rpl_saslmechs',   sub { $self->on_rpl_saslmechs     (@_) });

    # bot itself joining and parting channels
    $ed->register_handler('pbot.join', sub { $self->on_self_join(@_) });
    $ed->register_handler('pbot.part', sub { $self->on_self_part(@_) });

    # TODO: enqueue these events as needed instead of naively checking every 10 seconds
    $self->{pbot}->{event_queue}->enqueue(sub { $self->check_pending_whos }, 10, 'Check pending WHOs');
}

# default PBot::IRC handler. this handler prepends 'irc.' to the event-type
# and then dispatches the event through PBot::EventDispatcher
sub default_handler {
    my ($self, $conn, $event) = @_;

    my $result = $self->{pbot}->{event_dispatcher}->dispatch_event(
        "irc.$event->{type}",
        {
            conn => $conn,
            event => $event
        }
    );

    if (not defined $result and $self->{pbot}->{registry}->get_value('irc', 'log_default_handler')) {
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log(Dumper $event);
    }
}

sub on_init {
    my ($self, $conn, $event) = @_;
    my (@args) = ($event->args);
    shift @args;
    $self->{pbot}->{logger}->log("*** @args\n");
}

sub on_connect {
    my ($self, $event_type, $event) = @_;

    $self->{pbot}->{logger}->log("Connected!\n");

    if (not $self->{pbot}->{irc_capabilities}->{sasl}) {
        # not using SASL, so identify the old way by /msging NickServ or some such services bot
        if (length $self->{pbot}->{registry}->get_value('irc', 'identify_password')) {
            $self->{pbot}->{logger}->log("Identifying with NickServ . . .\n");

            my $nickserv = $self->{pbot}->{registry}->get_value('general', 'identify_nick')    // 'nickserv';
            my $command  = $self->{pbot}->{registry}->get_value('general', 'identify_command') // 'identify $nick $password';

            my $botnick  = $self->{pbot}->{registry}->get_value('irc', 'botnick');
            my $password = $self->{pbot}->{registry}->get_value('irc', 'identify_password');

            $command =~ s/\$nick\b/$botnick/g;
            $command =~ s/\$password\b/$password/g;

            $event->{conn}->privmsg($nickserv, $command);
        } else {
            # using SASL, we're already identified at this point
            $self->{pbot}->{logger}->log("No identify password; skipping identification to services.\n");
        }

        # auto-join channels unless general.autojoin_wait_for_nickserv is true
        if (not $self->{pbot}->{registry}->get_value('general', 'autojoin_wait_for_nickserv')) {
            $self->{pbot}->{logger}->log("Autojoining channels immediately; to wait for services set general.autojoin_wait_for_nickserv to 1.\n");
            $self->{pbot}->{channels}->autojoin;
        } else {
            $self->{pbot}->{logger}->log("Waiting for services identify response before autojoining channels.\n");
        }
    } else {
        # using SASL; go ahead and auto-join channels now
        $self->{pbot}->{logger}->log("Autojoining channels.\n");
        $self->{pbot}->{channels}->autojoin;
    }

    return 0;
}

sub on_disconnect {
    my ($self, $event_type, $event) = @_;

    $self->{pbot}->{logger}->log("Disconnected...\n");
    $self->{pbot}->{connected} = 0;

    # attempt to reconnect to server
    # TODO: maybe add a registry entry to control whether the bot auto-reconnects
    $self->{pbot}->connect;

    return 0;
}

sub on_motd {
    my ($self, $event_type, $event) = @_;

    if ($self->{pbot}->{registry}->get_value('irc', 'show_motd')) {
        my $from = $event->{event}->{from};
        my $msg  = $event->{event}->{args}->[1];
        $self->{pbot}->{logger}->log("MOTD from $from :: $msg\n");
    }

    return 0;
}

# the bot itself joining a channel
sub on_self_join {
    my ($self, $event_type, $event) = @_;

    # early-return if we don't send WHO on join
    # (we send WHO to see who is in the channel, for ban-evasion enforcement and such)
    return 0 if not $self->{pbot}->{registry}->get_value('general', 'send_who_on_join') // 1;

    # we turn on send_who if the following conditions are met
    my $send_who = 0;

    if ($self->{pbot}->{registry}->get_value('general', 'send_who_chanop_only') // 1) {
        # check if we only send WHO to where we can gain ops
        if ($self->{pbot}->{channels}->get_meta($event->{channel}, 'chanop')) {
            # yup, we can +o in this channel, turn on send_who
            $send_who = 1;
        }
    } else {
        # otherwise just go ahead turn on send_who
        $send_who = 1;
    }

    # schedule the WHO to be sent to this channel
    $self->send_who($event->{channel}) if $send_who;

    return 0;
}

# the bot itself leaving a channel
sub on_self_part {
    my ($self, $event_type, $event) = @_;
    # nothing to do here yet
    return 0;
}

sub on_public {
    my ($self, $event_type, $event) = @_;

    my ($from, $nick, $user, $host, $text) = (
        $event->{event}->{to}->[0],
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->{args}->[0],
    );

    ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

    # send text to be processed for bot commands, anti-flood enforcement, etc
    $event->{interpreted} = $self->{pbot}->{interpreter}->process_line($from, $nick, $user, $host, $text);

    return 0;
}

sub on_msg {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $text) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->{args}->[0],
    );

    ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

    # send text to be processed as a bot command, coming from $nick
    $event->{interpreted} = $self->{pbot}->{interpreter}->process_line($nick, $nick, $user, $host, $text, 1);

    return 0;
}

sub on_notice {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $to, $text)  = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->to,
        $event->{event}->{args}->[0],
    );

    # log notice
    $self->{pbot}->{logger}->log("NOTICE from $nick!$user\@$host to $to: $text\n");

    # notice from NickServ
    if ($nick eq 'NickServ') {
        # if we have enabled NickServ GUARD protection and we're not identified yet,
        # NickServ will warn us to identify -- this is our cue to identify.
        if ($text =~ m/This nickname is registered/) {
            if (length $self->{pbot}->{registry}->get_value('irc', 'identify_password')) {
                $self->{pbot}->{logger}->log("Identifying with NickServ . . .\n");
                $event->{conn}->privmsg("nickserv", "identify " . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));
            }
        }
        elsif ($text =~ m/You are now identified/) {
            # we have identified with NickServ
            if ($self->{pbot}->{registry}->get_value('irc', 'randomize_nick')) {
                # if irc.randomize_nicks was enabled, we go ahead and attempt to
                # change to our real botnick. we don't auto-join channels just yet in case
                # the nick change fails.
                $event->{conn}->nick($self->{pbot}->{registry}->get_value('irc', 'botnick'));
            } else {
                # otherwise go ahead and autojoin channels now
                $self->{pbot}->{channels}->autojoin;
            }
        }
        elsif ($text =~ m/has been ghosted/) {
            # we have ghosted someone using our botnick, let's attempt to regain it now
            $event->{conn}->nick($self->{pbot}->{registry}->get_value('irc', 'botnick'));
        }
    } else {
        # if NOTICE is sent to the bot then replace the `to` field with the
        # sender's nick instead so when we pass it on to on_public ...
        if ($to eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
            $event->{event}->{to}->[0] = $nick;
        }

        # handle this NOTICE as a public message
        # (check for bot commands, anti-flooding, etc)
        $self->on_public($event_type, $event) unless $to eq '*';
    }

    return 0;
}

sub on_action {
    my ($self, $event_type, $event) = @_;

    # prepend "/me " to the message text
    $event->{event}->{args}->[0] = "/me " . $event->{event}->{args}->[0];

    # pass this along to on_public
    $self->on_public($event_type, $event);
    return 0;
}

# FIXME: on_mode doesn't handle chanmodes that have parameters, e.g. +l
sub on_mode {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $mode_string, $channel) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->{args}->[0],
        lc $event->{event}->{to}->[0],
    );

    ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

    my $i = 0;
    my ($mode, $mode_char, $modifier, $target);

    while ($mode_string =~ m/(.)/g) {
        my $char = $1;

        if ($char eq '-' or $char eq '+') {
            $modifier = $char;
            next;
        }

        $mode   = $modifier . $char;
        $target = $event->{event}->{args}->[++$i];

        $self->{pbot}->{logger}->log("Mode $channel [$mode" . (length $target ? " $target" : '') . "] by $nick!$user\@$host\n");

        # TODO: figure out a good way to allow other packages to receive "track_mode" events
        # i.e., perhaps by emitting a modechange event or some such and registering handlers
        $self->{pbot}->{banlist}->track_mode("$nick!$user\@$host", $channel, $mode, $target);
        $self->{pbot}->{chanops}->track_mode("$nick!$user\@$host", $channel, $mode, $target);

        if (defined $target and length $target) {
            # mode set on user
            my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);

            $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "MODE $mode $target", $self->{pbot}->{messagehistory}->{MSG_CHAT});

            # TODO: here as well
            if ($modifier eq '-') {
                $self->{pbot}->{nicklist}->delete_meta($channel, $target, "+$mode_char");
            } else {
                $self->{pbot}->{nicklist}->set_meta($channel, $target, $mode, 1);
            }
        } else {
            # mode set on channel
            my $modes = $self->{pbot}->{channels}->get_meta($channel, 'MODE');

            if (defined $modes) {
                if ($modifier eq '+') {
                    $modes = '+' if not length $modes;
                    $modes .= $mode_char;
                } else {
                    $modes =~ s/\Q$mode_char//g;
                }

                # TODO: here as well
                $self->{pbot}->{channels}->{channels}->set($channel, 'MODE', $modes, 1);
            }
        }
    }

    return 0;
}

sub on_join {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $channel) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        lc $event->{event}->{to}->[0],
    );

    ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

    my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);
    $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "JOIN", $self->{pbot}->{messagehistory}->{MSG_JOIN});

    $self->{pbot}->{messagehistory}->{database}->devalidate_channel($message_account, $channel);

    my $msg = 'JOIN';

    # IRCv3 extended-join capability provides more details about user
    if (exists $self->{pbot}->{irc_capabilities}->{'extended-join'}) {
        my ($nickserv, $gecos) = (
            $event->{event}->{args}->[0],
            $event->{event}->{args}->[1],
        );

        $msg .= " $nickserv :$gecos";

        $self->{pbot}->{messagehistory}->{database}->update_gecos($message_account, $gecos, scalar time);

        if ($nickserv ne '*') {
            $self->{pbot}->{messagehistory}->{database}->link_aliases($message_account, undef, $nickserv);
            $self->{pbot}->{antiflood}->check_nickserv_accounts($nick, $nickserv);
        } else {
            $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($message_account, '');
        }

        $self->{pbot}->{antiflood}->check_bans($message_account, $event->{event}->from, $channel);
    }

    $self->{pbot}->{antiflood}->check_flood(
        $channel, $nick, $user, $host, $msg,
        $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_threshold'),
        $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_time_threshold'),
        $self->{pbot}->{messagehistory}->{MSG_JOIN}
    );

    return 0;
}

sub on_invite {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $target, $channel) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->to,
        lc $event->{event}->{args}->[0]
    );

    ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

    $self->{pbot}->{logger}->log("$nick!$user\@$host invited $target to $channel!\n");

    # if invited to a channel on our channel list, go ahead and join it
    if ($target eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
        if ($self->{pbot}->{channels}->is_active($channel)) {
            $self->{pbot}->{interpreter}->add_botcmd_to_command_queue($channel, "join $channel", 0);
        }
    }

    return 0;
}

sub on_kick {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $target, $channel, $reason) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->to,
        lc $event->{event}->{args}->[0],
        $event->{event}->{args}->[1]
    );

    ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

    $self->{pbot}->{logger}->log("$nick!$user\@$host kicked $target from $channel ($reason)\n");

    # hostmask of the person being kicked
    my $target_hostmask;

    # look up message history account for person being kicked
    my ($message_account) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($target);

    if (defined $message_account) {
        # update target hostmask
        $target_hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($message_account);

        # add "KICKED by" to kicked person's message history
        my $text = "KICKED by $nick!$user\@$host ($reason)";

        $self->{pbot}->{messagehistory}->add_message($message_account, $target_hostmask, $channel, $text, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});

        # do stuff that happens in check_flood
        my ($target_nick, $target_user, $target_host) = $target_hostmask =~ m/^([^!]+)!([^@]+)@(.*)/;

        $self->{pbot}->{antiflood}->check_flood(
            $channel, $target_nick, $target_user, $target_host, $text,
            $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_threshold'),
            $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_time_threshold'),
            $self->{pbot}->{messagehistory}->{MSG_DEPARTURE}
        );
    }

    # look up message history account for person doing the kicking
    $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account_id("$nick!$user\@$host");

    if (defined $message_account) {
        # replace target nick with target hostmask if available
        if (defined $target_hostmask) {
            $target = $target_hostmask;
        }

        # add "KICKED $target" to kicker's message history
        my $text = "KICKED $target from $channel ($reason)";
        $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, $text, $self->{pbot}->{messagehistory}->{MSG_CHAT});
    }

    return 0;
}

sub on_departure {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $channel, $args) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        lc $event->{event}->{to}->[0],
        $event->{event}->args
    );

    ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

    my $text = uc ($event->{event}->type) . ' ' . $args;

    my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);

    if ($text =~ m/^QUIT/) {
        # QUIT messages must be added to the mesasge history of each channel the user is on
        my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
        foreach my $chan (@$channels) {
            next if $chan !~ m/^#/;
            $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $chan, $text, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});
        }
    } else {
        $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, $text, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});
    }

    $self->{pbot}->{antiflood}->check_flood(
        $channel, $nick, $user, $host, $text,
        $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_threshold'),
        $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_time_threshold'),
        $self->{pbot}->{messagehistory}->{MSG_DEPARTURE}
    );

    my $u = $self->{pbot}->{users}->find_user($channel, "$nick!$user\@$host");

    # log user out if logged in and not stayloggedin
    # TODO: this should probably be in Users.pm with its own part/quit/kick handler
    if (defined $u and $u->{loggedin} and not $u->{stayloggedin}) {
        $self->{pbot}->{logger}->log("Logged out $nick.\n");
        delete $u->{loggedin};
        $self->{pbot}->{users}->save;
    }

    return 0;
}

sub on_isupport {
    my ($self, $event_type, $event) = @_;

    # remove and discard first and last arguments
    # (first arg is botnick, last arg is "are supported by this server")
    shift @{$event->{event}->{args}};
    pop   @{$event->{event}->{args}};

    my $logmsg = "$event->{event}->{from} supports:";

    foreach my $arg (@{$event->{event}->{args}}) {
        my ($key, $value) = split /=/, $arg;

        if ($key =~ s/^-//) {
            # server removed suppport for this key
            delete $self->{pbot}->{isupport}->{$key};
        } else {
            $self->{pbot}->{isupport}->{$key} = $value // 1;
        }

        $logmsg .= defined $value ? " $key=$value" : " $key";
    }

    $self->{pbot}->{logger}->log("$logmsg\n");

    return 0;
}

# IRCv3 client capability negotiation
# TODO: most, if not all, of this should probably be in PBot::IRC::Connection
# but at the moment I don't want to change Net::IRC more than the absolute
# minimum necessary.
#
# TODO: CAP NEW and CAP DEL

sub on_cap {
    my ($self, $event_type, $event) = @_;

    # configure client capabilities that PBot currently supports
    my %desired_caps = (
        'account-notify' => 1,
        'extended-join'  => 1,

        # TODO: unsupported capabilities worth looking into
        'away-notify'    => 0,
        'chghost'        => 0,
        'identify-msg'   => 0,
        'multi-prefix'   => 0,
    );

    if ($event->{event}->{args}->[0] eq 'LS') {
        my $capabilities;
        my $caps_done = 0;

        if ($event->{event}->{args}->[1] eq '*') {
            # more CAP LS messages coming
            $capabilities = $event->{event}->{args}->[2];
        } else {
            # final CAP LS message
            $caps_done    = 1;
            $capabilities = $event->{event}->{args}->[1];
        }

        $self->{pbot}->{logger}->log("Client capabilities available: $capabilities\n");

        my @caps = split /\s+/, $capabilities;

        foreach my $cap (@caps) {
            my $value;

            if ($cap =~ /=/) {
                ($cap, $value) = split /=/, $cap;
            } else {
                $value = 1;
            }

            # store available capability
            $self->{pbot}->{irc_capabilities_available}->{$cap} = $value;

            # request desired capabilities
            if ($desired_caps{$cap}) {
                $self->{pbot}->{logger}->log("Requesting client capability $cap\n");
                $event->{conn}->sl("CAP REQ :$cap");
            }
        }

        # capability negotiation done
        # now we either start SASL authentication or we send CAP END
        if ($caps_done) {
            # start SASL authentication if enabled
            if ($self->{pbot}->{registry}->get_value('irc', 'sasl')) {
                $self->{pbot}->{logger}->log("Requesting client capability sasl\n");
                $event->{conn}->sl("CAP REQ :sasl");
            } else {
                $self->{pbot}->{logger}->log("Completed client capability negotiation\n");
                $event->{conn}->sl("CAP END");
            }
        }
    }
    elsif ($event->{event}->{args}->[0] eq 'ACK') {
        $self->{pbot}->{logger}->log("Client capabilities granted: $event->{event}->{args}->[1]\n");

        my @caps = split /\s+/, $event->{event}->{args}->[1];

        foreach my $cap (@caps) {
            $self->{pbot}->{irc_capabilities}->{$cap} = 1;

            if ($cap eq 'sasl') {
                # begin SASL authentication
                # TODO: for now we support only PLAIN
                $self->{pbot}->{logger}->log("Performing SASL authentication PLAIN\n");
                $event->{conn}->sl("AUTHENTICATE PLAIN");
            }
        }
    }
    elsif ($event->{event}->{args}->[0] eq 'NAK') {
        $self->{pbot}->{logger}->log("Client capabilities rejected: $event->{event}->{args}->[1]\n");
    }
    else {
        $self->{pbot}->{logger}->log("Unknown CAP event:\n");
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log(Dumper $event->{event});
    }

    return 0;
}

# IRCv3 SASL authentication
# TODO: this should probably be in PBot::IRC::Connection as well...
# but at the moment I don't want to change Net::IRC more than the absolute
# minimum necessary.

sub on_sasl_authenticate {
    my ($self, $event_type, $event) = @_;

    my $nick     = $self->{pbot}->{registry}->get_value('irc', 'botnick');
    my $password = $self->{pbot}->{registry}->get_value('irc', 'identify_password');

    if (not defined $password or not length $password) {
        $self->{pbot}->{logger}->log("Error: Registry entry irc.identify_password is not set.\n");
        $self->{pbot}->exit;
    }

    $password = encode('UTF-8', "$nick\0$nick\0$password");

    $password = encode_base64($password, '');

    my @chunks = unpack('(A400)*', $password);

    foreach my $chunk (@chunks) {
        $event->{conn}->sl("AUTHENTICATE $chunk");
    }

    # must send final AUTHENTICATE + if last chunk was exactly 400 bytes
    if (length $chunks[$#chunks] == 400) {
        $event->{conn}->sl("AUTHENTICATE +");
    }

    return 0;
}

sub on_rpl_loggedin {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    return 0;
}

sub on_rpl_loggedout {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    return 0;
}

sub on_err_nicklocked {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    $self->{pbot}->exit;
}

sub on_rpl_saslsuccess {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    $event->{conn}->sl("CAP END");
    return 0;
}

sub on_err_saslfail {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    $self->{pbot}->exit;
}

sub on_err_sasltoolong {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    $self->{pbot}->exit;
}

sub on_err_saslaborted {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    $self->{pbot}->exit;
}

sub on_err_saslalready {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log($event->{event}->{args}->[1] . "\n");
    return 0;
}

sub on_rpl_saslmechs {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log("SASL mechanism not available.\n");
    $self->{pbot}->{logger}->log("Available mechanisms are: $event->{event}->{args}->[1]\n");
    $self->{pbot}->exit;
}

sub on_nickchange {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $newnick) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);

    ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

    $self->{pbot}->{logger}->log("[NICKCHANGE] $nick!$user\@$host changed nick to $newnick\n");

    if ($newnick eq $self->{pbot}->{registry}->get_value('irc', 'botnick') and not $self->{pbot}->{joined_channels}) {
        $self->{pbot}->{channels}->autojoin;
        return 0;
    }

    my $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
    $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($message_account, $self->{pbot}->{antiflood}->{NEEDS_CHECKBAN});
    my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
    foreach my $channel (@$channels) {
        next if $channel !~ m/^#/;
        $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "NICKCHANGE $newnick", $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE});
    }
    $self->{pbot}->{messagehistory}->{database}->update_hostmask_data("$nick!$user\@$host", {last_seen => scalar time});

    my $newnick_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($newnick, $user, $host, $nick);
    $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($newnick_account, $self->{pbot}->{antiflood}->{NEEDS_CHECKBAN});
    $self->{pbot}->{messagehistory}->{database}->update_hostmask_data("$newnick!$user\@$host", {last_seen => scalar time});

    $self->{pbot}->{antiflood}->check_flood(
        "$nick!$user\@$host", $nick, $user, $host, "NICKCHANGE $newnick",
        $self->{pbot}->{registry}->get_value('antiflood', 'nick_flood_threshold'),
        $self->{pbot}->{registry}->get_value('antiflood', 'nick_flood_time_threshold'),
        $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}
    );

    return 0;
}

sub on_nicknameinuse {
    my ($self, $event_type, $event) = @_;

    my (undef, $nick, $msg)   = $event->{event}->args;
    my $from = $event->{event}->from;

    $self->{pbot}->{logger}->log("Received nicknameinuse for nick $nick from $from: $msg\n");

    # attempt to use NickServ GHOST command to kick nick off
    $event->{conn}->privmsg("nickserv", "ghost $nick " . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));

    return 0;
}

sub on_channelmodeis {
    my ($self, $event_type, $event) = @_;

    my (undef, $channel, $modes) = $event->{event}->args;

    $self->{pbot}->{logger}->log("Channel $channel modes: $modes\n");

    $self->{pbot}->{channels}->{channels}->set($channel, 'MODE', $modes, 1);
}

sub on_channelcreate {
    my ($self,  $event_type, $event) = @_;

    my ($owner, $channel, $timestamp) = $event->{event}->args;

    $self->{pbot}->{logger}->log("Channel $channel created by $owner on " . localtime($timestamp) . "\n");

    $self->{pbot}->{channels}->{channels}->set($channel, 'CREATED_BY', $owner,     1);
    $self->{pbot}->{channels}->{channels}->set($channel, 'CREATED_ON', $timestamp, 1);
}

sub on_topic {
    my ($self, $event_type, $event) = @_;

    if (not length $event->{event}->{to}->[0]) {
        # on join
        my (undef, $channel, $topic) = $event->{event}->args;
        $self->{pbot}->{logger}->log("Topic for $channel: $topic\n");
        $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC', $topic, 1);
    } else {
        # user changing topic
        my ($nick, $user, $host) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);
        my $channel = $event->{event}->{to}->[0];
        my $topic   = $event->{event}->{args}->[0];

        $self->{pbot}->{logger}->log("$nick!$user\@$host changed topic for $channel to: $topic\n");
        $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC',        $topic,               1);
        $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC_SET_BY', "$nick!$user\@$host", 1);
        $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC_SET_ON', time);
    }

    return 0;
}

sub on_topicinfo {
    my ($self, $event_type, $event) = @_;
    my (undef, $channel, $by, $timestamp) = $event->{event}->args;
    $self->{pbot}->{logger}->log("Topic for $channel set by $by on " . localtime($timestamp) . "\n");
    $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC_SET_BY', $by,        1);
    $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC_SET_ON', $timestamp, 1);
    return 0;
}

sub on_nononreg {
    my ($self, $event_type, $event) = @_;

    my $target = $event->{event}->{args}->[1];

    $self->{pbot}->{logger}->log("Cannot send private /msg to $target; they are blocking unidentified /msgs.\n");

    return 0;
}

sub log_first_arg {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log("$event->{event}->{args}->[1]\n");
    return 0;
}

sub log_third_arg {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log("$event->{event}->{args}->[3]\n");
    return 0;
}

sub normalize_hostmask {
    my ($self, $nick, $user, $host) = @_;

    if ($host =~ m{^(gateway|nat)/(.*)/x-[^/]+$}) { $host = "$1/$2/x-$user"; }

    $host =~ s{/session$}{/x-$user};

    return ($nick, $user, $host);
}

my %who_queue;
my %who_cache;
my $last_who_id;
my $who_pending = 0;

sub on_whoreply {
    my ($self, $event_type, $event) = @_;

    my (undef, $id, $user, $host, $server, $nick, $usermodes, $gecos) = $event->{event}->args;

    ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

    my $hostmask = "$nick!$user\@$host";
    my $channel;

    if ($id =~ m/^#/) {
        $id = lc $id;
        foreach my $x (keys %who_cache) {
            if ($who_cache{$x} eq $id) {
                $id = $x;
                last;
            }
        }
    }

    $last_who_id = $id;
    $channel     = $who_cache{$id};
    delete $who_queue{$id};

    return 0 if not defined $channel;

    $self->{pbot}->{logger}->log("WHO id: $id [$channel], hostmask: $hostmask, $usermodes, $server, $gecos.\n");

    $self->{pbot}->{nicklist}->add_nick($channel, $nick);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'hostmask', $hostmask);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'user',     $user);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'host',     $host);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'server',   $server);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'gecos',    $gecos);

    my $account_id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
    $self->{pbot}->{messagehistory}->{database}->update_hostmask_data($hostmask, {last_seen => scalar time});

    $self->{pbot}->{messagehistory}->{database}->link_aliases($account_id, $hostmask, undef);

    $self->{pbot}->{messagehistory}->{database}->devalidate_channel($account_id, $channel);
    $self->{pbot}->{antiflood}->check_bans($account_id, $hostmask, $channel);

    return 0;
}

sub on_whospcrpl {
    my ($self, $event_type, $event) = @_;

    my (undef, $id, $user, $host, $nick, $nickserv, $gecos) = $event->{event}->args;

    ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

    $last_who_id = $id;
    my $hostmask = "$nick!$user\@$host";
    my $channel  = $who_cache{$id};
    delete $who_queue{$id};

    return 0 if not defined $channel;

    $self->{pbot}->{logger}->log("WHO id: $id [$channel], hostmask: $hostmask, $nickserv, $gecos.\n");

    $self->{pbot}->{nicklist}->add_nick($channel, $nick);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'hostmask', $hostmask);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'user',     $user);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'host',     $host);
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'nickserv', $nickserv) if $nickserv ne '0';
    $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'gecos',    $gecos);

    my $account_id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
    $self->{pbot}->{messagehistory}->{database}->update_hostmask_data($hostmask, {last_seen => scalar time});

    if ($nickserv ne '0') {
        $self->{pbot}->{messagehistory}->{database}->link_aliases($account_id, undef, $nickserv);
        $self->{pbot}->{antiflood}->check_nickserv_accounts($nick, $nickserv);
    }

    $self->{pbot}->{messagehistory}->{database}->link_aliases($account_id, $hostmask, undef);

    $self->{pbot}->{messagehistory}->{database}->devalidate_channel($account_id, $channel);
    $self->{pbot}->{antiflood}->check_bans($account_id, $hostmask, $channel);

    return 0;
}

sub on_endofwho {
    my ($self, $event_type, $event) = @_;
    $self->{pbot}->{logger}->log("WHO session $last_who_id ($who_cache{$last_who_id}) completed.\n");
    delete $who_cache{$last_who_id};
    delete $who_queue{$last_who_id};
    $who_pending = 0;
    return 0;
}

sub send_who {
    my ($self, $channel) = @_;
    $channel = lc $channel;
    $self->{pbot}->{logger}->log("pending WHO to $channel\n");

    for (my $id = 1; $id < 99; $id++) {
        if (not exists $who_cache{$id}) {
            $who_cache{$id} = $channel;
            $who_queue{$id} = $channel;
            $last_who_id    = $id;
            last;
        }
    }
}

sub check_pending_whos {
    my $self = shift;
    return if $who_pending;
    foreach my $id (keys %who_queue) {
        $self->{pbot}->{logger}->log("sending WHO to $who_queue{$id} [$id]\n");
        $self->{pbot}->{conn}->sl("WHO $who_queue{$id} %tuhnar,$id");
        $who_pending = 1;
        $last_who_id = $id;
        last;
    }
}

1;
