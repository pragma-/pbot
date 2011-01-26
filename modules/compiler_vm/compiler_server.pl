#!/usr/bin/perl

use warnings;
use strict;

use IO::Socket;
use Net::hostent;

my $PORT = 9000;

sub server_listen {
  my $port = shift @_;

  my $server = IO::Socket::INET->new( 
    Proto     => 'tcp',
    LocalPort => $port,
    Listen    => SOMAXCONN,
    Reuse     => 1);

  die "can't setup server" unless $server;

  print "[Server $0 accepting clients]\n";

  return $server;
}

sub vm_stop {
  my $pid = shift @_;
  return if not defined $pid;
  kill 'TERM', $pid;
}

sub vm_start {
  my $pid = fork;

  if(not defined $pid) {
    die "fork failed: $!";
  }

  if($pid == 0) {
    exec('"/cygdrive/c/Program Files (x86)\QemuManager\qemu\qemu-system-x86_64.exe" -L "C:\Program Files (x86)\QemuManager\qemu" -M "pc" -m 512 -cpu "qemu64" -vga cirrus -drive "file=C:\Program Files (x86)\QemuManager\images\Test.qcow2,index=0,media=disk" -enable-kqemu -kernel-kqemu -net none -localtime -serial "tcp:127.0.0.1:4444,server,nowait" -monitor "tcp:127.0.0.1:4445,server,nowait" -kernel-kqemu -loadvm 1 -nographic'); 
  } else {
    return $pid;
  }
}

sub execute {
  my ($cmdline) = @_;

  my ($ret, $result);

  my $child = fork;

  if($child == 0) {
    ($ret, $result) = eval {
      my $result = '';

      my $pid = open(my $fh, '-|', "$cmdline 2>&1");

      local $SIG{ALRM} = sub { print "Time out\n"; kill 'TERM', $pid; die "Timed-out\n"; };
      alarm(6);
      
      while(my $line = <$fh>) {
        $result .= $line;
      }

      close $fh;

      my $ret = $? >> 8;
      alarm 0;
      return ($ret, $result);
    };

    alarm 0;
    if($@ =~ /Timed-out/) {
      #kill 'TERM', $child;
      return (-13, '[Timed-out]');
    }

    print "[$ret, $result]\n";

    return ($ret, $result);
  } else {
    waitpid($child, 0);
    #print "child exited, parent continuing\n";
    return undef;
  }
}

sub compiler_server {
  my $vm_pid = vm_start;
  print "vm started pid: $vm_pid\n";

  my $server = server_listen($PORT);

  while (my $client = $server->accept()) {
    $client->autoflush(1);
    my $hostinfo = gethostbyaddr($client->peeraddr);
    printf "[Connect from %s]\n", $hostinfo->name || $client->peerhost;
    eval {
      my $lang;
      my $nick;
      my $code = "";

      local $SIG{ALRM} = sub { die 'Timed-out'; };
      alarm 1;

      while (my $line = <$client>) {
        $line =~ s/[\r\n]+$//;
        next if $line =~ m/^\s*$/;
        alarm 1;
        print "got: [$line]\n";

        if($line =~ /compile:end/) {
          $code = quotemeta($code);
          print "Attemping compile...\n";
          alarm 0;
          my $tnick = quotemeta($nick);
          my $tlang = quotemeta($lang);

          my ($ret, $result) = execute("./compiler_vm_client.pl $tnick -lang=$tlang $code");

          if(not defined $ret) {
            #print "parent continued\n";
            last;
          }

          print "Ret: $ret; result: [$result]\n";

          if($ret == -13) {
            print $client "$nick: ";
          }

          print $client $result . "\n";
          close $client;
          # child exit
          exit;
        }

        if($line =~ /compile:([^:]+):(.*)$/) {
          $nick = $1;
          $lang = $2;
          $code = "";
          next;
        }

        $code .= $line . "\n";

      }

      alarm 0;
    };

    alarm 0;

    close $client;

    print "stopping vm $vm_pid\n";
    vm_stop $vm_pid;
    $vm_pid = vm_start;
    print "new vm pid: $vm_pid\n";
  } 
}

compiler_server;
