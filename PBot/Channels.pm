# File: Channels.pm
# Author: pragma_
#
# Purpose: Manages list of channels and auto-joins.

package PBot::Channels;

use warnings;
use strict;

use Carp ();
use PBot::HashObject;

sub new {
  if(ref($_[1]) eq 'HASH') {
     Carp::croak ("Options to Commands should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to Channels");

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
  my ($channel, $key, $value) = split / /, $arguments, 3;

  if(not defined $channel) {
    return "Usage: chanset <channel> [key <value>]";
  }

  return $self->{channels}->set($channel, $key, $value);
}

sub unset {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $key) = split / /, $arguments;

  if(not defined $channel or not defined $key) {
    return "Usage: chanunset <channel> <key>";
  }

  return "msg $nick " . $self->{channels}->unset($channel, $key);
}

sub add {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if(not defined $arguments or not length $arguments) {
    return "/msg $nick Usage: chanadd <channel>";
  }

  my $hash = {};
  $hash->{enabled} = 1;
  $hash->{chanop} = 0;

  return "/msg $nick " . $self->{channels}->add($arguments, $hash);
}

sub remove {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if(not defined $arguments or not length $arguments) {
    return "/msg $nick Usage: chanrem <channel>";
  }

  return "/msg $nick " . $self->{channels}->remove($arguments);
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
  return "/msg $nick $result";
}

sub load_channels {
  my $self = shift;

  $self->{channels}->load_hash();
}

sub save_channels {
  my $self = shift;

  $self->{channels}->save_hash();
}

sub channels {
  my $self = shift;
  return $self->{channels};
}

1;
