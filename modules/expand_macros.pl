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

my $output = "";
my $nooutput = 'No output.';

if($#ARGV < 1) {
  print "Usage: expand <code>\n";
  exit 0;
}

my $code = join ' ', @ARGV;
my $lang = 'C89';
my $args = "";

print "      code: [$code]\n" if $debug;

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

print "code after \\n replacement: [$code]\n" if $debug;

my $single_quote = 0;
my $double_quote = 0;
my $parens = 0;
my $escaped = 0;
my $cpp = 0; # preprocessor

while($code =~ m/(.)/msg) {
  my $ch = $1;
  my $pos = pos $code;

  print "adding newlines, ch = [$ch], parens: $parens, cpp: $cpp, single: $single_quote, double: $double_quote, escaped: $escaped, pos: $pos\n" if $debug >= 10;

  if($ch eq '\\') {
    $escaped = not $escaped;
  } elsif($ch eq '#' and not $cpp and not $escaped and not $single_quote and not $double_quote) {
    $cpp = 1;

    if($code =~ m/include\s*[<"]([^>"]*)[>"]/msg) {
      my $match = $1;
      $pos = pos $code;
      substr ($code, $pos, 0) = "\n";
      pos $code = $pos;
      $cpp = 0;
    } else {
      pos $code = $pos;
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
    if(not substr($code, $pos, 1) =~ m/[\n\r]/) {
      substr ($code, $pos, 0) = "\n";
      pos $code = $pos + 1;
    }
  } elsif($ch eq "'") {
    $single_quote = not $single_quote unless $escaped or $double_quote;
    $escaped = 0;
  } elsif($ch eq 'n' and $escaped) {
    if(not $single_quote and not $double_quote) {
      print "added newline\n" if $debug >= 10;
      substr ($code, $pos - 2, 2) = "\n";
      pos $code = $pos;
      $cpp = 0;
    }
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
  } elsif($ch eq "\n" and $cpp and not $single_quote and not $double_quote) {
    $cpp = 0;
  } else {
    $escaped = 0;
  }
}

print "code after \\n additions: [$code]\n" if $debug;

#$code =~ s/#include [<"'].*?['">]//gm;

print "code after include removal: [$code]\n" if $debug;

my $precode = $code;
$code = '';

print "--- precode: [$precode]\n" if $debug;

my $has_main = 0;
if($lang eq 'C89' or $lang eq 'C99' or $lang eq 'C11' or $lang eq 'C++') {
  my $prelude = '';
  while($precode =~ s/^\s*(#.*\n{1,2})//g) {
    $prelude .= $1;
  }

  print "*** prelude: [$prelude]\n   precode: [$precode]\n" if $debug;

  my $preprecode = $precode;

  # white-out contents of quoted literals
  $preprecode =~ s/(?:\"((?:\\\"|(?!\").)*)\")/'"' . ('-' x length $1) . '"'/ge;
  $preprecode =~ s/(?:\'((?:\\\'|(?!\').)*)\')/"'" . ('-' x length $1) . "'"/ge;

  # strip C and C++ style comments
  if($lang eq 'C89' or $args =~ m/-std=(gnu89|c89)/i) {
    $preprecode =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/# #gs;
    $preprecode =~ s#|//([^\\]|[^\n][\n]?)*?\n|("(\\.|[^"\\])*"|'(\\.|[^'\\])*'|.[^/"'\\]*)#defined $2 ? $2 : ""#gse;
  } else {
    $preprecode =~ s#|//([^\\]|[^\n][\n]?)*?\n|("(\\.|[^"\\])*"|'(\\.|[^'\\])*'|.[^/"'\\]*)#defined $2 ? $2 : ""#gse;
    $preprecode =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/# #gs;
  }

  print "preprecode: [$preprecode]\n" if $debug;

  print "looking for functions, has main: $has_main\n" if $debug >= 2;

  my $func_regex = qr/^([ *\w]+)\s+([*\w]+)\s*\(([^;{]*)\s*\)\s*({.*|<%.*|\?\?<.*)/ims;

  # look for potential functions to extract
  while($preprecode =~ /$func_regex/ms) {
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

    if(not length $ret or $ret eq "else" or $ret eq "while" or $ret eq "if" or $ret eq "for" or $ident eq "for" or $ident eq "while" or $ident eq "if") {
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
        if($debug == 0) {
            print "error: unmatched brackets\n";
        } else {
            print "error: unmatched brackets for function '$ident';\n";
            print "body: [$potential_body]\n";
        }
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
    $code = "$prelude\n$code" . "int main(void) {\n$precode\n}\n";
    $nooutput = "No warnings, errors or output.";
  } else {
    print "code: [$code]; precode: [$precode]\n" if $debug;
    $code = "$prelude\n$precode\n\n$code\n";
    $nooutput = "No warnings, errors or output.";
  }
} else {
  $code = $precode;
}

print "after func extract, code: [$code]\n" if $debug;

$code =~ s/\|n/\n/g;
$code =~ s/^\s+//;
$code =~ s/\s+$//;
$code =~ s/({|})\n\s*;\n/$1\n/gs;
$code =~ s/(?:\n\n)+/\n\n/g;

print "final code: [$code]\n" if $debug;

open my $fh, ">prog.c" or die "Couldn't write prog.c: $!";
print $fh $code;
close $fh;

my ($ret, $result) = execute(5, "gcc -E prog.c");

$result =~ s/.*# \d+ "prog.c"(\s+\d+)*//ms;
$result =~ s/^#.*$//gm;
$result =~ s/[\n\r]/ /gm;
$result =~ s/\s+/ /gm;

print "result: [$result]\n" if $debug;

if(not $has_main) {
  $result =~ s/\s*int main\(void\) {//;
  $result =~ s/\s*}\s*$//;
}

$output = length $result ? $result : $nooutput;

print "$output\n";

sub execute {
  my $timeout = shift @_;
  my ($cmdline) = @_;

  my ($ret, $result);

  ($ret, $result) = eval {
    print "eval\n" if $debug;

    my $result = '';

    my $pid = open(my $fh, '-|', "$cmdline 2>&1");

    local $SIG{ALRM} = sub { print "Time out\n" if $debug; kill 'TERM', $pid; die "$result [Timed-out]\n"; };
    alarm($timeout);

    while(my $line = <$fh>) {
      $result .= $line;
    }

    close $fh;
    my $ret = $? >> 8;
    alarm 0;
    return ($ret, $result);
  };

  print "done eval\n" if $debug;
  alarm 0;

  if($@ =~ /Timed-out/) {
    return (-1, $@);
  }

  print "[$ret, $result]\n" if $debug;
  return ($ret, $result);
}


