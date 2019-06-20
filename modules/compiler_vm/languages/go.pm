#!/usr/bin/env perl

use warnings;
use strict;

package go;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.go';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '';
  $self->{cmdline}         = 'go $options run $sourcefile';
}

1;
