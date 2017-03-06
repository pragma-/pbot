#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

package bc;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.bc';
  $self->{execfile}        = 'prog.bc';
  $self->{default_options} = '-l';
  $self->{cmdline}         = 'BC_LINE_LENGTH=2000000000 bc -q $options $sourcefile';
}

sub preprocess_code {
  my $self = shift;
  $self->{code} .= "\nquit\n";
}

1;
