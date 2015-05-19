#!/usr/bin/perl

use warnings;
use strict;

package clangpp;
use parent '_c_base';

sub initialize {
  my ($self, %conf) = @_;

  $self->{name}            = 'clang++';
  $self->{sourcefile}      = 'prog.cpp';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '-std=c++14 -Wextra -Wall -Wno-unused -pedantic -Wfloat-equal -Wshadow -lm -Wfatal-errors -fsanitize=alignment,undefined';
  $self->{options_paste}   = '-fcaret-diagnostics';
  $self->{options_nopaste} = '-fno-caret-diagnostics';
  $self->{cmdline}         = 'clang++-3.7 -I/usr/include/x86_64-linux-gnu/c++/5/ -ggdb -g3 $sourcefile $options -o $execfile';

  $self->{prelude} = <<'END';
#if 0
#define _XOPEN_SOURCE 9001
#define __USE_XOPEN

#include <algorithm>
#include <fstream>
#include <list>
#include <regex>
#include <tuple>
#include <array>
#include <functional>
#include <locale>
#include <scoped_allocator>
#include <type_traits>
#include <atomic>
#include <future>
#include <map>
#include <set>
#include <typeindex>
#include <bitset>
#include <initializer_list>
#include <memory>
#include <sstream>
#include <typeinfo>
#include <chrono>
#include <iomanip>
#include <mutex>
#include <stack>
#include <unordered_map>
#include <codecvt>
#include <ios>
#include <new>
#include <stdexcept>
#include <unordered_set>
#include <complex>
#include <iosfwd>
#include <numeric>
#include <streambuf>
#include <utility>
#include <condition_variable>
#include <iostream>
#include <ostream>
#include <string>
#include <valarray>
#include <deque>
#include <istream>
#include <queue>
#include <vector>
#include <exception>
#include <iterator>
#include <system_error>
#include <forward_list>
#include <iostream>
#include <limits>
#include <ratio>
#include <thread>

#include <cassert>
#include <cinttypes>
#include <csignal>
#include <cstdio>
#include <cwchar>
#include <ccomplex>
#include <ciso646>
#include <cstdalign>
#include <cstdlib>
#include <cwctype>
#include <cctype>
#include <climits>
#include <cstdarg>
#include <cstring>
#include <cerrno>
#include <clocale>
#include <cstdbool>
#include <ctgmath>
#include <cfenv>
#include <cmath>
#include <cstddef>
#include <ctime>
#include <cfloat>
#include <csetjmp>
#include <cstdint>

#include <prelude.h>

using namespace std;
#endif

#include <prelude.hpp>

END
}

1;
