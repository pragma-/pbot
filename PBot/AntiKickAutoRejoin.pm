# File: AntiKickAutoRejoin.pm
# Author: pragma_
#
# Purpose: Temporarily bans people who immediately auto-rejoin after a kick.

package PBot::AntiKickAutoRejoin;

use warnings;
use strict;

use Carp ();
use Time::HiRes qw/gettimeofday/;
use Time::Duration;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot}    = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{pbot}->{registry}->add_default('array', 'antikickautorejoin', 'punishment', '300,900,1800,3600,28800');
  $self->{pbot}->{registry}->add_default('text',  'antikickautorejoin', 'threshold',  '4');

  $self->{pbot}->{event_dispatcher}->register_handler('irc.kick', sub { $self->on_kick(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.join', sub { $self->on_join(@_) });

  $self->{kicks} = {};
}

sub on_kick {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $target, $channel, $reason) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to, $event->{event}->{args}[0], $event->{event}->{args}[1]);

  return 0 if not exists $self->{pbot}->{channels}->{channels}->hash->{$channel} or not $self->{pbot}->{channels}->{channels}->hash->{$channel}{chanop};

  if (not exists $self->{kicks}->{$channel}
      or not exists $self->{kicks}->{$channel}->{$target}) {
    $self->{kicks}->{$channel}->{$target}->{rejoins} = 0;
  }

  $self->{kicks}->{$channel}->{$target}->{last_kick} = gettimeofday;

  return 0;
}

sub on_join {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);

  return 0 if not exists $self->{pbot}->{channels}->{channels}->hash->{$channel} or not $self->{pbot}->{channels}->{channels}->hash->{$channel}{chanop};

  if (exists $self->{kicks}->{$channel}
      and exists $self->{kicks}->{$channel}->{$nick}) {
    my $now = gettimeofday;

    if ($now - $self->{kicks}->{$channel}->{$nick}->{last_kick} <= $self->{pbot}->{registry}->get_value('antikickautorejoin', 'threshold')) {
      my $timeout = $self->{pbot}->{registry}->get_array_value('antikickautorejoin', 'punishment', $self->{kicks}->{$channel}->{$nick}->{rejoins});
      my $duration = duration($timeout);
      $duration =~ s/s$//; # hours -> hour, minutes -> minute

      $self->{pbot}->{chanops}->ban_user_timed("*!$user\@$host", $channel, $timeout);
      $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $nick $duration ban for auto-rejoining after kick");
      $self->{pbot}->{chanops}->gain_ops($channel);
      $self->{kicks}->{$channel}->{$nick}->{rejoins}++;
    }
  }

  return 0;
}

1;
