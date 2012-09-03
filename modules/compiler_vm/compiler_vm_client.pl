#!/usr/bin/perl

# use warnings;
use strict;
use feature "switch";

use IPC::Open2;
use Text::Balanced qw(extract_bracketed extract_delimited);
use IO::Socket;
use LWP::UserAgent;

my $debug = 0;

my $USE_LOCAL        = defined $ENV{'CC_LOCAL'}; 
my $MAX_UNDO_HISTORY = 1000000;

my $output = "";
my $nooutput = 'No output.';

my %languages = (
  'C11' => "gcc -std=c11 -pedantic -Wall -Wextra (default)",
  'C99' => "gcc -std=c99 -pedantic -Wall -Wextra",
  'C89' => "gcc -std=c89 -pedantic -Wall -Wextra",
);

my %preludes = ( 
  'C99'  => "#define _XOPEN_SOURCE 9001\n#define __USE_XOPEN\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n#include <math.h>\n#include <limits.h>\n#include <sys/types.h>\n#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdarg.h>\n#include <ctype.h>\n#include <inttypes.h>\n#include <float.h>\n#include <errno.h>\n#include <time.h>\n#include <assert.h>\n#include <prelude.h>\n\n",
  'C11'  => "#define _XOPEN_SOURCE 9001\n#define __USE_XOPEN\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n#include <math.h>\n#include <limits.h>\n#include <sys/types.h>\n#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdarg.h>\n#include <stdnoreturn.h>\n#include <stdalign.h>\n#include <ctype.h>\n#include <inttypes.h>\n#include <float.h>\n#include <errno.h>\n#include <time.h>\n#include <assert.h>\n#include <complex.h>\n#include <prelude.h>\n\n",
  'C'  => "#define _XOPEN_SOURCE 9001\n#define __USE_XOPEN\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n#include <math.h>\n#include <limits.h>\n#include <sys/types.h>\n#include <stdint.h>\n#include <errno.h>\n#include <ctype.h>\n#include <assert.h>\n#include <prelude.h>\n\n",
);

sub pretty {
  my $code = join '', @_;
  my $result;

  open my $fh, ">prog.c" or die "Couldn't write prog.c: $!";
  print $fh $code;
  close $fh;

  system("astyle", "-UHjfnq", "prog.c");

  open $fh, "<prog.c" or die "Couldn't read prog.c: $!";
  $result = join '', <$fh>;
  close $fh;

  return $result;
}

sub paste_codepad {
  my $text = join(' ', @_);

  $text =~ s/(.{120})\s/$1\n/g;

  my $ua = LWP::UserAgent->new();
  $ua->agent("Mozilla/5.0");
  push @{ $ua->requests_redirectable }, 'POST';

  my %post = ( 'lang' => 'C', 'code' => $text, 'private' => 'True', 'submit' => 'Submit' );
  my $response = $ua->post("http://codepad.org", \%post);

  if(not $response->is_success) {
    return $response->status_line;
  }

  return $response->request->uri;
}

sub paste_sprunge {
  my $text = join(' ', @_);

  $text =~ s/(.{120})\s/$1\n/g;

  my $ua = LWP::UserAgent->new();
  $ua->agent("Mozilla/5.0");
  $ua->requests_redirectable([ ]);

  my %post = ( 'sprunge' => $text, 'submit' => 'Submit' );
  my $response = $ua->post("http://sprunge.us", \%post);

  if(not $response->is_success) {
    return $response->status_line;
  }

  my $result = $response->content;
  $result =~ s/^\s+//;
  $result =~ s/\s+$/?c/;
  return $result;
}

