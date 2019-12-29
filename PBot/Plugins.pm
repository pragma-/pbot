# File: Plugins.pm
# Author: pragma-
#
# Purpose: Loads and manages plugins.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Plugins;

use warnings;
use strict;

use feature 'unicode_strings';

use File::Basename;
use Carp ();

sub new {
  if (ref($_[1]) eq 'HASH') {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{plugins} = {};

  $self->{pbot}->{commands}->register(sub { $self->load_cmd(@_)   },  "plug",     90);
  $self->{pbot}->{commands}->register(sub { $self->unload_cmd(@_) },  "unplug",   90);
  $self->{pbot}->{commands}->register(sub { $self->reload_cmd(@_) },  "replug",   90);
  $self->{pbot}->{commands}->register(sub { $self->list_cmd(@_)   },  "pluglist",  0);
}

sub autoload {
  my ($self, %conf) = @_;

  return if $self->{pbot}->{registry}->get_value('plugins', 'noautoload');

  my $path = $self->{pbot}->{registry}->get_value('general', 'plugin_dir') // 'Plugins';
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
    $plugin = basename $plugin;
    $plugin =~ s/.pm$//;

    # do not load plugins that begin with an underscore
    next if $plugin =~ m/^_/;

    $plugin_count++ if $self->load($plugin, %conf)
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
    my $mod = $class->new(pbot => $self->{pbot}, %conf);
    $self->{plugins}->{$plugin} = $mod;
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

    my $path = $self->{pbot}->{registry}->get_value('general', 'plugin_dir') // 'Plugins';
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

sub reload_cmd {
   my ($self, $from, $nick, $user, $host, $arguments) = @_;

   if (not length $arguments) {
     return "Usage: replug <plugin>";
   }

   my $unload_result = $self->unload_cmd($from, $nick, $user, $host, $arguments);
   my $load_result = $self->load_cmd($from, $nick, $user, $host, $arguments);

   my $result = "";
   $result .= "$unload_result " if $unload_result =~ m/^Unloaded/;
   $result .= $load_result;
   return $result;
}

sub load_cmd {
   my ($self, $from, $nick, $user, $host, $arguments) = @_;

   if (not length $arguments) {
     return "Usage: plug <plugin>";
   }

   if ($self->load($arguments)) {
     return "Loaded $arguments plugin.";
   } else {
     return "Plugin $arguments failed to load.";
   }
}

sub unload_cmd {
   my ($self, $from, $nick, $user, $host, $arguments) = @_;

   if (not length $arguments) {
     return "Usage: unplug <plugin>";
   }

   if ($self->unload($arguments)) {
     return "Unloaded $arguments plugin.";
   } else {
     return "Plugin $arguments not found.";
   }
}

sub list_cmd {
   my ($self, $from, $nick, $user, $host, $arguments) = @_;

   my $result = "Loaded plugins: ";
   my $count = 0;
   my $comma = '';

   foreach my $plugin (sort keys %{ $self->{plugins} }) {
     $result .= $comma . $plugin;
     $count++;
     $comma = ', ';
   }

   $result .= 'none' if $count == 0;

   return $result;
}

1;
