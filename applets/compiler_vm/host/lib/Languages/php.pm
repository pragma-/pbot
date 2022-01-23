#!/usr/bin/perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package Languages::php;
use parent 'Languages::_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.php';
  $self->{execfile}        = 'prog.php';
  $self->{default_options} = '';
  $self->{cmdline}         = 'php $options $sourcefile';
}

1;
