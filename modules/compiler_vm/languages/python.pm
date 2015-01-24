#!/usr/bin/env perl

use warnings;
use strict;

package python;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.py';
  $self->{execfile}        = 'prog.py';
  $self->{default_options} = '';
  $self->{cmdline}         = 'python $options $sourcefile';

  $self->{cmdline_opening_comment} = "'''\n=============== CMDLINE ===============\n";
  $self->{cmdline_closing_comment} = "=============== CMDLINE ===============\n'''\n";

  $self->{output_opening_comment} = "'''\n=============== OUTPUT ===============\n";
  $self->{output_closing_comment} = "=============== OUTPUT ===============\n'''\n";
}

1;
