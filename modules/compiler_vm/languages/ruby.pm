#!/usr/bin/perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

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
