#!/usr/bin/env perl

use warnings;
use strict;

package scheme;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.scm';
  $self->{execfile}        = 'prog.scm';
  $self->{default_options} = '';
  $self->{cmdline}         = 'guile $options $sourcefile';

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
