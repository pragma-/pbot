#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package zsh;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.zsh';
  $self->{execfile}        = 'prog.zsh';
  $self->{default_options} = '';
  $self->{cmdline}         = 'zsh $options $sourcefile';

  $self->{cmdline_opening_comment} = ": <<'____CMDLINE____'\n";
  $self->{cmdline_closing_comment} = "____CMDLINE____\n";

  $self->{output_opening_comment} = ": << '____OUTPUT____'\n";
  $self->{output_closing_comment} = "____OUTPUT____\n";
}

1;
