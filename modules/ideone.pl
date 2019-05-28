#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# use warnings;
use strict;
use feature qw(switch);

use SOAP::Lite;
$SOAP::Constants::DO_NOT_USE_XML_PARSER = 1;
use IPC::Open2;
use HTML::Entities;
use Text::Balanced qw(extract_codeblock extract_delimited);

my $user = 'test';
my $pass = 'test';
my $soap = SOAP::Lite->new(proxy => 'http://ideone.com/api/1/service');
my $result;

my $MAX_UNDO_HISTORY = 100;

my $output = "";
my $nooutput = 'No output.';

my %languages = (
  'Ada'                          => { 'id' =>    '7', 'name' => 'Ada (gnat-4.3.2)'                                 },
  'asm'                          => { 'id' =>   '13', 'name' => 'Assembler (nasm-2.07)'                            },
  'nasm'                         => { 'id' =>   '13', 'name' => 'Assembler (nasm-2.07)'                            },
  'gas'                          => { 'id' =>   '45', 'name' => 'Assembler (gcc-4.3.4)'                            },
  'Assembler'                    => { 'id' =>   '13', 'name' => 'Assembler (nasm-2.07)'                            },
  'Assembler'                    => { 'id' =>   '13', 'name' => 'Assembler (nasm-2.07)'                            },
  'gawk'                         => { 'id' =>  '104', 'name' => 'AWK (gawk) (gawk-3.1.6)'                          },
  'mawk'                         => { 'id' =>  '105', 'name' => 'AWK (mawk) (mawk-1.3.3)'                          },
  'Bash'                         => { 'id' =>   '28', 'name' => 'Bash (bash 4.0.35)'                               },
  'bc'                           => { 'id' =>  '110', 'name' => 'bc (bc-1.06.95)'                                  },
  'Brainfuck'                    => { 'id' =>   '12', 'name' => 'Brainf**k (bff-1.0.3.1)'                          },
  'bf'                           => { 'id' =>   '12', 'name' => 'Brainf**k (bff-1.0.3.1)'                          },
  'gnu89'                        => { 'id' =>   '11', 'name' => 'C (gcc-4.3.4)'                                    },
  'C89'                          => { 'id' =>   '11', 'name' => 'C (gcc-4.3.4)'                                    },
  'C'                            => { 'id' =>   '11', 'name' => 'C (gcc-4.3.4)'                                    },
  'C#'                           => { 'id' =>   '27', 'name' => 'C# (gmcs 2.0.1)'                                  },
  'C++'                          => { 'id' =>    '1', 'name' => 'C++ (gcc-4.3.4)'                                  },
  'C99'                          => { 'id' =>   '34', 'name' => 'C99 strict (gcc-4.3.4)'                           },
  'CLIPS'                        => { 'id' =>   '14', 'name' => 'CLIPS (clips 6.24)'                               },
  'Clojure'                      => { 'id' =>  '111', 'name' => 'Clojure (clojure 1.1.0)'                          },
  'COBOL'                        => { 'id' =>  '118', 'name' => 'COBOL (open-cobol-1.0)'                           },
  'COBOL85'                      => { 'id' =>  '106', 'name' => 'COBOL 85 (tinycobol-0.65.9)'                      },
  'clisp'                        => { 'id' =>   '32', 'name' => 'Common Lisp (clisp) (clisp 2.47)'                 },
  'D'                            => { 'id' =>  '102', 'name' => 'D (dmd) (dmd-2.042)'                              },
  'Erlang'                       => { 'id' =>   '36', 'name' => 'Erlang (erl-5.7.3)'                               },
  'Forth'                        => { 'id' =>  '107', 'name' => 'Forth (gforth-0.7.0)'                             },
  'Fortran'                      => { 'id' =>    '5', 'name' => 'Fortran (gfortran-4.3.4)'                         },
  'Go'                           => { 'id' =>  '114', 'name' => 'Go (gc 2010-01-13)'                               },
  'Haskell'                      => { 'id' =>   '21', 'name' => 'Haskell (ghc-6.8.2)'                              },
  'Icon'                         => { 'id' =>   '16', 'name' => 'Icon (iconc 9.4.3)'                               },
  'Intercal'                     => { 'id' =>    '9', 'name' => 'Intercal (c-intercal 28.0-r1)'                    },
  'Java'                         => { 'id' =>   '10', 'name' => 'Java (sun-jdk-1.6.0.17)'                          },
  'JS'                           => { 'id' =>   '35', 'name' => 'JavaScript (rhino) (rhino-1.6.5)'                 },
  'JScript'                      => { 'id' =>   '35', 'name' => 'JavaScript (rhino) (rhino-1.6.5)'                 },
  'JavaScript'                   => { 'id' =>   '35', 'name' => 'JavaScript (rhino) (rhino-1.6.5)'                 },
  'JavaScript-rhino'             => { 'id' =>   '35', 'name' => 'JavaScript (rhino) (rhino-1.6.5)'                 },
  'JavaScript-spidermonkey'      => { 'id' =>  '112', 'name' => 'JavaScript (spidermonkey) (spidermonkey-1.7)'     },
  'Lua'                          => { 'id' =>   '26', 'name' => 'Lua (luac 5.1.4)'                                 },
  'Nemerle'                      => { 'id' =>   '30', 'name' => 'Nemerle (ncc 0.9.3)'                              },
  'Nice'                         => { 'id' =>   '25', 'name' => 'Nice (nicec 0.9.6)'                               },
  'Ocaml'                        => { 'id' =>    '8', 'name' => 'Ocaml (ocamlopt 3.10.2)'                          },
  'Pascal'                       => { 'id' =>   '22', 'name' => 'Pascal (fpc) (fpc 2.2.0)'                         },
  'Pascal-fpc'                   => { 'id' =>   '22', 'name' => 'Pascal (fpc) (fpc 2.2.0)'                         },
  'Pascal-gpc'                   => { 'id' =>    '2', 'name' => 'Pascal (gpc) (gpc 20070904)'                      },
  'Perl'                         => { 'id' =>    '3', 'name' => 'Perl (perl 5.8.8)'                                },
  'PHP'                          => { 'id' =>   '29', 'name' => 'PHP (php 5.2.11)'                                 },
  'Pike'                         => { 'id' =>   '19', 'name' => 'Pike (pike 7.6.86)'                               },
  'Prolog'                       => { 'id' =>  '108', 'name' => 'Prolog (gnu) (gprolog-1.3.1)'                     },
  'Prolog-gnu'                   => { 'id' =>  '108', 'name' => 'Prolog (gnu) (gprolog-1.3.1)'                     },
  'Prolog-swi'                   => { 'id' =>   '15', 'name' => 'Prolog (swi) (swipl 5.6.64)'                      },
  'Python'                       => { 'id' =>    '4', 'name' => 'Python (python 2.6.4)'                            },
  'Python3'                      => { 'id' =>  '116', 'name' => 'Python3 (python-3.1.1)'                           },
  'R'                            => { 'id' =>  '117', 'name' => 'R (R-2.9.2)'                                      },
  'Ruby'                         => { 'id' =>   '17', 'name' => 'Ruby (ruby 1.8.7)'                                },
  'Scala'                        => { 'id' =>   '39', 'name' => 'Scala (Scalac 2.7.7)'                             },
  'Scheme'                       => { 'id' =>   '33', 'name' => 'Scheme (guile) (guile 1.8.5)'                     },
  'Smalltalk'                    => { 'id' =>   '23', 'name' => 'Smalltalk (gst 3.1)'                              },
  'Tcl'                          => { 'id' =>   '38', 'name' => 'Tcl (tclsh 8.5.7)'                                },
  'Unlambda'                     => { 'id' =>  '115', 'name' => 'Unlambda (unlambda-2.0.0)'                        },
  'VB'                           => { 'id' =>  '101', 'name' => 'Visual Basic .NET (mono-2.4.2.3)'                 },
);

