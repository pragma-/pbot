#!/usr/bin/perl

use warnings;
use strict;

package tendra;
use parent '_default';

sub postprocess {
  my $self = shift;

  # no errors compiling, but if output contains something, it must be diagnostic messages
  if(length $self->{output}) {
    $self->{output} =~ s/^\s+//;
    $self->{output} =~ s/\s+$//;
    $self->{output} = "[$self->{output}]\n";
  }

  my $input_quoted = quotemeta $self->{input};
  $input_quoted =~ s/\\"/"'\\"'"/g;
  my ($retval, $result) = $self->execute(60, "bash -c \"date -s \@$self->{date}; ulimit -t 1; /home/compiler/prog <<< echo $input_quoted > .output\"");

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
