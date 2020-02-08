# File: AntiNickSpam.pm
# Author: pragma_
#
# Purpose: Temporarily mutes $~a in channel if too many nicks were
#          mentioned within a time period; used to combat botnet spam

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::AntiNickSpam;

use warnings;
use strict;

use feature 'unicode_strings';

use Carp ();
use Time::Duration qw/duration/;
use Time::HiRes qw/gettimeofday/;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_action(@_) });
  $self->{nicks} = {};
}

sub unload {
  my ($self) = @_;
  $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
  $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
}

sub on_action {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);
  my $channel = $event->{event}->{to}[0];
  return 0 if $event->{interpreted};
  $self->check_flood($nick, $user, $host, $channel, $msg);
  return 0;
}

sub on_public {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);
  my $channel = $event->{event}->{to}[0];
  return 0 if $event->{interpreted};
  $self->check_flood($nick, $user, $host, $channel, $msg);
  return 0;
}

sub check_flood {
  my ($self, $nick, $user, $host, $channel, $msg) = @_;

  return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);

  $channel = lc $channel;
  my @words = split /\s+/, $msg;
  my @nicks;

  foreach my $word (@words) {
    $word =~ s/[:;\+,\.!?\@\%\$]+$//g;
    if ($self->{pbot}->{nicklist}->is_present($channel, $word) and not grep { $_ eq $word } @nicks) {
      push @{$self->{nicks}->{$channel}}, [scalar gettimeofday, $word];
      push @nicks, $word;
    }
  }

  $self->clear_old_nicks($channel);

  if (exists $self->{nicks}->{$channel} and @{$self->{nicks}->{$channel}} >= 10) {
    $self->{pbot}->{logger}->log("Nick spam flood detected in $channel\n");
    $self->{pbot}->{chanops}->mute_user_timed($self->{pbot}->{registry}->get_value('irc', 'botnick'), 'nick spam flooding', '$~a', $channel, 60 * 15);
  }
}

sub clear_old_nicks {
  my ($self, $channel) = @_;

  my $now = gettimeofday;

  return if not exists $self->{nicks}->{$channel};

  while (1) {
    if (@{$self->{nicks}->{$channel}} and $self->{nicks}->{$channel}->[0]->[0] <= $now - 15) {
      shift @{$self->{nicks}->{$channel}};
    } else {
      last;
    }
  }
  delete $self->{nicks}->{$channel} if not @{$self->{nicks}->{$channel}};
}

1;
