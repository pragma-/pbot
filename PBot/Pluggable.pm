# File: Pluggable.pm
# Author: pragma-
#
# Purpose: Loads and manages pluggable modules.

package PBot::Pluggable;

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

  $self->{modules} = {};

  $self->{pbot}->{commands}->register(sub { $self->load_cmd(@_)   },  "plug",     90);
  $self->{pbot}->{commands}->register(sub { $self->unload_cmd(@_) },  "unplug",   90);
  $self->{pbot}->{commands}->register(sub { $self->list_cmd(@_)   },  "pluglist",  0);

  $self->autoload();
}

sub autoload {
  my $self = shift;

  $self->{pbot}->{logger}->log("Loading pluggable modules ...\n");
  my $module_count = 0;

  my @modules = glob 'PBot/Pluggable/*.pm';

  foreach my $module (sort @modules) {
    $module = basename $module;
    $module =~ s/.pm$//;

    # do not load modules that begin with an underscore
    next if $module =~ m/^_/;

    $module_count++ if $self->load($module)
  }

  $self->{pbot}->{logger}->log("$module_count module" . ($module_count == 1 ? '' : 's') . " loaded.\n");
}

sub load {
  my ($self, $module) = @_;

  $self->unload($module);

  my $class = "PBot::Pluggable::$module";

  $self->{pbot}->{refresher}->{refresher}->refresh_module("PBot/Pluggable/$module.pm");

  my $ret = eval { 
    eval "require $class";

    if ($@) {
      chomp $@;
      $self->{pbot}->{logger}->log("Error loading $module: $@\n");
      return 0;
    }

    $self->{pbot}->{logger}->log("Loading $module\n");
    my $mod = $class->new(pbot => $self->{pbot});
    $self->{modules}->{$module} = $mod;
    $self->{pbot}->{refresher}->{refresher}->update_cache("PBot/Pluggable/$module.pm");
    return 1;
  };

  if ($@) {
    chomp $@;
    $self->{pbot}->{logger}->log("Error loading $module: $@\n");
    return 0;
  }

  return $ret;
}

sub unload {
  my ($self, $module) = @_;

  $self->{pbot}->{refresher}->{refresher}->unload_module("PBot::Pluggable::$module");
  $self->{pbot}->{refresher}->{refresher}->unload_subs("PBot/Pluggable/$module.pm");

  if (exists $self->{modules}->{$module}) {
    eval {
      $self->{modules}->{$module}->unload;
      delete $self->{modules}->{$module};
    };
    if ($@) {
      chomp $@;
      $self->{pbot}->{logger}->log("Warning: got error unloading module $module: $@\n");
    }
    $self->{pbot}->{logger}->log("Pluggable module $module unloaded.\n");
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
     return "Plugin $arguments not found.";
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

   foreach my $plugin (sort keys $self->{modules}) {
     $result .= $comma . $plugin;
     $count++;
     $comma = ', ';
   }

   $result .= 'none' if $count == 0;

   return $result;
}

1;
