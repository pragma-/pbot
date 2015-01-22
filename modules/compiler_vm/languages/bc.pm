#!/usr/bin/env perl

use warnings;
use strict;

package bc;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.bc';
  $self->{execfile}        = 'prog.bc';
  $self->{default_options} = '';
  $self->{cmdline}         = 'bc -q $options $sourcefile';
}

sub preprocess_code {
  my $self = shift;
  $self->{code} .= "\nquit\n";
}

1;
