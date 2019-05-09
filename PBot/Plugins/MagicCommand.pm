# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# This module is intended to provide a "magic" command that allows
# the bot owner to trigger special arbitrary code (by editing this
# module and refreshing loaded modules before running the magical
# command).

package PBot::Plugins::MagicCommand;

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
  $self->{pbot}->{commands}->register(sub { return $self->magic(@_)}, "mc", 90);
}

sub unload {
  my $self = shift;
  $self->{pbot}->{commands}->unregister("mc");
}

sub magic {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  # do something magical!
  return "Did something magical.";
}


1;
