# File: CommandMetadata.pm
#
# Purpose: Registers commands for manipulating command metadata.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::CommandMetadata;

use PBot::Imports;
use parent 'PBot::Core::Class';

sub initialize($self, %conf) {
    # register commands to manipulate command metadata
    $self->{pbot}->{commands}->register(sub { $self->cmd_set(@_) },   "cmdset",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unset(@_) }, "cmdunset", 1);
}

sub cmd_set($self, $context) {
    my ($command, $key, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);

    if (not defined $command) {
        return "Usage: cmdset <command> [key [value]]";
    }

    return $self->{pbot}->{commands}->{metadata}->set($command, $key, $value);
}

sub cmd_unset($self, $context) {
    my ($command, $key) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    if (not defined $command or not defined $key) {
        return "Usage: cmdunset <command> <key>";
    }

    return $self->{pbot}->{commands}->{metadata}->unset($command, $key);
}

1;
