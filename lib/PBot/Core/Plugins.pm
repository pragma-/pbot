# File: Plugins.pm
#
# Purpose: Loads and manages external plugins.

# SPDX-FileCopyrightText: 2015-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Plugins;
use parent 'PBot::Core::Class';

use PBot::Imports;

use File::Basename;

sub initialize($self, %conf) {
    # loaded plugins
    $self->{plugins} = {};

    # autoload plugins listed in `$data_dir/plugins_autoload` file
    $self->autoload(%conf);
}

sub autoload($self, %conf) {
    return if $self->{pbot}->{registry}->get_value('plugins', 'noautoload');

    my $data_dir = $self->{pbot}->{registry}->get_value('general', 'data_dir');

    my $plugin_count = 0;

    my $fh;
    if (not open $fh, "<$data_dir/plugin_autoload") {
        $self->{pbot}->{logger}->log("Plugins: autoload: file $data_dir/plugin_autoload does not exist; skipping autoloading of Plugins\n");
        return;
    }
    chomp(my @plugins = <$fh>);
    close $fh;

    $self->{pbot}->{logger}->log("Loading plugins:\n");

    $conf{quiet} = 1;

    foreach my $plugin (sort @plugins) {
        # do not load plugins that begin with a comment
        next if $plugin =~ m/^\s*#/;
        next if not length $plugin;

        $plugin = basename $plugin;
        $plugin =~ s/.pm$//;

        $self->{pbot}->{logger}->log("  $plugin\n");

        if ($self->load($plugin, %conf)) {
            $plugin_count++;
        } else {
            die "Plugin $plugin failed to autoload. You may remove it from $data_dir/plugin_autoload.\n";
        }
    }

    $self->{pbot}->{logger}->log("$plugin_count plugin" . ($plugin_count == 1 ? '' : 's') . " loaded.\n");
}

sub load($self, $plugin, %conf) {
    $self->unload($plugin);

    return if $self->{pbot}->{registry}->get_value('plugins', 'disabled');

    my $module = "PBot/Plugin/$plugin.pm";

    $self->{pbot}->{refresher}->{refresher}->refresh_module($module);

    my $ret = eval {
        $self->{pbot}->{logger}->log("Loading $plugin\n") unless $conf{quiet};
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

sub unload($self, $plugin) {
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