# C    11
# C99  34
# C++  1

my %preludes = ( 
                 '34'  => "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n#include <math.h>\n#include <limits.h>\n#include <sys/types.h>\n#include <stdint.h>\n",
                 '11'  => "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n#include <math.h>\n#include <limits.h>\n#include <sys/types.h>\n#include <stdint.h>\n",
                 '1'   => "#include <iostream>\n#include <cstdio>\n",
               );

if ($#ARGV <= 0) {
  print "Usage: cc [-lang=<language>] <code>\n";
  exit 0;
}

my $nick = shift @ARGV;
my $code = join ' ', @ARGV;
my @last_code;

if (open FILE, "< ideone_last_code.txt") {
  while (my $line = <FILE>) {
    chomp $line;
    push @last_code, $line;
  }
  close FILE;
}

if ($code =~ m/^\s*show\s*$/i) {
  if (defined $last_code[0]) {
    print "$nick: $last_code[0]\n";
  } else {
    print "$nick: No recent code to show.\n"
  }
  exit 0;
}

my $got_run;

if ($code =~ m/^\s*run\s*$/i) {
  if (defined $last_code[0]) {
    $code = $last_code[0];
    $got_run = 1;
  } else {
    print "$nick: No recent code to run.\n";
    exit 0;
  }
} else { 
  my $subcode = $code;
  my $got_undo = 0;
  my $got_sub = 0;

  while ($subcode =~ s/^\s*(and)?\s*undo//) {
    splice @last_code, 0, 1;
    if (not defined $last_code[0]) {
      print "$nick: No more undos remaining.\n";
      exit 0;
    } else {
      $code = $last_code[0];
      $got_undo = 1;
    }
  }

  my @replacements;
  my $prevchange = $last_code[0];
  my $got_changes = 0;

  while (1) {
    $got_sub = 0;
    $got_changes = 0;

    if ($subcode =~ m/^\s*(and)?\s*remove \s*([^']+)?\s*'/) {
      my $modifier = 'first';

      $subcode =~ s/^\s*(and)?\s*//;
      $subcode =~ s/remove\s*([^']+)?\s*//i;
      $modifier = $1 if defined $1;
      $modifier =~ s/\s+$//;

      my ($e, $r) = extract_delimited($subcode, "'");

      my $text;

      if (defined $e) {
        $text = $e;
        $text =~ s/^'//;
        $text =~ s/'$//;
        $subcode = "replace $modifier '$text' with ''$r";
      } else {
        print "$nick: Unbalanced single quotes.  Usage: !cc remove [all, first, .., tenth, last] 'text' [and ...]\n";
        exit 0;
      }
      next;
    }

    if ($subcode =~ s/^\s*(and)?\s*add '//) {
      $subcode = "'$subcode";

      my ($e, $r) = extract_delimited($subcode, "'");

      my $text;

      if (defined $e) {
        $text = $e;
        $text =~ s/^'//;
        $text =~ s/'$//;
        $subcode = $r;

        $got_sub = 1;
        $got_changes = 1;

        if (not defined $prevchange) {
          print "$nick: No recent code to append to.\n";
          exit 0;
        }

        $code = $prevchange;
        $code =~ s/$/ $text/;
        $prevchange = $code;
      } else {
        print "$nick: Unbalanced single quotes.  Usage: !cc add 'text' [and ...]\n";
        exit 0;
      }
      next;
    }

    if ($subcode =~ m/^\s*(and)?\s*replace\s*([^']+)?\s*'.*'\s*with\s*'.*'/i) {
      $got_sub = 1;
      my $modifier = 'first';

      $subcode =~ s/^\s*(and)?\s*//;
      $subcode =~ s/replace\s*([^']+)?\s*//i;
      $modifier = $1 if defined $1;
      $modifier =~ s/\s+$//;

      my ($from, $to);
      my ($e, $r) = extract_delimited($subcode, "'");

      if (defined $e) {
        $from = $e;
        $from =~ s/^'//;
        $from =~ s/'$//;
        $from = quotemeta $from;
        $subcode = $r;
        $subcode =~ s/\s*with\s*//i;
      } else {
        print "$nick: Unbalanced single quotes.  Usage: !cc replace 'from' with 'to' [and ...]\n";
        exit 0;
      }

      ($e, $r) = extract_delimited($subcode, "'");

      if (defined $e) {
        $to = $e;
        $to =~ s/^'//;
        $to =~ s/'$//;
        $subcode = $r;
      } else {
        print "$nick: Unbalanced single quotes.  Usage: !cc replace 'from' with 'to' [and replace ... with ... [and ...]]\n";
        exit 0;
      }

      given($modifier) {
        when($_ eq 'all'    ) {}
        when($_ eq 'last'   ) {}
        when($_ eq 'first'  ) { $modifier = 1; }
        when($_ eq 'second' ) { $modifier = 2; }
        when($_ eq 'third'  ) { $modifier = 3; }
        when($_ eq 'fourth' ) { $modifier = 4; }
        when($_ eq 'fifth'  ) { $modifier = 5; }
        when($_ eq 'sixth'  ) { $modifier = 6; }
        when($_ eq 'seventh') { $modifier = 7; }
        when($_ eq 'eighth' ) { $modifier = 8; }
        when($_ eq 'nineth' ) { $modifier = 9; }
        when($_ eq 'tenth'  ) { $modifier = 10; }
        default { print "$nick: Bad replacement modifier '$modifier'; valid modifiers are 'all', 'first', 'second', ..., 'tenth', 'last'\n"; exit 0; }
      }

      my $replacement = {};
      $replacement->{'from'} = $from;
      $replacement->{'to'} = $to;
      $replacement->{'modifier'} = $modifier;

      push @replacements, $replacement;
      next;
    }

    if ($subcode =~ m/^\s*(and)?\s*s\/.*\//) {
      $got_sub = 1;
      $subcode =~ s/^\s*(and)?\s*s//;

      my ($regex, $to);
      my ($e, $r) = extract_delimited($subcode, '/');

      if (defined $e) {
        $regex = $e;
        $regex =~ s/^\///;
        $regex =~ s/\/$//;
        $subcode = "/$r";
      } else {
        print "$nick: Unbalanced slashes.  Usage: !cc s/regex/substitution/[gi] [and s/.../.../ [and ...]]\n";
        exit 0;
      }

      ($e, $r) = extract_delimited($subcode, '/');

      if (defined $e) {
        $to = $e;
        $to =~ s/^\///;
        $to =~ s/\/$//;
        $subcode = $r;
      } else {
        print "$nick: Unbalanced slashes.  Usage: !cc s/regex/substitution/[gi] [and s/.../.../ [and ...]]\n";
        exit 0;
      }

      my $suffix;
      $suffix = $1 if $subcode =~ s/^([^ ]+)//;

      if (length $suffix and $suffix =~ m/[^gi]/) {
        print "$nick: Bad regex modifier '$suffix'.  Only 'i' and 'g' are allowed.\n";
        exit 0;
      }
      if (defined $prevchange) {
        $code = $prevchange;
      } else {
        print "$nick: No recent code to change.\n";
        exit 0;
      }

      my $ret = eval {
        my $ret;
        my $a;
        my $b;
        my $c;
        my $d;
        my $e;
        my $f;
        my $g;
        my $h;
        my $i;
        my $before;
        my $after;

        if (not length $suffix) {
          $ret = $code =~ s|$regex|$to|;
          $a = $1;
          $b = $2;
          $c = $3;
          $d = $4;
          $e = $5;
          $f = $6;
          $g = $7;
          $h = $8;
          $i = $9;
          $before = $`;
          $after = $';
        } elsif ($suffix =~ /^i$/) {
          $ret = $code =~ s|$regex|$to|i; 
          $a = $1;
          $b = $2;
          $c = $3;
          $d = $4;
          $e = $5;
          $f = $6;
          $g = $7;
          $h = $8;
          $i = $9;
          $before = $`;
          $after = $';
        } elsif ($suffix =~ /^g$/) {
          $ret = $code =~ s|$regex|$to|g;
          $a = $1;
          $b = $2;
          $c = $3;
          $d = $4;
          $e = $5;
          $f = $6;
          $g = $7;
          $h = $8;
          $i = $9;
          $before = $`;
          $after = $';
        } elsif ($suffix =~ /^ig$/ or $suffix =~ /^gi$/) {
          $ret = $code =~ s|$regex|$to|gi;
          $a = $1;
          $b = $2;
          $c = $3;
          $d = $4;
          $e = $5;
          $f = $6;
          $g = $7;
          $h = $8;
          $i = $9;
          $before = $`;
          $after = $';
        }

        if ($ret) {
          $code =~ s/\$1/$a/g;
          $code =~ s/\$2/$b/g;
          $code =~ s/\$3/$c/g;
          $code =~ s/\$4/$d/g;
          $code =~ s/\$5/$e/g;
          $code =~ s/\$6/$f/g;
          $code =~ s/\$7/$g/g;
          $code =~ s/\$8/$h/g;
          $code =~ s/\$9/$i/g;
          $code =~ s/\$`/$before/g;
          $code =~ s/\$'/$after/g;
        }

        return $ret;
      };

      if ($@) {
        print "$nick: $@\n";
        exit 0;
      }

      if ($ret) {
        $got_changes = 1;
      }

      $prevchange = $code;
    }

    if ($got_sub and not $got_changes) {
      print "$nick: No substitutions made.\n";
      exit 0;
    } elsif ($got_sub and $got_changes) {
      next;
    }

    last;
  }

  if ($#replacements > -1) {
    @replacements = sort { $a->{'from'} cmp $b->{'from'} or $a->{'modifier'} <=> $b->{'modifier'} } @replacements;

    my ($previous_from, $previous_modifier);

    foreach my $replacement (@replacements) {
      my $from = $replacement->{'from'};
      my $to = $replacement->{'to'};
      my $modifier = $replacement->{'modifier'};

      if (defined $previous_from) {
        if ($previous_from eq $from and $previous_modifier =~ /^\d+$/) {
          $modifier -= $modifier - $previous_modifier;
        }
      }

      if (defined $prevchange) {
        $code = $prevchange;
      } else {
        print "$nick: No recent code to change.\n";
        exit 0;
      }

      my $ret = eval {
        my $got_change;

        my ($first_char, $last_char, $first_bound, $last_bound);
        $first_char = $1 if $from =~ m/^(.)/;
        $last_char = $1 if $from =~ m/(.)$/;

        if ($first_char =~ /\W/) {
          $first_bound = '.';
        } else {
          $first_bound = '\b';
        }

        if ($last_char =~ /\W/) {
          $last_bound = '\B';
        } else {
          $last_bound = '\b';
        }

        if ($modifier eq 'all') {
          while ($code =~ s/($first_bound)$from($last_bound)/$1$to$2/) {
            $got_change = 1;
          }
        } elsif ($modifier eq 'last') {
          if ($code =~ s/(.*)($first_bound)$from($last_bound)/$1$2$to$3/) {
            $got_change = 1;
          }
        } else {
          my $count = 0;
          my $unescaped = $from;
          $unescaped =~ s/\\//g;
          if ($code =~ s/($first_bound)$from($last_bound)/if (++$count == $modifier) { "$1$to$2"; } else { "$1$unescaped$2"; }/gex) {
            $got_change = 1;
          }
        }
        return $got_change;
      };

      if ($@) {
        print "$nick: $@\n";
        exit 0;
      }

      if ($ret) {
        $got_sub = 1;
        $got_changes = 1;
      }

      $prevchange = $code;
      $previous_from = $from;
      $previous_modifier = $modifier;
    }

    if ($got_sub and not $got_changes) {
      print "$nick: No replacements made.\n";
      exit 0;
    }
  }

  open FILE, "> ideone_last_code.txt";

  unless ($got_undo and not $got_sub) {
    unshift @last_code, $code;
  }

  my $i = 0;
  foreach my $line (@last_code) {
    last if (++$i > $MAX_UNDO_HISTORY);
    print FILE "$line\n";
  }
  close FILE;

  if ($got_undo and not $got_sub) {
    print "$nick: $code\n";
    exit 0;
  }
}

unless ($got_run) {
  open FILE, ">> ideone_log.txt";
  print FILE "$nick: $code\n";
}

my $lang = "C99";
$lang = $1 if $code =~ s/-lang=([^\b\s]+)//i;

$lang = "C" if $code =~ s/-nowarn[ings]*//i;

my $show_link = 0;
$show_link = 1 if $code =~ s/-showurl//i;

my $found = 0;
my @langs;
foreach my $l (sort { uc $a cmp uc $b } keys %languages) {
  push @langs, sprintf("      %-30s => %s", $l, $languages{$l}{'name'});
  if (uc $lang eq uc $l) {
    $lang = $l;
    $found = 1;
  }
}

if (not $found) {
  print "$nick: Invalid language '$lang'.  Supported languages are:\n", (join ",\n", @langs), "\n";
  exit 0;
}

my $input = "";
$input = $1 if $code =~ s/-input=(.*)$//i;

$code =~ s/#include <([^>]+)>/\n#include <$1>\n/g;
$code =~ s/#([^ ]+) (.*?)\\n/\n#$1 $2\n/g;
$code =~ s/#([\w\d_]+)\\n/\n#$1\n/g;

my $precode = $preludes{$languages{$lang}{'id'}} . $code;
$code = '';

if ($languages{$lang}{'id'} == 1 or $languages{$lang}{'id'} == 11 or $languages{$lang}{'id'} == 34) {
  my $has_main = 0;
  
  my $prelude = '';
  $prelude = "$1$2" if $precode =~ s/^\s*(#.*)(#.*?[>\n])//s;
  
  while ($precode =~ s/([ a-zA-Z0-9_*\[\]]+)\s+([a-zA-Z0-9_*]+)\s*\((.*?)\)\s*({.*)//) {
    my ($ret, $ident, $params, $potential_body) = ($1, $2, $3, $4);

    my @extract = extract_codeblock($potential_body, '{}');
    my $body;
    if (not defined $extract[0]) {
      $output .= "error: unmatched brackets for function '$ident';\n";
      $body = $extract[1];
    } else {
      $body = $extract[0];
      $precode .= $extract[1];
    }
    $code .= "$ret $ident($params) $body\n\n";
    $has_main = 1 if $ident eq 'main';
  }

  $precode =~ s/^\s+//;
  $precode =~ s/\s+$//;

  if (not $has_main) {
    $code = "$prelude\n\n$code\n\nint main(int argc, char **argv) { $precode\n;\n return 0;}\n";
    $nooutput = "Success [no output].";
  } else {
    $code = "$prelude\n\n$precode\n\n$code\n";
    $nooutput = "No output.";
  }
} else {
  $code = $precode;
}

if ($languages{$lang}{'id'} == 1 or $languages{$lang}{'id'} == 11 or $languages{$lang}{'id'} == 35
     or $languages{$lang}{'id'} == 27 or $languages{$lang}{'id'} == 10 or $languages{$lang}{'id'} == 34) {
  $code = pretty($code) 
}

$code =~ s/\\n/\n/g if $languages{$lang}{'id'} == 13 or $languages{$lang}{'id'} == 101 or $languages{$lang}{'id'} == 45;
$code =~ s/;/\n/g if $languages{$lang}{'id'} == 13 or $languages{$lang}{'id'} == 45;
$code =~ s/\|n/\n/g;
$code =~ s/^\s+//;
$code =~ s/\s+$//;

$result = get_result($soap->createSubmission($user, $pass, $code, $languages{$lang}{'id'}, $input, 1, 1));

my $url = $result->{link};

# wait for compilation/execution to complete
while (1) {
  $result = get_result($soap->getSubmissionStatus($user, $pass, $url));
  last if $result->{status} == 0;
  sleep 1;
}

$result = get_result($soap->getSubmissionDetails($user, $pass, $url, 0, 0, 1, 1, 1));

my $COMPILER_ERROR = 11;
my $RUNTIME_ERROR = 12;
my $TIMELIMIT = 13;
my $SUCCESSFUL = 15;
my $MEMORYLIMIT = 17;
my $ILLEGAL_SYSCALL = 19;
my $INTERNAL_ERROR = 20;

# signals extracted from ideone.com
my @signame;
$signame[0] = 'SIGZERO';
$signame[1] = 'SIGHUP';
$signame[2] = 'SIGINT';
$signame[3] = 'SIGQUIT';
$signame[4] = 'SIGILL';
$signame[5] = 'SIGTRAP';
$signame[6] = 'SIGABRT';
$signame[7] = 'SIGBUS';
$signame[8] = 'SIGFPE';
$signame[9] = 'SIGKILL';
$signame[10] = 'SIGUSR1';
$signame[11] = 'SIGSEGV';
$signame[12] = 'SIGUSR2';
$signame[13] = 'SIGPIPE';
$signame[14] = 'SIGALRM';
$signame[15] = 'SIGTERM';
$signame[16] = 'SIGSTKFLT';
$signame[17] = 'SIGCHLD';
$signame[18] = 'SIGCONT';
$signame[19] = 'SIGSTOP';
$signame[20] = 'SIGTSTP';
$signame[21] = 'SIGTTIN';
$signame[22] = 'SIGTTOU';
$signame[23] = 'SIGURG';
$signame[24] = 'SIGXCPU';
$signame[25] = 'SIGXFSZ';
$signame[26] = 'SIGVTALRM';
$signame[27] = 'SIGPROF';
$signame[28] = 'SIGWINCH';
$signame[29] = 'SIGIO';
$signame[30] = 'SIGPWR';
$signame[31] = 'SIGSYS';
$signame[32] = 'SIGNUM32';
$signame[33] = 'SIGNUM33';
$signame[34] = 'SIGRTMIN';
$signame[35] = 'SIGNUM35';
$signame[36] = 'SIGNUM36';
$signame[37] = 'SIGNUM37';
$signame[38] = 'SIGNUM38';
$signame[39] = 'SIGNUM39';
$signame[40] = 'SIGNUM40';
$signame[41] = 'SIGNUM41';
$signame[42] = 'SIGNUM42';
$signame[43] = 'SIGNUM43';
$signame[44] = 'SIGNUM44';
$signame[45] = 'SIGNUM45';
$signame[46] = 'SIGNUM46';
$signame[47] = 'SIGNUM47';
$signame[48] = 'SIGNUM48';
$signame[49] = 'SIGNUM49';
$signame[50] = 'SIGNUM50';
$signame[51] = 'SIGNUM51';
$signame[52] = 'SIGNUM52';
$signame[53] = 'SIGNUM53';
$signame[54] = 'SIGNUM54';
$signame[55] = 'SIGNUM55';
$signame[56] = 'SIGNUM56';
$signame[57] = 'SIGNUM57';
$signame[58] = 'SIGNUM58';
$signame[59] = 'SIGNUM59';
$signame[60] = 'SIGNUM60';
$signame[61] = 'SIGNUM61';
$signame[62] = 'SIGNUM62';
$signame[63] = 'SIGNUM63';
$signame[64] = 'SIGRTMAX';
$signame[65] = 'SIGIOT';
$signame[66] = 'SIGCLD';
$signame[67] = 'SIGPOLL';
$signame[68] = 'SIGUNUSED';

if ($result->{result} != $SUCCESSFUL or $languages{$lang}{'id'} == 13) {
  $output .= $result->{cmpinfo};
  $output =~ s/[\n\r]/ /g;
}

  if ($result->{result} == $RUNTIME_ERROR) {
    $output .= "\n[Runtime error]";
    if ($result->{signal}) {
      $output .= "\n[Signal: $signame[$result->{signal}] ($result->{signal})]";
    }
  } else {
    if ($result->{signal}) {
      $output .= "\n[Exit code: $result->{signal}]";
    }
  }

if ($result->{result} == $TIMELIMIT) {
  $output .= "\n[Time limit exceeded]";
}

if ($result->{result} == $MEMORYLIMIT) {
  $output .= "\n[Out of memory]";
}

if ($result->{result} == $ILLEGAL_SYSCALL) {
  $output .= "\n[Disallowed system call]";
}

if ($result->{result} == $INTERNAL_ERROR) {
  $output .= "\n[Internal error]";
}

$output .= "\n" . $result->{stderr};
$output .= "\n" . $result->{output}; 

$output = decode_entities($output);

$output =~ s/cc1: warnings being treated as errors//;
$output =~ s/ Line \d+ ://g;
$output =~ s/ \(first use in this function\)//g;
$output =~ s/error: \(Each undeclared identifier is reported only once.*?\)//msg;
$output =~ s/prog\.c:[:\s\d]*//g;
$output =~ s/ld: warning: cannot find entry symbol _start; defaulting to [^ ]+//;
$output =~ s/error: (.*?) error/error: $1; error/msg;

my $left_quote = chr(226) . chr(128) . chr(152);
my $right_quote = chr(226) . chr(128) . chr(153);
$output =~ s/$left_quote/'/g;
$output =~ s/$right_quote/'/g;

$output = $nooutput if $output =~ m/^\s+$/;

unless ($got_run) {
  print FILE localtime() . "\n";
  print FILE "$nick: [ http://ideone.com/$url ] $output\n\n";
  close FILE;
}

if ($show_link) {
  print "$nick: [ http://ideone.com/$url ] $output\n";
} else {
  print "$nick: $output\n";
}

# ---------------------------------------------

sub get_result {
  my $result = shift @_;

  use Data::Dumper;

  if ($result->fault) {
    print join ', ', $result->faultcode, $result->faultstring, $result->faultdetail;
    exit 0;
  } else {
    if ($result->result->{error} ne "OK") {
      print "error\n";
      print Dumper($result->result->{error});
      exit 0;
    } else {
      return $result->result;
    }
  }
}

sub pretty {
  my $code = join '', @_;
  my $result;

  my $pid = open2(\*IN, \*OUT, 'astyle -xUpf');
  print OUT "$code\n";
  close OUT;
  while (my $line = <IN>) {
    $result .= $line;
  }
  close IN;
  waitpid($pid, 0);
  return $result;
}
