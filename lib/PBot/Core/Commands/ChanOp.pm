# File: ChanOp.pm
#
# Purpose: Channel operator command subroutines.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::ChanOp;

use PBot::Imports;

use Time::Duration;
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

    # register commands
    $self->{pbot}->{commands}->register(sub { $self->cmd_op(@_) },      "op",      1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_deop(@_) },    "deop",    1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_voice(@_) },   "voice",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_devoice(@_) }, "devoice", 1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_ban(@_) },     "ban",     1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unban(@_) },   "unban",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_mute(@_) },    "mute",    1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unmute(@_) },  "unmute",  1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_kick(@_) },    "kick",    1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_mode(@_) },    "mode",    1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_invite(@_) },  "invite",  1);

    # allow commands to set modes
    $self->{pbot}->{capabilities}->add('can-ban',     'can-mode-b', 1);
    $self->{pbot}->{capabilities}->add('can-unban',   'can-mode-b', 1);
    $self->{pbot}->{capabilities}->add('can-mute',    'can-mode-q', 1);
    $self->{pbot}->{capabilities}->add('can-unmute',  'can-mode-q', 1);
    $self->{pbot}->{capabilities}->add('can-op',      'can-mode-o', 1);
    $self->{pbot}->{capabilities}->add('can-deop',    'can-mode-o', 1);
    $self->{pbot}->{capabilities}->add('can-voice',   'can-mode-v', 1);
    $self->{pbot}->{capabilities}->add('can-devoice', 'can-mode-v', 1);

    # create can-mode-any capabilities group
    foreach my $mode ("a" .. "z", "A" .. "Z") { $self->{pbot}->{capabilities}->add('can-mode-any', "can-mode-$mode", 1); }
    $self->{pbot}->{capabilities}->add('can-mode-any', 'can-mode', 1);

    # add to chanop capabilities group
    $self->{pbot}->{capabilities}->add('chanop', 'can-ban',        1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-unban',      1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-mute',       1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-unmute',     1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-kick',       1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-op',         1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-deop',       1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-voice',      1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-devoice',    1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-invite',     1);
    $self->{pbot}->{capabilities}->add('chanop', 'is-whitelisted', 1);

    # add to admin capability group
    $self->{pbot}->{capabilities}->add('admin', 'chanop',       1);
    $self->{pbot}->{capabilities}->add('admin', 'can-mode',     1);
    $self->{pbot}->{capabilities}->add('admin', 'can-mode-any', 1);

    # allow users to use !unban * or !unmute *
    $self->{pbot}->{capabilities}->add('can-clear-bans',  undef, 1);
    $self->{pbot}->{capabilities}->add('can-clear-mutes', undef, 1);

    # allow admins to use !unban * or !unmute *
    $self->{pbot}->{capabilities}->add('admin', 'can-clear-bans',  1);
    $self->{pbot}->{capabilities}->add('admin', 'can-clear-mutes', 1);

    # allows users to use wildcards in command
    $self->{pbot}->{capabilities}->add('can-op-wildcard',    undef, 1);
    $self->{pbot}->{capabilities}->add('can-voice-wildcard', undef, 1);
    $self->{pbot}->{capabilities}->add('can-kick-wildcard',  undef, 1);

    $self->{pbot}->{capabilities}->add('admin',   'can-kick-wildcard',  1);
    $self->{pbot}->{capabilities}->add('admin',   'can-op-wildcard',    1);
    $self->{pbot}->{capabilities}->add('admin',   'can-voice-wildcard', 1);
    $self->{pbot}->{capabilities}->add('chanmod', 'can-voice-wildcard', 1);

    $self->{invites} = {};    # track who invited who in order to direct invite responses to them

    # handle invite responses
    $self->{pbot}->{event_dispatcher}->register_handler('irc.inviting',      sub { $self->on_inviting(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.useronchannel', sub { $self->on_useronchannel(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.nosuchnick',    sub { $self->on_nosuchnick(@_) });
}

sub on_inviting {
    my ($self, $event_type, $event) = @_;

    my ($botnick, $target, $channel) = $event->{event}->args;

    $self->{pbot}->{logger}->log("User $target invited to channel $channel.\n");

    if (not exists $self->{invites}->{lc $channel} or not exists $self->{invites}->{lc $channel}->{lc $target}) {
        return 0;
    }

    $event->{conn}->privmsg($self->{invites}->{lc $channel}->{lc $target}, "$target invited to $channel.");

    delete $self->{invites}->{lc $channel}->{lc $target};
    return 1;
}

sub on_useronchannel {
    my ($self, $event_type, $event)   = @_;

    my ($botnick, $target, $channel) = $event->{event}->args;

    $self->{pbot}->{logger}->log("User $target is already on channel $channel.\n");

    if (not exists $self->{invites}->{lc $channel} or not exists $self->{invites}->{lc $channel}->{lc $target}) {
        return 0;
    }

    $event->{conn}->privmsg($self->{invites}->{lc $channel}->{lc $target}, "$target is already on $channel.");

    delete $self->{invites}->{lc $channel}->{lc $target};
    return 1;
}

sub on_nosuchnick {
    my ($self, $event_type, $event) = @_;

    my ($botnick, $target, $msg) = $event->{event}->args;

    $self->{pbot}->{logger}->log("$target: $msg\n");

    my $nick;
    foreach my $channel (keys %{$self->{invites}}) {
        if (exists $self->{invites}->{$channel}->{lc $target}) {
            $nick = $self->{invites}->{$channel}->{lc $target};
            delete $self->{invites}->{$channel}->{lc $target};
            last;
        }
    }

    return 0 if not defined $nick;
    $event->{conn}->privmsg($nick, "$target: $msg");
    return 1;
}

sub cmd_invite {
    my ($self, $context) = @_;
    my ($channel, $target);

    if ($context->{from} !~ m/^#/) {
        # from /msg
        my $usage = "Usage from /msg: invite <channel> [nick]; if you omit [nick] then you will be invited";
        return $usage if not length $context->{arguments};
        ($channel, $target) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
        return "$channel is not a channel; $usage" if $channel !~ m/^#/;
        $target = $context->{nick} if not defined $target;
    } else {
        # in channel
        return "Usage: invite [channel] <nick>" if not length $context->{arguments};

        # add current channel as default channel
        $self->{pbot}->{interpreter}->unshift_arg($context->{arglist}, $context->{from}) if $context->{arglist}[0] !~ m/^#/;
        ($channel, $target) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
    }

    $self->{invites}->{lc $channel}->{lc $target} = $context->{nick};
    $self->{pbot}->{chanops}->add_op_command($channel, "sl invite $target $channel");
    $self->{pbot}->{chanops}->gain_ops($channel);
    return "";    # responses handled by events
}

sub generic_mode {
    my ($self, $mode_flag, $mode_name, $context) = @_;
    my $result = '';
    my $channel = $context->{from};

    my ($flag, $mode_char) = $mode_flag =~ m/(.)(.)/;

    if ($channel !~ m/^#/) {
        # from message
        $channel = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});
        if    (not defined $channel) { return "Usage from message: $mode_name <channel> [nick]"; }
        elsif ($channel !~ m/^#/)    { return "$channel is not a channel. Usage from message: $mode_name <channel> [nick]"; }
    }

    $channel = lc $channel;
    if (not $self->{pbot}->{chanops}->can_gain_ops($channel)) { return "I am not configured as an OP for $channel. See `chanset` command for more information."; }

    # add $nick to $args if no argument
    if (not $self->{pbot}->{interpreter}->arglist_size($context->{arglist})) { $self->{pbot}->{interpreter}->unshift_arg($context->{arglist}, $context->{nick}); }

    my $max_modes = $self->{pbot}->{isupport}->{MODES} // 1;
    my $mode      = $flag;
    my $list      = '';
    my $i         = 0;

    foreach my $targets ($self->{pbot}->{interpreter}->unquoted_args($context->{arglist})) {
        foreach my $target (split /,/, $targets) {
            $mode .= $mode_char;
            $list .= "$target ";
            $i++;

            if ($i >= $max_modes) {
                $context->{arguments} = "$channel $mode $list";
                $context->{arglist}   = $self->{pbot}->{interpreter}->make_args($context->{arguments});
                $result               = $self->cmd_mode($context);
                $mode                 = $flag;
                $list                 = '';
                $i                    = 0;
                last if $result ne '' and $result ne 'Done.';
            }
        }
    }

    if ($i) {
        $context->{arguments} = "$channel $mode $list";
        $context->{arglist}   = $self->{pbot}->{interpreter}->make_args($context->{arguments});
        $result = $self->cmd_mode($context);
    }

    return $result;
}

sub cmd_op {
    my ($self, $context) = @_;
    return $self->generic_mode('+o', 'op', $context);
}

sub cmd_deop {
    my ($self, $context) = @_;
    return $self->generic_mode('-o', 'deop', $context);
}

sub cmd_voice {
    my ($self, $context) = @_;
    return $self->generic_mode('+v', 'voice', $context);
}

sub cmd_devoice {
    my ($self, $context) = @_;
    return $self->generic_mode('-v', 'devoice', $context);
}

sub cmd_mode {
    my ($self, $context) = @_;

    if (not length $context->{arguments}) { return "Usage: mode [channel] <arguments>"; }

    # add current channel as default channel
    if ($context->{arglist}[0] !~ m/^#/) {
        if ($context->{from} =~ m/^#/) {
            $self->{pbot}->{interpreter}->unshift_arg($context->{arglist}, $context->{from});
        } else {
            return "Usage from private message: mode <channel> <arguments>";
        }
    }

    my ($channel, $modes, $args) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);
    my @targets = split /\s+/, $args if defined $args;
    my $modifier;
    my $i   = 0;
    my $arg = 0;

    my ($new_modes, $new_targets) = ("", "");
    my $max_modes = $self->{pbot}->{isupport}->{MODES} // 1;

    my $u = $self->{pbot}->{users}->loggedin($channel, $context->{hostmask});

    while ($modes =~ m/(.)/g) {
        my $mode = $1;

        if ($mode eq '-' or $mode eq '+') {
            $modifier = $mode;
            $new_modes .= $mode;
            next;
        }

        if (not $self->{pbot}->{capabilities}->userhas($u, "can-mode-$mode")) {
            return "/msg $context->{nick} Your user account does not have the can-mode-$mode capability required to set this mode.";
        }

        my $target = $targets[$arg++] // "";

        if (($mode eq 'v' or $mode eq 'o') and $target =~ m/\*/) {
            # wildcard used; find all matching nicks; test against whitelist, etc
            my $q_target = lc quotemeta $target;
            $q_target =~ s/\\\*/.*/g;
            $channel = lc $channel;

            if (not exists $self->{pbot}->{nicklist}->{nicklist}->{$channel}) {
                return "I have no nicklist for channel $channel; cannot use wildcard.";
            }

            my $u = $self->{pbot}->{users}->loggedin($channel, $context->{hostmask});
            if ($mode eq 'v') {
                if (not $self->{pbot}->{capabilities}->userhas($u, 'can-voice-wildcard')) {
                    return "/msg $context->{nick} Using wildcards with `mode v` requires the can-voice-wildcard capability, which your user account does not have.";
                }
            } else {
                if (not $self->{pbot}->{capabilities}->userhas($u, 'can-op-wildcard')) {
                    return "/msg $context->{nick} Using wildcards with `mode o` requires the can-op-wildcard capability, which your user account does not have.";
                }
            }

            foreach my $n (keys %{$self->{pbot}->{nicklist}->{nicklist}->{$channel}}) {
                if ($n =~ m/^$q_target$/) {
                    my $nick_data = $self->{pbot}->{nicklist}->{nicklist}->{$channel}->{$n};

                    if ($modifier eq '-') {
                        # removing mode -- check against whitelist, etc
                        next if $nick_data->{nick} eq $self->{pbot}->{registry}->get_value('irc', 'botnick');
                        my $u = $self->{pbot}->{users}->loggedin($channel, $nick_data->{hostmask});
                        next if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');
                    }

                    # skip nick if already has mode set/unset
                    if ($modifier eq '+') { next if exists $nick_data->{"+$mode"}; }
                    else                  { next unless exists $nick_data->{"+$mode"}; }

                    $new_modes = $modifier if not length $new_modes;
                    $new_modes   .= $mode;
                    $new_targets .= "$self->{pbot}->{nicklist}->{nicklist}->{$channel}->{$n}->{nick} ";
                    $i++;

                    if ($i == $max_modes) {
                        $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $new_modes $new_targets");
                        $new_modes   = "";
                        $new_targets = "";
                        $i           = 0;
                    }
                }
            }
        } else {
            # no wildcard used; explicit mode requested - no whitelist checking
            $new_modes   .= $mode;
            $new_targets .= "$target " if length $target;
            $i++;

            if ($i == $max_modes) {
                $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $new_modes $new_targets");
                $new_modes   = "";
                $new_targets = "";
                $i           = 0;
            }
        }
    }

    if ($i) { $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $new_modes $new_targets"); }

    $self->{pbot}->{chanops}->gain_ops($channel);

    if   ($context->{from} !~ m/^#/) { return "Done."; }
    else                             { return "";      }
}

sub cmd_ban {
    my ($self, $context) = @_;
    my ($target, $channel, $length) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);

    $channel = '' if not defined $channel;
    $length  = '' if not defined $length;

    if (not defined $context->{from}) {
        $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
        return "";
    }

    if ($channel !~ m/^#/) {
        $length  = "$channel $length";
        $length  = undef if $length eq ' ';
        $channel = exists $context->{admin_channel_override} ? $context->{admin_channel_override} : $context->{from};
    }

    if (not defined $channel or not length $channel) {
        $channel = exists $context->{admin_channel_override} ? $context->{admin_channel_override} : $context->{from};
    }

    if (not defined $target) { return "Usage: ban <mask> [channel [timeout (default: 24 hours)]]"; }

    my $no_length = 0;
    if (not defined $length) {
        # TODO: user account length override
        $length = $self->{pbot}->{registry}->get_value($channel, 'default_ban_timeout', 0, $context)
          // $self->{pbot}->{registry}->get_value('general', 'default_ban_timeout', 0, $context) // 60 * 60 * 24;    # 24 hours
        $no_length = 1;
    } else {
        my $error;
        ($length, $error) = $self->{pbot}->{parsedate}->parsedate($length);
        return $error if defined $error;
    }

    $channel = lc $channel;
    $target  = lc $target;

    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
    return "I don't think so." if $target =~ /^\Q$botnick\E!/i;

    my $result      = '';
    my $sep         = '';
    my @targets     = split /,/, $target;
    my $immediately = @targets > 1 ? 0 : 1;
    my $duration;

    foreach my $t (@targets) {
        my $mask = lc $self->{pbot}->{banlist}->nick_to_banmask($t);

        my $timeout = $self->{pbot}->{banlist}->{banlist}->get_data($channel, $mask, 'timeout') // 0;

        if ($no_length && $timeout > 0) {
            my $d = duration($timeout - gettimeofday);
            $result .= "$sep$mask has $d remaining on their $channel ban";
            $sep = '; ';
        } else {
            $self->{pbot}->{banlist}->ban_user_timed($channel, 'b', $mask, $length, $context->{hostmask}, undef, $immediately);
            $duration = $length > 0 ? duration $length : 'all eternity';
            if ($immediately) {
                $result .= "$sep$mask banned in $channel for $duration";
                $sep = '; ';
            } else {
                $result .= "$sep$mask";
                $sep = ', ';
            }
        }
    }

    if (not $immediately) {
        $result .= " banned in $channel for $duration";
        $self->{pbot}->{banlist}->flush_ban_queue;
    }

    $result = "/msg $context->{nick} $result" if $result !~ m/remaining on their/;
    return $result;
}

sub cmd_unban {
    my ($self, $context) = @_;

    if (not defined $context->{from}) {
        $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
        return "";
    }

    my ($target, $channel, $immediately) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);

    if (defined $target and defined $channel and $channel !~ /^#/) {
        my $temp = $target;
        $target  = $channel;
        $channel = $temp;
    }

    if (not defined $target) { return "Usage: unban <nick/mask> [channel [false value to use unban queue]]"; }

    if (not defined $channel) {
        $channel = exists $context->{admin_channel_override} ? $context->{admin_channel_override} : $context->{from};
    }

    $immediately = 1 if not defined $immediately;

    return "Usage for /msg: unban <nick/mask> <channel> [false value to use unban queue]" if $channel !~ /^#/;

    my @targets = split /,/, $target;
    $immediately = 0 if @targets > 1;

    foreach my $t (@targets) {
        if ($t eq '*') {
            my $u = $self->{pbot}->{users}->loggedin($channel, $context->{hostmask});
            if (not $self->{pbot}->{capabilities}->userhas($u, 'can-clear-bans')) {
                return "/msg $context->{nick} Clearing the channel bans requires the can-clear-bans capability, which your user account does not have.";
            }
            $channel = lc $channel;
            if ($self->{pbot}->{banlist}->{banlist}->exists($channel)) {
                $immediately = 0;
                foreach my $banmask ($self->{pbot}->{banlist}->{banlist}->get_keys($channel)) {
                    $self->{pbot}->{banlist}->unban_user($channel, 'b', $banmask, $immediately);
                }
                last;
            }
        } else {
            $self->{pbot}->{banlist}->unban_user($channel, 'b', $t, $immediately);
        }
    }

    $self->{pbot}->{banlist}->flush_unban_queue if not $immediately;
    return "/msg $context->{nick} $target has been unbanned from $channel.";
}

