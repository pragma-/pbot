#!/usr/bin/perl

use warnings;
use strict;

use IPC::Open2;
use Fcntl qw/:flock/;
use POSIX ":sys_wait_h";
use Linux::Pid qw/getppid/;

my $outfile = '.output';

sub write_output {
  my ($msg) = @_;

  print "output: writing [$msg]\n";

  open my $fh, '>>', $outfile;
  flock $fh, LOCK_EX;
  print $fh "$msg\n";
  print "output: wrote [$msg]\n";
  close $fh;
}

sub merge_file {
  my ($file, $pid) = @_;

  # create empty file
  open my $fh, '>', $file;
  close $fh;

  my ($out, $in);
  open2 $out, $in, "tail -q -F $file --pid=$pid";
  print "merging $file to $outfile\n";
  while(my $line = <$out>) {
    chomp $line;
    if(getppid == 1) {
      print "$file: Parent died, exiting\n";
      exit;
    }
    print "$file: got [$line]\n";
    write_output $line;
  }
}

sub merge {
  my ($file) = @_;

  my $pid = fork;
  die "fork failed: $!" if not defined $pid;

  if($pid == 0) {
    print "$file pid: $$\n";
    while(1) {
      merge_file $file, $$;
      print "merge $file killed, restarting...\n";
    }
    exit;
  } else {
    return $pid;
  }
}

my ($gdb_pid, $prog_pid);

sub merge_outputs {
  $gdb_pid  = merge '.gdb_output';
  $prog_pid = merge '.prog_output';

  print "merge_outputs: gdb_pid: $gdb_pid; prog_pid: $prog_pid\n";

  while(1) {
    sleep 1;
  }
}

$SIG{CHLD} = \&REAPER;
sub REAPER {
  my $stiff;
  while (($stiff = waitpid(-1, &WNOHANG)) > 0) {
    print "child died: $stiff\n";
    print "reaper: gdb_pid: $gdb_pid; prog_pid: $prog_pid\n";

    if($stiff == $gdb_pid) {
      $gdb_pid = merge '.gdb_output';
    } elsif($stiff == $prog_pid) {
      $prog_pid = merge '.prog_output';
    }
  }
  $SIG{CHLD} = \&REAPER;
}

merge_outputs;
