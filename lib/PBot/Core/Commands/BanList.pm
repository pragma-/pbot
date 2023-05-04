# File: BanList.pm
#
# Purpose: Registers commands related to bans/quiets.

# SPDX-FileCopyrightText: 2007-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::BanList;
use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Core::MessageHistory::Constants ':all';

use Time::HiRes qw/gettimeofday/;
use Time::Duration;
use POSIX qw/strftime/;

sub initialize($self, %conf) {
    $self->{pbot}->{commands}->register(sub { $self->cmd_banlist(@_) },    "banlist",    0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_checkban(@_) },   "checkban",   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_checkmute(@_) },  "checkmute",  0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unbanme(@_) },    "unbanme",    0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_ban_exempt(@_) }, "ban-exempt", 1);

    # add capability to admin group
    $self->{pbot}->{capabilities}->add('admin', 'can-ban-exempt', 1);
}

sub cmd_banlist($self, $context) {
    if (not length $context->{arguments}) {
        return "Usage: banlist <channel>";
    }

    my $result = "Ban list for $context->{arguments}:\n";

    if ($self->{pbot}->{banlist}->{banlist}->exists($context->{arguments})) {
        my $count = $self->{pbot}->{banlist}->{banlist}->get_keys($context->{arguments});
        $result .= "$count ban" . ($count == 1 ? '' : 's') . ":\n";
        foreach my $mask ($self->{pbot}->{banlist}->{banlist}->get_keys($context->{arguments})) {
            my $data = $self->{pbot}->{banlist}->{banlist}->get_data($context->{arguments}, $mask);
            $result .= "  $mask banned ";

            if (defined $data->{timestamp}) {
                my $date = strftime "%a %b %e %H:%M:%S %Y %Z", localtime $data->{timestamp};
                my $ago = concise ago (time - $data->{timestamp});
                $result .= "on $date ($ago) ";
            }

            $result .= "by $data->{owner} "       if defined $data->{owner};
            $result .= "because $data->{reason} " if defined $data->{reason};
            if (defined $data->{timeout} and $data->{timeout} > 0) {
                my $duration = concise duration($data->{timeout} - gettimeofday);
                $result .= "($duration remaining)";
            }
            $result .= ";\n";
        }
    } else {
        $result .= "bans: none;\n";
    }

    if ($self->{pbot}->{banlist}->{quietlist}->exists($context->{arguments})) {
        my $count = $self->{pbot}->{banlist}->{quietlist}->get_keys($context->{arguments});
        $result .= "$count mute" . ($count == 1 ? '' : 's') . ":\n";
        foreach my $mask ($self->{pbot}->{banlist}->{quietlist}->get_keys($context->{arguments})) {
            my $data = $self->{pbot}->{banlist}->{quietlist}->get_data($context->{arguments}, $mask);
            $result .= "  $mask muted ";

            if (defined $data->{timestamp}) {
                my $date = strftime "%a %b %e %H:%M:%S %Y %Z", localtime $data->{timestamp};
                my $ago = concise ago (time - $data->{timestamp});
                $result .= "on $date ($ago) ";
            }

            $result .= "by $data->{owner} "       if defined $data->{owner};
            $result .= "because $data->{reason} " if defined $data->{reason};
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

sub cmd_checkban($self, $context) {
    my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    return "Usage: checkban <mask> [channel]" if not defined $target;
    $channel = $context->{from} if not defined $channel;

    return "Channel must be specified in /msg; usage: checkban <mask> <channel>" if $channel !~ /^#/;
    return $self->{pbot}->{banlist}->checkban($channel, 'b', $target);
}

sub cmd_checkmute($self, $context) {
    my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    return "Usage: checkmute <mask> [channel]" if not defined $target;
    $channel = $context->{from} if not defined $channel;

    return "Channel must be specified in /msg; usage: checkmute <mask> <channel>" if $channel !~ /^#/;
    return $self->{pbot}->{banlist}->checkban($channel, $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char'), $target);
}

sub cmd_unbanme($self, $context) {
    my $unbanned;

    my %aliases = $self->{pbot}->{messagehistory}->{database}->get_also_known_as($context->{nick});

    foreach my $alias (keys %aliases) {
        next if $aliases{$alias}->{type} == LINK_WEAK;
        next if $aliases{$alias}->{nickchange} == 1;

        my $join_flood_channel = $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_channel') // '#stop-join-flood';

        my ($anick, $auser, $ahost) = $alias =~ m/([^!]+)!([^@]+)@(.*)/;
        my $banmask = $self->{pbot}->{antiflood}->address_to_mask($ahost);
        my $mask    = "*!$auser\@$banmask\$$join_flood_channel";

        my @channels = $self->{pbot}->{messagehistory}->{database}->get_channels($aliases{$alias}->{id});

        foreach my $channel (@channels) {
            next if exists $unbanned->{$channel} and exists $unbanned->{$channel}->{$mask};
            next if not $self->{pbot}->{banlist}->{banlist}->exists($channel . '-floodbans', $mask);

            my $message_account   = $self->{pbot}->{messagehistory}->{database}->get_message_account($anick, $auser, $ahost);
            my @nickserv_accounts = $self->{pbot}->{messagehistory}->{database}->get_nickserv_accounts($message_account);

            push @nickserv_accounts, undef;

            foreach my $nickserv_account (@nickserv_accounts) {
                my $baninfos = $self->{pbot}->{banlist}->get_baninfo($channel, "$anick!$auser\@$ahost", $nickserv_account);

                if (defined $baninfos) {
                    foreach my $baninfo (@$baninfos) {
                        my $u           = $self->{pbot}->{users}->loggedin($baninfo->{channel}, $context->{hostmask});
                        my $whitelisted = $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');
                        if ($self->{pbot}->{banlist}->ban_exempted($baninfo->{channel}, $baninfo->{mask}) || $whitelisted) {
                            $self->{pbot}->{logger}->log("anti-flood: [unbanme] $anick!$auser\@$ahost banned as $baninfo->{mask} in $baninfo->{channel}, but allowed through whitelist\n");
                        } else {
                            if ($channel eq lc $baninfo->{channel}) {
                                my $mode = $baninfo->{type} eq 'b' ? "banned" : "quieted";
                                $self->{pbot}->{logger}->log("anti-flood: [unbanme] $anick!$auser\@$ahost $mode as $baninfo->{mask} in $baninfo->{channel} by $baninfo->{owner}, unbanme rejected\n");
                                return "/msg $context->{nick} You have been $mode as $baninfo->{mask} by $baninfo->{owner}, unbanme will not work until it is removed.";
                            }
                        }
                    }
                }
            }

            my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'unbanmes');
            if ($channel_data->{unbanmes} <= 2) {
                $channel_data->{unbanmes}++;
                $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
            }

            $unbanned->{$channel}->{$mask} = $channel_data->{unbanmes};
        }
    }

    if (keys %$unbanned) {
        my $channels = '';

        my $sep               = '';
        my $channels_warning  = '';
        my $sep_warning       = '';
        my $channels_disabled = '';
        my $sep_disabled      = '';

        foreach my $channel (keys %$unbanned) {
            foreach my $mask (keys %{$unbanned->{$channel}}) {
                if ($self->{pbot}->{channels}->is_active_op("${channel}-floodbans")) {
                    if ($unbanned->{$channel}->{$mask} <= 2) {
                        $self->{pbot}->{banlist}->unban_user($channel . '-floodbans', 'b', $mask);
                        $channels .= "$sep$channel";
                        $sep = ", ";
                    }

                    if ($unbanned->{$channel}->{$mask} == 1) {
                        $channels_warning .= "$sep_warning$channel";
                        $sep_warning = ", ";
                    } else {
                        $channels_disabled .= "$sep_disabled$channel";
                        $sep_disabled = ", ";
                    }
                }
            }
        }

        $self->{pbot}->{banlist}->flush_unban_queue();

        $channels          =~ s/(.*), /$1 and /;
        $channels_warning  =~ s/(.*), /$1 and /;
        $channels_disabled =~ s/(.*), /$1 and /;

        my $warning = '';

        if (length $channels_warning) {
            $warning =
              " You may use `unbanme` one more time today for $channels_warning; please ensure that your client or connection issues are resolved.";
        }

        if (length $channels_disabled) {
            $warning .=
              " You may not use `unbanme` again for several hours for $channels_disabled.";
        }

        if   (length $channels) { return "/msg $context->{nick} You have been unbanned from $channels.$warning"; }
        else                    { return "/msg $context->{nick} $warning"; }
    } else {
        return "/msg $context->{nick} There is no join-flooding ban set for you.";
    }
}

sub cmd_ban_exempt($self, $context) {
    my $arglist = $context->{arglist};
    $self->{pbot}->{interpreter}->lc_args($arglist);

    my $command = $self->{pbot}->{interpreter}->shift_arg($arglist);
    return "Usage: ban-exempt <command>, where commands are: list, add, remove" if not defined $command;

    given ($command) {
        when ($_ eq 'list') {
            my $text    = "Ban-evasion exemptions:\n";
            my $entries = 0;
            foreach my $channel ($self->{pbot}->{banlist}->{'ban-exemptions'}->get_keys) {
                $text .= ' ' . $self->{pbot}->{banlist}->{'ban-exemptions'}->get_key_name($channel) . ":\n";
                foreach my $mask ($self->{pbot}->{banlist}->{'ban-exemptions'}->get_keys($channel)) {
                    $text .= "    $mask,\n";
                    $entries++;
                }
            }
            $text .= "none" if $entries == 0;
            return $text;
        }
        when ("add") {
            my ($channel, $mask) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
            return "Usage: ban-exempt add <channel> <mask>" if not defined $channel or not defined $mask;

            my $data = {
                owner      => $context->{hostmask},
                created_on => scalar gettimeofday
            };

            $self->{pbot}->{banlist}->{'ban-exemptions'}->add($channel, $mask, $data);
            return "/say $mask exempted from ban-evasions in channel $channel";
        }
        when ("remove") {
            my ($channel, $mask) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
            return "Usage: ban-exempt remove <channel> <mask>" if not defined $channel or not defined $mask;
            return $self->{pbot}->{banlist}->{'ban-exemptions'}->remove($channel, $mask);
        }
        default { return "Unknown command '$command'; commands are: list, add, remove"; }
    }
}

1;
