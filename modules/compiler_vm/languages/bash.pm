#!/usr/bin/env perl

use warnings;
use strict;

package bash;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.bash';
  $self->{execfile}        = 'prog.bash';
  $self->{default_options} = '';
  $self->{cmdline}         = 'bash $options $sourcefile';
}

1;
