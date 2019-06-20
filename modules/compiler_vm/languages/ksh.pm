#!/usr/bin/env perl

use warnings;
use strict;

package ksh;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.ksh';
  $self->{execfile}        = 'prog.ksh';
  $self->{default_options} = '';
  $self->{cmdline}         = 'ksh $options $sourcefile';

  $self->{cmdline_opening_comment} = ": <<'____CMDLINE____'\n";
  $self->{cmdline_closing_comment} = "____CMDLINE____\n";

  $self->{output_opening_comment} = ": << '____OUTPUT____'\n";
  $self->{output_closing_comment} = "____OUTPUT____\n";
}

1;
