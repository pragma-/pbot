#!/usr/bin/perl

use warnings;
use strict;

package tendra;
use parent '_c_base';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.c';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '-Xp';
  $self->{cmdline}         = 'tcc -Wa,-32 -Wl,-melf_i386 -g $sourcefile $options -o $execfile';

  $self->{prelude} = <<'END';
#define _XOPEN_SOURCE 9001
#define __USE_XOPEN
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <errno.h>
#include <ctype.h>
#include <assert.h>
#include <locale.h>
#include <setjmp.h>
#include <signal.h>

END
}

1;
