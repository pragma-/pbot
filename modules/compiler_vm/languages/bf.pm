#!/usr/bin/env perl

use warnings;
use strict;

package bf;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.bf';
  $self->{execfile}        = 'prog.bf';
  $self->{default_options} = '';
  $self->{cmdline}         = 'bf $options $sourcefile';
}

1;
