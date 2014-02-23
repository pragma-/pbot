#!/usr/bin/perl

use warnings;
use strict;

my $USE_LOCAL = defined $ENV{'CC_LOCAL'}; 

my %languages = (
  'C89' => {
    'cmdline' => 'gcc $file $args -o prog -ggdb -g3',
    'args' => '-Wextra -Wall -Wno-unused -std=gnu89 -lm -Wfatal-errors',
    'file' => 'prog.c',
  },
  'C++' => {
    'cmdline' => 'g++ $file $args -o prog -ggdb',
    'args' => '-lm',
    'file' => 'prog.cpp',
  },
  'C99' => {
    'cmdline' => 'gcc $file $args -o prog -ggdb -g3',
    'args' => '-Wextra -Wall -Wno-unused -pedantic -Wfloat-equal -std=c99 -lm -Wfatal-errors',
    'file' => 'prog.c',
  },
  'C11' => {
    'cmdline' => 'gcc $file $args -o prog -ggdb -g3',
    'args' => '-Wextra -Wall -Wno-unused -pedantic -Wfloat-equal -std=c11 -lm -Wfatal-errors',
    'file' => 'prog.c',
  },
);

sub runserver {
  my ($input, $output, $heartbeat);

  if(not defined $USE_LOCAL or $USE_LOCAL == 0) {
    open($input, '<', "/dev/ttyS0") or die $!;
    open($output, '>', "/dev/ttyS0") or die $!;
    open($heartbeat, '>', "/dev/ttyS1") or die $!;
  } else {
    open($input, '<', "/dev/stdin") or die $!;
    open($output, '>', "/dev/stdout") or die $!;
  }

  my $date;
  my $lang;
  my $code;
  my $user_args;
  my $user_input;

  print "Waiting for input...\n";

  my $pid = fork;
  die "Fork failed: $!" if not defined $pid;

  if($pid == 0) {
    while(my $line = <$input>) {
      chomp $line;

      print "Got [$line]\n";

      if($line =~ m/^compile:\s*end/) {
        next if not defined $lang or not defined $code;

        print "Attempting compile [$lang] ...\n";

        my $result = interpret($lang, $code, $user_args, $user_input, $date);

        print "Done compiling; result: [$result]\n";
        print $output "result:$result\n";
        print $output "result:end\n";

        #system("rm prog");

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

        ($lang, $user_args, $user_input, $date) = split /:/, $options;

        $code = "";
        $lang = "C11" if not defined $lang;
        $user_args = "" if not defined $user_args;
        $user_input = "" if not defined $user_input;

        print "Setting lang [$lang]; [$user_args]; [$user_input]; [$date]\n";
        next;
      }

      $code .= $line . "\n";
    }
  } else {
    while(1) {
      print $heartbeat "\n";
      sleep 1;
    }
  }

  close $input;
  close $output;
  close $heartbeat;
}

sub interpret {
  my ($lang, $code, $user_args, $user_input, $date) = @_;

  print "lang: [$lang], code: [$code], user_args: [$user_args], input: [$user_input], date: [$date]\n";

  $lang = uc $lang;

  if(not exists $languages{$lang}) {
    return "No support for language '$lang' at this time.\n";
  }

  system("chmod -R 755 /home/compiler");

  open(my $fh, '>', $languages{$lang}{'file'}) or die $!;
  print $fh $code . "\n";
  close $fh;

  my $cmdline = $languages{$lang}{'cmdline'};

  if(length $user_args) {
    print "Replacing args with $user_args\n";
    my $user_args_quoted = quotemeta($user_args);
    $user_args_quoted =~ s/\\ / /g;
    $cmdline =~ s/\$args/$user_args_quoted/;
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

  if($user_args =~ m/--version/) {
    # arg contained --version, so don't compile and just return the version output
    return $result;
  }

  # no errors compiling, but if $result contains something, it must be a warning message
  # so prepend it to the output
  my $output = "";
  if(length $result) {
    $result =~ s/^\s+//;
    $result =~ s/\s+$//;
    $output = "[$result]\n";
  }

  print "Executing gdb\n";
  my $user_input_quoted = quotemeta $user_input;
  ($ret, $result) = execute(60, "bash -c 'date -s \@$date; ulimit -t 1; compiler_watchdog.pl $user_input_quoted > .output'");

  $result = "";

  open(FILE, '.output');
  while(<FILE>) {
    $result .= $_;
    last if length $result >= 2048 * 20;
  }
  close(FILE);
 
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
