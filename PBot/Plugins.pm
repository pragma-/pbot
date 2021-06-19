# File: Plugins.pm
#
# Purpose: Loads and manages external plugins.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Plugins;
use parent 'PBot::Class';

use PBot::Imports;

use File::Basename;

sub initialize {
    my ($self, %conf) = @_;
    $self->{plugins} = {};
    $self->{pbot}->{commands}->register(sub { $self->cmd_plug(@_) },     "plug",     1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_unplug(@_) },   "unplug",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_replug(@_) },   "replug",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_pluglist(@_) }, "pluglist", 0);

    # load configured plugins
    $self->autoload(%conf);
}

sub cmd_plug {
    my ($self, $context) = @_;
    my $plugin = $context->{arguments};

    if (not length $plugin) { return "Usage: plug <plugin>"; }

    if   ($self->load($plugin)) { return "Loaded $plugin plugin."; }
    else                        { return "Plugin $plugin failed to load."; }
}

sub cmd_unplug {
    my ($self, $context) = @_;
    my $plugin = $context->{arguments};

    if (not length $plugin) { return "Usage: unplug <plugin>"; }

    if   ($self->unload($plugin)) { return "Unloaded $plugin plugin."; }
    else                          { return "Plugin $plugin is not loaded."; }
}

sub cmd_replug {
    my ($self, $context) = @_;
    my $plugin = $context->{arguments};

    if (not length $plugin) { return "Usage: replug <plugin>"; }

    my $unload_result = $self->cmd_unplug($context);
    my $load_result   = $self->cmd_plug($context);

    my $result = "";
    $result .= "$unload_result " if $unload_result =~ m/^Unloaded/;
    $result .= $load_result;
    return $result;
}

sub cmd_pluglist {
    my ($self, $context) = @_;

    my @plugins = sort keys %{$self->{plugins}};

    return "No plugins loaded." if not @plugins;

    return scalar @plugins . ' plugin' . (@plugins == 1 ? '' : 's') . ' loaded: ' . join (', ', @plugins);
}

sub autoload {
    my ($self, %conf) = @_;
    return if $self->{pbot}->{registry}->get_value('plugins', 'noautoload');

    my $path     = $self->{pbot}->{registry}->get_value('general', 'plugin_dir') // 'Plugins';
    my $data_dir = $self->{pbot}->{registry}->get_value('general', 'data_dir');

    $self->{pbot}->{logger}->log("Loading plugins ...\n");
    my $plugin_count = 0;

    my $fh;
    if (not open $fh, "<$data_dir/plugin_autoload") {
        $self->{pbot}->{logger}->log("warning: file $data_dir/plugin_autoload does not exist; skipping autoloading of Plugins\n");
        return;
    }

    chomp(my @plugins = <$fh>);
    close $fh;

    foreach my $plugin (sort @plugins) {
        # do not load plugins that begin with a comment
        next if $plugin =~ m/^\s*#/;
        next if not length $plugin;

        $plugin = basename $plugin;
        $plugin =~ s/.pm$//;
        $plugin_count++ if $self->load($plugin, %conf);
    }
    $self->{pbot}->{logger}->log("$plugin_count plugin" . ($plugin_count == 1 ? '' : 's') . " loaded.\n");
}

sub load {
    my ($self, $plugin, %conf) = @_;

    $self->unload($plugin);

    return if $self->{pbot}->{registry}->get_value('plugins', 'disabled');

    my $path = $self->{pbot}->{registry}->get_value('general', 'plugin_dir') // 'Plugins';

    if (not grep { $_ eq $path } @INC) {
        unshift @INC, $path;
    }

    $self->{pbot}->{refresher}->{refresher}->refresh_module("$path/$plugin.pm");

    my $ret = eval {
        require "$path/$plugin.pm";

        if ($@) {
            chomp $@;
            $self->{pbot}->{logger}->log("Error loading $plugin: $@\n");
            return 0;
        }

        $self->{pbot}->{logger}->log("Loading $plugin\n");
        my $class = "Plugins::$plugin";
        $self->{plugins}->{$plugin} = $class->new(pbot => $self->{pbot}, %conf);
        $self->{pbot}->{refresher}->{refresher}->update_cache("$path/$plugin.pm");
        return 1;
    };

    if ($@) {
        chomp $@;
        $self->{pbot}->{logger}->log("Error loading $plugin: $@\n");
        return 0;
    }
    return $ret;
}

sub unload {
    my ($self, $plugin) = @_;

    if (exists $self->{plugins}->{$plugin}) {
        eval {
            $self->{plugins}->{$plugin}->unload;
            delete $self->{plugins}->{$plugin};
        };
        if ($@) {
            chomp $@;
            $self->{pbot}->{logger}->log("Warning: got error unloading plugin $plugin: $@\n");
        }

        my $path  = $self->{pbot}->{registry}->get_value('general', 'plugin_dir') // 'Plugins';
        my $class = $path;
        $class =~ s,[/\\],::,g;

        $self->{pbot}->{refresher}->{refresher}->unload_module($class . '::' . $plugin);
        $self->{pbot}->{refresher}->{refresher}->unload_subs("$path/$plugin.pm");

        $self->{pbot}->{logger}->log("Plugin $plugin unloaded.\n");
        return 1;
    } else {
        return 0;
    }
}

1;
