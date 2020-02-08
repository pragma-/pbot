# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Class;

# purpose: base class for all PBot classes
#
# This prevents each PBot class from needing to define the new() subroutine
# and such boilerplate.

use warnings;
use strict;

sub new {
  my ($proto, %conf) = @_;
  my $class = ref($proto) || $proto;
  my $self = bless {}, $class;

  if (not exists $conf{pbot}) {
    my ($package, $filename, $line) = caller(0);
    my (undef, undef, undef, $subroutine) = caller(1);
    Carp::croak("Missing pbot reference to " . $class . ", created by $subroutine at $filename:$line");
  }

  $self->{pbot} = $conf{pbot};
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($package, $filename, $line) = caller(0);
  my (undef, undef, undef, $subroutine) = caller(1);
  Carp::croak("Missing initialize subroutine, created by $subroutine at $filename:$line");
}

1;
