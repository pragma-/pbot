#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021-2024 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package Languages::bf;
use parent 'Languages::_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.bf';
  $self->{execfile}        = 'prog.bf';
  $self->{default_options} = '';
  $self->{cmdline}         = 'bff $options $sourcefile';
}

1;
