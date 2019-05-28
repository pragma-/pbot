#!/usr/bin/env perl

use warnings;
use strict;

package qbasic;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.bas';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '';
  $self->{cmdline}         = 'fbc -g -lang qb $options $sourcefile';

  $self->{cmdline_opening_comment} = "/'\n=============== CMDLINE ===============\n";
  $self->{cmdline_closing_comment} = "=============== CMDLINE ===============\n'/\n";

  $self->{output_opening_comment} = "/'\n=============== OUTPUT ===============\n";
  $self->{output_closing_comment} = "=============== OUTPUT ===============\n'/\n";

  $self->{sprunge_lexer} = 'basic';
}

1;
