#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

package go;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.go';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '';
  $self->{cmdline}         = 'golang-go $options run $sourcefile';
}

1;
