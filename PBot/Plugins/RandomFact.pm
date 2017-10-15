# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Author: Joey Pabalinas <alyptik@protonmail.com>

package PBot::Plugins::RandomFact;

use warnings;
use strict;

use Carp ();

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{commands}->register(sub { $self->rand_factoid(@_) }, 'rfact', 0);
}

sub unload {
  my $self = shift;
  $self->{pbot}->{commands}->unregister('rfact');
}

sub rand_factoid {
  my $self = shift;
  my ($chan) = @_;
  my $usage = "Usage: rfact [<channel>]";
  my @channels = keys %{ $self->{pbot}->{factoids}->hash };
  my @triggers = keys %{ $self->{pbot}->{triggers}->hash->{$chan} };

  # pick random channel unless given one
  if (defined $chan) {
    my $flag = 0;
    # iterate over known channels
    map { $flag = 1 if m/^$chan$/; } @channels;
    # show usage if given an invalid channel
    return $usage unless $flag;
  } else {
    $chan = $channels[int rand @channels];
  }

  # pick random trigger
  my $trig = $triggers[int rand @triggers];
  my $owner = $self->{factoids}->hash->{$chan}->{$trig}->{owner};
  my $action = $self->{factoids}->hash->{$chan}->{$trig}->{action};

  return "$trig is \"$action\" (created by $owner [$chan])";
}

1;
