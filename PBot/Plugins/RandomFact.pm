# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Author: Joey Pabalinas <alyptik@protonmail.com>

package PBot::Plugins::RandomFact;

use feature qw/state/;
use warnings;
use strict;

use Carp ();
use Time::HiRes qw/gettimeofday/;
use Time::Duration;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  state ($last_regen, $time_of_death, $kneads_until_death);

  $self->initialize(%conf);
  $self->{pbot}->{states}->{randomfact} = {
    last_regen => $last_regen,
    time_of_death => $time_of_death,
    kneads_until_death => $kneads_until_death,
  };
  $self->{pbot}->{states}->{randomfact}->{last_regen} = gettimeofday;
  $self->{pbot}->{states}->{randomfact}->{time_of_death} = gettimeofday;
  $self->{pbot}->{states}->{randomfact}->{kneads_until_death} = $self->{pbot}->{registry}->get_value('randomfact', 'knead_max');

  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{commands}->register(sub { $self->rand_factoid(@_) }, 'rfact', 0);

  $self->{pbot}->{registry}->add_default('text', 'randomfact', 'savageosity',  '1');
  $self->{pbot}->{registry}->add_default('text', 'randomfact', 'hp_regen',  '30');
  $self->{pbot}->{registry}->add_default('text', 'randomfact', 'knead_max', '6');

  $self->{pbot}->{event_dispatcher}->register_handler('irc.kick', sub { $self->on_kick(@_) });
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
  my $flag = 0;

  if (length($chan) > 1) {
    for (@channels) {
      last if ($flag);
      $flag = 1 if (m/^$chan$/)
    }
  }

  my $idx = scalar @channels;
  until ($flag or $idx < 0) {
    $chan = $channels[int rand $idx--];
    $flag = 1 if (length($chan) > 1);
  }

  return $usage unless ($flag);
  my $trig = $triggers[int rand @triggers];
  my ($owner, $action) =
    ($self->{factoids}->hash->{$chan}->{$trig}->{owner},
    $self->{factoids}->hash->{$chan}->{$trig}->{action});

  return "$trig is \"$action\" (created by $owner [$chan])";
}

1;
