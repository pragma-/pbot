#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package Languages::clisp;
use parent 'Languages::_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.lisp';
  $self->{execfile}        = 'prog.lisp';
  $self->{default_options} = '';
  $self->{cmdline}         = 'clisp $options $sourcefile';

  if (length $self->{arguments}) {
    $self->{cmdline} .= " $self->{arguments}";
  }

  $self->{sprunge_lexer}   = 'cl';

  $self->{cmdline_opening_comment} = "#|=============== CMDLINE ===============\n";
  $self->{cmdline_closing_comment} = "================= CMDLINE ===============|#\n";

  $self->{output_opening_comment} = "#|=============== OUTPUT ===============\n";
  $self->{output_closing_comment} = "================= OUTPUT ===============|#\n";
}

sub postprocess_output {
  my $self = shift;
  $self->SUPER::postprocess_output;

  $self->{output} =~ s/^\n//;
}

1;
