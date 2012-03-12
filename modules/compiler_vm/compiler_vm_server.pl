#!/usr/bin/perl

use warnings;
use strict;

my $USE_LOCAL = defined $ENV{'CC_LOCAL'}; 

my %languages = (
  'C' => {
    'cmdline' => 'gcc $args $file -o prog -ggdb -g3',
    'args' => '-Wextra -Wall -Wno-unused -std=gnu89 -lm -Wfatal-errors',
    'file' => 'prog.c',
  },
  'C++' => {
    'cmdline' => 'g++ $args $file -o prog -ggdb',
    'args' => '-lm',
    'file' => 'prog.cpp',
  },
  'C99' => {
    'cmdline' => 'gcc $args $file -o prog -ggdb -g3',
    'args' => '-Wextra -Wall -Wno-unused -pedantic -std=c99 -lm -Wfatal-errors',
    'file' => 'prog.c',
  },
  'C11' => {
    'cmdline' => 'gcc $args $file -o prog -ggdb -g3',
    'args' => '-Wextra -Wall -Wno-unused -Wcast-qual -Wconversion -Wlogical-op -pedantic -std=c11 -lm -Wfatal-errors',
    'file' => 'prog.c',
  },
);

sub runserver {
  my ($input, $output);

  if(not defined $USE_LOCAL or $USE_LOCAL == 0) {
    open($input, '<', "/dev/ttyS0") or die $!;
    open($output, '>', "/dev/ttyS0") or die $!;
  } else {
    open($input, '<', "/dev/stdin") or die $!;
    open($output, '>', "/dev/stdout") or die $!;
  }

  my $lang;
  my $code;
  my $user_args;
  my $user_input;

  print "Waiting for input...\n";

  while(my $line = <$input>) {
    chomp $line;
    next unless length $line;

    print "Got [$line]\n";

    if($line =~ m/^compile:\s*end/) {
      next if not defined $lang or not defined $code;

      print "Attempting compile [$lang] ...\n";
      
      my $result = interpret($lang, $code, $user_args, $user_input);
      
      print "Done compiling; result: [$result]\n";
      print $output "result:$result\n";
      print $output "result:end\n";

      #system("rm *");

      if(not defined $USE_LOCAL or $USE_LOCAL == 0) {
        print "input: ";
        next;
      } else {
        exit;
      }
    }

    if($line =~ m/^compile:\s*(.*)/) {
      my $options = $1;
      $user_args = undef;
      $user_input = undef;
      $lang = undef;

      ($lang, $user_args, $user_input) = split /:/, $options;

      $code = "";
      $lang = "C11" if not defined $lang;
      $user_args = "" if not defined $user_args;
      $user_input = "" if not defined $user_input;

      print "Setting lang [$lang]; [$user_args]; [$user_input]\n";
      next;
    }

    $code .= $line . "\n";
  }

  close $input;
  close $output;
}

