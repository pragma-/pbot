#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

use File::Basename;
use JSON;

my $USERNAME = 'compiler';
my $USE_LOCAL = defined $ENV{'CC_LOCAL'}; 

# uncomment the following if installed to the virtual machine
# use constant MOD_DIR => '/usr/local/share/compiler_vm/languages';

use constant MOD_DIR => '/usr/local/share/compiler_vm/languages';

use lib MOD_DIR;

my %languages;

sub load_modules {
  my @files = glob MOD_DIR . "/*.pm";
  foreach my $mod (@files){
    print "Loading module $mod\n";
    my $filename = basename($mod);
    require $filename;
    $filename =~ s/\.pm$//;
    $languages{$filename} = 1;
  }
}

sub run_server {
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
  my $sourcefile;
  my $execfile;
  my $code;
  my $cmdline;
  my $user_input;

  my $pid = fork;
  die "Fork failed: $!" if not defined $pid;

  if($pid == 0) {
    my $buffer = "";
    my $length = 4096;
    my $line;
    my $total_read = 0;

    while (1) {
      print "Waiting for input...\n";
      my $ret = sysread($input, my $buf, $length);

      if (not defined $ret) {
        print "Error reading: $!\n";
        next;
      }

      $total_read += $ret;

      if ($ret == 0) {
        print "input  ded?\n";
        print "got buffer [$buffer]\n";
        exit;
      }

      chomp $buf;
      print "read $ret bytes [$total_read so far] [$buf]\n";
      $buffer.= $buf;

      if ($buffer =~ s/\s*:end:\s*$//m) {
        $line = $buffer;
        $buffer = "";
        $total_read = 0;
      } else {
        next;
      }

      chomp $line;

      print "-" x 40, "\n";
      print "Got [$line]\n";

      my $compile_in = decode_json($line);

      print "Attempting compile [$compile_in->{lang}] ...\n";

      my $pid = fork;

      if (not defined $pid) {
        print "fork failed: $!\n";
        next;
      }

      if ($pid == 0) {
        my ($uid, $gid) = (getpwnam $USERNAME)[2, 3];
        if (not $uid and not $gid) {
          print "Could not find user $USERNAME: $!\n";
          exit;
        }

        if ($compile_in->{'persist-key'}) {
          system("mount /dev/vdb1 /root/factdata");
          system("mkdir /root/factdata/$compile_in->{'persist-key'}");
          system("cp -R -p /root/factdata/$compile_in->{'persist-key'}/* /home/compiler/");
        }

        system("chmod -R 755 /home/compiler");
        system("chown -R compiler /home/compiler/*");
        system("chgrp -R compiler /home/compiler/*");
        system("rm -rf /home/compiler/prog*");

        $( = $gid;
        $< = $uid;

        my $result = interpret(%$compile_in);

        my $compile_out = { result => $result };
        my $json = encode_json($compile_out);

        print "Done compiling; result: [$result] [$json]\n";
        print $output "result:$json\n";
        print $output "result:end\n";

        $( = 0;
        $< = 0;

        if ($compile_in->{'persist-key'}) {
          system("id");
          system("cp -R -p /home/compiler/* /root/factdata/$compile_in->{'persist-key'}/");
          system("umount /root/factdata");
          system ("rm -rf /home/compiler/*");
        }

        exit;
      } else {
        waitpid $pid, 0;
      }

      if(not defined $USE_LOCAL or $USE_LOCAL == 0) {
        print "=" x 40, "\n";
        print "input: ";
        next;
      } else {
        exit;
      }
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
  my %h = @_;

  print "lang: [$h{lang}], sourcefile: [$h{sourcefile}], execfile [$h{execfile}], code: [$h{code}], cmdline: [$h{cmdline}], input: [$h{input}], date: [$h{date}]\n";

  $h{lang} = '_default' if not exists $languages{$h{lang}};

  chdir("/home/compiler");

  my $mod = $h{lang}->new(%h);

  $mod->preprocess;

  $mod->postprocess if not $mod->{error} and not $mod->{done};

  if (exists $mod->{no_output} or not length $mod->{output}) {
    if ($h{factoid}) {
      $mod->{output} = "";
    } else {
      $mod->{output} .= "\n" if length $mod->{output};
      $mod->{output} .= "Success (no output).\n" if not $mod->{error};
      $mod->{output} .= "Success (exit code $mod->{error}).\n" if $mod->{error};
    }
  }

  return $mod->{output};
}

load_modules;
run_server;
