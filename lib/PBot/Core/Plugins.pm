# File: Plugins.pm
#
# Purpose: Loads and manages external plugins.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Plugins;
use parent 'PBot::Core::Class';

use PBot::Imports;

use File::Basename;

sub initialize {
    my ($self, %conf) = @_;

    # loaded plugins
    $self->{plugins} = {};

    # autoload plugins listed in `$data_dir/plugins_autoload` file
    $self->autoload(%conf);
}

sub autoload {
    my ($self, %conf) = @_;

    return if $self->{pbot}->{registry}->get_value('plugins', 'noautoload');

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

    my $module = "PBot/Plugin/$plugin.pm";

    $self->{pbot}->{refresher}->{refresher}->refresh_module($module);

    my $ret = eval {
        $self->{pbot}->{logger}->log("Loading $plugin\n");
        require "$module";
        my $class = "PBot::Plugin::$plugin";
        $self->{plugins}->{$plugin} = $class->new(pbot => $self->{pbot}, %conf);
        $self->{pbot}->{refresher}->{refresher}->update_cache($module);
        return 1;
    };

    if (my $exception = $@) {
        $self->{pbot}->{logger}->log("Error loading $plugin: $exception");
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

        if (my $exception = $@) {
            $self->{pbot}->{logger}->log("Warning: got error unloading plugin $plugin: $exception");
        }

        my $module = "PBot/Plugin/$plugin.pm";
        $self->{pbot}->{refresher}->{refresher}->unload_module($module);
        $self->{pbot}->{logger}->log("Plugin $plugin unloaded.\n");
        return 1;
    } else {
        return 0;
    }
}

1;
