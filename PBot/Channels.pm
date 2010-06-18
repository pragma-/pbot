# File: Channels.pm
# Author: pragma_
#
# Purpose: Manages list of channels and auto-joins.

package PBot::Channels;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

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

  my $pbot = delete $conf{pbot};
  if(not defined $pbot) {
     Carp::croak ("Missing pbot reference to Channels");
  }

  my $filename = delete $conf{filename};

  $self->{pbot} = $pbot;
  $self->{channels} = PBot::HashObject->new(pbot => $pbot, name => 'Channels', index_key => 'channel', filename => $filename);

  $pbot->commands->register(sub { $self->set(@_)       },  "chanset",   40);
  $pbot->commands->register(sub { $self->unset(@_)     },  "chanunset", 40);
  $pbot->commands->register(sub { $self->add(@_)       },  "chanadd",   40);
  $pbot->commands->register(sub { $self->remove(@_)    },  "chanrem",   40);
}

sub set {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $key, $value) = split / /, $arguments, 3;

  if(not defined $channel) {
    return "/msg $nick Usage: chanset <channel> [[key] <value>]";
  }

  return "/msg $nick " . $self->channels->set($channel, $key, $value);
}

sub unset {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $key) = split / /, $arguments;

  if(not defined $channel or not defined $key) {
    return "/msg $nick Usage: chanunset <channel> <key>";
  }

  return "/msg $nick " . $self->channels->unset($channel, $key);
}

sub add {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if(not defined $arguments) {
    return "/msg $nick Usage: chanadd <channel>";
  }

  my $hash = {};
  $hash->{channel} = $arguments;
  $hash->{enabled} = 1;
  $hash->{chanop} = 0;

  return "/msg $nick " . $self->channels->add($hash);
}

sub remove {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if(not defined $arguments) {
    return "/msg $nick Usage: chanrem <channel>";
  }

  return "/msg $nick " . $self->channels->remove($arguments);
}

sub load_channels {
  my $self = shift;

  $self->channels->load_hash();
}

sub save_channels {
  my $self = shift;

  $self->channels->save_hash();
}

sub channels {
  my $self = shift;
  return $self->{channels};
}

1;