sub compile {
  my ($lang, $code, $args, $input, $local) = @_;

  my ($compiler, $compiler_output, $pid);

  if(defined $local and $local != 0) {
    print "Using local compiler instead of virtual machine\n";
    $pid = open2($compiler_output, $compiler, './compiler_vm_server.pl') || die "repl failed: $@\n";
    print "Started compiler, pid: $pid\n";
  } else {
    $compiler  = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => '3333', Proto => 'tcp', Type => SOCK_STREAM);
    die "Could not create socket: $!" unless $compiler;
    $compiler_output = $compiler;
  }

  print $compiler "compile:$lang:$args:$input\n";
  print $compiler "$code\n";
  print $compiler "compile:end\n";

  my $result = "";
  my $got_result = 0;

  while(my $line = <$compiler_output>) {
    $line =~ s/[\r\n]+$//;

    last if $line =~ /^result:end$/;

    if($line =~ /^result:/) {
      $line =~ s/^result://;
      $result .= $line;
      $got_result = 1;
      next;
    }

    if($got_result) {
      $result .= $line . "\n";
    }
  }

  close $compiler;
  close $output if defined $output;
  waitpid($pid, 0) if defined $pid;
  return $result;
}

if($#ARGV < 1) {
  print "Usage: cc [-compiler -options] <code> [-stdin=input]\n";
  exit 0;
}

my $nick = shift @ARGV;
my $code = join ' ', @ARGV;
my @last_code;

print "      code: [$code]\n" if $debug;

my $lang = "C11";
$lang = uc $1 if $code =~ s/-lang=([^\b\s]+)//i;

my $input = "";
$input = $1 if $code =~ s/-(?:input|stdin)=(.*)$//i;

my $args = "";
$args .= "$1 " while $code =~ s/^\s*(-[^ ]+)\s*//;
$args =~ s/\s+$//;

if(open FILE, "< last_code.txt") {
  while(my $line = <FILE>) {
    chomp $line;
    push @last_code, $line;
  }
  close FILE;
}

if($code =~ m/^\s*show\s*$/i) {
  if(defined $last_code[0]) {
    print "$nick: $last_code[0]\n";
  } else {
    print "$nick: No recent code to show.\n"
  }
  exit 0;
}

my $got_run = undef;

