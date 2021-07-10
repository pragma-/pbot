#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package go;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.go';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '';
  $self->{cmdline}         = 'go $options run $sourcefile';
}

1;