sub interpret {
  my ($lang, $code, $user_args, $user_input) = @_;

  print "lang: [$lang], code: [$code], user_args: [$user_args], input: [$user_input]\n";

  $lang = uc $lang;

  if(not exists $languages{$lang}) {
    return "No support for language '$lang' at this time.\n";
  }

  open(my $fh, '>', $languages{$lang}{'file'}) or die $!;
  print $fh $code . "\n";
  close $fh;

  my $cmdline = $languages{$lang}{'cmdline'};

  if(length $user_args) {
    print "Replacing args with $user_args\n";
    $user_args = quotemeta($user_args);
    $user_args =~ s/\\ / /g;
    $cmdline =~ s/\$args/$user_args/;
  } else {
    $cmdline =~ s/\$args/$languages{$lang}{'args'}/;
  }

  $cmdline =~ s/\$file/$languages{$lang}{'file'}/;

  print "Executing [$cmdline]\n";
  my ($ret, $result) = execute(60, "$cmdline 2>&1");
  # print "Got result: ($ret) [$result]\n";

  # if exit code was not 0, then there was a problem compiling, such as an error diagnostic
  # so return the compiler output
  if($ret != 0) {
    return $result;
  }

  my $output = "";

  my $splint_result;
  ($ret, $splint_result) = execute(60, "splint -paramuse -varuse -warnposix -exportlocal -retvalint -predboolint -compdef -formatcode +bounds -boolops +boolint +charint +matchanyintegral +charintliteral -I/usr/lib/gcc/x86_64-linux-gnu/4.7/include -I /usr/lib/gcc/x86_64-linux-gnu/4.7/include-fixed/ -I /usr/include/x86_64-linux-gnu/ prog.c 2>/dev/null");

  if($ret == 0) {
      $splint_result = "";
  } else {
      $splint_result =~ s/\s*prog.c:\s*\(in function main\)\s*prog.c:\d+:\d+:\s*Fresh\s*storage\s*.*?\s*not\s*released.*?reference\s*to\s*it\s*is\s*lost.\s*\(Use\s*.*?\s*to\s*inhibit\s*warning\)\s*//msg;
      $splint_result =~ s/prog.c:\d+:\d+:?//g;
      $splint_result =~ s/prog.c:\s*//g;
      $splint_result =~ s/\s*(\(\s*in\s*function\s*.*?\s*\))?\s*Possible\s*out-of-bounds\s*(read|store):\s*.*?\s*Unable\s*to\s*resolve\s*constraint:\s*requires\s*max(Read|Set)\(.*?\)\s*>=\s*0\s*needed\s*to\s*satisfy\s*precondition:\s*requires\s*max(Read|Set)\(.*?\)\s*>=\s*0\s*(A\s*memory.*?beyond\s*the\s*allocated\s*(storage|buffer).\s*\(Use\s*.*?\s*to\s*inhibit\s*warning\))?//msg;
      $splint_result =~ s/\s*(\(\s*in\s*function\s*.*?\s*\))?\s*Possible\s*out-of-bounds\s*(read|store):\s*.*?\s*Unable\s*to\s*resolve\s*constraint:\s*requires\s*max(Read|Set)\(.*?\)\s*>=\s*.*?\s*\+\s*-\d+\s*needed\s*to\s*satisfy\s*precondition:\s*requires\s*max(Read|Set)\(.*?\)\s*>=\s*.*?\s*\+\s*-\d+\s*derived\s*from\s*.*?\s*precondition:\s*requires.*?\s*\+\s*-\d+\s*(A\s*memory.*?beyond\s*the\s*allocated\s*(storage|buffer).\s*\(Use\s*.*?\s*to\s*inhibit\s*warning\))?//msg;
      $splint_result =~ s/Storage .*? becomes observer\s*//g;
      $splint_result =~ s/Fresh storage .*? created\s*//g;
      $splint_result =~ s/^\s+//msg;
      $splint_result =~ s/\s+$//msg;
      $splint_result =~ s/\s+/ /msg;
      print "splint_result: [$splint_result]\n";
  }

  # no errors compiling, but if $result contains something, it must be a warning message
  # so prepend it to the output
  if(length $result or length $splint_result) {
    $result =~ s/^\s+//;
    $result =~ s/\s+$//;
    $splint_result =~ s/^\s+//;
    $splint_result =~ s/\s+$//;
    $splint_result = " $splint_result" if length $result and length $splint_result;
    $output = "[$result$splint_result]\n";
    $output =~ s/^\[\s*\]\s*//;
    $output =~ s/^\[\s*(.*?)\s*\]\s*$/[$1]\n/; # remove whitespace hack
  }

  my $user_input_quoted = quotemeta $user_input;
  ($ret, $result) = execute(60, "compiler_watchdog.pl $user_input_quoted 2>&1");

  #$result =~ s/^\s+//;
  $result =~ s/\s+$//;

  # print "Executed prog; got result: ($ret) [$result]\n";

  if(not length $result) {
    $result = "Success (no output).\n" if $ret == 0;
    $result = "Success (exit code $ret).\n" if $ret != 0;
  }

  return $output . "\n" . $result;
}

sub execute {
  my $timeout = shift @_;
  my ($cmdline) = @_;

  my ($ret, $result);

  ($ret, $result) = eval {
    print "eval\n";

    my $result = '';

    my $pid = open(my $fh, '-|', "$cmdline");

    local $SIG{ALRM} = sub { print "Time out\n"; kill 'TERM', $pid; die "$result [Timed-out]\n"; };
    alarm($timeout);

    while(my $line = <$fh>) {
      $result .= $line;
    }

    close $fh;
    my $ret = $? >> 8;
    alarm 0;
    return ($ret, $result);
  };

  print "done eval\n";
  alarm 0;

  if($@ =~ /Timed-out/) {
    return (-1, $@);
  }

  print "[$ret, $result]\n";
  return ($ret, $result);
}

runserver;
