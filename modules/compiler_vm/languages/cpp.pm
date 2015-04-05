#!/usr/bin/perl

use warnings;
use strict;

package cpp;
use parent '_c_base';

sub initialize {
  my ($self, %conf) = @_;

  $self->{name}            = 'c++';
  $self->{sourcefile}      = 'prog.cpp';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '-std=c++11 -Wextra -Wall -Wno-unused -pedantic -Wfloat-equal -Wshadow -lm -Wfatal-errors';
  $self->{options_paste}   = '-fdiagnostics-show-caret';
  $self->{options_nopaste} = '-fno-diagnostics-show-caret';
  $self->{cmdline}         = 'g++ -ggdb -g3 $sourcefile $options -o $execfile';

  $self->{prelude} = <<'END';
#define _XOPEN_SOURCE 9001
#define __USE_XOPEN
#include <iostream>
#include <limits>
#include <vector>
#include <exception>
#include <stdexcept>
#include <typeinfo>
#include <type_traits>
#include <typeindex>
#include <cstdlib>
#include <cstdio>
#include <cstdarg>
#include <functional>
#include <tuple>
#include <prelude.h>

END
}

1;
