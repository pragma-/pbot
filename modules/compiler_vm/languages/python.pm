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
}

1;
