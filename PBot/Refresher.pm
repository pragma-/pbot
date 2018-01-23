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

use Module::Refresh;
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
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
      if ($self->{refresher}->refresh_module_if_modified($arguments)) {
        $self->{pbot}->{logger}->log("Refreshed module.\n");
        return "Refreshed module.\n";
      } else {
        $self->{pbot}->{logger}->log("Module had no changes; not refreshed.\n");
        return "Module had no changes; not refreshed.\n";
      }
    }
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Error refreshing: $@\n");
    return $@;
  }

  # update version factoid
  use PBot::VERSION;
  my $version = PBot::VERSION::BUILD_NAME . " revision " . PBot::VERSION::BUILD_REVISION . " " . PBot::VERSION::BUILD_DATE;
  $self->{pbot}->{factoids}->{factoids}->hash->{'.*'}->{'version'}->{'action'} = "/say $version";

  return $result;
}

1;
