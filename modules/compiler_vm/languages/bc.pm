#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package bc;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.bc';
  $self->{execfile}        = 'prog.bc';
  $self->{default_options} = '-l';
  $self->{cmdline}         = 'sh -c \'BC_LINE_LENGTH=2000000000 bc -q $options $sourcefile\'';
}

sub preprocess_code {
  my $self = shift;
  $self->{code} .= "\nquit\n";
}

1;
