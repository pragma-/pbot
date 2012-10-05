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
    my $command = 'nice -n -20 qemu-system-x86_64 -M pc -net none -hda /home/compiler/compiler/compiler-savedvm.qcow2 -m 128 -monitor tcp:127.0.0.1:3335,server,nowait -serial tcp:127.0.0.1:3333,server,nowait -boot c -loadvm 1 -enable-kvm -nographic';
    my @command_list = split / /, $command;
    exec(@command_list); 
  } else {
    return $pid;
  }
}

sub vm_reset {
  use IO::Socket;

  print "Resetting vm\n";
  my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => 4445, Prot => 'tcp');
  if(not defined $sock) {
    print "[vm_reset] Unable to connect to monitor: $!\n";
    return;
  }

  print $sock "loadvm 1\n";
  close $sock;
  print "Resetted vm\n";
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

      local $SIG{ALRM} = sub { print "Time out\n"; kill 'TERM', $pid; die "Timed-out: $result\n"; };
      alarm(7);
      
      while(my $line = <$fh>) {
        $result .= $line;
      }

      close $fh;

      my $ret = $? >> 8;
      alarm 0;
      #print "[$ret, $result]\n";
      return ($ret, $result);
    };

    alarm 0;
    if($@ =~ /Timed-out: (.*)/) {
      return (-13, "[Timed-out] $1");
    }

    return ($ret, $result);
  } else {
    waitpid($child, 0);
    my $result = $? >> 8;
    print "child exited, parent continuing [result = $result]\n";
    return (undef, $result);
  }
}

sub compiler_server {
  my $vm_pid = vm_start;
  print "vm started pid: $vm_pid\n";

  my $server = server_listen($PORT);

  while (my $client = $server->accept()) {
    $client->autoflush(1);
    my $hostinfo = gethostbyaddr($client->peeraddr);
    print '-' x 20, "\n";
    printf "[Connect from %s]\n", $client->peerhost;
    my $timed_out = 0;
    my $killed = 0;

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

        if($line =~ m/^compile:end$/) {
          $code = quotemeta($code);
          print "Attemping compile...\n";
          alarm 0;
          my $tnick = quotemeta($nick);
          my $tlang = quotemeta($lang);

          my ($ret, $result) = execute("./compiler_vm_client.pl $tnick -lang=$tlang $code");

          if(not defined $ret) {
            #print "parent continued\n";
            print "parent continued [$result]\n";
            $timed_out = 1 if $result == 243; # -13 == 243
            $killed = 1 if $result == 242; # -14 = 242
            last;
          }

          $result =~ s/\s+$//;
          print "Ret: $ret; result: [$result]\n";

          if($result =~ m/Killed$/) {
            print "Processed was killed\n";
            $killed = 1;
          }

          if($ret == -13) {
            print $client "$nick: ";
          }

          print $client $result . "\n";
          close $client;

          $ret = -14 if $killed;

          # child exit
          # print "child exit\n";
          exit $ret;
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

    next unless ($timed_out or $killed);
    
    print "stopping vm $vm_pid\n";
    vm_stop $vm_pid;
    $vm_pid = vm_start;
    print "new vm pid: $vm_pid\n";
  } 
}

compiler_server;
