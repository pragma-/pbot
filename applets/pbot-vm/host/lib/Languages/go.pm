#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package Languages::go;
use parent 'Languages::_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.go';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '';
  $self->{cmdline}         = 'go $options run $sourcefile';
}

1;
