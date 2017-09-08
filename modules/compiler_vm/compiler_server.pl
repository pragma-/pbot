#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

use IO::Socket;
use Net::hostent;
use IPC::Shareable;
use Time::HiRes qw/gettimeofday/;

my $SERVER_PORT    = 9000;
my $MONITOR_PORT   = 3335;
my $SERIAL_PORT    = 3333;
my $HEARTBEAT_PORT = 3336;

my $COMPILE_TIMEOUT = 10;
my $NOGRAPHIC       = 1;

sub server_listen {
  my $port = shift @_;

  my $server = IO::Socket::INET->new( 
    Proto     => 'tcp',
    LocalPort => $port,
    Listen    => SOMAXCONN,
    Reuse     => 1);

  die "can't setup server: $!" unless $server;

  print "[Server $0 accepting clients]\n";

  return $server;
}

sub vm_stop {
  my $pid = shift @_;
  return if not defined $pid;
  print "killing vm $pid\n";
  kill 'INT', $pid;
  waitpid($pid, 0);
}

sub vm_start {
  my $pid = fork;

  if(not defined $pid) {
    die "fork failed: $!";
  }

  if($pid == 0) {
    my $command = "qemu-system-x86_64 -M pc -net none -hda compiler-snap.qcow2 -m 512 -monitor tcp:127.0.0.1:$MONITOR_PORT,server,nowait -serial tcp:127.0.0.1:$SERIAL_PORT,server,nowait -serial tcp:127.0.0.1:$HEARTBEAT_PORT,server -boot c -enable-kvm -loadvm 1" . ($NOGRAPHIC ? " -nographic" : "");
    my @command_list = split / /, $command;
    exec(@command_list); 
  } else {
    return $pid;
  }
}

sub vm_reset {
  use IO::Socket;

  print "Resetting vm\n";
  my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $MONITOR_PORT, Prot => 'tcp');
  if(not defined $sock) {
    print "[vm_reset] Unable to connect to monitor: $!\n";
    return;
  }

  print $sock "loadvm 1\n";
  close $sock;
  print "Reset vm\n";
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

      local $SIG{ALRM} = sub { print "Time out\n"; kill 9, $pid; print "sent KILL to $pid\n"; die "Timed-out: $result\n"; };
      alarm($COMPILE_TIMEOUT);
      
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
  my ($server, $heartbeat_pid, $heartbeat_monitor);

  my $heartbeat;
  my $running;

  tie $heartbeat, 'IPC::Shareable', 'dat1', { create => 1 };
  tie $running,   'IPC::Shareable', 'dat2', { create => 1 };

  my $last_wait = 0;

  while(1) {
    $running = 1;
    $heartbeat = 0;

    my $vm_pid = vm_start;
    print "vm started pid: $vm_pid\n";

    $heartbeat_pid = fork;
    die "Fork failed: $!" if not defined $heartbeat_pid;

    if($heartbeat_pid == 0) {
      tie $heartbeat, 'IPC::Shareable', 'dat1', { create => 1 };
      tie $running,   'IPC::Shareable', 'dat2', { create => 1 };

      $heartbeat_monitor = undef;
      my $attempts = 0;
      while((not $heartbeat_monitor) and $attempts < 5) {
        print "Connecting to heartbeat ...";
        $heartbeat_monitor = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $HEARTBEAT_PORT, Proto => 'tcp', Type => SOCK_STREAM);
        if(not $heartbeat_monitor) {
          print " failed.\n";
          ++$attempts;
          sleep 2;
        } else {
          print " success!\n";
        }
      }

      if ($attempts >= 5) {
        print "heart not beating... restarting\n";
        $heartbeat = -1;
        sleep 5;
        next;
      }

      print "child: running: $running\n";

      while($running and <$heartbeat_monitor>) {
        $heartbeat = 1;
        #print "child: got heartbeat\n";
      }

      print "child no longer running\n";
      exit;
    } else {

      while ($heartbeat <= 0) {
        if ($heartbeat == -1) {
          print "heartbeat died\n";
          last;
        }
        print "sleeping for heartbeat...\n";
        sleep 1;
      }

      if ($heartbeat == -1) {
        print "fucking dead, restarting\n";
        waitpid $heartbeat_pid, 0;
        vm_stop $vm_pid;
        next;
      }

      print "K, got heartbeat, here we go...\n";

      if(not defined $server) {
        print "Starting compiler server on port $SERVER_PORT\n";
        $server = server_listen($SERVER_PORT);
      } else {
        print "Compiler server already listening on port $SERVER_PORT\n";
      }

      print "parent: running: $running\n";

      while ($running and my $client = $server->accept()) {
        $client->autoflush(1);
        my $hostinfo = gethostbyaddr($client->peeraddr);
        print '-' x 20, "\n";
        printf "[Connect from %s at %s]\n", $client->peerhost, scalar localtime;
        my $timed_out = 0;
        my $killed = 0;

        eval {
          my $lang;
          my $nick;
          my $channel;
          my $code = "";

          local $SIG{ALRM} = sub { die 'Timed-out'; };
          alarm 5;

          while (my $line = <$client>) {
            $line =~ s/[\r\n]+$//;
            next if $line =~ m/^\s*$/;
            alarm 5;
            print "got: [$line]\n";

            if($line =~ m/^compile:end$/) {
              if($heartbeat <= 0) {
                print "No heartbeat yet, ignoring compile attempt.\n";
                print $client "$nick: Recovering from previous snippet, please wait.\n" if gettimeofday - $last_wait > 60;
                $last_wait = gettimeofday;
                last;
              }

              print "Attempting compile...\n";
              alarm 0;

              my ($ret, $result) = execute("./compiler_vm_client.pl \Q$lang\E \Q$nick\E \Q$channel\E \Q$code\E");

              if(not defined $ret) {
                #print "parent continued\n";
                print "parent continued [$result]\n";
                $timed_out = 1 if $result == 243; # -13 == 243
                $killed = 1 if $result == 242; # -14 = 242
                last;
              }

              $result =~ s/\s+$//;
              print "Ret: $ret; result: [$result]\n";

              if($result =~ m/\[Killed\]$/) {
                print "Process was killed\n";
                $killed = 1;
              }

              if($ret == -13) {
                print $client "$nick: ";
              }

              print $client $result . "\n";
              close $client;

              $ret = -14 if $killed;

              # child exit
               print "child exit\n";
              exit $ret;
            }

            if($line =~ /compile:([^:]+):([^:]+):(.*)$/) {
              $nick = $1;
              $channel = $2;
              $lang = $3;
              $code = "";
              next;
            }

            $code .= $line . "\n";
          }

          alarm 0;
        };

        alarm 0;

        close $client;

        #next unless ($timed_out or $killed);
        #next unless $timed_out;

        print "stopping vm $vm_pid\n";
        vm_stop $vm_pid;
        $running = 0;
        last;
      } 
      print "Compiler server no longer running, restarting...\n";
    }
    waitpid($heartbeat_pid, 0);
  }
}

compiler_server;