sub cmd_mute {
    my ($self, $context) = @_;
    my ($target, $channel, $length) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);

    $channel = '' if not defined $channel;

    if (not defined $context->{from}) {
        $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
        return "";
    }

    if (not length $channel and $context->{from} !~ m/^#/) {
        return "Usage from private message: mute <mask> <channel> [timeout (default: 24 hours)]";
    }

    if ($channel !~ m/^#/) {
        $length  = $channel . ' ' . (defined $length ? $length : '');
        $length  = undef if $length eq ' ';
        $channel = exists $context->{admin_channel_override} ? $context->{admin_channel_override} : $context->{from};
    }

    $channel = exists $context->{admin_channel_override} ? $context->{admin_channel_override} : $context->{from} if not defined $channel;

    if ($channel !~ m/^#/) { return "Please specify a channel."; }

    if (not defined $target) { return "Usage: mute <mask> [channel [timeout (default: 24 hours)]]"; }

    my $no_length = 0;
    if (not defined $length) {
        $length = $self->{pbot}->{registry}->get_value($channel, 'default_mute_timeout', 0, $context)
          // $self->{pbot}->{registry}->get_value('general', 'default_mute_timeout', 0, $context) // 60 * 60 * 24;    # 24 hours
        $no_length = 1;
    } else {
        my $error;
        ($length, $error) = $self->{pbot}->{parsedate}->parsedate($length);
        return $error if defined $error;
    }

    $channel = lc $channel;
    $target  = lc $target;

    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
    return "I don't think so." if $target =~ /^\Q$botnick\E!/i;

    my $result      = '';
    my $sep         = '';
    my @targets     = split /,/, $target;
    my $immediately = @targets > 1 ? 0 : 1;
    my $duration;

    foreach my $t (@targets) {
        my $mask = lc $self->{pbot}->{banlist}->nick_to_banmask($t);

        my $timeout = $self->{pbot}->{banlist}->{quietlist}->get_data($channel, $mask, 'timeout') // 0;

        if ($no_length && $timeout > 0) {
            my $d = duration($timeout - gettimeofday);
            $result .= "$sep$mask has $d remaining on their $channel mute";
            $sep = '; ';
        } else {
            $self->{pbot}->{banlist}->ban_user_timed($channel, 'q', $t, $length, $context->{hostmask}, undef, $immediately);
            $duration = $length > 0 ? duration $length : 'all eternity';
            if ($immediately) {
                $result .= "$sep$mask muted in $channel for $duration";
                $sep = '; ';
            } else {
                $result .= "$sep$mask";
                $sep = ', ';
            }
        }
    }

    if (not $immediately) {
        $result .= " muted in $channel for $duration";
        $self->{pbot}->{banlist}->flush_ban_queue;
    }

    $result = "/msg $context->{nick} $result" if $result !~ m/remaining on their/;
    return $result;
}

