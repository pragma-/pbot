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
}

1;
