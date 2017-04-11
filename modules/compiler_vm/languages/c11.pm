#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

package c11;
use parent '_c_base';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.c';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '-Wextra -Wall -Wno-unused -pedantic -Wfloat-equal -Wshadow -std=c11 -lm -Wfatal-errors -fsanitize=alignment,undefined';
  $self->{options_paste}   = '-fdiagnostics-show-caret';
  $self->{options_nopaste} = '-fno-diagnostics-show-caret';
  $self->{cmdline}         = 'gcc -ggdb -g3 $sourcefile $options -o $execfile';

  $self->{default_options} .= ' -Werror' if defined $self->{nick} && $self->{nick} =~ m/marchelz/i;

  $self->{prelude} = <<'END';
#define _XOPEN_SOURCE 9001
#define __USE_XOPEN
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
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
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>
#include <prelude.h>

END
}

1;
