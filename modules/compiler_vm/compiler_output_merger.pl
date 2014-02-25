#!/usr/bin/perl

use warnings;
use strict;

use IPC::Open2;
use Fcntl qw/:flock/;

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

sub merge {
  my ($file) = @_;

  # create empty file
  open my $fh, '>', $file;
  close $fh;

  my ($out, $in);
  open2 $out, $in, "tail -f $file";
  print "merging $file to $outfile\n";
  while(my $line = <$out>) {
    chomp $line;
    print "$file: got [$line]\n";
    write_output $line;
  }
}

my $pid = fork();
die "fork failed: $!" if not defined $pid;

if($pid == 0) {
  merge '.gdb_output';
  exit;
} else {
  merge '.prog_output';
}

waitpid $pid, 0;
