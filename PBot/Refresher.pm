# File: Refresher.pm
# Author: pragma_
#
# Purpose: Refreshes/reloads module subroutines. Does not refresh/reload
# module member data, only subroutines. TODO: reinitialize modules in order
# to refresh member data too.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Refresher;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use Module::Refresh;

sub initialize {
  my ($self, %conf) = @_;
  $self->{refresher} = Module::Refresh->new;
  $self->{pbot}->{commands}->register(sub { $self->refresh(@_) }, "refresh", 1);
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
  return $result;
}

1;
