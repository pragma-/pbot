# File: Plugins.pm
# Author: pragma-
#
# Purpose: Loads and manages plugins.

package PBot::Plugins;

use warnings;
use strict;

use File::Basename;
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
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
  $self->{pbot}->{commands}->register(sub { $self->list_cmd(@_)   },  "pluglist",  0);

  $self->autoload(%conf);
}

sub autoload {
  my ($self, %conf) = @_;

  $self->{pbot}->{logger}->log("Loading plugins ...\n");
  my $plugin_count = 0;

  my @plugins = glob 'PBot/Plugins/*.pm';

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

  my $class = "PBot::Plugins::$plugin";

  $self->{pbot}->{refresher}->{refresher}->refresh_module("PBot/Plugins/$plugin.pm");

  my $ret = eval { 
    eval "require $class";

    if ($@) {
      chomp $@;
      $self->{pbot}->{logger}->log("Error loading $plugin: $@\n");
      return 0;
    }

    $self->{pbot}->{logger}->log("Loading $plugin\n");
    my $mod = $class->new(pbot => $self->{pbot}, %conf);
    $self->{plugins}->{$plugin} = $mod;
    $self->{pbot}->{refresher}->{refresher}->update_cache("PBot/Plugins/$plugin.pm");
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

  $self->{pbot}->{refresher}->{refresher}->unload_module("PBot::Plugins::$plugin");
  $self->{pbot}->{refresher}->{refresher}->unload_subs("PBot/Plugins/$plugin.pm");

  if (exists $self->{plugins}->{$plugin}) {
    eval {
      $self->{plugins}->{$plugin}->unload;
      delete $self->{plugins}->{$plugin};
    };
    if ($@) {
      chomp $@;
      $self->{pbot}->{logger}->log("Warning: got error unloading plugin $plugin: $@\n");
    }
    $self->{pbot}->{logger}->log("Plugin $plugin unloaded.\n");
    return 1;
  } else {
    return 0;
  }
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
     return "Plugin $arguments failed to load.";
   }
}

sub list_cmd {
   my ($self, $from, $nick, $user, $host, $arguments) = @_;

   my $result = "Loaded plugins: ";
   my $count = 0;
   my $comma = '';

   foreach my $plugin (sort keys $self->{plugins}) {
     $result .= $comma . $plugin;
     $count++;
     $comma = ', ';
   }

   $result .= 'none' if $count == 0;

   return $result;
}

1;
