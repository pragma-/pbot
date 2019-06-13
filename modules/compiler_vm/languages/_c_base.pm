#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;
use feature "switch";

no if $] >= 5.018, warnings => "experimental::smartmatch";

package _c_base;
use parent '_default';

use Text::Balanced qw/extract_bracketed/;

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.c';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '-Wextra -Wall -Wno-unused -pedantic -Wfloat-equal -Wshadow -std=c11 -lm -Wfatal-errors';
  $self->{options_paste}   = '-fdiagnostics-show-caret';
  $self->{options_nopaste} = '-fno-diagnostics-show-caret';
  $self->{cmdline}         = 'gcc -ggdb -g3 $sourcefile $options -o $execfile';

  $self->{prelude} = <<'END';
#define _XOPEN_SOURCE 9001
#define __USE_XOPEN
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

sub process_custom_options {
  my $self = shift;

  $self->add_option("-nomain") if $self->{code} =~ s/(?:^|(?<=\s))-nomain\s*//i;
  $self->add_option("-noheaders") if $self->{code} =~ s/(?:^|(?<=\s))-noheaders\s*//i;

  $self->{include_options} = "";
  while ($self->{code} =~ s/(?:^|(?<=\s))-include\s+(\S+)\s+//) {
    $self->{include_options} .= "#include <$1> ";
    $self->add_option("-include $1");
  }
}

sub pretty_format {
  my $self = shift;
  my $code = join '', @_;
  my $result;

  $code = $self->{code} if not defined $code;

  open my $fh, ">$self->{sourcefile}" or die "Couldn't write $self->{sourcefile}: $!";
  print $fh $code;
  close $fh;

  system("astyle", "-A3 -UHpnfq", $self->{sourcefile});

  open $fh, "<$self->{sourcefile}" or die "Couldn't read $self->{sourcefile}: $!";
  $result = join '', <$fh>;
  close $fh;

  return $result;
}

