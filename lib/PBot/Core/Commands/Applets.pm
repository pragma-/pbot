# File: Applets.pm
#
# Purpose: Registers commands to load and unload PBot applets.

# SPDX-FileCopyrightText: 2007-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::Applets;
use parent 'PBot::Core::Class';

use PBot::Imports;

use IPC::Run qw/run timeout/;
use Encode;

sub initialize($self, %conf) {
    # bot commands to load and unload applets
    $self->{pbot}->{commands}->register(sub { $self->cmd_load(@_) },   "load",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unload(@_) }, "unload", 1);
}

sub cmd_load($self, $context) {
    my ($keyword, $applet) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    return "Usage: load <keyword> <applet>" if not defined $applet;

    my $factoids = $self->{pbot}->{factoids}->{data}->{storage};

    if ($factoids->exists('.*', $keyword)) {
        return 'There is already a keyword named ' . $factoids->get_data('.*', $keyword, '_name') . '.';
    }

    $self->{pbot}->{factoids}->{data}->add('applet', '.*', $context->{hostmask}, $keyword, $applet, 1);

    $factoids->set('.*', $keyword, 'add_nick',   1, 1);
    $factoids->set('.*', $keyword, 'nooverride', 1);

    $self->{pbot}->{logger}->log("$context->{hostmask} loaded applet $keyword => $applet\n");

    return "Loaded applet $keyword => $applet";
}

sub cmd_unload($self, $context) {
    my $applet = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    return "Usage: unload <keyword>" if not defined $applet;

    my $factoids = $self->{pbot}->{factoids}->{data}->{storage};

    if (not $factoids->exists('.*', $applet)) {
        return "/say $applet not found.";
    }

    if ($factoids->get_data('.*', $applet, 'type') ne 'applet') {
        return "/say " . $factoids->get_data('.*', $applet, '_name') . ' is not an applet.';
    }

    my $name = $factoids->get_data('.*', $applet, '_name');

    $factoids->remove('.*', $applet);

    $self->{pbot}->{logger}->log("$context->{hostmask} unloaded applet $applet\n");

    return "/say $name unloaded.";
}

1;
