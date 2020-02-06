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

use feature 'unicode_strings';

use Carp ();
use PBot::HashObject;

sub new {
  Carp::croak ("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{channels} = PBot::HashObject->new(pbot => $self->{pbot}, name => 'Channels', filename => $conf{filename});
  $self->load_channels;

  $self->{pbot}->{commands}->register(sub { $self->join(@_)   },  "join",      1);
  $self->{pbot}->{commands}->register(sub { $self->part(@_)   },  "part",      1);
  $self->{pbot}->{commands}->register(sub { $self->set(@_)    },  "chanset",   1);
  $self->{pbot}->{commands}->register(sub { $self->unset(@_)  },  "chanunset", 1);
  $self->{pbot}->{commands}->register(sub { $self->add(@_)    },  "chanadd",   1);
  $self->{pbot}->{commands}->register(sub { $self->remove(@_) },  "chanrem",   1);
  $self->{pbot}->{commands}->register(sub { $self->list(@_)   },  "chanlist",  1);

  $self->{pbot}->{capabilities}->add('admin', 'can-join',     1);
  $self->{pbot}->{capabilities}->add('admin', 'can-part',     1);
  $self->{pbot}->{capabilities}->add('admin', 'can-chanlist', 1);
}

sub join {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  foreach my $channel (split /[\s+,]/, $arguments) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host made me join $channel\n");
    $self->{pbot}->{chanops}->join_channel($channel);
  }

  return "/msg $nick Joining $arguments";
}

sub part {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  $arguments = $from if not $arguments;

  foreach my $channel (split /[\s+,]/, $arguments) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host made me part $channel\n");
    $self->{pbot}->{chanops}->part_channel($channel);
  }

  return "/msg $nick Parting $arguments";
}

sub set {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($channel, $key, $value) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);
  return "Usage: chanset <channel> [key [value]]" if not defined $channel;
  return $self->{channels}->set($channel, $key, $value);
}

sub unset {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($channel, $key) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);
  return "Usage: chanunset <channel> <key>" if not defined $channel or not defined $key;
  return $self->{channels}->unset($channel, $key);
}

sub add {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if (not defined $arguments or not length $arguments) {
    return "Usage: chanadd <channel>";
  }

  my $data = {
    enabled => 1,
    chanop => 0,
    permop => 0
  };

  return $self->{channels}->add($arguments, $data);
}

sub remove {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if (not defined $arguments or not length $arguments) {
    return "Usage: chanrem <channel>";
  }

  $arguments = lc $arguments;

  # clear unban timeouts
  if (exists $self->{pbot}->{chanops}->{unban_timeout}->{hash}->{$arguments}) {
    delete $self->{pbot}->{chanops}->{unban_timeout}->{hash}->{$arguments};
    $self->{pbot}->{chanops}->{unban_timeout}->save;
  }

  # clear unmute timeouts
  if (exists $self->{pbot}->{chanops}->{unmute_timeout}->{hash}->{$arguments}) {
    delete $self->{pbot}->{chanops}->{unmute_timeout}->{hash}->{$arguments};
    $self->{pbot}->{chanops}->{unmute_timeout}->save;
  }

  # TODO: ignores, etc?

  return $self->{channels}->remove($arguments);
}

sub list {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my $result;

  foreach my $index (sort keys %{ $self->{channels}->{hash} }) {
    $result .= "$self->{channels}->{hash}->{$index}->{_name}: {";
    my $comma = ' ';
    foreach my $key (sort keys %{ $self->{channels}->{hash}->{$index} }) {
      $result .= "$comma$key => $self->{channels}->{hash}->{$index}->{$key}";
      $comma = ', ';
    }
    $result .= " }\n";
  }
  return $result;
}

sub autojoin {
  my ($self) = @_;
  return if $self->{pbot}->{joined_channels};
  my $chans;
  foreach my $chan (keys %{ $self->{channels}->{hash} }) {
    if ($self->{channels}->{hash}->{$chan}->{enabled}) {
      $chans .= "$self->{channels}->{hash}->{$chan}->{_name},";
    }
  }
  $self->{pbot}->{logger}->log("Joining channels: $chans\n");
  $self->{pbot}->{chanops}->join_channel($chans);
  $self->{pbot}->{joined_channels} = 1;
}

sub is_active {
  my ($self, $channel) = @_;
  my $lc_channel = lc $channel;
  return exists $self->{channels}->{hash}->{$lc_channel} && $self->{channels}->{hash}->{$lc_channel}->{enabled};
}

sub is_active_op {
  my ($self, $channel) = @_;
  return $self->is_active($channel) && $self->{channels}->{hash}->{lc $channel}->{chanop};
}

sub get_meta {
  my ($self, $channel, $key) = @_;
  $channel = lc $channel;
  return undef if not exists $self->{channels}->{hash}->{$channel};
  return $self->{channels}->{hash}->{$channel}->{$key};
}

sub load_channels {
  my ($self) = @_;
  $self->{channels}->load;
}

sub save_channels {
  my ($self) = @_;
  $self->{channels}->save;
}

1;
