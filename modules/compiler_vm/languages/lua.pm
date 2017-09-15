#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

package lua;
use parent '_default';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.lua';
  $self->{execfile}        = 'prog.lua';
  $self->{default_options} = '';
  $self->{cmdline}         = 'lua $options $sourcefile';

  if (length $self->{arguments}) {
    $self->{cmdline} .= " $self->{arguments}";
  }

  $self->{cmdline_opening_comment} = "--[[--------------- CMDLINE ---------------\n";
  $self->{cmdline_closing_comment} = "------------------- CMDLINE ---------------]]\n";

  $self->{output_opening_comment} = "--[[--------------- OUTPUT ---------------\n";
  $self->{output_closing_comment} = "------------------- OUTPUT ---------------]]\n";
}

1;
