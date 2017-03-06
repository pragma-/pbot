#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

package perl;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.pl';
  $self->{execfile}        = 'prog.pl';
  $self->{default_options} = '';
  $self->{cmdline}         = 'perl $options $sourcefile';
}

sub postprocess_output {
  my $self = shift;
  $self->SUPER::postprocess_output;

  $self->{output} =~ s/\s+at $self->{sourcefile} line \d+, near ".*?"//;
  $self->{output} =~ s/\s*Execution of $self->{sourcefile} aborted due to compilation errors.//;

  $self->{cmdline_opening_comment} = "=cut =============== CMDLINE ===============\n";
  $self->{cmdline_closing_comment} = "=cut\n";

  $self->{output_opening_comment} = "=cut =============== OUTPUT ===============\n";
  $self->{output_closing_comment} = "=cut\n";
}

1;
