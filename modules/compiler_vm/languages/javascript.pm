#!/usr/bin/env perl

use warnings;
use strict;

package javascript;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.js';
  $self->{execfile}        = 'prog.js';
  $self->{default_options} = '';
  $self->{cmdline}         = 'd8 $options $sourcefile';

  if (length $self->{arguments}) {
    $self->{cmdline} .= " $self->{arguments}";
  }

  $self->{cmdline_opening_comment} = "/************* CMDLINE *************\n";
  $self->{cmdline_closing_comment} = "************** CMDLINE *************/\n";

  $self->{output_opening_comment} = "/************* OUTPUT *************\n";
  $self->{output_closing_comment} = "************** OUTPUT *************/\n";
}

1;
