#!/usr/bin/perl

use warnings;
use strict;

my $USE_LOCAL = defined $ENV{'CC_LOCAL'}; 

my %languages = (
  'C' => {
    'cmdline' => 'gcc $args $file -o prog -ggdb',
    'args' => '-Wextra -Wall -Wno-unused -std=gnu89',
    'file' => 'prog.c',
  },
  'C++' => {
    'cmdline' => 'g++ $args $file -o prog -ggdb',
    'args' => '',
    'file' => 'prog.cpp',
  },
  'C99' => {
    'cmdline' => 'gcc $args $file -o prog -ggdb',
    'args' => '-Wextra -Wall -Wno-unused -pedantic -std=c99 -lm',
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
      $lang = "C99" if not defined $lang;
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
  my ($ret, $result) = execute(60, $cmdline);
  # print "Got result: ($ret) [$result]\n";

  # if exit code was not 0, then there was a problem compiling, such as an error diagnostic
  # so return the compiler output
  if($ret != 0) {
    return $result;
  }

  my $output = "";

  # no errors compiling, but if $result contains something, it must be a warning message
  # so prepend it to the output
  if(length $result) {
    $result =~ s/^\s+//;
    $result =~ s/\s+$//;
    $output = "[$result]\n";
  }

  my $user_input_quoted = quotemeta $user_input;
  ($ret, $result) = execute(5, "./compiler_watchdog.pl $user_input_quoted");

  $result =~ s/^\s+//;
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

    my $pid = open(my $fh, '-|', "$cmdline 2>&1");

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