if($code =~ m/^\s*(run|paste)\s*$/i) {
  $got_run = lc $1;
  if(defined $last_code[0]) {
    $code = $last_code[0];
  } else {
    print "$nick: No recent code to $got_run.\n";
    exit 0;
  }
} else { 
  my $subcode = $code;
  my $got_undo = 0;
  my $got_sub = 0;

  while($subcode =~ s/^\s*(and)?\s*undo//) {
    splice @last_code, 0, 1;
    if(not defined $last_code[0]) {
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

  while(1) {
    $got_sub = 0;
    $got_changes = 0;

    if($subcode =~ m/^\s*(and)?\s*remove \s*([^']+)?\s*'/) {
      my $modifier = 'first';

      $subcode =~ s/^\s*(and)?\s*//;
      $subcode =~ s/remove\s*([^']+)?\s*//i;
      $modifier = $1 if defined $1;
      $modifier =~ s/\s+$//;

      my ($e, $r) = extract_delimited($subcode, "'");

      my $text;

      if(defined $e) {
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

    if($subcode =~ s/^\s*(and)?\s*prepend '//) {
      $subcode = "'$subcode";

      my ($e, $r) = extract_delimited($subcode, "'");

      my $text;

      if(defined $e) {
        $text = $e;
        $text =~ s/^'//;
        $text =~ s/'$//;
        $subcode = $r;

        $got_sub = 1;
        $got_changes = 1;

        if(not defined $prevchange) {
          print "$nick: No recent code to prepend to.\n";
          exit 0;
        }

        $code = $prevchange;
        $code =~ s/^/$text /;
        $prevchange = $code;
      } else {
        print "$nick: Unbalanced single quotes.  Usage: !cc prepend 'text' [and ...]\n";
        exit 0;
      }
      next;
    }

    if($subcode =~ s/^\s*(and)?\s*append '//) {
      $subcode = "'$subcode";

      my ($e, $r) = extract_delimited($subcode, "'");

      my $text;

      if(defined $e) {
        $text = $e;
        $text =~ s/^'//;
        $text =~ s/'$//;
        $subcode = $r;

        $got_sub = 1;
        $got_changes = 1;

        if(not defined $prevchange) {
          print "$nick: No recent code to append to.\n";
          exit 0;
        }

        $code = $prevchange;
        $code =~ s/$/ $text/;
        $prevchange = $code;
      } else {
        print "$nick: Unbalanced single quotes.  Usage: !cc append 'text' [and ...]\n";
        exit 0;
      }
      next;
    }

    if($subcode =~ m/^\s*(and)?\s*replace\s*([^']+)?\s*'.*'\s*with\s*'.*'/i) {
      $got_sub = 1;
      my $modifier = 'first';

      $subcode =~ s/^\s*(and)?\s*//;
      $subcode =~ s/replace\s*([^']+)?\s*//i;
      $modifier = $1 if defined $1;
      $modifier =~ s/\s+$//;

      my ($from, $to);
      my ($e, $r) = extract_delimited($subcode, "'");

      if(defined $e) {
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

      if(defined $e) {
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

    if($subcode =~ m/^\s*(and)?\s*s\/.*\//) {
      $got_sub = 1;
      $subcode =~ s/^\s*(and)?\s*s//;

      my ($regex, $to);
      my ($e, $r) = extract_delimited($subcode, '/');

      if(defined $e) {
        $regex = $e;
        $regex =~ s/^\///;
        $regex =~ s/\/$//;
        $subcode = "/$r";
      } else {
        print "$nick: Unbalanced slashes.  Usage: !cc s/regex/substitution/[gi] [and s/.../.../ [and ...]]\n";
        exit 0;
      }

      ($e, $r) = extract_delimited($subcode, '/');

      if(defined $e) {
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

      if(length $suffix and $suffix =~ m/[^gi]/) {
        print "$nick: Bad regex modifier '$suffix'.  Only 'i' and 'g' are allowed.\n";
        exit 0;
      }
      if(defined $prevchange) {
        $code = $prevchange;
      } else {
        print "$nick: No recent code to change.\n";
        exit 0;
      }

      my $ret = eval {
        my ($ret, $a, $b, $c, $d, $e, $f, $g, $h, $i, $before, $after);

        if(not length $suffix) {
          $ret = $code =~ s|$regex|$to|;
          ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
          $before = $`;
          $after = $';
        } elsif($suffix =~ /^i$/) {
          $ret = $code =~ s|$regex|$to|i; 
          ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
          $before = $`;
          $after = $';
        } elsif($suffix =~ /^g$/) {
          $ret = $code =~ s|$regex|$to|g;
          ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
          $before = $`;
          $after = $';
        } elsif($suffix =~ /^ig$/ or $suffix =~ /^gi$/) {
          $ret = $code =~ s|$regex|$to|gi;
          ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
          $before = $`;
          $after = $';
        }

        if($ret) {
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

      if($@) {
        print "$nick: $@\n";
        exit 0;
      }

      if($ret) {
        $got_changes = 1;
      }

      $prevchange = $code;
    }

    if($got_sub and not $got_changes) {
      print "$nick: No substitutions made.\n";
      exit 0;
    } elsif($got_sub and $got_changes) {
      next;
    }

    last;
  }

  if($#replacements > -1) {
    @replacements = sort { $a->{'from'} cmp $b->{'from'} or $a->{'modifier'} <=> $b->{'modifier'} } @replacements;

    my ($previous_from, $previous_modifier);

    foreach my $replacement (@replacements) {
      my $from = $replacement->{'from'};
      my $to = $replacement->{'to'};
      my $modifier = $replacement->{'modifier'};

      if(defined $previous_from) {
        if($previous_from eq $from and $previous_modifier =~ /^\d+$/) {
          $modifier -= $modifier - $previous_modifier;
        }
      }

      if(defined $prevchange) {
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

        if($first_char =~ /\W/) {
          $first_bound = '.';
        } else {
          $first_bound = '\b';
        }

        if($last_char =~ /\W/) {
          $last_bound = '\B';
        } else {
          $last_bound = '\b';
        }

        if($modifier eq 'all') {
          while($code =~ s/($first_bound)$from($last_bound)/$1$to$2/) {
            $got_change = 1;
          }
        } elsif($modifier eq 'last') {
          if($code =~ s/(.*)($first_bound)$from($last_bound)/$1$2$to$3/) {
            $got_change = 1;
          }
        } else {
          my $count = 0;
          my $unescaped = $from;
          $unescaped =~ s/\\//g;
          if($code =~ s/($first_bound)$from($last_bound)/if(++$count == $modifier) { "$1$to$2"; } else { "$1$unescaped$2"; }/gex) {
            $got_change = 1;
          }
        }
        return $got_change;
      };

      if($@) {
        print "$nick: $@\n";
        exit 0;
      }

      if($ret) {
        $got_sub = 1;
        $got_changes = 1;
      }

      $prevchange = $code;
      $previous_from = $from;
      $previous_modifier = $modifier;
    }

    if($got_sub and not $got_changes) {
      print "$nick: No replacements made.\n";
      exit 0;
    }
  }

  open FILE, "> last_code.txt";

  unless ($got_undo and not $got_sub) {
    unshift @last_code, $code;
  }

  my $i = 0;
  foreach my $line (@last_code) {
    last if(++$i > $MAX_UNDO_HISTORY);
    print FILE "$line\n";
  }

  close FILE;

  if($got_undo and not $got_sub) {
    print "$nick: $code\n";
    exit 0;
  }
}

# check to see if -flags were added by replacements
$lang = uc $1 if $code =~ s/-lang=([^\b\s]+)//i;
$input = $1 if $code =~ s/-(?:input|stdin)=(.*)$//i;
$args .= "$1 " while $code =~ s/^\s*(-[^ ]+)\s*//;
$args =~ s/\s+$//;

unless($got_run) {
  open FILE, ">> log.txt";
  print FILE "------------------------------------------------------------------------\n";
  print FILE localtime() . "\n";
  print FILE "$nick: $code\n";
}

my $found = 0;
my @langs;
foreach my $l (sort { uc $a cmp uc $b } keys %languages) {
  push @langs, sprintf("      %-30s => %s", $l, $languages{$l});
  if(uc $lang eq uc $l) {
    $lang = $l;
    $found = 1;
  }
}

if(not $found) {
  print "$nick: Invalid language '$lang'.  Supported languages are:\n", (join ",\n", @langs), "\n";
  exit 0;
}

print "code before: [$code]\n" if $debug;

$code =~ s/#include <([^>]+)>/#include <$1>\n/g;

# replace \n outside of quotes with literal newline
my $new_code = "";

use constant {
  NORMAL        => 0,
  DOUBLE_QUOTED => 1,
  SINGLE_QUOTED => 2,
};

my $state = NORMAL;
my $escaped = 0;

while($code =~ m/(.)/gs) {
  my $ch = $1;

  given ($ch) {
    when ('\\') {
      if($escaped == 0) {
        $escaped = 1;
        next;
      }
    }

    if($state == NORMAL) {
      when ($_ eq '"' and not $escaped) {
        $state = DOUBLE_QUOTED;
      }

      when ($_ eq "'" and not $escaped) {
        $state = SINGLE_QUOTED;
      }

      when ($_ eq 'n' and $escaped == 1) {
        $ch = "\n";
        $escaped = 0;
      }
    }

    if($state == DOUBLE_QUOTED) {
      when ($_ eq '"' and not $escaped) {
        $state = NORMAL;
      }
    }

    if($state == SINGLE_QUOTED) {
      when ($_ eq "'" and not $escaped) {
        $state = NORMAL;
      }
    }
  }

  $new_code .= '\\' and $escaped = 0 if $escaped;
  $new_code .= $ch;
}

$code = $new_code;

print "code after: [$code]\n" if $debug;

my $precode;
if($code =~ m/#include/) {
  $precode = $code; 
} else {
  $precode = $preludes{$lang} . $code;
}
$code = '';

print "--- precode: [$precode]\n" if $debug;

if($lang eq 'C' or $lang eq 'C99' or $lang eq 'C11' or $lang eq 'C++') {
  my $has_main = 0;

  my $prelude = '';
  while($precode =~ s/^\s*(#.*\n)//g) {
    $prelude .= $1;
  }

  #$prelude = "$1" if $precode =~ s/^\s*(#.*\n)//s;

  print "*** prelude: [$prelude]\n   precode: [$precode]\n" if $debug;

  # strip C and C++ style comments
  $precode =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/|//([^\\]|[^\n][\n]?)*?\n|("(\\.|[^"\\])*"|'(\\.|[^'\\])*'|.[^/"'\\]*)#defined $3 ? $3 : ""#gse;

  print "   precode: [$precode]\n" if $debug;

  my $preprecode = $precode;

  # white-out contents of quoted literals
  $preprecode =~ s/(?:\"((?:\\\"|(?!\").)*)\")/'"' . ('-' x length $1) . '"'/ge;
  $preprecode =~ s/(?:\'((?:\\\'|(?!\').)*)\')/"'" . ('-' x length $1) . "'"/ge;

  print "preprecode: [$preprecode]\n" if $debug;

  print "looking for functions, has main: $has_main\n" if $debug >= 2;

  my $func_regex = qr/([ a-zA-Z0-9_*\[\]]+)\s+([a-zA-Z0-9_*]+)\s*\(([^;]*)\)\s*(\{.*)/ms;

  # look for potential functions to extract
  while($preprecode =~ /$func_regex/ms) {
    my ($pre_ret, $pre_ident, $pre_params, $pre_potential_body) = ($1, $2, $3, $4);

    print "looking for functions, found [$pre_ret][$pre_ident][$pre_params][$pre_potential_body], has main: $has_main\n" if $debug >= 2;

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

    if(not length $ret or $ret eq "else" or $ret eq "while" or $ret eq "if" or $ret eq "for" or $ident eq "for" or $ident eq "while" or $ident eq "if") {
      $precode .= "$ret $ident ($params) $potential_body";
      next;
    } else {
      $tmpcode =~ s/$func_regex//ms;
    }

    my @extract = extract_bracketed($potential_body, '{}');
    my $body;
    if(not defined $extract[0]) {
      print "error: unmatched brackets for function '$ident';\n";
      exit;
    } else {
      $body = $extract[0];
      $preprecode .= $extract[1];
      $precode .= $extract[1];
    }

    print "final extract: [$ret][$ident][$params][$body]\n" if $debug;
    $code .= "$ret $ident($params) $body\n\n";
    $has_main = 1 if $ident eq 'main';
  }

  $precode =~ s/^\s+//;
  $precode =~ s/\s+$//;

  $precode =~ s/^{(.*)}$/$1/s;

  if(not $has_main) {
    $code = "$prelude\n\n$code\n\nint main(int argc, char **argv) {\n$precode\n;\nreturn 0;\n}\n";
    $nooutput = "No warnings, errors or output.";
  } else {
    print "code: [$code]; precode: [$precode]\n" if $debug;
    $code = "$prelude\n\n$precode\n\n$code\n";
    $nooutput = "No warnings, errors or output.";
  }
} else {
  $code = $precode;
}

print "after func extract, code: [$code]\n" if $debug;

$code =~ s/\|n/\n/g;
$code =~ s/^\s+//;
$code =~ s/\s+$//;
$code =~ s/;\s+;\n/;\n/gs;

my $single_quote = 0;
my $double_quote = 0;
my $parens = 0;
my $escaped = 0;
my $cpp = 0; # preprocessor

while($code =~ m/(.)/msg) {
    my $ch = $1;
    my $pos = pos $code;

    print "adding newlines, ch = [$ch], single: $single_quote, double: $double_quote, escape: $escaped, pos: $pos\n" if $debug >= 10;

    if($ch eq '\\') {
        $escaped = not $escaped;
    } elsif($ch eq '#' and not $cpp and not $escaped and not $single_quote and not $double_quote) {
        $cpp = 1;
    } elsif($ch eq '"') {
        $double_quote = not $double_quote unless $escaped;
        $escaped = 0;
    } elsif($ch eq '(' and not $single_quote and not $double_quote) {
        $parens++;
    } elsif($ch eq ')' and not $single_quote and not $double_quote) {
        $parens--;
        $parens = 0 if $parens < 0;
    } elsif($ch eq ';' and not $single_quote and not $double_quote and $parens == 0) {
        if(not substr($code, $pos, 1) =~ m/[\n\r]/) {
            substr ($code, $pos, 0) = "\n";
            pos $code = $pos + 1;
        }
    } elsif($ch eq "'") {
        $single_quote = not $single_quote unless $escaped;
        $escaped = 0;
    } elsif($ch eq 'n' and $escaped) {
        substr ($code, $pos - 2, 2) = "\n" and pos $code = $pos unless $single_quote or $double_quote;
        $cpp = 0 unless $single_quote or $double_quote;
        $escaped = 0;
    } elsif($ch eq '{' and not $cpp and not $single_quote and not $double_quote) {
        if(not substr($code, $pos, 1) =~ m/[\n\r]/) {
            substr ($code, $pos, 0) = "\n";
            pos $code = $pos + 1;
        }
    } elsif($ch eq '}' and not $cpp and not $single_quote and not $double_quote) {
        if(not substr($code, $pos, 1) =~ m/[\n\r;]/) {
            substr ($code, $pos, 0) = "\n";
            pos $code = $pos + 1;
        }
    } else {
        $escaped = 0;
    }
}

$code =~ s/(?:\n\n)+/\n\n/g;

print "final code: [$code]\n" if $debug;

if(defined $got_run and $got_run eq "paste") {
  my $uri = paste_sprunge(pretty($code));
  print "$nick: $uri\n";
  exit 0;
}

print FILE "$nick: [lang:$lang][args:$args][input:$input]\n", pretty($code), "\n";

$input = "Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet." if not length $input;

$output = compile($lang, pretty($code), $args, $input, $USE_LOCAL);

if($output =~ m/^\s*$/) {
  $output = $nooutput 
} else {
  unless($got_run) {
      print FILE localtime() . "\n";
      print FILE "$output\n";
  }

  $output =~ s/cc1: warnings being treated as errors//;
  $output =~ s/ Line \d+ ://g;
  $output =~ s/ \(first use in this function\)//g;
  $output =~ s/error: \(Each undeclared identifier is reported only once.*?\)//msg;
  $output =~ s/prog\.c:[:\d]*//g;
  $output =~ s/ld: warning: cannot find entry symbol _start; defaulting to [^ ]+//;
  $output =~ s/error: (.*?) error/error: $1; error/msg;
  $output =~ s/\/tmp\/.*\.o://g;
  $output =~ s/collect2: ld returned \d+ exit status//g;
  $output =~ s/\(\.text\+[^)]+\)://g;
  $output =~ s/\[ In/[In/;
  $output =~ s/warning: Can't read pathname for load map: Input.output error.//g;
  my $left_quote = chr(226) . chr(128) . chr(152);
  my $right_quote = chr(226) . chr(128) . chr(153);
  $output =~ s/$left_quote/'/g;
  $output =~ s/$right_quote/'/g;
  $output =~ s/\t/   /g;
  $output =~ s/\s*In function 'main':\s*//g;
  $output =~ s/warning: unknown conversion type character 'b' in format \[-Wformat\]\s+warning: too many arguments for format \[-Wformat-extra-args\]/info: %b is a candide extension/g;
  $output =~ s/warning: unknown conversion type character 'b' in format \[-Wformat\]//g;
  $output =~ s/\s\(core dumped\)/./;
#  $output =~ s/\[\s+/[/g;
  $output =~ s/ \[enabled by default\]//g;
  $output =~ s/initializer\s+warning: \(near/initializer (near/g;
  $output =~ s/note: each undeclared identifier is reported only once for each function it appears in//g;
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
  $output =~ s/glibc detected \*\*\* \/home\/compiler\/prog: //;
  $output =~ s/: \/home\/compiler\/prog terminated//;
  $output =~ s/<Defined at \/home\/compiler\/>/<Defined at \/home\/compiler\/prog.c:0>/g;
  $output =~ s/\s*In file included from\s+\/usr\/include\/.*?:\d+:\d+:\s*/, /g;
  $output =~ s/\s*collect2: error: ld returned 1 exit status//g;
  $output =~ s/In function\s*`main':\s*\/home\/compiler\/ undefined reference to/error: undefined reference to/g;
  $output =~ s/\/home\/compiler\///g;
  $output =~ s/compilation terminated.//;
  $output =~ s/<'(.)' = char>/<'$1' = int>/g;
  $output =~ s/, <incomplete sequence >//g;
  $output =~ s/\s*warning: shadowed declaration is here \[-Wshadow\]//g;
  $output =~ s/preprocessor macro>\s+<at\s+>/preprocessor macro>/g;

  # remove duplicate warnings/infos
  $output =~ s/(\[*.*warning:.*?\s*)\1/$1/g;
  $output =~ s/(info: .*?\s)\1/$1/g;
  $output =~ s/^\[\s+(warning:|info:)/[$1/;  # remove leading spaces in first warning/info
  
  # splint
  $output =~ s/Splint 3.1.2 --- 03 May 2009\s*//;
  $output =~ s/Finished checking --- \d+ code warning\s*//;
  print FILE "splint: [$output]\n";
  $output =~ s/\s*\(in function main\)\s*Fresh\s*storage\s*.*?\s*not\s*released.*?reference\s+to\s+it\s+is\s+lost.\s*//msg;
  $output =~ s/\s*\(in function main\)\s*//g;
  $output =~ s/\s*\(Use\s+.*?\s+to\s+inhibit\s+warning\)//msg;
  $output =~ s/Suspect modification of observer/Suspect modification of string-literal/g;
  $output =~ s/Storage\s*declared\s*with\s*observer\s*is\s*possibly\s*modified.\s*Observer\s*storage\s*may\s*not\s*be\s*modified./Such modification is undefined-behavior./gs;
  $output =~ s/Storage\s*(.*?)?\s*becomes observer\s*//g;
  $output =~ s/Fresh storage .*? created\s*//g;
  $output =~ s/Storage .*? becomes null\s*//g;
  $output =~ s/To\s*make\s*char\s*and\s*int\s*types\s*equivalent,\s*use\s*\+charint.\s*//gs;
  $output =~ s/To\s*ignore\s*signs\s*in\s*type\s*comparisons\s*use\s*\+ignoresigns\s*//gs;
  $output =~ s/Fresh storage/Allocated storage/g;
  $output =~ s/derived\s*from\s*.*?\s*precondition:\s*requires\s*maxSet\(.*?\)\s*>=\s*maxRead\(.*?\)\s*//gs;
  $output =~ s/\s*needed\s*to\s*satisfy\s*precondition:\s*requires\s*max.*?\(.*?\)\s*>=\s*\d+//gs;
  $output =~ s/\s*needed\s*to\s*satisfy\s*precondition:\s*requires\s*max.*?\(.*?\)\s*>=\s*.*?@//gs;
  $output =~ s/\s*To allow all numeric types to match, use \+relaxtypes.//g;
  $output =~ s/\s*Corresponding format code//g;
  $output =~ s/Command Line: Setting .*? redundant with current value\s*//g;
  # $output =~ s/maxSet\((.*?)\s*@\s*\)/$1/g;
  $output =~ s/\s*Unable to resolve constraint: requires .*? >= [^ \]]+//gs;
  $output =~ s/\s*To\s*allow\s*arbitrary\s*integral\s*types\s*to\s*match\s*any\s*integral\s*type,\s*use\s*\+matchanyintegral.//gs;
  $output =~ s/\s*Storage\s*.*?\s*becomes\s*static//gs;
  $output =~ s/Possibly\s*null\s*storage\s*passed\s*as\s*non-null\s*param:/Possibly null storage passed to function:/g;
  $output =~ s/A\s*possibly\s*null\s*pointer\s*is\s*passed\s*as\s*a\s*parameter\s*corresponding\s*to\s*a\s*formal\s*parameter\s*with\s*no\s*\/\*\@null\@\*\/\s*annotation.\s*If\s*NULL\s*may\s*be\s*used\s*for\s*this\s*parameter,\s*add\s*a\s*\/\*\@null\@\*\/\s*annotation\s*to\s*the\s*function\s*parameter\s*declaration./A possibly null pointer is passed as a parameter to a function./gs;
  $output =~ s/ called by \?\? \(\)//g;
}

unless($got_run) {
  print FILE "$nick: $output\n";
  close FILE;
}

print "$nick: $output\n";
