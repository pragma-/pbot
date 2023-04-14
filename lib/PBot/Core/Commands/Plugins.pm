# File: Plugins.pm
#
# Purpose: Registers commands for loading and unloading plugins.

# SPDX-FileCopyrightText: 2015-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::Plugins;

use PBot::Imports;
use parent 'PBot::Core::Class';

use File::Basename;

sub initialize($self, %conf) {
    # plugin management bot commands
    $self->{pbot}->{commands}->register(sub { $self->cmd_plug(@_) },     "plug",     1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unplug(@_) },   "unplug",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_replug(@_) },   "replug",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_pluglist(@_) }, "pluglist", 0);
}

sub cmd_plug($self, $context) {
    my $plugin = $context->{arguments};

    if (not length $plugin) { return "Usage: plug <plugin>"; }

    if ($self->{pbot}->{plugins}->load($plugin)) {
        return "Loaded $plugin plugin.";
    } else {
        return "Plugin $plugin failed to load.";
    }
}

sub cmd_unplug($self, $context) {
    my $plugin = $context->{arguments};

    if (not length $plugin) { return "Usage: unplug <plugin>"; }

    if ($self->{pbot}->{plugins}->unload($plugin)) {
        return "Unloaded $plugin plugin.";
    } else {
        return "Plugin $plugin is not loaded.";
    }
}

sub cmd_replug($self, $context) {
    my $plugin = $context->{arguments};

    if (not length $plugin) { return "Usage: replug <plugin>"; }

    my $unload_result = $self->cmd_unplug($context);
    my $load_result   = $self->cmd_plug($context);

    my $result;
    $result .= "$unload_result " if $unload_result =~ m/^Unloaded/;
    $result .= $load_result;
    return $result;
}

sub cmd_pluglist($self, $context) {
    my @plugins = sort keys %{$self->{pbot}->{plugins}->{plugins}};

    return "No plugins loaded." if not @plugins;

    return scalar @plugins . ' plugin' . (@plugins == 1 ? '' : 's') . ' loaded: ' . join (', ', @plugins);
}

1;
