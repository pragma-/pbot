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

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
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
  if(not defined $pbot) {
    Carp::croak("Missing pbot reference to BotAdminCommands");
  }

  $self->{pbot} = $pbot;
  
  $pbot->{commands}->register(sub { return $self->login(@_)        },       "login",         0);
  $pbot->{commands}->register(sub { return $self->logout(@_)       },       "logout",        0);
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

  $self->{pbot}->{conn}->sl($arguments);
  return "";
}

sub login {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if($self->{pbot}->{admins}->loggedin($from, "$nick!$user\@$host")) {
    return "/msg $nick You are already logged into channel $from.";
  }

  my $result = $self->{pbot}->{admins}->login($from, "$nick!$user\@$host", $arguments);
  return "/msg $nick $result";
}

sub logout {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  return "/msg $nick Uh, you aren't logged into channel $from." if(not $self->{pbot}->{admins}->loggedin($from, "$nick!$user\@$host"));
  $self->{pbot}->{admins}->logout($from, "$nick!$user\@$host");
  return "/msg $nick Good-bye, $nick.";
}

sub adminadd {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  my ($name, $channel, $hostmask, $level, $password) = split /\s+/, $arguments, 5;

  if(not defined $name or not defined $channel or not defined $hostmask or not defined $level
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
  my ($from, $nick, $user, $host, $arguments) = @_;

  my ($channel, $hostmask) = split /\s+/, $arguments, 2;

  if(not defined $channel or not defined $hostmask) {
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

  if($self->{pbot}->{admins}->remove_admin($channel, $hostmask)) {
    return "Admin removed.";
  } else {
    return "No such admin found.";
  }
}

sub adminset {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $hostmask, $key, $value) = split /\s+/, $arguments, 4 if defined $arguments;

  if(not defined $channel or not defined $hostmask) {
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

  return $self->{pbot}->{admins}->{admins}->set($channel, $hostmask, $key, $value);
}

sub adminunset {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $hostmask, $key) = split /\s+/, $arguments, 3 if defined $arguments;

  if(not defined $channel or not defined $hostmask) {
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

  foreach my $channel (split /\s+/, $arguments) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host made me join $channel\n");
    $self->{pbot}->{chanops}->join_channel($channel);
  }

  return "/msg $nick Joining $arguments";
}

sub part_channel {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  $arguments = $from if not $arguments;

  foreach my $channel (split /\s+/, $arguments) {
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

  if(not defined $arguments) {
    return "/msg $nick Usage: export <modules|factoids|admins>";
  }

  if($arguments =~ /^modules$/i) {
    return "/msg $nick Coming soon.";
  }

  if($arguments =~ /^factoids$/i) {
    return $self->{pbot}->{factoids}->export_factoids; 
  }

  if($arguments =~ /^admins$/i) {
    return "/msg $nick Coming soon.";
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

  given ($arguments) {
    when ("blacklist") {
      $self->{pbot}->{blacklist}->clear_blacklist;
      $self->{pbot}->{blacklist}->load_blacklist;
      return "Blacklist reloaded.";
    }

    when ("whitelist") {
      $self->{pbot}->{antiflood}->{whitelist}->clear;
      $self->{pbot}->{antiflood}->{whitelist}->load;
      return "Whitelist reloaded.";
    }

    when ("ignores") {
      $self->{pbot}->{ignorelist}->clear_ignores;
      $self->{pbot}->{ignorelist}->load_ignores;
      return "Ignore list reloaded.";
    }

    when ("admins") {
      $self->{pbot}->{admins}->{admins}->clear;
      $self->{pbot}->{admins}->load_admins;
      return "Admins reloaded.";
    }

    when ("channels") {
      $self->{pbot}->{channels}->{channels}->clear;
      $self->{pbot}->{channels}->load_channels;
      return "Channels reloaded.";
    }

    when ("bantimeouts") {
      $self->{pbot}->{chanops}->{unban_timeout}->clear;
      $self->{pbot}->{chanops}->{unban_timeout}->load;
      return "Ban timeouts reloaded.";
    }

    when ("mutetimeouts") {
      $self->{pbot}->{chanops}->{unmute_timeout}->clear;
      $self->{pbot}->{chanops}->{unmute_timeout}->load;
      return "Mute timeouts reloaded.";
    }

    when ("registry") {
      $self->{pbot}->{registry}->{registry}->clear;
      $self->{pbot}->{registry}->load;
      return "Registry reloaded.";
    }

    when ("factoids") {
      $self->{pbot}->{factoids}->{factoids}->clear;
      $self->{pbot}->{factoids}->load_factoids;
      return "Factoids reloaded.";
    }

    default {
      return "Usage: reload <blacklist|whitelist|ignores|admins|channels|bantimeouts|mutetimeouts|registry|factoids>";
    }
  }
}

1;
