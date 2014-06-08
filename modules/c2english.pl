#!/usr/bin/perl

use warnings;
use strict;

use Text::Balanced qw(extract_codeblock extract_delimited);

my $code = join ' ', @ARGV;
my $output;

my $force;
if($code =~ s/^-f\s+//) {
  $force = 1;
}

$code =~ s/#include <([^>]+)>/\n#include <$1>\n/g;
$code =~ s/#([^ ]+) (.*?)\\n/\n#$1 $2\n/g;
$code =~ s/#([\w\d_]+)\\n/\n#$1\n/g;

my $original_code = $code;

my $precode = $code;
$code = '';

my ($has_function, $has_main);

my $prelude_base = "#define _XOPEN_SOURCE 9001\n#define __USE_XOPEN\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n#include <math.h>\n#include <limits.h>\n#include <sys/types.h>\n#include <stdint.h>\n#include <errno.h>\n#include <ctype.h>\n#include <assert.h>\n\n";
my $prelude = $prelude_base;
$prelude .= "$1$2" if $precode =~ s/^\s*(#.*)(#.*?[>\n])//s;

my $preprecode = $precode;

while($preprecode =~ s/([ a-zA-Z0-9\_\*\[\]]+)\s+([a-zA-Z0-9_*]+)\s*\((.*?)\)\s*({.*)//) {
  my ($ret, $ident, $params, $potential_body) = ($1, $2, $3, $4);

  $ret =~ s/^\s+//;
  $ret =~ s/\s+$//;

  if($ret eq "else" or $ret eq "while") {
    $precode .= "$ret $ident ($params) $potential_body";
    next;
  } else {
    $precode =~ s/([ a-zA-Z0-9\_\*\[\]]+)\s+([a-zA-Z0-9_*]+)\s*\((.*?)\)\s*({.*)//;
  }

  my @extract = extract_codeblock($potential_body, '{}');
  my $body;
  if(not defined $extract[0]) {
    $output = "error: unmatched brackets for function '$ident';\n";
    $body = $extract[1];
  } else {
    $body = $extract[0];
    $preprecode .= $extract[1];
    $precode .= $extract[1];
  }
  $code .= "$ret $ident($params) $body\n\n";
  $has_function = 1;
  $has_main = 1 if $ident eq 'main';
}

$precode =~ s/^\s+//;
$precode =~ s/\s+$//;

if(not $has_main) {
  $code = "$prelude\n\n$code\n\nint main(void) {\n$precode\n;\nreturn 0;}\n";
} else {
  $code = "$prelude\n\n$precode\n\n$code\n";
}

$code =~ s/\|n/\n/g;
$code =~ s/^\s+//;
$code =~ s/\s+$//;
$code =~ s/;\s*;\n/;\n/gs;
$code =~ s/;(\s*\/\*.*?\*\/\s*);\n/;$1/gs;
$code =~ s/;(\s*\/\/.*?\s*);\n/;$1/gs;
$code =~ s/({|})\n\s*;\n/$1\n/gs;

chdir "c2english" or die "Could not chdir: $!";

open my $fh, '>', 'code.c' or die "Could not write code: $!";
print $fh $code;
close $fh;

#my ($ret, $result) = execute(10, "gcc -std=c89 -pedantic -Werror -Wno-unused -fsyntax-only -fno-diagnostics-show-option -fno-diagnostics-show-caret code.c");
my ($ret, $result) = execute(10, "gcc -std=gnu89 -Werror -Wno-unused -fsyntax-only -fno-diagnostics-show-option -fno-diagnostics-show-caret code.c");

if(not $force and $ret != 0) {
  $output = $result;

  $output =~ s/code\.c:\d+:\d+://g;
  $output =~ s/code\.c://g;
  $output =~ s/error=edantic/error=pedantic/g;
  $output =~ s/(\d+:\d+:\s*)*cc1: all warnings being treated as errors//;
  $output =~ s/(\d+:\d+:\s*)* \(first use in this function\)//g;
  $output =~ s/(\d+:\d+:\s*)*error: \(Each undeclared identifier is reported only once.*?\)//msg;
  $output =~ s/(\d+:\d+:\s*)*ld: warning: cannot find entry symbol _start; defaulting to [^ ]+//;
  #$output =~ s/(\d+:\d+:\s*)*error: (.*?) error/error: $1; error/msg;
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
  $output =~ s/(\d+:\d+:\s*)*\s*In function .main.:\s*//g;
  $output =~ s/(\d+:\d+:\s*)*warning: unknown conversion type character 'b' in format \[-Wformat\]\s+(\d+:\d+:\s*)*warning: too many arguments for format \[-Wformat-extra-args\]/info: %b is a candide extension/g;
  $output =~ s/(\d+:\d+:\s*)*warning: unknown conversion type character 'b' in format \[-Wformat\]//g;
  $output =~ s/\s\(core dumped\)/./;
#  $output =~ s/\[\s+/[/g;
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
  $output =~ s/(\\\d{3})+//g;
  $output =~ s/<\s*included at \/home\/compiler\/>\s*//g;
  $output =~ s/\s*compilation terminated due to -Wfatal-errors\.//g;
  $output =~ s/^======= Backtrace.*\[vsyscall\]\s*$//ms;
  $output =~ s/glibc detected \*\*\* \/home\/compiler\/code: //;
  $output =~ s/: \/home\/compiler\/code terminated//;
  $output =~ s/<Defined at \/home\/compiler\/>/<Defined at \/home\/compiler\/code.c:0>/g;
  $output =~ s/\s*In file included from\s+\/usr\/include\/.*?:\d+:\d+:\s*/, /g;
  $output =~ s/\s*collect2: error: ld returned 1 exit status//g;
  $output =~ s/In function\s*`main':\s*\/home\/compiler\/ undefined reference to/error: undefined reference to/g;
  $output =~ s/\/home\/compiler\///g;
  $output =~ s/compilation terminated.//;
  $output =~ s/<'(.*)' = char>/<'$1' = int>/g;
  $output =~ s/= (-?\d+) ''/= $1/g;
  $output =~ s/, <incomplete sequence >//g;
  $output =~ s/\s*error: expected ';' before 'return'//g;
  $output =~ s/^\s+//;
  $output =~ s/\s+$//;
  $output =~ s/error: ISO C forbids nested functions\s+//g;

  # don't error about undeclared objects
  $output =~ s/error: '[^']+' undeclared\s*//g;

  if(length $output) {
    print "$output\n";
    exit 0;
  } else {
    $output = undef;
  }
}

$code =~ s/^\Q$prelude_base\E\s*//;

open my $fh, '>', 'code2eng.c' or die "Could not write code: $!";
print $fh $code;
close $fh;

$output = `./c2eng.pl code2eng.c` if not defined $output;

if(not $has_function and not $has_main) {
  $output =~ s/Let .main. be a function taking no parameters and returning int.\s*To perform the function:\s*//;
  $output =~ s/\s*Return 0.\s*$//;
  $output =~ s/\s*Return 0.\s*End of function .main..\s*//;
  $output =~ s/\s*Do nothing.\s*$//;
  $output =~ s/^\s*(.)/\U$1/;
}

$output =~ s/\s+/ /;
if(not $output) {
  $output = "Does not compute.  I only know about C89 and valid code.\n";
}

print "[Note: Work-in-progress; may be issues!] $output\n";

sub execute {
  my $timeout = shift @_;
  my ($cmdline) = @_;

  my ($ret, $result);

  ($ret, $result) = eval {
    my $result = '';

    my $pid = open(my $fh, '-|', "$cmdline 2>&1");

    local $SIG{ALRM} = sub { kill 'TERM', $pid; die "$result [Timed-out]\n"; };
    alarm($timeout);

    while(my $line = <$fh>) {
      $result .= $line;
    }

    close $fh;
    my $ret = $? >> 8;
    alarm 0;
    return ($ret, $result);
  };

  alarm 0;

  if($@ =~ /Timed-out/) {
    return (-1, $@);
  }

  return ($ret, $result);
}
