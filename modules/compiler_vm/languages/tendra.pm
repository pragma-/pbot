#!/usr/bin/perl

use warnings;
use strict;

package tendra;
use parent '_c_base';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.c';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '-Xp -Yansi';
  $self->{cmdline}         = 'tcc -Wa,-32 -Wl,-melf_i386 -g $sourcefile $options -o $execfile';

  $self->{prelude} = <<'END';
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <float.h>
#include <math.h>
#include <limits.h>
#include <errno.h>
#include <ctype.h>
#include <assert.h>
#include <locale.h>
#include <setjmp.h>
#include <signal.h>
#include <time.h>
#include <stdarg.h>
#include <stddef.h>

END
}

sub postprocess_output {
  my $self = shift;
  $self->SUPER::postprocess_output;

  $self->{output} =~ s/^\n+//mg;

  $self->{output} =~ s/^\[Warning: Directory 'c89' already defined.\]\s*//;
  $self->{output} =~ s/\s*Warning: Directory 'c89' already defined.//g;

  if ((not exists $self->{options}->{'-paste'}) and (not defined $self->{got_run} or $self->{got_run} ne 'paste')) {
    $self->{output} =~ s/"$self->{sourcefile}", line \d+:\s*//g;
    $self->{output} =~ s/Error:\s+\[/Error: [/g;
    $self->{output} =~ s/Warning:\s+\[/Warning: [/g;
  }
}

1;
