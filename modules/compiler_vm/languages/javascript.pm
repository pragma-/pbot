#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
