# File: CommandMetadata.pm
#
# Purpose: Registers commands for manipulating command metadata.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Commands::CommandMetadata;

use PBot::Imports;

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

    # register commands to manipulate command metadata
    $self->{pbot}->{commands}->register(sub { $self->cmd_set(@_) },   "cmdset",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unset(@_) }, "cmdunset", 1);
}

sub cmd_set {
    my ($self, $context) = @_;

    my ($command, $key, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);

    if (not defined $command) {
        return "Usage: cmdset <command> [key [value]]";
    }

    return $self->{metadata}->set($command, $key, $value);
}

sub cmd_unset {
    my ($self, $context) = @_;

    my ($command, $key) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    if (not defined $command or not defined $key) {
        return "Usage: cmdunset <command> <key>";
    }

    return $self->{metadata}->unset($command, $key);
}

1;
