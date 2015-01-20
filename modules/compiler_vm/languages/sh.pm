#!/usr/bin/env perl

use warnings;
use strict;

package sh;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.sh';
  $self->{execfile}        = 'prog.sh';
  $self->{default_options} = '';
  $self->{cmdline}         = 'sh $options $sourcefile';
}

1;
