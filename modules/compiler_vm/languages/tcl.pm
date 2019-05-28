#!/usr/bin/env perl

use warnings;
use strict;

package tcl; 
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.tcl';
  $self->{execfile}        = 'prog.tcl';
  $self->{default_options} = '';
  $self->{cmdline}         = 'tclsh $options $sourcefile';

  if (length $self->{arguments}) {
    $self->{cmdline} .= " $self->{arguments}";
  }

  $self->{cmdline_opening_comment} = "set CMDLINE {\n";
  $self->{cmdline_closing_comment} = "}\n";

  $self->{output_opening_comment} = "set OUTPUT {\n";
  $self->{output_closing_comment} = "}\n";
}

1;
