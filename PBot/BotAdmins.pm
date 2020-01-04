# File: BotAdmins.pm
# Author: pragma_
#
# Purpose: Manages list of bot admins and whether they are logged in.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::BotAdmins;

use warnings;
use strict;

use feature 'unicode_strings';

use PBot::DualIndexHashObject;
use PBot::BotAdminCommands;

use Carp ();

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot}     = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{admins}   = PBot::DualIndexHashObject->new(name => 'Admins', filename => $conf{filename}, pbot => $conf{pbot});
  $self->{commands} = PBot::BotAdminCommands->new(pbot => $conf{pbot});
  $self->load_admins;
}

sub add_admin {
  my $self = shift;
  my ($name, $channel, $hostmask, $level, $password, $dont_save) = @_;
  $channel = lc $channel;
  $channel = '.*' if $channel !~ m/^#/;
  $hostmask = lc $hostmask;
  $self->{admins}->hash->{$channel}->{$hostmask}->{name}     = $name;
  $self->{admins}->hash->{$channel}->{$hostmask}->{level}    = $level;
  $self->{admins}->hash->{$channel}->{$hostmask}->{password} = $password;
  $self->{pbot}->{logger}->log("Adding new level $level admin: [$name] [$hostmask] for channel [$channel]\n");
  $self->save_admins unless $dont_save;
}

sub remove_admin {
  my $self = shift;
  my ($channel, $hostmask) = @_;

  $channel = lc $channel;
  $hostmask = lc $hostmask;
  $channel = '.*' if $channel !~ m/^#/;

  my $admin = delete $self->{admins}->hash->{$channel}->{$hostmask};

  if (not keys %{$self->{admins}->hash->{$channel}}) {
    delete $self->{admins}->hash->{$channel};
  }

  if (defined $admin) {
    $self->{pbot}->{logger}->log("Removed level $admin->{level} admin [$admin->{name}] [$hostmask] from channel [$channel]\n");
    $self->save_admins;
    return 1;
  } else {
    $self->{pbot}->{logger}->log("Attempt to remove non-existent admin [$hostmask] from channel [$channel]\n");
    return 0;
  }
}

sub load_admins {
  my $self = shift;
  my $filename;

  if (@_) { $filename = shift; } else { $filename = $self->{admins}->filename; }

  if (not defined $filename) {
    Carp::carp "No admins path specified -- skipping loading of admins";
    return;
  }

  $self->{admins}->load;

  my $i = 0;
  foreach my $channel (keys %{ $self->{admins}->hash } ) {
    foreach my $hostmask (keys %{ $self->{admins}->hash->{$channel} }) {
      $i++;
      my $name = $self->{admins}->hash->{$channel}->{$hostmask}->{name};
      my $level = $self->{admins}->hash->{$channel}->{$hostmask}->{level};
      my $password = $self->{admins}->hash->{$channel}->{$hostmask}->{password};

      if (not defined $name or not defined $level or not defined $password) {
        Carp::croak "Admin #$i of $filename is missing critical data\n";
      }

      $self->{pbot}->{logger}->log("Adding new level $level admin: [$name] [$hostmask] for channel [$channel]\n");
    }
  }

  $self->{pbot}->{logger}->log("  $i admins loaded.\n");
}

sub save_admins {
  my $self = shift;
  $self->{admins}->save;
}

sub find_admin {
  my ($self, $from, $hostmask) = @_;

  $from = $self->{pbot}->{registry}->get_value('irc', 'botnick') if not defined $from;
  $hostmask = '.*' if not defined $hostmask;
  $hostmask = lc $hostmask;

  my $result = eval {
    foreach my $channel_regex (keys %{ $self->{admins}->hash }) {
      if ($from !~ m/^#/ or $from =~ m/^$channel_regex$/i) {
        foreach my $hostmask_regex (keys %{ $self->{admins}->hash->{$channel_regex} }) {
          if ($hostmask_regex =~ m/\.\*/) {
            # contains .* so it's considered a regex
            return $self->{admins}->hash->{$channel_regex}->{$hostmask_regex} if $hostmask =~ m/^$hostmask_regex$/i;
          } elsif ($hostmask_regex =~ m/\*/) {
            # contains * so it's converted to a regex
            my $hostmask_quoted = quotemeta $hostmask_regex;
            $hostmask_quoted =~ s/\\\*/.*/g;
            return $self->{admins}->hash->{$channel_regex}->{$hostmask_regex} if $hostmask =~ m/^$hostmask_quoted$/i;
          } else {
            # direct comparison
            return $self->{admins}->hash->{$channel_regex}->{$hostmask_regex} if $hostmask eq lc $hostmask_regex;
          }
        }
      }
    }
    return undef;
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Error in find_admin parameters: $@\n");
  }

  return $result;
}

sub loggedin {
  my ($self, $channel, $hostmask) = @_;
  my $admin = $self->find_admin($channel, $hostmask);

  if (defined $admin && $admin->{loggedin}) {
    return $admin;
  } else {
    return undef;
  }
}

sub login {
  my ($self, $channel, $hostmask, $password) = @_;
  my $admin = $self->find_admin($channel, $hostmask);

  if (not defined $admin) {
    $self->{pbot}->{logger}->log("Attempt to login non-existent [$channel][$hostmask] failed\n");
    return "You do not have an account in $channel.";
  }

  if ($admin->{password} ne $password) {
    $self->{pbot}->{logger}->log("Bad login password for [$channel][$hostmask]\n");
    return "I don't think so.";
  }

  $admin->{loggedin} = 1;
  $self->{pbot}->{logger}->log("$hostmask logged into $channel\n");
  return "Logged into $channel.";
}

sub logout {
  my ($self, $channel, $hostmask) = @_;
  my $admin = $self->find_admin($channel, $hostmask);
  delete $admin->{loggedin} if defined $admin;
}

1;
