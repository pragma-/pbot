#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021-2024 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package Languages::ksh;
use parent 'Languages::_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.ksh';
  $self->{execfile}        = 'prog.ksh';
  $self->{default_options} = '';
  $self->{cmdline}         = 'ksh $options $sourcefile';

  $self->{cmdline_opening_comment} = ": <<'CMDLINE'\n";
  $self->{cmdline_closing_comment} = "CMDLINE\n";

  $self->{output_opening_comment} = ": << 'OUTPUT'\n";
  $self->{output_closing_comment} = "OUTPUT\n";
}

1;