sub cmd_unmute {
    my ($self, $context) = @_;

    if (not defined $context->{from}) {
        $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
        return "";
    }

    my ($target, $channel, $immediately) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);

    if (defined $target and defined $channel and $channel !~ /^#/) {
        my $temp = $target;
        $target  = $channel;
        $channel = $temp;
    }

    if (not defined $target) { return "Usage: unmute <nick/mask> [channel [false value to use unban queue]]"; }

    $channel     = exists $context->{admin_channel_override} ? $context->{admin_channel_override} : $context->{from} if not defined $channel;
    $immediately = 1 if not defined $immediately;

    return "Usage for /msg: unmute <nick/mask> <channel> [false value to use unban queue]" if $channel !~ /^#/;

    my @targets = split /,/, $target;
    $immediately = 0 if @targets > 1;

    foreach my $t (@targets) {
        if ($t eq '*') {
            my $u = $self->{pbot}->{users}->loggedin($channel, $context->{hostmask});
            if (not $self->{pbot}->{capabilities}->userhas($u, 'can-clear-mutes')) {
                return "/msg $context->{nick} Clearing the channel mutes requires the can-clear-mutes capability, which your user account does not have.";
            }
            $channel = lc $channel;
            if ($self->{pbot}->{banlist}->{quietlist}->exists($channel)) {
                $immediately = 0;
                foreach my $banmask ($self->{pbot}->{banlist}->{quietlist}->get_keys($channel)) {
                    $self->{pbot}->{banlist}->unban_user($channel, 'q', $banmask, $immediately);
                }
                last;
            }
        } else {
            $self->{pbot}->{banlist}->unban_user($channel, 'q', $t, $immediately);
        }
    }

    $self->{pbot}->{banlist}->flush_unban_queue if not $immediately;
    return "/msg $context->{nick} $target has been unmuted in $channel.";
}

