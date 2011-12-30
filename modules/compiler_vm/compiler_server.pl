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
  kill 9, $pid;
  waitpid($pid, 0);
}

sub vm_start {
  my $pid = fork;

  if(not defined $pid) {
    die "fork failed: $!";
  }

  if($pid == 0) {
      #system('cp /home/compiler/compiler-saved-vm-backup /home/compiler/compiler-saved-vm');
    my $command = 'qemu-system-x86_64 -M pc -net none -hda /home/compiler/compiler-saved-vm -m 128 -monitor tcp:127.0.0.1:4445,server,nowait -serial tcp:127.0.0.1:4444,server,nowait -enable-kvm -boot c -nographic -loadvm 1';
    my @command_list = split / /, $command;
    exec(@command_list); 
  } else {
    return $pid;
  }
}

sub vm_reset {
  use IO::Socket;

  my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => 4445, Prot => 'tcp');
  if(not defined $sock) {
    print "Unable to connect to monitor: $!\n";
    return;
  }

  print $sock "loadvm 1\n";
  close $sock;
}

sub execute {
  my ($cmdline) = @_;

  print "execute($cmdline)\n";

  my ($ret, $result);

  my $child = fork;

  if($child == 0) {
    ($ret, $result) = eval {
      my $result = '';

      my $pid = open(my $fh, '-|', "$cmdline 2>&1");

      local $SIG{ALRM} = sub { print "Time out\n"; kill 'TERM', $pid; die "Timed-out\n"; };
      alarm(7);
      
      while(my $line = <$fh>) {
        $result .= $line;
      }

      close $fh;

      my $ret = $? >> 8;
      alarm 0;
      print "[$ret, $result]\n";
      return ($ret, $result);
    };

    alarm 0;
    if($@ =~ /Timed-out/) {
      return (-13, '[Timed-out]');
    }

    return ($ret, $result);
  } else {
    waitpid($child, 0);
    print "child exited, parent continuing\n";
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
    printf "[Connect from %s]\n", $client->peerhost;
    eval {
      my $lang;
      my $nick;
      my $code = "";

      local $SIG{ALRM} = sub { die 'Timed-out'; };
      alarm 5;

      while (my $line = <$client>) {
        $line =~ s/[\r\n]+$//;
        next if $line =~ m/^\s*$/;
        alarm 5;
        print "got: [$line]\n";

        if($line =~ /compile:end/) {
          $code = quotemeta($code);
          print "Attemping compile...\n";
          alarm 0;
          my $tnick = quotemeta($nick);
          my $tlang = quotemeta($lang);

          my ($ret, $result) = execute("./compiler_vm_client.pl $tnick -lang=$tlang $code");

          if(not defined $ret) {
            print "parent continued\n";
            last;
          }

          print "Ret: $ret; result: [$result]\n";

          if($ret == -13) {
            print $client "$nick: ";
          }

          print $client $result . "\n";
          close $client;
          # child exit
          print "child exit\n";
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
