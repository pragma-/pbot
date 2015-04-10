#!/usr/bin/perl

use warnings;
use strict;

package java; 
use parent '_default';

sub postprocess {
  my $self = shift;

  # no errors compiling, but if output contains something, it must be diagnostic messages
  if(length $self->{output}) {
    $self->{output} =~ s/^\s+//;
    $self->{output} =~ s/\s+$//;
    $self->{output} = "[$self->{output}]\n";
  }

  print "Executing java\n";
  my $input_quoted = quotemeta $self->{input};
  $input_quoted =~ s/\\"/"'\\"'"/g;
  my ($retval, $result) = $self->execute(60, "bash -c \"date -s \@$self->{date}; ulimit -t 1; echo $input_quoted | java prog > .output\"");

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
  }

  $self->{output} .= $result;
}

1;
