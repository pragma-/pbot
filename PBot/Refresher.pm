# File: Refresher.pm
# Author: pragma_
#
# Purpose: Refreshes/reloads module subroutines. Does not refresh/reload
# module member data, only subroutines.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Refresher;

use warnings;
use strict;

use feature 'unicode_strings';

use Module::Refresh;
use Carp ();

sub new {
  if (ref($_[1]) eq 'HASH') {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot} = $pbot;

  $self->{refresher} = Module::Refresh->new;

  $pbot->{commands}->register(sub { return $self->refresh(@_) }, "refresh", 90);
}

sub refresh {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  my $result = eval {
    if (not $arguments) {
      $self->{pbot}->{logger}->log("Refreshing all modified modules\n");
      $self->{refresher}->refresh;
      return "Refreshed all modified modules.\n";
    } else {
      $self->{pbot}->{logger}->log("Refreshing module $arguments\n");
      $self->{refresher}->refresh_module($arguments);
      $self->{pbot}->{logger}->log("Refreshed module.\n");
      return "Refreshed module.\n";
    }
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Error refreshing: $@\n");
    return $@;
  }

  # update version factoid
  my $version = $self->{pbot}->{version}->version();
  if ($self->{pbot}->{factoids}->{factoids}->{hash}->{'.*'}->{'version'}->{'action'} ne "/say $version") {
    $self->{pbot}->{factoids}->{factoids}->{hash}->{'.*'}->{'version'}->{'action'} = "/say $version";
    $self->{pbot}->{logger}->log("New version: $version\n");
  }

  return $result;
}

1;
