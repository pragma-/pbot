#!/usr/bin/env perl

use warnings;
use strict;

package java;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.java';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '';
  $self->{cmdline}         = 'javac $options $sourcefile';
}

1;
