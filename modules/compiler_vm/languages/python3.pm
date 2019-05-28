#!/usr/bin/env perl

use warnings;
use strict;

package python3;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.py3';
  $self->{execfile}        = 'prog.py3';
  $self->{default_options} = '';
  $self->{cmdline}         = 'python3 $options $sourcefile';

  if (length $self->{arguments}) {
    $self->{cmdline} .= " $self->{arguments}";
  }

  $self->{cmdline_opening_comment} = "'''\n=============== CMDLINE ===============\n";
  $self->{cmdline_closing_comment} = "=============== CMDLINE ===============\n'''\n";

  $self->{output_opening_comment} = "'''\n=============== OUTPUT ===============\n";
  $self->{output_closing_comment} = "=============== OUTPUT ===============\n'''\n";
}

1;
