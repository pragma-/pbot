# File: BotAdminCommands.pm
# Author: pragma_
#
# Purpose: Administrative command subroutines.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::BotAdminCommands;

use warnings;
use strict;

use feature 'unicode_strings';

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use Carp ();

sub new {
  if (ref($_[1]) eq 'HASH') {
    Carp::croak("Options to BotAdminCommands should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot};
  if (not defined $pbot) {
    Carp::croak("Missing pbot reference to BotAdminCommands");
  }

  $self->{pbot} = $pbot;

  $pbot->{commands}->register(sub { return $self->login(@_)        },       "login",         0);
  $pbot->{commands}->register(sub { return $self->logout(@_)       },       "logout",        0);
  $pbot->{commands}->register(sub { return $self->in_channel(@_)   },       "in",            0);
  $pbot->{commands}->register(sub { return $self->join_channel(@_) },       "join",          40);
  $pbot->{commands}->register(sub { return $self->part_channel(@_) },       "part",          40);
  $pbot->{commands}->register(sub { return $self->ack_die(@_)      },       "die",           90);
  $pbot->{commands}->register(sub { return $self->adminadd(@_)     },       "adminadd",      60);
  $pbot->{commands}->register(sub { return $self->adminrem(@_)     },       "adminrem",      60);
  $pbot->{commands}->register(sub { return $self->adminset(@_)     },       "adminset",      60);
  $pbot->{commands}->register(sub { return $self->adminunset(@_)   },       "adminunset",    60);
  $pbot->{commands}->register(sub { return $self->sl(@_)           },       "sl",            90);
  $pbot->{commands}->register(sub { return $self->export(@_)       },       "export",        90);
  $pbot->{commands}->register(sub { return $self->reload(@_)       },       "reload",        90);
  $pbot->{commands}->register(sub { return $self->evalcmd(@_)      },       "eval",          99);
}

sub sl {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if (not length $arguments) {
    return "Usage: sl <ircd command>";
  }

  $self->{pbot}->{conn}->sl($arguments);
  return "";
}

sub in_channel {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my $usage = "Usage: in <channel> <command>";

  if (not $arguments) {
    return $usage;
  }

  my ($channel, $command) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);
  return $usage if not defined $channel or not defined $command;

  $stuff->{admin_channel_override} = $channel;
  $stuff->{command} = $command;
  return $self->{pbot}->{interpreter}->interpret($stuff);
}

sub login {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $channel = $from;

  if (not $arguments) {
    return "Usage: login [channel] password";
  }

  if ($arguments =~ m/^([^ ]+)\s+(.+)/) {
    $channel = $1;
    $arguments = $2;
  }

  if ($self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
    return "/msg $nick You are already logged into channel $channel.";
  }

  my $result = $self->{pbot}->{admins}->login($channel, "$nick!$user\@$host", $arguments);
  return "/msg $nick $result";
}

sub logout {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  return "/msg $nick Uh, you aren't logged into channel $from." if (not $self->{pbot}->{admins}->loggedin($from, "$nick!$user\@$host"));
  $self->{pbot}->{admins}->logout($from, "$nick!$user\@$host");
  return "/msg $nick Good-bye, $nick.";
}

sub adminadd {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;

  my ($name, $channel, $hostmask, $level, $password) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 5);

  if (not defined $name or not defined $channel or not defined $hostmask or not defined $level
    or not defined $password) {
    return "/msg $nick Usage: adminadd <name> <channel> <hostmask> <level> <password>";
  }

  $channel = '.*' if lc $channel eq 'global';

  my $admin  = $self->{pbot}->{admins}->find_admin($from, "$nick!$user\@$host");

  if (not $admin) {
    return "You are not an admin in $from.\n";
  }

  if ($admin->{level} < 90 and $level > 60) {
    return "You may not set admin level higher than 60.\n";
  }

  $self->{pbot}->{admins}->add_admin($name, $channel, $hostmask, $level, $password);
  return "Admin added.";
}

sub adminrem {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;

  my ($channel, $hostmask) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (not defined $channel or not defined $hostmask) {
    return "/msg $nick Usage: adminrem <channel> <hostmask/name>";
  }

  $channel = lc $channel;
  $hostmask = lc $hostmask;

  $channel = '.*' if $channel eq 'global';

  if (exists $self->{pbot}->{admins}->{admins}->hash->{$channel}) {
    if (not exists $self->{pbot}->{admins}->{admins}->hash->{$channel}->{$hostmask}) {
      foreach my $mask (keys %{ $self->{pbot}->{admins}->{admins}->hash->{$channel} }) {
        if ($self->{pbot}->{admins}->{admins}->hash->{$channel}->{$mask}->{name} eq $hostmask) {
          $hostmask = $mask;
          last;
        }
      }
    }
  }

  if ($self->{pbot}->{admins}->remove_admin($channel, $hostmask)) {
    return "Admin removed.";
  } else {
    return "No such admin found.";
  }
}

