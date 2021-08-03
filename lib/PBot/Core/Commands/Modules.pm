# File: Modules.pm
#
# Purpose: Registers commands to load and unload PBot modules.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::Modules;
use parent 'PBot::Core::Class';

use PBot::Imports;

use IPC::Run qw/run timeout/;
use Encode;

sub initialize {
    my ($self, %conf) = @_;

    # bot commands to load and unload modules
    $self->{pbot}->{commands}->register(sub { $self->cmd_load(@_) },   "load",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unload(@_) }, "unload", 1);
}

sub cmd_load {
    my ($self, $context) = @_;

    my ($keyword, $module) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    return "Usage: load <keyword> <module>" if not defined $module;

    my $factoids = $self->{pbot}->{factoids}->{data}->{storage};

    if ($factoids->exists('.*', $keyword)) {
        return 'There is already a keyword named ' . $factoids->get_data('.*', $keyword, '_name') . '.';
    }

    $self->{pbot}->{factoids}->{data}->add('module', '.*', $context->{hostmask}, $keyword, $module, 1);

    $factoids->set('.*', $keyword, 'add_nick',   1, 1);
    $factoids->set('.*', $keyword, 'nooverride', 1);

    $self->{pbot}->{logger}->log("$context->{hostmask} loaded module $keyword => $module\n");

    return "Loaded module $keyword => $module";
}

sub cmd_unload {
    my ($self, $context) = @_;

    my $module = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    return "Usage: unload <keyword>" if not defined $module;

    my $factoids = $self->{pbot}->{factoids}->{data}->{storage};

    if (not $factoids->exists('.*', $module)) {
        return "/say $module not found.";
    }

    if ($factoids->get_data('.*', $module, 'type') ne 'module') {
        return "/say " . $factoids->get_data('.*', $module, '_name') . ' is not a module.';
    }

    my $name = $factoids->get_data('.*', $module, '_name');

    $factoids->remove('.*', $module);

    $self->{pbot}->{logger}->log("$context->{hostmask} unloaded module $module\n");

    return "/say $name unloaded.";
}

1;
