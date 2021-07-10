#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

use Text::Balanced qw(extract_codeblock extract_delimited extract_bracketed);

use feature 'switch';
no if $] >= 5.018, warnings => 'experimental::smartmatch';

my $debug = 0;

my $code = join ' ', @ARGV;

if (not length $code) {
    print "Usage: english <any C11 code>\n";
    exit;
}

my $output;

my $force;
if ($code =~ s/^-f\s+//) { $force = 1; }

my ($has_function, $has_main, $got_nomain);
my $prelude_base =
  "#define _XOPEN_SOURCE 9001\n#define __USE_XOPEN\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n#include <math.h>\n#include <limits.h>\n#include <sys/types.h>\n#include <stdint.h>\n#include <errno.h>\n#include <ctype.h>\n#include <assert.h>\n#include <stdnoreturn.h>\n#include <stdbool.h>\n#include <stdalign.h>\n#include <time.h>\n#include <stddef.h>\n#include <uchar.h>\n#define _Atomic\n#define _Static_assert(a, b)\n\n";
my $prelude = $prelude_base;

print "code before: [$code]\n" if $debug;

# replace \n outside of quotes with literal newline
my $new_code = "";

use constant {
    NORMAL        => 0,
    DOUBLE_QUOTED => 1,
    SINGLE_QUOTED => 2,
};

my $state   = NORMAL;
my $escaped = 0;

while ($code =~ m/(.)/gs) {
    my $ch = $1;

    given ($ch) {
        when ('\\') {
            if ($escaped == 0) {
                $escaped = 1;
                next;
            }
        }

        if ($state == NORMAL) {
            when ($_ eq '"' and not $escaped) { $state = DOUBLE_QUOTED; }

            when ($_ eq "'" and not $escaped) { $state = SINGLE_QUOTED; }

            when ($_ eq 'n' and $escaped == 1) {
                $ch      = "\n";
                $escaped = 0;
            }
        }

        if ($state == DOUBLE_QUOTED) {
            when ($_ eq '"' and not $escaped) { $state = NORMAL; }
        }

        if ($state == SINGLE_QUOTED) {
            when ($_ eq "'" and not $escaped) { $state = NORMAL; }
        }
    }

    $new_code .= '\\' and $escaped = 0 if $escaped;
    $new_code .= $ch;
}

$code = $new_code;

print "code after \\n replacement: [$code]\n" if $debug;

my $single_quote = 0;
my $double_quote = 0;
my $parens       = 0;
$escaped = 0;
my $cpp = 0;    # preprocessor

while ($code =~ m/(.)/msg) {
    my $ch  = $1;
    my $pos = pos $code;

    print "adding newlines, ch = [$ch], parens: $parens, cpp: $cpp, single: $single_quote, double: $double_quote, escaped: $escaped, pos: $pos\n" if $debug >= 10;

    if ($ch eq '\\') { $escaped = not $escaped; }
    elsif ($ch eq '#' and not $cpp and not $escaped and not $single_quote and not $double_quote) {
        $cpp = 1;

        if ($code =~ m/include\s*[<"]([^>"]*)[>"]/msg) {
            my $match = $1;
            $pos = pos $code;
            substr($code, $pos, 0) = "\n";
            pos $code = $pos;
            $cpp = 0;
        } else {
            pos $code = $pos;
        }
    } elsif ($ch eq '"') {
        $double_quote = not $double_quote unless $escaped or $single_quote;
        $escaped      = 0;
    } elsif ($ch eq '(' and not $single_quote and not $double_quote) {
        $parens++;
    } elsif ($ch eq ')' and not $single_quote and not $double_quote) {
        $parens--;
        $parens = 0 if $parens < 0;
    } elsif ($ch eq ';' and not $cpp and not $single_quote and not $double_quote and $parens == 0) {
        if (not substr($code, $pos, 1) =~ m/[\n\r]/) {
            substr($code, $pos, 0) = "\n";
            pos $code = $pos + 1;
        }
    } elsif ($ch eq "'") {
        $single_quote = not $single_quote unless $escaped or $double_quote;
        $escaped      = 0;
    } elsif ($ch eq 'n' and $escaped) {
        if (not $single_quote and not $double_quote) {
            print "added newline\n" if $debug >= 10;
            substr($code, $pos - 2, 2) = "\n";
            pos $code = $pos;
            $cpp = 0;
        }
        $escaped = 0;
    } elsif ($ch eq '{' and not $cpp and not $single_quote and not $double_quote) {
        if (not substr($code, $pos, 1) =~ m/[\n\r]/) {
            substr($code, $pos, 0) = "\n";
            pos $code = $pos + 1;
        }
    } elsif ($ch eq '}' and not $cpp and not $single_quote and not $double_quote) {
        if (not substr($code, $pos, 1) =~ m/[\n\r;]/) {
            substr($code, $pos, 0) = "\n";
            pos $code = $pos + 1;
        }
    } elsif ($ch eq "\n" and $cpp and not $single_quote and not $double_quote) {
        $cpp = 0;
    } else {
        $escaped = 0;
    }
}

print "code after \\n additions: [$code]\n" if $debug;

# white-out contents of quoted literals
my $white_code = $code;
$white_code =~ s/(?:\"((?:\\\"|(?!\").)*)\")/'"' . ('-' x length $1) . '"'/ge;
$white_code =~ s/(?:\'((?:\\\'|(?!\').)*)\')/"'" . ('-' x length $1) . "'"/ge;

my $precode;
if   ($white_code =~ m/#include/) { $precode = $code; }
else                              { $precode = $prelude . $code; }
$code = '';
my $warn_unterminated_define = 0;

print "--- precode: [$precode]\n" if $debug;

my $lang = 'C89';

if ($lang eq 'C89' or $lang eq 'C99' or $lang eq 'C11' or $lang eq 'C++') {
    my $prelude = '';
    while ($precode =~ s/^\s*(#.*\n{1,2})//g) { $prelude .= $1; }

    if ($precode =~ m/^\s*(#.*)/ms) {
        my $line = $1;

        if ($line !~ m/\n/) { $warn_unterminated_define = 1; }
    }

    print "*** prelude: [$prelude]\n   precode: [$precode]\n" if $debug;

    my $preprecode = $precode;

    # white-out contents of quoted literals
    $preprecode =~ s/(?:\"((?:\\\"|(?!\").)*)\")/'"' . ('-' x length $1) . '"'/ge;
    $preprecode =~ s/(?:\'((?:\\\'|(?!\').)*)\')/"'" . ('-' x length $1) . "'"/ge;

    # strip C and C++ style comments
    if ($lang eq 'C89') {
        $preprecode =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/# #gs;
        $preprecode =~ s#|//([^\\]|[^\n][\n]?)*?\n|("(\\.|[^"\\])*"|'(\\.|[^'\\])*'|.[^/"'\\]*)#defined $2 ? $2 : ""#gse;
    } else {
        $preprecode =~ s#|//([^\\]|[^\n][\n]?)*?\n|("(\\.|[^"\\])*"|'(\\.|[^'\\])*'|.[^/"'\\]*)#defined $2 ? $2 : ""#gse;
        $preprecode =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/# #gs;
    }

    print "preprecode: [$preprecode]\n" if $debug;

    print "looking for functions, has main: $has_main\n" if $debug >= 2;

    my $func_regex = qr/^([ *\w]+)\s+([ ()*\w]+)\s*\(([^;{]*)\s*\)\s*({.*|<%.*|\?\?<.*)/ims;

    # look for potential functions to extract
    while ($preprecode =~ /$func_regex/ms) {
        my ($pre_ret, $pre_ident, $pre_params, $pre_potential_body) = ($1, $2, $3, $4);

        print "looking for functions, found [$pre_ret][$pre_ident][$pre_params][$pre_potential_body], has main: $has_main\n" if $debug >= 1;

        # find the pos at which this function lives, for extracting from precode
        $preprecode =~ m/(\Q$pre_ret\E\s+\Q$pre_ident\E\s*\(\s*\Q$pre_params\E\s*\)\s*\Q$pre_potential_body\E)/g;
        my $extract_pos = (pos $preprecode) - (length $1);

        # now that we have the pos, substitute out the extracted potential function from preprecode
        $preprecode =~ s/$func_regex//ms;

        # create tmpcode object that starts from extract pos, to skip any quoted code
        my $tmpcode = substr($precode, $extract_pos);
        print "tmpcode: [$tmpcode]\n" if $debug;

        $precode = substr($precode, 0, $extract_pos);
        print "precode: [$precode]\n" if $debug;

        $tmpcode =~ m/$func_regex/ms;
        my ($ret, $ident, $params, $potential_body) = ($1, $2, $3, $4);

        print "1st extract: [$ret][$ident][$params][$potential_body]\n" if $debug;

        $ret =~ s/^\s+//;
        $ret =~ s/\s+$//;

        if (not length $ret or $ret eq "else" or $ret eq "while" or $ret eq "if" or $ret eq "for" or $ident eq "for" or $ident eq "while" or $ident eq "if") {
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
        if (not defined $extract[0]) {
            if ($debug == 0) { print "error: unmatched brackets\n"; }
            else {
                print "error: unmatched brackets for function '$ident';\n";
                print "body: [$potential_body]\n";
            }
            exit;
        } else {
            $body = $extract[0];
            $preprecode .= $extract[1];
            $precode    .= $extract[1];
        }

        print "final extract: [$ret][$ident][$params][$body]\n" if $debug;
        $code .= "$ret $ident($params) $body\n\n";
        $has_main     = 1 if $ident =~ m/^\s*\(?\s*main\s*\)?\s*$/;
        $has_function = 1;
    }

    $precode =~ s/^\s+//;
    $precode =~ s/\s+$//;

    $precode =~ s/^{(.*)}$/$1/s;

    if (not $has_main and not $got_nomain) { $code = "$prelude\n$code" . "int main(void) {\n$precode\n;\n}\n"; }
    else {
        print "code: [$code]; precode: [$precode]\n" if $debug;
        $code = "$prelude\n$precode\n\n$code\n";
    }
} else {
    $code = $precode;
}

print "after func extract, code: [$code]\n" if $debug;

$code =~ s/\|n/\n/g;
$code =~ s/^\s+//;
$code =~ s/\s+$//;
$code =~ s/;\s*;\n/;\n/gs;
$code =~ s/(;)?(\s*\/\*.*?\*\/\s*);\n/$1$2/gs;
$code =~ s/(;)?(\s*\/\/.*?\s*);\n/$1$2/gs;
$code =~ s/({|})\n\s*;\n/$1\n/gs;
$code =~ s/(?:\n\n)+/\n\n/g;

print "final code: [$code]\n" if $debug;

chdir "c2english" or die "Could not chdir: $!";

open my $fh, '>', 'code.c' or die "Could not write code: $!";
print $fh $code;
close $fh;

#my ($ret, $result) = execute(10, "gcc -std=c89 -pedantic -Werror -Wno-unused -fsyntax-only -fno-diagnostics-show-option -fno-diagnostics-show-caret code.c");
my ($ret, $result) =
  execute(10, "gcc -std=c11 -pedantic -Werror -Wno-implicit -Wno-unused -fsyntax-only -fno-diagnostics-show-option -fno-diagnostics-show-caret code.c");

if (not $force and $ret != 0) {
    $output = $result;

    #print STDERR "output: [$output]\n";

    $output =~ s/\s*In file included from\s+.*?:\d+:\d+:\s*//g;
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
    my $left_quote  = chr(226) . chr(128) . chr(152);
    my $right_quote = chr(226) . chr(128) . chr(153);
    $output =~ s/$left_quote/'/msg;
    $output =~ s/$right_quote/'/msg;
    $output =~ s/`/'/msg;
    $output =~ s/\t/   /g;
    $output =~ s/(\d+:\d+:\s*)*\s*In function .main.:\s*//g;
    $output =~
      s/(\d+:\d+:\s*)*warning: unknown conversion type character 'b' in format \[-Wformat\]\s+(\d+:\d+:\s*)*warning: too many arguments for format \[-Wformat-extra-args\]/info: %b is a candide extension/g;
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

    #  $output =~ s/(\\\d{3})+//g;
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
    $output =~ s/\s*note: this is the location of the previous definition//g;
    $output =~ s/\s*note: use option -std=c99 or -std=gnu99 to compile your code//g;
    $output =~ s/\s*\(declared at .*?\)//g;
    $output =~ s/, note: declared here//g;
    $output =~ s#/usr/include/.*?.h:\d+:\d+:/##g;
    $output =~ s/\s*error: storage size of.*?isn't known\s*//g;
    $output =~ s/; did you mean '.*?'\?//g;

    # don't error about undeclared objects
    $output =~ s/error: '[^']+' undeclared\s*//g;

    if (length $output) {
        print "$output\n";
        exit 0;
    } else {
        $output = undef;
    }
}

$code =~ s/^\Q$prelude_base\E\s*//;

open $fh, '>', 'code2eng.c' or die "Could not write code: $!";
print $fh $code;
close $fh;

$output = `./c2eng.pl code2eng.c` if not defined $output;

if (not $has_function and not $has_main) {
    $output =~ s/Let .main. be a function taking no arguments and returning int.\s*When called, the function will.\s*(do nothing.)?//i;
    $output =~ s/\s*Return 0.\s*End of function .main..\s*//;
    $output =~ s/\s*Finally, return 0.$//;
    $output =~ s/\s*and then return 0.$/./;
    $output =~ s/\s*Do nothing.\s*$//;
    $output =~ s/^\s*(.)/\U$1/;
    $output =~ s/\.\s+(\S)/. \U$1/g;
} elsif ($has_function and not $has_main) {
    $output =~ s/\s*Let `main` be a function taking no arguments and returning int.\s*When called, the function will do nothing.//;
    $output =~ s/\s*Finally, return 0.$//;
    $output =~ s/\s*and then return 0.$/./;
}

$output =~ s/\s+/ /;
if (not $output) { $output = "Does not compute; I only understand valid C11 code.\n"; }

print "$output\n";

sub execute {
    my $timeout = shift @_;
    my ($cmdline) = @_;

    my ($ret, $result);

    ($ret, $result) = eval {
        my $result = '';

        my $pid = open(my $fh, '-|', "$cmdline 2>&1");

        local $SIG{ALRM} = sub { kill 'TERM', $pid; die "$result [Timed-out]\n"; };
        alarm($timeout);

        while (my $line = <$fh>) { $result .= $line; }

        close $fh;
        my $ret = $? >> 8;
        alarm 0;
        return ($ret, $result);
    };

    alarm 0;

    if ($@ =~ /Timed-out/) { return (-1, $@); }

    return ($ret, $result);
}
