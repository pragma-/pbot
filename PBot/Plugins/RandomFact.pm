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

sub on_kick {
  my $self = shift;
  my $ktd = \$self->{pbot}->{states}->{randomfact}->{kneads_until_death};
  my $tod = \$self->{pbot}->{states}->{randomfact}->{time_of_death};
  my $lregen = \$self->{pbot}->{states}->{randomfact}->{last_regen};
  $$ktd = $self->{pbot}->{registry}->get_value('randomfact', 'knead_max');
  $$lregen = $$tod = gettimeofday;

  return 0;
}

sub rand_factoid {
  my ($self, $from, $nick, $user, $host, $channel) = @_;
  my $usage = "Usage: rfact [<channel>]";
  my $flag = 0;
  my @channels = keys %{ $self->{pbot}->{factoids}->hash };
  my @triggers = keys %{ $self->{pbot}->{triggers}->hash->{$channel} };

  if (length($channel) > 1) {
    for (@channels) {
      last if ($flag);
      $flag = 1 if (m/^$channel$/)
    }
  }

  my $idx = scalar @channels;
  until ($flag or $idx < 0) {
    $channel = $channels[int rand $idx--];
    $flag = 1 if (length($channel) > 1);
  }

  return $usage unless ($flag);

  my $trig = $triggers[int rand @triggers];
  my ($owner, $action) =
    ($self->{factoids}->hash->{$channel}->{$trig}->{owner},
    $self->{factoids}->hash->{$channel}->{$trig}->{action});

  $self->knead_of_death(@_);

  return "$trig is \"$action\" (created by $owner [$channel])";
}

sub knead_of_death {
  my ($self, $from, $nick, $user, $host, $channel) = @_;

  $channel = lc $channel;
  return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);
  return 0 unless (exists $self->{kicks}->{$channel} and exists $self->{kicks}->{$channel}->{$nick});

  my $ktd = \$self->{pbot}->{states}->{randomfact}->{kneads_until_death};
  my $tod = \$self->{pbot}->{states}->{randomfact}->{time_of_death};
  my $lregen = \$self->{pbot}->{states}->{randomfact}->{last_regen};
  my $now = gettimeofday;
  my $time_diff = $now - $$lregen;

  if ($time_diff > $self->{pbot}->{registry}->get_value('randomfact', 'hp_regen')) {
    $$ktd++;
    $$lregen = gettimeofday;
  }

  # 50% chance of a decrement scaled by savageosity
  $$ktd -= (((gettimeofday())[1]) % 2) * $self->{pbot}->{registry}->get_value('randomfact', 'savageosity');
  if ($$ktd < 0) {
    # rip.
    $self->{pbot}->{chanops}->gain_ops($channel);
    $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $nick *BANG!*");
  }
}

1;
