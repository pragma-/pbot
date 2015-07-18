#!/usr/bin/perl

use warnings;
use strict;

package _c_base; 
use parent '_default';

sub preprocess {
  my $self = shift;
  $self->SUPER::preprocess;

  if ($self->{cmdline} =~ m/--(?:version|analyze)/) {
    $self->{output} =~ s/Ubuntu //;
    $self->{output} =~ s/-\d+ubuntu\d+//;
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
  my ($retval, $result) = $self->execute(60, "bash -c \"date -s \@$self->{date}; ulimit -t 5; compiler_watchdog.pl > .output\"");

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
