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

  my ($name, $channel, $hostmask, $level, $password) = split / /, $arguments, 5;

  if(not defined $name or not defined $channel or not defined $hostmask or not defined $level
    or not defined $password) {
    return "/msg $nick Usage: adminadd <name> <channel> <hostmask> <level> <password>";
  }

  $channel = '.*' if lc $channel eq 'global';

  $self->{pbot}->{admins}->add_admin($name, $channel, $hostmask, $level, $password);
  return "Admin added.";
}

sub adminrem {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  my ($channel, $hostmask) = split / /, $arguments, 2;

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
  my ($channel, $hostmask, $key, $value) = split / /, $arguments, 4 if defined $arguments;

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

  return $self->{pbot}->{admins}->{admins}->set($channel, $hostmask, $key, $value);
}

sub adminunset {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $hostmask, $key) = split / /, $arguments, 3 if defined $arguments;

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

1;
