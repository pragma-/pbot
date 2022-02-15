#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package Languages::tcl;
use parent 'Languages::_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.tcl';
  $self->{execfile}        = 'prog.tcl';
  $self->{default_options} = '';
  $self->{cmdline}         = 'tclsh $options $sourcefile';

  $self->{cmdline_opening_comment} = "set CMDLINE {\n";
  $self->{cmdline_closing_comment} = "}\n";

  $self->{output_opening_comment} = "set OUTPUT {\n";
  $self->{output_closing_comment} = "}\n";
}

1;
