#!/usr/bin/perl

use warnings;
use strict;

use POSIX ":sys_wait_h";
use IPC::Open2;

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

sub debug_program {
  my ($input, $output);

  my $pid = open2($output, $input, 'gdb -silent -batch -x debugcommands ./prog ./core 2>/dev/null');

  if(not $pid) {
    print "Error debugging program.\n";
    exit;
  }

  my $result = "";

  while(my $line = <$output>) {
	  if($line =~ s/^#\d+//) {
            next if $line =~ /\?\?/;
            next if $line =~ /in main\s*\(/;

		  $line =~ s/\s*0x[0-9a-fA-F]+\s*//;
		  $line =~ s/\s+at .*:\d+//;

		  if($line !~ m/^\s*in\s+/) {
			  $result = "in $line from ";
		  } else {
			  $result .= "$line at ";
		  }
	  }
	  elsif($line =~ s/^\d+//) {
		  next if $line =~ /No such file/;

                  $result .= "at " if not length $result;
		  $result .= "statement: $line";
		  last;
	  }
  }

  close $output;
  close $input;
  waitpid($pid, 0);

  $result =~ s/^\s+//;
  $result =~ s/\s+$//;
  print "$result\n";
  exit;
}

sub reaper {
  my $child;
  while (($child=waitpid(-1,WNOHANG))>0) {

    # See waitpid(2) and POSIX(3perl)
    my $status      = $?;
    my $exitcode    = $status >> 8;
    my $wifexited   = WIFEXITED($status);
    my $wexitstatus = $wifexited ? WEXITSTATUS($status) : undef;
    my $wifsignaled = WIFSIGNALED($status);
    my $wtermsig    = $wifsignaled ? WTERMSIG($status) : undef;
    my $wifstopped  = WIFSTOPPED($status);
    my $wstopsig    = $wifstopped ? WSTOPSIG($status) : undef;

    if($wifsignaled == 1) {
      print "\nProgram received signal $wtermsig ($signame[$wtermsig])\n";
      debug_program if $wtermsig != 0;
      exit;
    }

    if(($wifexited == 1) && ($exitcode != 0)) {
      print "\nExit: $exitcode\n";
      exit;
    } elsif(($wifexited ==1) && ($exitcode == 0)) {
      exit;
    }
    else {

      print ""
      ." status=$status exitcode=$exitcode"
      ." wifexited=$wifexited"
      ." wexitstatus=".(defined($wexitstatus) ? $wexitstatus : "
        +undef")
      ." wifsignaled=$wifsignaled"
      ." wtermsig=".(defined($wtermsig) ? $wtermsig : "undef")
      ." wifstopped=$wifstopped"
      ." wstopsig=".(defined($wstopsig) ? $wstopsig : "undef")
      ."\n";
      exit;
    }
  }
}

sub execute {
  my ($cmdline) = @_;
  my ($ret, $result);

  local $SIG{CHLD} = \&reaper;

  my $child = fork;

  local $SIG{TERM} = sub { kill 'TERM', $child; };

  if($child == 0) {
    exec("$cmdline 2>&1");
   } else {
    while(1) { sleep 10; }
  }
}

execute("./prog");
