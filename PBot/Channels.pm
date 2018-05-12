# File: Channels.pm
# Author: pragma_
#
# Purpose: Manages list of channels and auto-joins.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Channels;

use warnings;
use strict;

use Carp ();
use PBot::HashObject;

sub new {
  if(ref($_[1]) eq 'HASH') {
     Carp::croak ("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{channels} = PBot::HashObject->new(pbot => $self->{pbot}, name => 'Channels', filename => delete $conf{filename});
  $self->load_channels;

  $self->{pbot}->{commands}->register(sub { $self->set(@_)       },  "chanset",   40);
  $self->{pbot}->{commands}->register(sub { $self->unset(@_)     },  "chanunset", 40);
  $self->{pbot}->{commands}->register(sub { $self->add(@_)       },  "chanadd",   40);
  $self->{pbot}->{commands}->register(sub { $self->remove(@_)    },  "chanrem",   40);
  $self->{pbot}->{commands}->register(sub { $self->list(@_)      },  "chanlist",  10);
}

sub set {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $key, $value) = split /\s+/, $arguments, 3;

  if(not defined $channel) {
    return "Usage: chanset <channel> [key [value]]";
  }

  return $self->{channels}->set($channel, $key, $value);
}

sub unset {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $key) = split /\s+/, $arguments;

  if(not defined $channel or not defined $key) {
    return "Usage: chanunset <channel> <key>";
  }

  return $self->{channels}->unset($channel, $key);
}

sub add {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if(not defined $arguments or not length $arguments) {
    return "Usage: chanadd <channel>";
  }

  my $hash = {};
  $hash->{enabled} = 1;
  $hash->{chanop} = 0;
  $hash->{permop} = 0;

  return $self->{channels}->add($arguments, $hash);
}

sub remove {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if(not defined $arguments or not length $arguments) {
    return "Usage: chanrem <channel>";
  }

  return $self->{channels}->remove($arguments);
}

sub list {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my $result;

  foreach my $index (sort keys %{ $self->{channels}->hash }) {
    $result .= "$index: {";
    my $comma = ' ';
    foreach my $key (sort keys %{ ${ $self->{channels}->hash }{$index} }) {
      $result .= "$comma$key => ${ $self->{channels}->hash }{$index}{$key}";
      $comma = ', ';
    }
    $result .= " }\n";
  }
  return $result;
}

sub is_active {
  my ($self, $channel) = @_;

  return exists $self->{channels}->hash->{$channel} && $self->{channels}->hash->{$channel}->{enabled};
}

sub is_active_op {
  my ($self, $channel) = @_;

  return $self->is_active($channel) && $self->{channels}->hash->{$channel}->{chanop};
}

sub load_channels {
  my $self = shift;

  $self->{channels}->load();
}

sub save_channels {
  my $self = shift;

  $self->{channels}->save();
}

sub channels {
  my $self = shift;
  return $self->{channels};
}

1;
