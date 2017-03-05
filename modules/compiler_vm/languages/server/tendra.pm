#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

package tendra;
use parent '_default';

sub postprocess {
  my $self = shift;
  $self->SUPER::postprocess;

  # no errors compiling, but if output contains something, it must be diagnostic messages
  if(length $self->{output}) {
    $self->{output} =~ s/^\s+//;
    $self->{output} =~ s/\s+$//;
    $self->{output} = "[$self->{output}]\n";
  }

  my ($retval, $result) = $self->execute(60, "bash -c \"date -s \@$self->{date}; ulimit -t 5; cat .input | /home/compiler/prog > .output\"");

  $self->{error} = $retval;

  $result = "";
  open(FILE, '.output');
  while(<FILE>) {
    $result .= $_;
    last if length $result >= 1024 * 20;
  }
  close(FILE);

  $result =~ s/\s+$//;

  $self->{no_output} = 1 if not length $result;

  $self->{output} .= $result;
}

1;
