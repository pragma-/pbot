# Applets

<!-- md-toc-begin -->
* [About](#about)
* [Creating applets](#creating-applets)
* [Documentation for built-in applets](#documentation-for-built-in-applets)
  * [cc](#cc)
    * [Usage](#usage)
    * [Supported Languages](#supported-languages)
    * [Default Language](#default-language)
    * [Disallowed system calls](#disallowed-system-calls)
    * [Program termination with no output](#program-termination-with-no-output)
    * [Abnormal program termination](#abnormal-program-termination)
    * [C and C++ Functionality](#c-and-c-functionality)
    * [Using the preprocessor](#using-the-preprocessor)
      * [Default #includes](#default-includes)
      * [Using #include](#using-include)
      * [Using #define](#using-define)
    * [main() Function Unnecessary](#main-function-unnecessary)
    * [Embedding Newlines](#embedding-newlines)
    * [Printing in binary/base2](#printing-in-binarybase2)
    * [Using the GDB debugger](#using-the-gdb-debugger)
      * [print](#print)
      * [ptype](#ptype)
      * [watch](#watch)
      * [trace](#trace)
      * [gdb](#gdb)
    * [Interactive Editing](#interactive-editing)
      * [copy](#copy)
      * [show](#show)
      * [diff](#diff)
      * [paste](#paste)
      * [run](#run)
      * [undo](#undo)
      * [s//](#s)
      * [replace](#replace)
      * [prepend](#prepend)
      * [append](#append)
      * [remove](#remove)
    * [Some Examples](#some-examples)
  * [english](#english)
  * [expand](#expand)
  * [prec](#prec)
  * [paren](#paren)
  * [faq](#faq)
  * [cfact](#cfact)
  * [cjeopardy](#cjeopardy)
    * [hint](#hint)
    * [what](#what)
    * [w](#w)
    * [filter](#filter)
    * [score](#score)
    * [rank](#rank)
    * [reset](#reset)
    * [qstats](#qstats)
    * [qshow](#qshow)
  * [c99std](#c99std)
  * [c11std](#c11std)
  * [man](#man)
  * [google](#google)
  * [define](#define)
  * [dict](#dict)
  * [foldoc](#foldoc)
  * [vera](#vera)
  * [udict](#udict)
  * [wdict](#wdict)
  * [acronym](#acronym)
  * [math](#math)
  * [calc](#calc)
  * [qalc](#qalc)
  * [compliment](#compliment)
  * [insult](#insult)
  * [excuse](#excuse)
  * [horoscope](#horoscope)
  * [quote](#quote)
<!-- md-toc-end -->

## About
Applets are external command-line executable programs and scripts that can be
loaded via PBot Factoids.

Command arguments are passed to Applet scripts/programs as command-line arguments. The
standard output from the Applet script/program is returned as the command result. The
standard error output is stored in a file named `<applet>-stderr` in the `applets/`
directory.

## Creating applets
Suppose you have the [Qalculate!](https://qalculate.github.io/) command-line
program and you want to provide a PBot command for it. You can create a _very_ simple
shell script containing:

    #!/bin/sh
    qalc "$*"

And let's call it `qalc.sh` and put it in PBot's `applets/` directory.

Then you can use the [`load`](Admin.md#load) command:

    !load qalc qalc.sh

Note: this is equivalent to creating a factoid and setting its `type` to `applet`:

    !factadd global qalc qalc.sh
    !factset global qalc type applet

Now you have a `qalc` calculator in PBot!

    <pragma-> !qalc 2 * 2
       <PBot> 2 * 2 = 4

## Documentation for built-in applets
PBot comes with several Applets included. Here is the documentation for most of them.

### cc
Code compiler (and executor).  This command will compile and execute user-provided code in a number of languages, and then display the compiler and/or program output.

The program is executed within a gdb debugger instance, which may be interacted with via the [gdb macros described below](#using-the-gdb-debugger) or with the `gdb("command")` function.

The compiler and program are executed inside a virtual machine.  After each run, the virtual machine is restored to a previous state.  No system calls have been disallowed.  You can write to and read from the filesystem, provided you do it in the same program.  The network cable has been unplugged.  You are free to write and test any code you like.  Have fun.

#### Usage

- `cc [-lang=<language>] [-info] [-paste] [-args "command-line arguments"] [-stdin "stdin input"] [compiler/language options] <code>`
- `cc <run|undo|show|paste|copy|replace|prepend|append|remove|s/// [and ...]>`
- `cc <diff>`
- `[nick] { <same as above without the cc in front> }`

You can pass any gcc compiler options.  By default, `-Wall -Wextra -std=c11 -pedantic` are passed unless an option is specified.

The `-paste` option will pretty-format and paste the code/output to a paste site and display the URL (useful to preserve newlines in output, and to refer to line-numbers).

The `-nomain` flag will prevent the code from being wrapped with a `main()` function. This is not necessary if you're explicitly defining a `main` function; it's only necessary if you don't want a `main` function at all.

The `-noheaders` flag will prevent any of the default headers from being added to the code. This is not necessary if you explicitly include any headers since doing so will override the default headers. This flag is only necessary if you want absolutely no headers whatsoever.

The `-stdin <stdin input>` option provides STDIN input (i.e., `scanf()`, `getc(stdin)`, etc.).

The `-args <command-line arguments>` option provides command-line arguments (i.e., `argv`).

The `run`, `undo`, `show`, `replace`, etc commands are part of [interactive-editing](#interactive-editing).

The `diff` command can be used to display the differences between the two most recent snippets.

#### Supported Languages
The `-lang` option can be used to specify an alternate compiler or language. Use `-lang=?` to list available languages.

    <pragma-> cc -lang=?
       <PBot> Language '?' is not supported. Supported languages are: bash, bc, bf, c11, c89, c99, clang, clang11, clang89, clang99, clang++, clisp, c++, freebasic, go, haskell, java, javascript, ksh, lua, perl, php, python, python3, qbasic, ruby, scheme, sh, tcl, tendra, zsh

Most, if not all, of these languages have an direct alias to invoke them.

    <pragma-> factshow perl
       <PBot> [global] perl: /call cc -lang=perl $args
    <pragma-> perl print 'hi'
       <PBot> hi

#### Default Language
The default language (e.g., without an explicit `-lang` or `-std` option) is C11 pedantic; which is `gcc -Wall -Wextra -std=c11 -pedantic`.

#### Disallowed system calls
None.  The network cable has been unplugged.  Other than that, anything goes.  Have fun.

#### Program termination with no output
If there is no output, information about the local variables and/or the last statement will be displayed.

    <pragma-> cc int x = 5, y = 16; x ^= y, y ^= x, x ^= y;
       <PBot> pragma-:  no output: x = 16; y = 5

<!-- -->

    <pragma-> cc #include <sys/utsname.h> struct utsname u; uname(&u);
       <PBot> pragma-:  no output: u = {sysname = "Linux", nodename = "compiler", release = "3.2.0-8-generic", version = "#15-Ubuntu SMP Wed Jan 11 13:57:44 UTC 2012", machine = "x86_64",  __domainname = "(none)"}

<!-- -->

    <pragma-> cc int a = 2, b = 3;  ++a + b;
       <PBot> pragma-:  no output: ++a + b = 6; a = 3; b = 3

<!-- -->

    <pragma-> cc sizeof (char)
       <PBot> pragma-:  no output: sizeof (char) = 1

<!-- -->

    <pragma-> cc 2 + 2
       <PBot> pragma-:  no output: 2 + 2 = 4

#### Abnormal program termination
If a signal is detected, the bot will display useful information.

    < pragma-> cc char *p = 0; *p = 1;
        <PBot> pragma-: Program received signal 11 (SIGSEGV) at statement: *p = 1; <local variables: p = 0x0>

<!-- -->

    <pragma-> cc void bang() { char *p = 0, s[] = "lol"; strcpy(p, s); }  bang();
       <PBot> pragma-: Program received signal 11 (SIGSEGV) in bang () at statement: strcpy(p, s); <local variables: p = 0x0, s = "lol">

<!-- -->

    <pragma-> cc int a = 2 / 0;
       <PBot> pragma-: [In function 'main': warning: division by zero] Program received signal 8 (SIGFPE) at statement: int a = 2 / 0;

#### C and C++ Functionality
#### Using the preprocessor

##### Default #includes
These are the default includes for C11.  To get the most up-to-date list of #includes, use the `cc paste` command.

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

##### Using #include
In C and C++, you may `#include <file.h>` one after another on the same line.  The bot will automatically put them on separate lines.  If you do use `#include`, the files you specify will replace the default includes.  You do not need to append a `\n` after the `#include`.

    <pragma-> cc #include <sys/utsname.h> struct utsname u; uname(&u);
       <PBot> pragma-:  <no output: u = {sysname = "Linux", nodename = "compiler", release = "3.2.0-8-generic", version = "#15-Ubuntu SMP Wed Jan 11 13:57:44 UTC 2012", machine = "x86_64",  __domainname = "(none)"}>

<!-- -->

    <pragma-> cc #include <stdio.h> #include <stdlib.h> void func(void) { puts("Hello, world"); } func();
       <PBot> pragma-: Hello, World

In the previous examples, only the specified includes (e.g., `<sys/utsname.h>` in the first example, `<stdio.h>` and `<stdlib.h>` in the second, will be included instead of the default includes.

##### Using #define
You can also `#define` macros; however, `#defines` require an explicit `\n` sequence to terminate, oe the remainder of the line will be part of the macro.

    <pragma-> cc #define GREETING "Hello, World"\n puts(GREETING);
       <PBot> pragma-: Hello, World

#### main() Function Unnecessary
In C and C++, if there is no `main` function, then a `main` function will created and wrapped around the appropriate bits of your code (unless the `-nomain` flag was specified); anything outside of any functions, excluding preprocessor stuff, will be put into this new `main` function.

    <pragma-> cc -paste int add(int a, int b) { return a + b; } printf("4 + 6 = %d -- ", add(4, 6)); int add3(int a, int b, int c)
            { return add(a, b) + c; } printf("7 + 8 + 9 = %d", add3(7, 8, 9));
       <PBot> http://sprunge.us/ehRA?c

The `-paste` flag causes the code to be pretty-formatted and pasted with output in comments to a paste site, which displays the following:

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
    #include <prelude.h>


    int add(int a, int b) {
        return a + b;
    }

    int add3(int a, int b, int c) {
        return add(a, b) + c;
    }

    int main(void) {
        printf("4 + 6 = %d -- ", add(4, 6));

        printf("7 + 8 + 9 = %d", add3(7, 8, 9));
        return 0;
    }

    /************* OUTPUT *************
    4 + 6 = 10 -- 7 + 8 + 9 = 24
    ************** OUTPUT *************/

#### Embedding Newlines
Any `\n` character sequence appearing outside of a character literal or a string literal will be replaced with a literal newline.

#### Printing in binary/base2
A freenode ##c regular, Wulf, has provided a printf format specifier `b` which can be used to print values in base2.

    <Wulf> cc printf("%b", 1234567);
    <PBot> 000100101101011010000111

<!-- -->

    <Wulf> cc printf("%#'b", 1234567);
    <PBot> 0001.0010.1101.0110.1000.0111

#### Using the GDB debugger
The program is executed within a gdb debugger instance, which may be interacted with via the following gdb macros.

##### print
The `print()` macro prints the values of expressions.  Useful for printing out structures and arrays.

    <pragma-> cc int a[] = { 1, 2, 3 }; print(a);
       <PBot> pragma-: a = {1, 2, 3}

<!-- -->

    <pragma-> cc #include <sys/utsname.h> struct utsname u; uname(&u); print(u);
       <PBot> pragma-: u = {sysname = "Linux", nodename = "compiler", release = "3.2.0-8-generic", version = "#15-Ubuntu SMP Wed Jan 11 13:57:44 UTC 2012", machine = "x86_64",  __domainname = "(none)"}

<!-- -->

    <pragma-> cc print(sizeof(int));
       <PBot> pragma-: sizeof(int) = 4

<!-- -->

    <pragma-> cc print(2+2);
       <PBot> pragma-: 2 + 2 = 4

##### ptype
The `ptype()` macro prints the types of expressions.

    <pragma-> cc int *a[] = {0}; ptype(a); ptype(a[0]); ptype(*a[0]);
       <PBot> pragma-: a = int *[1]  a[0] = int *  *a[0] = int

##### watch
The `watch()` macro watches a variable and displays its value when it changes.

    <pragma-> cc int n = 0, last = 1; watch(n); while(n <= 144) { n += last; last = n - last; } /* fibonacci */
       <PBot> pragma-: n = 1  n = 2  n = 3  n = 5  n = 8  n = 13  n = 21  n = 34  n = 55  n = 89  n = 144

##### trace
The `trace()` macro traces a function's calls, displaying passed and returned values.

    <pragma-> ,cc trace(foo); char *foo(int n) { puo, world"); return "Good-bye, world"; } foo(42);
       <PBot> pragma-: entered [1] foo (n=42)  Hello, world  leaving [1] foo (n=42), returned 0x401006 "Good-bye, world"

##### gdb
The `gdb()` function takes a string argument which it passes to the gdb debugger and then displays the output if any.

    <pragma-> ,cc gdb("info macro NULL");
       <PBot> pragma-: Defined at /usr/lib/gcc/x86_64-linux-gnu/4.7/include/stddef.h:402  #define NULL ((void *)0)

<!-- -->

    <pragma-> ,cc void foo() { gdb("info frame"); } foo();
       <PBot> pragma-: Stack level 1, frame at 0x7fffffffe660: rip = 0x400e28 in foo (); saved rip 0x400e43 called by frame at 0x7fffffffe680, caller of frame at 0x7fffffffe650 source language c. Arglist at 0x7fffffffe650, args: Locals at 0x7fffffffe650, Previous frame's sp is 0x7fffffffe660 Saved registers: rbp at 0x7fffffffe650, rip at 0x7fffffffe658

#### Interactive Editing
The [cc](#cc) command supports interactive-editing.  The general syntax is:  `cc [command]`.

Each cc snippet is saved in a buffer which is named after the channel or nick it was used in.  You can use [show](#show) or [diff](#diff) with a buffer argument to view that buffer; otherwise you can use the [copy](#copy) command to copy the most recent snippet of another buffer into the current buffer and optionally chain it with another command -- for example, to copy the `##c` buffer (e.g., from a private message or a different channel) and paste it: `cc copy ##c and paste`.

The commands are:  [copy](#copy), [show](#show), [diff](#diff), [paste](#paste), [run](#run), [undo](#undo), [s//](#s), [replace](#replace), [prepend](#prepend), [append](#append), and [remove](#remove).  Most of the commands may be chained together by separating them with whitespace or "and".

The commands are described in more detail below:

##### copy
To copy the most recent snippet from another buffer (e.g., to copy another channel's or private message's buffer to your own private message or channel), use the `copy` command.  Other commands can optionally be chained after this command.

Usage: `cc copy <buffer> [and ...]`

##### show
To show the latest code in the buffer, use the `show` command.  This command can take an optional buffer argument.

    <pragma-> cc show
       <PBot> pragma-: printf("Hello, world!");

This command is stand-alone and cannot be chained with other interactive-editing commands.

##### diff
To see the differences between the two most recent snippets, use the `diff` command.  This command can take an optional buffer argument.

    <pragma-> cc diff
       <PBot> pragma: printf("<replaced `Hello` with `Good-bye`>, <replaced `world` with `void`>");

This command is stand-alone and cannot be chained with other interactive-editing commands.

##### paste
To paste the full source of the latest code in the buffer as the compiler sees it, use the `paste` command:

    <pragma-> cc paste
       <PBot> pragma-: http://some.random.paste-site.com/paste/results

This command is stand-alone and cannot be chained with other interactive-editing commands.

##### run
To attempt to compile and execute the latest code in the buffer, use the `run` command:

    <pragma-> cc run
       <PBot> pragma-: Hello, world!

This command is stand-alone and cannot be chained with other interactive-editing commands.

##### undo
To undo any changes, use `undo`.  The `undo` command must be the first command before any subsequent commands.

##### s//
To change the latest code in the buffer, use the `s/regex/substitution/[gi]` pattern.

    <pragma-> cc s/Hello/Good-bye/ and s/world/void/
       <PBot> pragma-: Good-bye, void!
    <pragma-> cc show
       <PBot> pragma-: printf("Good-bye, void!");

##### replace
Alternatively, you may use the `replace` command.  The usage is (note the required single-quotes):

`cc replace [all, first, second, ..., tenth, last] 'from' with 'to'`

##### prepend
Text may be prepended with the `prepend` command:

`cc prepend 'text'`

##### append
Text may be appended with the `append` command:

`cc append 'text'`

##### remove
Text may be deleted with the `remove` command:

`cc remove [all, first, second, ..., tenth, last] 'text'`

#### Some Examples

    <pragma-> cc int fib2(int n, int p0, int p1) { return n == 1 ? p1 : fib2(n  - 1, p1, p0 + p1); }
                int fib(int n) { return n == 0 ? 0 : fib2(n, 0, 1); } for(int i = 0; i < 21; i++) printf("%d ", fib(i));
       <PBot> pragma-: 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181 6765

<!-- -->

    <pragma-> cc int i = 0, last = 1; while(i <= 7000) { printf("%d ", i); i += last; last = i - last; }
       <PBot> pragma-: 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181 6765

<!-- -->

    <Icewing> cc int n=0, f[2]={0,1}; while(n<20) printf("%d ",f[++n&1]=f[0]+f[1]); // based on cehteh
       <PBot> Icewing: 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181 6765

<!-- -->

  <3monkeys> cc @p=(0,1); until($#p>20) { print"$p[-2]\n"; push @p, $p[-2] + $p[-1] } -lang=Perl
      <PBot> 3monkeys: 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181

<!-- -->

    <spiewak> cc -lang=Ruby p,c=0,1; 20.times{p p; c=p+p=c}
       <PBot> spiewak: 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181

<!-- -->

    <Jafet> cc main = print $ take 20 $ let fibs = 0 : scanl (+) 1 fibs in fibs; -lang=Haskell
     <PBot> Jafet: [0,1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597,2584,4181]

### english
Converts C11 code into English sentences.

Usage: english `<C snippet>`

    <pragma-> english char (*a)[10];  char *b[10];
       <PBot> Let a be a pointer to an array of length 10 of type char. Let b be an array of length 10 of type pointer to char.

<!-- -->

    <pragma-> english for(;;);
       <PBot> Repeatedly do nothing.

<!-- -->

    <pragma-> english typedef char Batman; char Bruce_Wayne; char superhero = (Batman) Bruce_Wayne;
       <PBot> Let Batman be another name for a character. Let Bruce_Wayne be a character. Let superhero be a character, with value being Bruce_Wayne cast to a Batman.

### expand
Expands macros in C code and displays the resulting code.  Macros must be terminated by a `\n` sequence.  You may `#include` headers to expand macros defined within.

Usage: `expand <C snippet>`

    <pragma-> expand #define WHILE while ( \n #define DO ) { \n #define WEND } \n  int i = 5; WHILE --i DO puts("hi"); WEND
       <PBot> pragma-: int i = 5; while ( --i ) { puts("hi"); }
    <pragma-> expand #include <stdlib.h> NULL
       <PBot> pragma-: ((void *)0)

### prec
### paren
Shows operator precedence in C99 expressions by adding parentheses.
Usage: `prec <expression>` `paren <expression>`

    <pragma-> prec *a++
       <PBot> pragma-: *(a++)

<!-- -->

    <pragma-> prec a = b & c
       <PBot> pragma-: a = (b & c)

<!-- -->

    <pragma-> prec token = strtok(s, d) != NULL
       <PBot> pragma-: token = (strtok(s, d) != NULL)

### faq
Displays questions from the [http://http://www.eskimo.com/~scs/C-faq/top.html](comp.lang.c FAQ).  Some queries may return more than one result; if this happens, you may use the `match #` optional argument to specify the match you'd like to view.

Usage: `faq [match #] <search regex>`

    <pragma-> faq cast malloc
       <PBot> 2 results, displaying #1: 7. Memory Allocation, 7.6 Why am I getting ``warning: assignment of pointer from integer lacks a cast** for calls to malloc? : http://www.eskimo.com/~scs/C-faq/q7.6.html
    <pragma-> faq 2 cast malloc
       <PBot> 2 results, displaying #2: 7. Memory Allocation, 7.7 Why does some code carefully cast the values returned by  malloc to the pointer type being allocated? : http://www.eskimo.com/~scs/C-faq/q7.7.html
    <pragma-> faq ^6.4
       <PBot> 6. Arrays and Pointers, 6.4 Why are array and pointer declarations interchangeable as function formal parameters? : http://www.eskimo.com/~scs/C-faq/q6.4.html

### cfact
Displays a random C fact.  You may specify a search text to limit the random set to those containing that text.

`Usage: cfact [search text]`

    <pragma-> cfact
       <PBot> pragma-: [6.7.2.1 Structure and union specifiers] A structure or union may have a member declared to consist of a specified number of bits. Such a member is called a bit-field.

### cjeopardy
C Jeopardy is loosely based on the Jeopardy! game show. The questions are phrased in the form of an answer and are answered in the form of a question.

There are approximately 1,330 questions. All of the questions are sentences extracted from the C11 draft standard PDF, with certain nouns or phrases replaced with `this`. The goal of the game
is to answer the correct noun or phrase.

The `cjeopardy` command displays a random C Jeopardy question.  You can specify a search text to limit the random set to those containing that text.
Can be used to skip the current question after 5 minutes have elapsed.

Usage: `cjeopardy [search text]`

Example game:

    <pragma-> !cjeopardy
       <PBot> 1009) This macro expands to a integer constant expressions that can be used as the argument to the exit function to return successful termination status to the host environment.
    <pragma-> !what is EXIT_SUCCESS?
       <PBot> pragma-: 'EXIT_SUCCESS' is correct! (1m15s)
       <PBot> pragma-: Next question: 288) Of an integer type, this is the number of bits it uses to represent values, including any sign and padding bits.
    <pragma-> !w width
       <PBot> pragma-: 'width' is correct! (25s)
       <PBot> pragma-: Next question: 83) A byte with all bits set to 0 is called this.
       <jdoe> !hint
       <PBot> Hint: n... ...r....r
       <jdoe> !w null integer
       <PBot> jdoe: Sorry, 'null integer' is only 50.0% correct.
       <jdoe> !w null character
    <pragma-> !w null character
       <PBot> jdoe: 'null character' is correct! (2m15s)
       <PBot> pragma-: Too slow by 2s, jdoe got the correct answer!

#### hint
Displays a hint for the current C Jeopardy question. Each subsequent hint request reveals more of the answer.

When an answer can have multiple forms, the hint always chooses the longest one.

#### what
#### w
Answers a C Jeopardy question. `w` may be used as an alternative short-hand.

Usage: `what is <answer>?`

Usage: `w <answer>`

#### filter
`filter` can skip questions containing undesirable words such as wide-character or floating-point.

Usage: `filter <comma separated list of words>` or `filter clear` to clear the filter.

#### score
Shows the personal C Jeopardy statistics for a player. If used without any arguments, it shows your own statistics.

Usage: `score [player name]`

#### rank
Shows ranking for various C Jeopardy statistics, or your personal rankings in each of the statistics. If used without any arguments, it shows the available keywords for which statistics to rank.

Usage: `rank [keyword or player name]`

#### reset
Resets your personal C Jeopardy statistics for the current session. Your life-time records will still be retained.

#### qstats
Shows statistics specific to a C Jeopardy question. Can also rank questions by a specific statistic.

Usage: `qstats [question id]`

Usage: `qstats rank [keyword or question id]`

#### qshow
Displays a specific C Jeopardy question without making it the current question. Useful for seeing which question belongs to a question id; .e.g. with `qstats`.

Usage: `qshow <question id>`

### c99std
Searches ISO/IEC 9899:TC3 (WG14/N1256), also known as the C99 draft standard.   http://www.open-std.org/jtc1/sc22/WG14/www/docs/n1256.pdf

Usage: `c99std [-list] [-n#] [section] [search regex]`

If specified, `section` must be in the form of `X.YpZ` where `X` and `Y` are section/chapter and, optionally, `pZ` is paragraph.

To display a specific section and all its paragraphs, specify just the `section` without `pZ`.

To display just a specific paragraph, specify the full `section` identifier (`X.YpZ`).

You may use `-n #` to skip to the nth match.

To list only the section numbers containing 'search text', add `-list`.

If both `section` and `search regex` are specified, then the search space will be within the specified section identifier.

    <pragma-> c99std pointer value
       <PBot> Displaying #1 of 64 matches: 5.1.2.2.1p1: [Program startup] If they are declared, the parameters to the main function shall obey the following constraints: -- The value of argc shall be nonnegative. -- argv[argc] shall be a null pointer. -- If the value of argc is greater than zero, the array members argv[0] through argv[argc-1] inclusive shall contain pointers to st... truncated; see http://codepad.org/f2DULaGQ for full text.

<!-- -->

     <pragma-> c99std pointer value -list
        <PBot> Sections containing 'pointer value': 5.1.2.2.1p2, 5.1.2.3p9, 6.2.5p20, 6.2.5p27, 6.3.2.1p3, 6.3.2.1p4, 6.3.2.3p2, 6.3.2.3p6, 6.5.2.1p3, 6.5.2.2p5, 6.5.2.2p6, 6.5.2.4p1, 6.5.2.4p2, 6.5.3.1p1, 6.5.3.2p3, 6.5.3.2p4, 6.5.3.3p5, 6.5.3.4p5, 6.5.6p8, 6.5.6p9, 6.5.8p5, 6.5.15p6, 6.6p7, 6.6p9, 6.7.2.2p5, 6.7.2.3p7, 6.7.2.3p3, 6.7.5.1p3, 6.7.5.2p7, 7.1.1p1, 7.1.1p4, 7.1.4p1, 7... truncated; see http://codepad.org/qQlnJYJk for full text.

<!-- -->

    <pragma-> Hmm, how about just section 6.3?
    <pragma-> c99std pointer value 6.3
       <PBot> Displaying #1 of 4 matches: 6.3.2.1p1: [Lvalues, arrays, and function designators] Except when it is the operand of the sizeof operator or the unary & operator, or is a string literal used to initialize an array, an expression that has type ``array of type is converted to an expression with type ``pointer to type that points to the initial element of the array ob... truncated; see http://codepad.org/mf1RNnr2 for full text.

<!-- -->

    <pragma-> c99std pointer value 6.3 -list
       <PBot> Sections containing 'pointer value': 6.3.2.1p3, 6.3.2.1p4, 6.3.2.3p2, 6.3.2.3p6

<!-- -->

    <pragma-> c99std pointer value 6.3 -n3
       <PBot> Displaying #3 of 4 matches: 6.3.2.3p1: [Pointers] For any qualifier q, a pointer to a non-q-qualified type may be converted to a pointer to the q-qualified version of the type; the values stored in the original and converted pointers shall compare equal.

### c11std
Searches ISO/IEC 9811:201X (WG14/N1256), also known as the C11 draft standard.  http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf

Usage is identical to `c99std`.

### man
Displays manpage summaries and/or C related tidbits (headers, prototypes, specifications), as well as a link to the FreeBSD manpage.

Usage:  `man [section] query`

    <pragma-> man fork
       <PBot> Includes: sys/types.h, unistd.h - pid_t fork(void); - SVr4, SVID, POSIX, X/OPEN, BSD - fork creates a child process that differs from the parent process only in its PID and PPID, and in the fact that resource utilizations are set to 0 - http://www.iso-9899.info/man?fork

    <pragma-> man atexit
       <PBot> Includes: stdlib.h - int aid (*function)(void)); - SVID 3, BSD 4.3, ISO 9899 - atexit () function registers the given function to be called at normal program termination, whether via exit(3) or via return from the program's main - http://www.iso-9899.info/man?atexit

    <pragma-> man getcwd
       <PBot> Includes: unistd.h - char *getcwd(char *buf, size_t size); - POSIX.1 - getcwd () function copies an absolute pathname of the current working directory to the array pointed to by buf, which is of length size - http://www.iso-9899.info/man?getcwd

### google
Displays google results for a query.

Usage: `google [number of results] <query>`

    <pragma-> google brian kernighan
       <PBot> brian kernighan (115,000): Brian Kernighan's Home Page: (http://www.cs.princeton.edu/~bwk/)

 <!-- -->

    <pragma-> google 3 brian kernighan
       <PBot> brian kernighan (115,000): Brian Kernighan's Home Page: (http://www.cs.princeton.edu/~bwk/), An Interview with Brian Kernighan: (http://www-2.cs.cmu.edu/~mihaib/kernighan-interview/), Interview with Brian Kernighan | Linux Journal: (http://www.linuxjournal.com/article.php?sid=7035), Brian W. Kernighan: (http://www.lysator.liu.se/c/bwk/) ,Brian W. Kernighan: Programming in C: A Tutorial: (http://www.lysator.liu.se/c/bwk-tutor.html)

### define
### dict
Displays dictionary definitions from http://dict.org using DICT protocol.

Databases for the `-d` option are listed here: http://www.iso-9899.info/PBot/dict_databases.txt -- Note that there may be several commands aliased to one of these databases; for example, the `foldoc` command is an alias to `dict -d foldoc`.

Usage: `dict [-d database] [-n start from definition number] [-t abbreviation of word class type (n]oun, v]erb, adv]erb, adj]ective, etc)] [-search <regex> for definitions matching <regex>] <word>`

    <pragma-> dict hit
       <PBot> hit: n: 1) (baseball) a successful stroke in an athletic contest (especially in baseball); "he came all the way around on Williams' hit", 2) the act of contacting one thing with another; "repeated hitting raised a large bruise"; "after three misses she finally got a hit" [syn: hitting, striking], 3) a conspicuous success; "that song was his first hit and marked the beginning of his career"; "that new Broadway show is a real smasher"

<!-- -->

    <pragma-> dict -n 4 hit
       <PBot> hit: n: 4) (physics) an brief event in which two or more bodies come together; "the collision of the particles resulted in an exchange of energy and a change of direction" [syn: collision], 5) a dose of a narcotic drug, 6) a murder carried out by an underworld syndicate; "it has all the earmarks of a Mafia hit", 7) a connection made via the internet to another website; "WordNet gets many hits from users worldwide"

<!-- -->

    <pragma-> dict -t v hit
       <PBot> hit: v: 1) cause to move by striking; "hit a ball", 2) hit against; come into sudden contact with; "The car hit a tree"; "He struck the table with his elbow" [syn: strike, impinge on, run into, collide with] [ant: miss], 3) affect or afflict suddenly, usually adversely; "We were hit by really bad weather"; "He was stricken with cancer when he was still a teenager"; "The earstruck at midnight" [syn: strike], 4) deal a blow to

<!-- -->

    <pragma-> dict -search ball hit
       <PBot> hit: n: 1) (baseball) a successful stroke in an athletic contest (especially in baseball); "he came all the way around on Williams' hit", v: 1) cause to move by striking; "hit a ball"

<!-- -->

    <pragma-> dict -d eng-fra hit
       <PBot> hit: 1) [hit] battre, frapper, heurter frapper, heurter atteindre, frapper, parvenir, saisir

### foldoc
This is an alias for `dict -d foldoc`.

### vera
This is an alias for `dict -d vera`.

### udict
Displays dictionary definitions from http://urbandictionary.com.

Usage: `udict <query>`

### wdict
Displays Wikipedia article abstracts (first paragraph).  Note: case-sensitive and very picky.

Usage: `wdict <query>`

### acronym
Displays expanded acronyms.

Usage: `acronym <query>`

    <pragma-> acronym posix
       <PBot> posix (3 entries): Portable Operating System for Information Exchange, Portable Operating System Interface Extensions (IBM), Portable Operating System Interface for Unix
    <pragma-> acronym linux
       <PBot> linux (1 entries): Linux Is Not UniX

### math
### calc
Evaluate calculations.  Can also perform various unit conversions.

Usage:  `math <expression>` `calc <expression>`

    <pragma-> calc 5 + 5
       <PBot> 5 + 5 = 10

<!-- -->

    <pragma-> calc 80F to C
       <PBot> pragma-: 80F to C = 26.6666666666667 C

### qalc
Evaluate calculations using the `QCalculate!` program.

Usage: `qalc <expression>`

### compliment
Displays a random Markov-chain compliment/insult.

Usage: `compliment [nick]`

### insult
Displays a random insult.

Usage: `insult [nick]`

### excuse
Displays a random excuse.

Usage: `excuse [nick]`

### horoscope
Displays a horoscope for a Zodiac sign (google this if you don't know your sign).

Usage: `horoscope <sign>`

### quote
Displays quotes from a popular quotation database.  If you use `quote` without arguments, it returns a random quote; if you use it
with an argument, it searches for quotes containing that text; if you add `--author <name>` at the end, it searches for a quote by
that author; if you specify `text` and `--author`, it searches for quotes by that author, containing that text.

Usage: `quote [search text] [--author <author name>]`

    <pragma-> quote
       <PBot> "Each success only buys an admission ticket to a more difficult problem." -- Henry Kissinger (1923 -  ).
    <pragma-> quote --author lao tzu
       <PBot> 41 matching quotes found. "A journey of a thousand miles begins with a single step." -- Lao-tzu (604 BC - 531 BC).
    <pragma-> quote butterfly
       <PBot> 11 matching quotes found. "A chinese philosopher once had a dream that he was a butterfly. From that day on, he was never quite certain that he was not a butterfly, dreaming that he was a man." -- Unknown.

