# File: BlackList.pm
#
# Purpose: Command to manage list of hostmasks that are not allowed
# to join a channel.

# SPDX-FileCopyrightText: 2015-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::BlackList;
use parent 'PBot::Core::Class';

use PBot::Imports;
use PBot::Core::Utils::IsAbbrev;

sub initialize($self, %conf) {
    $self->{pbot}->{commands}->register(sub { $self->cmd_blacklist(@_) }, "blacklist", 1);

    # add capability to admin group
    $self->{pbot}->{capabilities}->add('admin', 'can-blacklist', 1);
}

sub cmd_blacklist($self, $context) {
    my $arglist = $context->{arglist};
    $self->{pbot}->{interpreter}->lc_args($arglist);

    my $command = $self->{pbot}->{interpreter}->shift_arg($arglist);

    if (not defined $command) {
        return "Usage: blacklist <command>, where commands are: list/show, add, remove";
    }

    my $blacklist = $self->{pbot}->{blacklist}->{storage};

    given (lc $command) {
        when (isabbrev($_, 'list') or isabbrev($_, 'show')) {
            my $blacklist = $self->{pbot}->{blacklist}->{storage};
            my $text    = "Blacklist:\n";
            my $entries = 0;

            foreach my $channel (sort keys %$blacklist) {
                if ($channel eq '.*') {
                    $text .= "  all channels:\n";
                } else {
                    $text .= "  $channel:\n";
                }

                foreach my $mask (sort keys %{$blacklist->{$channel}}) {
                    $text .= "    $mask,\n";
                    $entries++;
                }
            }

            $text .= "none" if $entries == 0;
            return "/msg $context->{nick} $text";
        }

        when (isabbrev($_, 'add')) {
            my ($mask, $channel) = $self->{pbot}->{interpreter}->split_args($arglist, 2);

            if (not defined $mask) {
                return "Usage: blacklist add <hostmask regex> [channel]";
            }

            $channel = '.*' if not defined $channel;

            $self->{pbot}->{logger}->log("$context->{hostmask} added [$mask] to blacklist for channel [$channel]\n");
            $self->{pbot}->{blacklist}->add($channel, $mask);
            return "/say $mask blacklisted in channel $channel";
        }

        when (isabbrev($_, 'remove')) {
            my ($mask, $channel) = $self->{pbot}->{interpreter}->split_args($arglist, 2);

            if (not defined $mask) {
                return "Usage: blacklist remove <hostmask regex> [channel]";
            }

            $channel = '.*' if not defined $channel;

            if (exists $blacklist->{$channel} and not exists $blacklist->{$channel}->{$mask}) {
                return "/say $mask not found in blacklist for channel $channel (use `blacklist list` to display blacklist)";
            }

            $self->{pbot}->{blacklist}->remove($channel, $mask);
            $self->{pbot}->{logger}->log("$context->{hostmask} removed $mask from blacklist for channel $channel\n");
            return "/say $mask removed from blacklist for channel $channel";
        }

        default {
            return "Unknown command '$command'; commands are: list/show, add, remove";
        }
    }
}

1;