sub preprocess_code {
  my $self = shift;
  $self->SUPER::preprocess_code;

  my $default_prelude = exists $self->{options}->{'-noheaders'} ? '' : $self->{prelude};

#  $self->{debug} = 10;
  $self->{code} = $self->{include_options} . $self->{code};

  print "code before: [$self->{code}]\n" if $self->{debug};

  # add newlines to ends of statements and #includes
  my $single_quote = 0;
  my $double_quote = 0;
  my $parens = 0;
  my $cpp = 0; # preprocessor
  my $escaped = 0;

  while($self->{code} =~ m/(.)/msg) {
    my $ch = $1;
    my $pos = pos $self->{code};

    print "adding newlines, ch = [$ch], parens: $parens, cpp: $cpp, single: $single_quote, double: $double_quote, escaped: $escaped, pos: $pos\n" if $self->{debug} >= 10;

    if($ch eq '\\') {
      $escaped = not $escaped;
    } elsif($ch eq '#' and not $cpp and not $escaped and not $single_quote and not $double_quote) {
      $cpp = 1;

      if($self->{code} =~ m/include\s*<([^>\n]*)>/msg) {
        my $match = $1;
        $pos = pos $self->{code};
        substr ($self->{code}, $pos, 0) = "\n";
        pos $self->{code} = $pos;
        $cpp = 0;
      } elsif($self->{code} =~ m/include\s*"([^"\n]*)"/msg) {
        my $match = $1;
        $pos = pos $self->{code};
        substr ($self->{code}, $pos, 0) = "\n";
        pos $self->{code} = $pos;
        $cpp = 0;
      } else {
        pos $self->{code} = $pos;
      }
    } elsif($ch eq '"') {
      $double_quote = not $double_quote unless $escaped or $single_quote;
      $escaped = 0;
    } elsif($ch eq '(' and not $single_quote and not $double_quote) {
      $parens++;
    } elsif($ch eq ')' and not $single_quote and not $double_quote) {
      $parens--;
      $parens = 0 if $parens < 0;
    } elsif($ch eq ';' and not $cpp and not $single_quote and not $double_quote and $parens == 0) {
      if(not substr($self->{code}, $pos, 1) =~ m/[\n\r]/) {
        substr ($self->{code}, $pos, 0) = "\n";
        pos $self->{code} = $pos + 1;
      }
    } elsif($ch eq "'") {
      $single_quote = not $single_quote unless $escaped or $double_quote;
      $escaped = 0;
    } elsif($ch eq 'n' and $escaped) {
      if(not $single_quote and not $double_quote) {
        print "added newline\n" if $self->{debug} >= 10;
        substr ($self->{code}, $pos - 2, 2) = "\n";
        pos $self->{code} = $pos;
        $cpp = 0;
      }
      $escaped = 0;
    } elsif($ch eq "\n" and $cpp and not $single_quote and not $double_quote) {
      $cpp = 0;
    } else {
      $escaped = 0;
    }
  }

  print "code after \\n additions: [$self->{code}]\n" if $self->{debug};

  # white-out contents of quoted literals so content within literals aren't parsed as code
  my $white_code = $self->{code};
  $white_code =~ s/(?:\"((?:\\\"|(?!\").)*)\")/'"' . ('-' x length $1) . '"'/ge;
  $white_code =~ s/(?:\'((?:\\\'|(?!\').)*)\')/"'" . ('-' x length $1) . "'"/ge;

  my $precode;

  if($white_code =~ m/#include/) {
    $precode = $self->{code}; 
  } else {
    $precode = $default_prelude . $self->{code};
  }

  $self->{code} = '';

  print "--- precode: [$precode]\n" if $self->{debug};

  $self->{warn_unterminated_define} = 0;

  my $has_main = 0;

  my $prelude = '';
  while($precode =~ s/^\s*(#.*\n{1,2}|using.*\n{1,2})//g) {
    $prelude .= $1;
  }

  if($precode =~ m/^\s*(#.*)/ms) {
    my $line = $1;

    if($line !~ m/\n/) {
      $self->{warn_unterminated_define} = 1;
    }
  }

  if (not $self->{no_gdb_extensions} and $prelude !~ m/^#include <prelude.h>/mg) {
    $prelude .= "\n#include <prelude.h>\n";
  }

  print "*** prelude: [$prelude]\n   precode: [$precode]\n" if $self->{debug};

  my $preprecode = $precode;

  # white-out contents of quoted literals
  $preprecode =~ s/(?:\"((?:\\\"|(?!\").)*)\")/'"' . ('-' x length $1) . '"'/ge;
  $preprecode =~ s/(?:\'((?:\\\'|(?!\').)*)\')/"'" . ('-' x length $1) . "'"/ge;

  # strip comments
  if ($self->{lang} eq 'c89') {
    $preprecode =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/# #gs;
    $preprecode =~ s#|//([^\\]|[^\n][\n]?)*?\n|("(\\.|[^"\\])*"|'(\\.|[^'\\])*'|.[^/"'\\]*)#defined $2 ? $2 : ""#gse;
  } else {
    $preprecode =~ s#|//([^\\]|[^\n][\n]?)*?\n|("(\\.|[^"\\])*"|'(\\.|[^'\\])*'|.[^/"'\\]*)#defined $2 ? $2 : ""#gse;
    $preprecode =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/# #gs;
  }

  print "preprecode: [$preprecode]\n" if $self->{debug};

  print "looking for functions, has main: $has_main\n" if $self->{debug} >= 2;

  my $func_regex = qr/^([ *\w]+)\s+([ ()*\w:]+)\s*\(([^;{]*)\s*\)\s*({.*|<%.*|\?\?<.*)/ims;

  # look for potential functions to extract
  while($preprecode =~ /$func_regex/ms) {
    my ($pre_ret, $pre_ident, $pre_params, $pre_potential_body) = ($1, $2, $3, $4);
    my $precode_code;

    print "looking for functions, found [$pre_ret][$pre_ident][$pre_params][$pre_potential_body], has main: $has_main\n" if $self->{debug} >= 1;

    # find the pos at which this function lives, for extracting from precode
    $preprecode =~ m/(\Q$pre_ret\E\s+\Q$pre_ident\E\s*\(\s*\Q$pre_params\E\s*\)\s*\Q$pre_potential_body\E)/g;
    my $extract_pos = (pos $preprecode) - (length $1);

    # now that we have the pos, substitute out the extracted potential function from preprecode
    $preprecode =~ s/$func_regex//ms;

    # create tmpcode object that starts from extract pos, to skip any quoted code
    my $tmpcode = substr($precode, $extract_pos);
    $tmpcode =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/# #gs;
    print "tmpcode: [$tmpcode]\n" if $self->{debug};

    $precode = substr($precode, 0, $extract_pos);
    print "precode: [$precode]\n" if $self->{debug};
    $precode_code = $precode;

    $tmpcode =~ m/$func_regex/ms;
    my ($ret, $ident, $params, $potential_body) = ($1, $2, $3, $4);

    print "1st extract: [$ret][$ident][$params][$potential_body]\n" if $self->{debug};

    $ret =~ s/^\s+//;
    $ret =~ s/\s+$//;

    if(not length $ret
       or $ret eq "switch"
       or $ret eq "else"
       or $ret eq "while"
       or $ret eq "if"
       or $ret eq "for"
       or $ident eq "switch"
       or $ident eq "for"
       or $ident eq "while"
       or $ident eq "if") {
      $precode .= "$ret $ident ($params) $potential_body";
      next;
    } else {
      $tmpcode =~ s/$func_regex//ms;
    }

    $potential_body =~ s/^\s*<%/{/ms;
    $potential_body =~ s/%>\s*$/}/ms;
    $potential_body =~ s/^\s*\?\?</{/ms;
    $potential_body =~ s/\?\?>$/}/ms;

    my @extract = extract_bracketed($potential_body, '{}');
    my $body;
    if(not defined $extract[0]) {
      if($self->{debug} == 0) {
        print "error: unmatched brackets\n";
      } else {
        print "error: unmatched brackets for function '$ident';\n";
        print "body: [$potential_body]\n";
      }
      exit;
    } else {
      $body = $extract[0];
      $preprecode = $extract[1];
      $precode = $extract[1];
    }

    print "final extract: [$ret][$ident][$params][$body]\n" if $self->{debug};
    $self->{code} .= "$precode_code\n$ret $ident($params) $body\n";

    if($self->{debug} >= 2) { print '-' x 20 . "\n" }
    print "     code: [$self->{code}]\n" if $self->{debug} >= 2;
    if($self->{debug} >= 2) { print '-' x 20 . "\n" }
    print "  precode: [$precode]\n" if $self->{debug} >= 2;

    $has_main = 1 if $ident =~ m/^\s*\(?\s*main\s*\)?\s*$/;
  }

  $precode =~ s/^\s+//;
  $precode =~ s/\s+$//;

  $precode =~ s/^{(.*)}$/$1/s;

  if(not $has_main and not exists $self->{options}->{'-nomain'}) {
    if ($precode =~ s/^(};?)//) {
      $self->{code} .= $1;
    }

    print "pc: [$precode]\n" if $self->{debug};
    unless ($self->{no_gdb_extensions}) {
      if ($self->{code} !~ m/\b(?:ptype|dump|print|trace|watch|gdb)\b/ && $precode =~ m/(\n?)\s*(.*?);?$/) {
        my $stmt = $2;
        if ($stmt !~ m/\b(?:\w*scanf|fgets|memset|printf|puts|while|for|do|if|switch|ptype|dump|print|trace|watch|gdb|assert|main|return|exec[lvpe]+)\b/
          && $stmt !~ m/^\w+\s+(?<!sizeof )\w+/  # don't match `int a` but do match `sizeof a`
          && $stmt !~ m/[#{}]/                   # don't match preprocessor or structs/functions
          && $stmt !~ m{(?:/\*|\*/|//)}          # don't match comments
          && $stmt !~ m/\?\?/                    # don't match diagraphs
          && $stmt =~ m/\w/                      # must contain at least one word character
          && $stmt !~ m/(?:\b|\s)=(?:\b|\s)/) {  # don't match assignments, but do match equality (==)
          $precode =~ s/(\n?)\s*(.*?);?$/$1 print_last_statement($2);/;
        }
      }
    }

    $self->{code} = "$prelude\n$self->{code}\n" . "int main(int argc, char *argv[]) {\n$precode\n;\nreturn 0;\n}\n";
  } else {
    $self->{code} = "$prelude\n$self->{code}\n";
  }

  print "after func extract, code: [$self->{code}]\n" if $self->{debug};

  $self->{code} =~ s/\|n/\n/g;
  $self->{code} =~ s/^\s+//;
  $self->{code} =~ s/\s+$//;
  $self->{code} =~ s/;\s*;\n/;\n/gs;
  $self->{code} =~ s/;(\s*\/\*.*?\*\/\s*);\n/;$1/gs;
  $self->{code} =~ s/;(\s*\/\/.*?\s*);\n/;$1/gs;
  $self->{code} =~ s/({|})\n\s*;\n/$1\n/gs;
  $self->{code} =~ s/(?:\n\n)+/\n\n/g;

  print "final code: [$self->{code}]\n" if $self->{debug};
}

sub postprocess_output {
  my $self = shift;
  $self->SUPER::postprocess_output;

  my $output = $self->{output};

  $output =~ s/In file included from .*?from \/usr\/include\/prelude.h.*?from $self->{sourcefile}:\d+.\s*//msg;
  $output =~ s/In file included from .*?:\d+:\d+.\s*from $self->{sourcefile}:\d+.\s*//msg;
  $output =~ s/In file included from .*?:\d+:\d+.\s*//msg;
  $output =~ s/\s*from $self->{sourcefile}:\d+.\s*//g;
  $output =~ s/$self->{execfile}: $self->{sourcefile}:\d+: [^:]+: Assertion/Assertion/g;
  $output =~ s,/usr/include/[^:]+:\d+:\d+:\s+,,g;

  unless(exists $self->{options}->{'-paste'} or (defined $self->{got_run} and $self->{got_run} eq "paste")) {
    $output =~ s/ Line \d+ ://g;
    $output =~ s/$self->{sourcefile}:[:\d]*//g;
  } else {
    $output =~ s/$self->{sourcefile}:(\d+)/\n$1/g;
    $output =~ s/$self->{sourcefile}://g;
  }

  $output =~ s/;?\s?__PRETTY_FUNCTION__ = "[^"]+"//g;
  $output =~ s/(\d+:\d+:\s*)*cc1: (all\s+)?warnings being treated as errors//;
  $output =~ s/(\d+:\d+:\s*)* \(first use in this function\)//g;
  $output =~ s/(\d+:\d+:\s*)*error: \(Each undeclared identifier is reported only once.*?\)//msg;
  $output =~ s/(\d+:\d+:\s*)*ld: warning: cannot find entry symbol _start; defaulting to [^ ]+//;
  $output =~ s/(\d+:\d+:\s*)*\/tmp\/.*\.o://g;
  $output =~ s/(\d+:\d+:\s*)*collect2: ld returned \d+ exit status//g;
  $output =~ s/\(\.text\+[^)]+\)://g;
  $output =~ s/\[ In/[In/;
  $output =~ s/(\d+:\d+:\s*)*warning: Can't read pathname for load map: Input.output error.//g;
  my $left_quote = chr(226) . chr(128) . chr(152);
  my $right_quote = chr(226) . chr(128) . chr(153);
  $output =~ s/$left_quote/'/msg;
  $output =~ s/$right_quote/'/msg;
  $output =~ s/`/'/msg;
  $output =~ s/\t/   /g;
  if($output =~ /In function '([^']+)':/) {
    if($1 eq 'main') {
      $output =~ s/(\d+:\d+:\s*)*\s?In function .main.:\s*//g;
    } else {
      $output =~ s/(\d+:\d+:\s*)*\s?In function .main.:\s?/In function 'main':/g;
    }
  }
  $output =~ s/(\d+:\d+:\s*)*warning: unknown conversion type character 'b' in format \[-Wformat=?\]\s+(\d+:\d+:\s*)*warning: too many arguments for format \[-Wformat-extra-args\]/note: %b is a candide extension/g; #gcc
  $output =~ s/(\d+:\d+:\s*)*warning: invalid conversion specifier 'b' \[-Wformat-invalid-specifier\]/note: %b is a candide extension/g; #clang
  $output =~ s/(\d+:\d+:\s*)*warning: unknown conversion type character 'b' in format \[-Wformat=?\]/note: %b is a candide extension/g;
  $output =~ s/\s\(core dumped\)/./;
  $output =~ s/ \[enabled by default\]//g;
  $output =~ s/initializer\s+warning: \(near/initializer (near/g;
  $output =~ s/(\d+:\d+:\s*)*note: each undeclared identifier is reported only once for each function it appears in//g;
  $output =~ s/\(gdb\)//g;
  $output =~ s/", '\\(\d{3})' <repeats \d+ times>,? ?"/\\$1/g;
  $output =~ s/, '\\(\d{3})' <repeats \d+ times>\s*//g;
  $output =~ s/(\\000)+/\\0/g;
  $output =~ s/\\0[^">']+/\\0/g;
  $output =~ s/= (\d+) '\\0'/= $1/g;
  $output =~ s/\\0"/"/g;
  $output =~ s/"\\0/"/g;
  $output =~ s/\.\.\.>/>/g;
  $output =~ s/<\s*included at \/home\/compiler\/>\s*//g;
  $output =~ s/\s*compilation terminated due to -Wfatal-errors\.//g;
  $output =~ s/^======= Backtrace.*\[vsyscall\]\s*$//ms;
  $output =~ s/glibc detected \*\*\* \/home\/compiler\/$self->{execfile}: //;
  $output =~ s/: \/home\/compiler\/$self->{execfile} terminated//;
  $output =~ s/<Defined at \/home\/compiler\/>/<Defined at \/home\/compiler\/$self->{sourcefile}:0>/g;
  $output =~ s/\s*In file included from\s+\/usr\/include\/.*?:\d+:\d+:\s*/, /g;
  $output =~ s/\s*collect2: error: ld returned 1 exit status//g;
  $output =~ s/In function\s*`main':\s*\/home\/compiler\/ undefined reference to/error: undefined reference to/g;
  $output =~ s/\/home\/compiler\///g;
  $output =~ s/compilation terminated.//;
  $output =~ s/'(.*?)' = char/'$1' = int/g; $output =~ s/(\(\s*char\s*\)\s*'.*?') = int/$1 = char/; # gdb thinks 'a' is type char, which is not true for C
  $output =~ s/sizeof '(.*?)' = 1/sizeof '$1' = 4/g; # gdb thinks sizeof 'a' is sizeof char, which is not true for C
  $output =~ s/sizeof\('(.*?)'\) = 1/sizeof('$1') = 4/g; # gdb thinks sizeof 'a' is sizeof char, which is not true for C
  $output =~ s/= (-?\d+) ''/= $1/g;
  $output =~ s/, <incomplete sequence >//g;
  $output =~ s/\s*warning: shadowed declaration is here \[-Wshadow\]//g unless exists $self->{options}->{'-paste'} or (defined $self->{got_run} and $self->{got_run} eq 'paste');
  $output =~ s/\s*note: shadowed declaration is here//g unless exists $self->{options}->{'-paste'} or (defined $self->{got_run} and $self->{got_run} eq 'paste');
  $output =~ s/preprocessor macro>\s+<at\s+>/preprocessor macro>/g;
  $output =~ s/<No symbol table is loaded.  Use the "file" command.>\s*//g;
  $output =~ s/cc1: all warnings being treated as; errors//g;
  $output =~ s/, note: this is the location of the previous definition//g;
  $output =~ s/\s+note: previous declaration of '.*?' was here//g;
  $output =~ s/ called by gdb \(\) at statement: void gdb\(\) \{ __asm__\(""\); \}//g;
  $output =~ s/called by \?\? \(\) //g;
  $output =~ s/\s0x[a-z0-9]+: note: pointer points here.*?\^//gms;
  $output =~ s/\s0x[a-z0-9]+: note: pointer points here\s+<memory cannot be printed>//gms;
  $output =~ s/store to address 0x[a-z0-9]+ with insufficient space/store to address with insufficient space/gms;
  $output =~ s/load of misaligned address 0x[a-z0-9]+ for type/load of misaligned address for type/gms;
  $output =~ s/=+\s+==\d+==ERROR: (.*?) on address.*==\d+==ABORTING\s*/$1\n/gms;
  $output =~ s/Copyright \(C\) 2015 Free Software Foundation.*//ms;
  $output =~ s/==\d+==WARNING: unexpected format specifier in printf interceptor: %[^\s]+\s*//gms;
  $output =~ s/(Defined at .*?)\s+included at/$1/msg;
  $output =~ s/^\nno output/no output/ms;
  $output =~ s/expand ([^\s]+)expands to/expand $1 expands to/g;

  $output =~ s/(note: %b is a candide extension\s*)+/note: %b is a candide extension  /g;
  $output =~ s/candide extension\s+\]/candide extension]/;

  my $removed_warning = 0;

  $removed_warning++ if $output =~ s/\s*warning: ISO C forbids nested functions \[-pedantic\]\s*/ /g;
  $removed_warning++ if $output =~ s/\s*warning: too many arguments in call to 'gdb'\s+note: expanded from macro '.*?'\s*/ /msg;

  if($removed_warning) {
    $output =~ s/^\[\s*\]\s//;
    $output =~ s/^\[\s+/[/m;
    $output =~ s/\s+\]$/]/m;
  }

  $output =~ s/^\[\s+(warning:|note:)/[$1/;  # remove leading spaces in first warning/info

  if($self->{warn_unterminated_define} == 1) {
    if($output =~ m/^\[(warning:|note:)/) {
      $output =~ s/^\[/[warning: preprocessor directive not terminated by \\n, the remainder of the line will be part of this directive /;
    } else {
      $output =~ s/^/[warning: preprocessor directive not terminated by \\n, the remainder of the line will be part of this directive] /;
    }
  }

  $output =~ s/preprocessor macro\s+at/preprocessor macro/g;

  $self->{output} = $output;
}

1;