sub adminset {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($channel, $hostmask, $key, $value) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 4);

  if (not defined $channel or not defined $hostmask) {
    return "Usage: adminset <channel> <hostmask/name> [key] [value]";
  }

  $channel = lc $channel;
  $hostmask = lc $hostmask;

  $channel = '.*' if $channel eq 'global';

  if (exists $self->{pbot}->{admins}->{admins}->hash->{$channel}) {
    if (not exists $self->{pbot}->{admins}->{admins}->hash->{$channel}->{$hostmask}) {
      foreach my $mask (keys %{ $self->{pbot}->{admins}->{admins}->hash->{$channel} }) {
        if ($self->{pbot}->{admins}->{admins}->hash->{$channel}->{$mask}->{name} eq $hostmask) {
          $hostmask = $mask;
          last;
        }
      }
    }
  }

  my $admin  = $self->{pbot}->{admins}->find_admin($from, "$nick!$user\@$host");
  my $target = $self->{pbot}->{admins}->find_admin($channel, $hostmask);

  if (not $admin) {
    return "You are not an admin in $from.";
  }

  if (not $target) {
    return "There is no admin $hostmask in channel $channel.";
  }

  if ($key eq 'level' && $admin->{level} < 90 and $value > 60) {
    return "You may not set admin level higher than 60.\n";
  }

  if ($target->{level} > $admin->{level}) {
    return "You may not modify admins higher in level than you.";
  }

  my $result = $self->{pbot}->{admins}->{admins}->set($channel, $hostmask, $key, $value);
  $result =~ s/^password => .*;$/password => <private>;/m;
  return $result;
}

sub adminunset {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($channel, $hostmask, $key) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

  if (not defined $channel or not defined $hostmask) {
    return "Usage: adminunset <channel> <hostmask/name> <key>";
  }

  $channel = lc $channel;
  $hostmask = lc $hostmask;

  $channel = '.*' if $channel eq 'global';

  if (exists $self->{pbot}->{admins}->{admins}->hash->{$channel}) {
    if (not exists $self->{pbot}->{admins}->{admins}->hash->{$channel}->{$hostmask}) {
      foreach my $mask (keys %{ $self->{pbot}->{admins}->{admins}->hash->{$channel} }) {
        if ($self->{pbot}->{admins}->{admins}->hash->{$channel}->{$mask}->{name} eq $hostmask) {
          $hostmask = $mask;
          last;
        }
      }
    }
  }

  return $self->{pbot}->{admins}->{admins}->unset($channel, $hostmask, $key);
}


sub join_channel {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  foreach my $channel (split /[\s+,]/, $arguments) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host made me join $channel\n");
    $self->{pbot}->{chanops}->join_channel($channel);
  }

  return "/msg $nick Joining $arguments";
}

sub part_channel {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  $arguments = $from if not $arguments;

  foreach my $channel (split /[\s+,]/, $arguments) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host made me part $channel\n");
    $self->{pbot}->{chanops}->part_channel($channel);
  }

  return "/msg $nick Parting $arguments";
}

sub ack_die {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  $self->{pbot}->{logger}->log("$nick!$user\@$host made me exit.\n");
  $self->{pbot}->atexit();
  $self->{pbot}->{conn}->privmsg($from, "Good-bye.") if defined $from;
  $self->{pbot}->{conn}->quit("Departure requested.");
  exit 0;
}

sub export {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if (not defined $arguments) {
    return "/msg $nick Usage: export <factoids>";
  }

  if ($arguments =~ /^factoids$/i) {
    return $self->{pbot}->{factoids}->export_factoids;
  }
}

sub evalcmd {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  $self->{pbot}->{logger}->log("[$from] $nick!$user\@$host Evaluating [$arguments]\n");

  my $ret;
  my $result = eval $arguments;
  if ($@) {
    if (length $result) {
      $ret .= "[Error: $@] ";
    } else {
      $ret .= "Error: $@";
    }
    $ret =~ s/ at \(eval \d+\) line 1.//;
  }
  return "/say $ret $result";
}

sub reload {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  my %reloadables = (
    'blacklist' => sub {
      $self->{pbot}->{blacklist}->clear_blacklist;
      $self->{pbot}->{blacklist}->load_blacklist;
      return "Blacklist reloaded.";
    },

    'whitelist' => sub {
      $self->{pbot}->{antiflood}->{whitelist}->clear;
      $self->{pbot}->{antiflood}->{whitelist}->load;
      return "Whitelist reloaded.";
    },

    'ignores' => sub {
      $self->{pbot}->{ignorelist}->clear_ignores;
      $self->{pbot}->{ignorelist}->load_ignores;
      return "Ignore list reloaded.";
    },

    'admins' => sub {
      $self->{pbot}->{admins}->{admins}->clear;
      $self->{pbot}->{admins}->load_admins;
      return "Admins reloaded.";
    },

    'channels' => sub {
      $self->{pbot}->{channels}->{channels}->clear;
      $self->{pbot}->{channels}->load_channels;
      return "Channels reloaded.";
    },

    'bantimeouts' => sub {
      $self->{pbot}->{chanops}->{unban_timeout}->clear;
      $self->{pbot}->{chanops}->{unban_timeout}->load;
      return "Ban timeouts reloaded.";
    },

    'mutetimeouts' => sub {
      $self->{pbot}->{chanops}->{unmute_timeout}->clear;
      $self->{pbot}->{chanops}->{unmute_timeout}->load;
      return "Mute timeouts reloaded.";
    },

    'registry' => sub {
      $self->{pbot}->{registry}->{registry}->clear;
      $self->{pbot}->{registry}->load;
      return "Registry reloaded.";
    },

    'factoids' => sub {
      $self->{pbot}->{factoids}->{factoids}->clear;
      $self->{pbot}->{factoids}->load_factoids;
      return "Factoids reloaded.";
    },

    'funcs' => sub {
      $self->{pbot}->{func_cmd}->init_funcs;
      return "Funcs reloaded.";
    }
  );

  if (not length $arguments or not exists $reloadables{$arguments}) {
    my $usage = 'Usage: reload <';
    $usage .= join '|', sort keys %reloadables;
    $usage .= '>';
    return $usage;
  }

  return $reloadables{$arguments}();
}

1;