sub cmd_kick {
    my ($self, $context) = @_;

    if (not defined $context->{from}) {
        $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
        return "";
    }

    my ($channel, $victim, $reason);
    my $arguments = $context->{arguments};

    if (not $context->{from} =~ /^#/) {
        # used in private message
        if (not $arguments =~ s/^(^#\S+) (\S+)\s*//) { return "Usage from private message: kick <channel> <nick> [reason]"; }
        ($channel, $victim) = ($1, $2);
    } else {
        # used in channel
        if    ($arguments =~ s/^(#\S+)\s+(\S+)\s*//) { ($channel, $victim) = ($1, $2); }
        elsif ($arguments =~ s/^(\S+)\s*//)          { ($victim, $channel) = ($1, exists $context->{admin_channel_override} ? $context->{admin_channel_override} : $context->{from}); }
        else                                         { return "Usage: kick [channel] <nick> [reason]"; }
    }

    $reason = $arguments;

    # If the user is too stupid to remember the order of the arguments,
    # we can help them out by seeing if they put the channel in the reason.
    if ($reason =~ s/^(#\S+)\s*//) { $channel = $1; }

    my @insults;
    if (not length $reason) {
        if (open my $fh, '<', $self->{pbot}->{registry}->get_value('general', 'module_dir') . '/insults.txt') {
            @insults = <$fh>;
            close $fh;
            $reason = $insults[rand @insults];
            $reason =~ s/\s+$//;
        } else {
            $reason = 'Bye!';
        }
    }

    if ($context->{keyword} =~ /^[A-Z]+$/) {
        $reason = uc $reason;
    } elsif ($context->{keyword} eq 'KiCk' or $context->{keyword} eq 'kIcK') {
        $reason =~ s/(.)(.)/lc($1) . uc($2)/ge;
    }

    my @nicks = split /,/, $victim;
    foreach my $n (@nicks) {
        if ($n =~ m/\*/) {
            # wildcard used; find all matching nicks; test against whitelist, etc
            my $q_target = lc quotemeta $n;
            $q_target =~ s/\\\*/.*/g;
            $channel = lc $channel;

            if (not exists $self->{pbot}->{nicklist}->{nicklist}->{$channel}) { return "I have no nicklist for channel $channel; cannot use wildcard."; }

            my $u = $self->{pbot}->{users}->loggedin($channel, $context->{hostmask});
            if (not $self->{pbot}->{capabilities}->userhas($u, 'can-kick-wildcard')) {
                return "/msg $context->{nick} Using wildcards with `kick` requires the can-kick-wildcard capability, which your user account does not have.";
            }

            foreach my $nl (keys %{$self->{pbot}->{nicklist}->{nicklist}->{$channel}}) {
                if ($nl =~ m/^$q_target$/) {
                    my $nick_data = $self->{pbot}->{nicklist}->{nicklist}->{$channel}->{$nl};

                    next if $nick_data->{nick} eq $self->{pbot}->{registry}->get_value('irc', 'botnick');
                    my $u = $self->{pbot}->{users}->loggedin($channel, $nick_data->{hostmask});
                    next if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

                    $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $nl $reason");
                }
            }
        } else {
            # no wildcard used, explicit kick
            $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $n $reason");
        }

        # randomize next kick reason
        if (@insults) {
            $reason = $insults[rand @insults];
            $reason =~ s/\s+$//;
        }
    }

    $self->{pbot}->{chanops}->gain_ops($channel);
    return "";
}

1;
