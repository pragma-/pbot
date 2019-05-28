#!/usr/bin/perl

use warnings;
use strict;

package clang11;
use parent '_c_base';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.c';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '-Wextra -Wall -Wno-unused -Wno-unused-parameter -pedantic -Wfloat-equal -Wshadow -std=c11 -lm -Wfatal-errors -fsanitize=integer,undefined,alignment';
  $self->{options_paste}   = '-fcaret-diagnostics';
  $self->{options_nopaste} = '-fno-caret-diagnostics';
  $self->{cmdline}         = 'clang -ggdb -g3 $sourcefile $options -o $execfile';

  $self->{prelude} = <<'END';
#define _XOPEN_SOURCE 9001
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <limits.h>
#include <sys/types.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdnoreturn.h>
#include <stdalign.h>
#include <ctype.h>
#include <inttypes.h>
#include <float.h>
#include <errno.h>
#include <time.h>
#include <assert.h>
#include <complex.h>
#include <setjmp.h>
#include <wchar.h>
#include <wctype.h>
#include <tgmath.h>
#include <fenv.h>
#include <locale.h>
#include <iso646.h>
#include <signal.h>
#include <uchar.h>
#include <prelude.h>

END
}

1;
