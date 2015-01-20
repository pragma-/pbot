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
}

1;
