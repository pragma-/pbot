#!/usr/bin/perl

use warnings;
use strict;

package php;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.php';
  $self->{execfile}        = 'prog.php';
  $self->{default_options} = '';
  $self->{cmdline}         = 'php $options $sourcefile';
}

1;
