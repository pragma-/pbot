#!/usr/bin/perl

use warnings;
use strict;

package c99;
use parent 'c11';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.c';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '-Wextra -Wall -Wno-unused -pedantic -Wfloat-equal -Wshadow -std=c99 -lm -Wfatal-errors';
  $self->{cmdline}         = 'gcc -ggdb -g3 $sourcefile $options -o $execfile';

  $self->{prelude} = <<'END';
#define _XOPEN_SOURCE 9001
#define __USE_XOPEN
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <complex.h>
#include <math.h>
#include <tgmath.h>
#include <limits.h>
#include <sys/types.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdarg.h>
#include <ctype.h>
#include <inttypes.h>
#include <float.h>
#include <errno.h>
#include <time.h>
#include <assert.h>
#include <locale.h>
#include <wchar.h>
#include <fenv.h>
#inclue <iso646.h>
#include <setjmp.h>
#include <signal.h>
#include <prelude.h>

END
}

1;
