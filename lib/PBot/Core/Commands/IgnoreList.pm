# File: IgnoreList.pm
#
# Purpose: Commands to manage ignore list.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::IgnoreList;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::Duration qw/concise duration/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->register(sub { $self->cmd_ignore(@_) },   "ignore",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unignore(@_) }, "unignore", 1);

    # add capabilites to admin group
    $self->{pbot}->{capabilities}->add('admin', 'can-ignore',   1);
    $self->{pbot}->{capabilities}->add('admin', 'can-unignore', 1);

    # add capabilities to chanop group
    $self->{pbot}->{capabilities}->add('chanop', 'can-ignore',   1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-unignore', 1);
}

sub cmd_ignore {
    my ($self, $context) = @_;

    my ($target, $channel, $length) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);

    if (not defined $target) {
        return "Usage: ignore <hostmask> [channel [timeout]] | ignore list";
    }

    if ($target =~ /^list$/i) {
        my $text = "Ignored:\n\n";
        my $now  = time;
        my $ignored = 0;

        my $ignorelist = $self->{pbot}->{ignorelist}->{storage};

        foreach my $channel (sort $ignorelist->get_keys) {
            $text .= $channel eq '.*' ? "global:\n" : "$channel:\n";

            my @list;
            foreach my $hostmask (sort $ignorelist->get_keys($channel)) {
                my $timeout = $ignorelist->get_data($channel, $hostmask, 'timeout');

                if ($timeout == -1) {
                    push @list, "  $hostmask";
                } else {
                    push @list, "  $hostmask (" . (concise duration $timeout - $now) . ')';
                }

                $ignored++;
            }

            $text .= join ";\n", @list;
            $text .= "\n";
        }

        return "Ignore list is empty." if not $ignored;
        return "/msg $context->{nick} $text";
    }

    if (not defined $channel) {
        $channel = ".*";    # all channels
    }

    if (not defined $length) {
        $length = -1;       # permanently
    } else {
        my $error;
        ($length, $error) = $self->{pbot}->{parsedate}->parsedate($length);
        return $error if defined $error;
    }

    return $self->{pbot}->{ignorelist}->add($channel, $target, $length, $context->{hostmask});
}

sub cmd_unignore {
    my ($self, $context) = @_;

    my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    if (not defined $target) {
        return "Usage: unignore <hostmask> [channel]";
    }

    if (not defined $channel) {
        $channel = '.*';
    }

    return $self->{pbot}->{ignorelist}->remove($channel, $target);
}

1;
