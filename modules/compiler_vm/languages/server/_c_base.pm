#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

package _c_base; 
use parent '_default';

sub preprocess {
  my $self = shift;
  $self->SUPER::preprocess;

  if ($self->{cmdline} =~ m/--(?:version|analyze)/) {
    $self->{done} = 1;
  }
}

sub postprocess {
  my $self = shift;
  $self->SUPER::postprocess;

  # no errors compiling, but if output contains something, it must be diagnostic messages
  if(length $self->{output}) {
    $self->{output} =~ s/^\s+//;
    $self->{output} =~ s/\s+$//;
    $self->{output} = "[$self->{output}]\n";
  }

  print "Executing gdb\n";
  my ($retval, $result) = $self->execute(60, "date -s \@$self->{date}; ulimit -t 5; compiler_watchdog.pl $self->{arguments} > .output");

  $result = "";
  open(FILE, '.output');
  while(<FILE>) {
    $result .= $_;
    last if length $result >= 1024 * 20;
  }
  close(FILE);

  $result =~ s/\s+$//;

  if (not length $result) {
    $self->{no_output} = 1;
  } elsif ($self->{code} =~ m/print_last_statement\(.*\);$/m
    && ($result =~ m/A syntax error in expression/ || $result =~ m/No symbol.*in current context/ || $result =~ m/has unknown return type; cast the call to its declared/ || $result =~ m/Can't take address of.*which isn't an lvalue/)) {
    # strip print_last_statement and rebuild/re-run
    $self->{code} =~ s/print_last_statement\((.*)\);/$1;/mg;
    $self->preprocess;
    $self->postprocess;
  } else {
    $self->{output} .= $result;
  }
}

1;
