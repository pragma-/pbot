#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

package ruby;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.rb';
  $self->{execfile}        = 'prog.rb';
  $self->{default_options} = '-w';
  $self->{cmdline}         = 'ruby $options $sourcefile';
}

1;
