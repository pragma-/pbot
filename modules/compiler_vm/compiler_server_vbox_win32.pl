#!/usr/bin/perl

use warnings;
use strict;

use IO::Select;
use IO::Socket;
use Net::hostent;
use Win32::MMF;

my $fh = select STDOUT;
$| = 1;
select $fh;

my $VBOX           = '/cygdrive/e/VirtualBox/VBoxManage';
my $SERVER_PORT    = 9000;
my $SERIAL_PORT    = 3333;
my $HEARTBEAT_PORT = 3336;

my $COMPILE_TIMEOUT = 5;
my $NOGRAPHIC       = 0;

$SIG{INT} = sub { vm_stop(); exit 1; };

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
  system("$VBOX controlvm compiler poweroff");
  sleep 2;
}

sub vm_start {
  print "\nStarting vbox\n";
  system("$VBOX snapshot compiler restore compiler");
  sleep 2;
  system("$VBOX startvm compiler" . ($NOGRAPHIC ? " --type headless" : ""));
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

      local $SIG{ALRM} = sub { print "Time out\n"; kill 'INT', $pid; die "Timed-out: $result\n"; };
      alarm($COMPILE_TIMEOUT);

      while(my $line = <$fh>) {
        $result .= $line;
      }

      close $fh;

      my $ret = $? >> 8;
      alarm 0;
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

  while(1) {
    vm_start;
    print "vm started\n";

    $heartbeat_pid = fork;
    die "Fork failed: $!" if not defined $heartbeat_pid;

    if($heartbeat_pid == 0) {
      my $ns = Win32::MMF->new();

      while(not $ns->findvar('running')) {
        print "Child waiting for running status\n";
        sleep 1;
      }

      $heartbeat_monitor = undef;
      while(not $heartbeat_monitor) {
        print "Connecting to heartbeat ...";
        $heartbeat_monitor = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $HEARTBEAT_PORT, Proto => 'tcp', Type => SOCK_STREAM);
        if(not $heartbeat_monitor) {
          print " failed.\n";
          sleep 2;
        } else {
          print " success!\n";
        }
      }

      my $select = IO::Select->new();
      $select->add($heartbeat_monitor);

      while($ns->getvar('running')) {
        my @ready = $select->can_read(1);
        foreach my $fh (@ready) {
          my $ret = sysread($fh, my $buf, 32);

          if(not defined $ret) {
            print "Heartbeat read error: $!\n";
            $ns->setvar('running', 0);
          }

          if($ret == 0) {
            print "Heartbeat disconnected.\n";
            $ns->setvar('running', 0);
          }

          $ns->setvar('heartbeat', 1);
          print ".";
        }
      }

      $heartbeat_monitor->shutdown(3);
      $ns->deletevar('heartbeat');
      $ns->deletevar('running');
      print "child no longer running\n";
      exit;
    } else {
      print "Heartbeat pid: $heartbeat_pid\n";

      if(not defined $server) {
        print "Starting compiler server on port $SERVER_PORT\n";
        $server = server_listen($SERVER_PORT);
      } else {
        print "Compiler server already listening on port $SERVER_PORT\n";
      }

      my $ns = Win32::MMF->new();

      $ns->setvar('running', 1);
      $ns->setvar('heartbeat', 0);

      while ($ns->getvar('running') and my $client = $server->accept()) {
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
              if(not $ns->getvar('heartbeat')) {
                print "No heartbeat yet, ignoring compile attempt.\n";
                print $client "$nick: Recovering from previous snippet, please wait.\n";
                last;
              }

              print "Attempting compile...\n";
              alarm 0;

              my ($ret, $result) = execute("./compiler_vm_client.pl \Q$nick\E \Q$channel\E -lang=\Q$lang\E \Q$code\E");

              if(not defined $ret) {
                #print "parent continued\n";
                print "parent continued [$result]\n";
                $timed_out = 1 if $result == 243; # -13 == 243
                $killed = 1 if $result == 242; # -14 = 242
                $client->shutdown(3);
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
              $client->shutdown(3);

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

        $client->shutdown(3);

        next unless ($timed_out);

        $server->shutdown(3);
        undef $server;
        print "stopping vm\n";
        $ns->setvar('running', 0);
        vm_stop;
        last;
      } 
      print "Compiler server no longer running, restarting...\n";
    }
    print "Waiting for heartbeat $heartbeat_pid to die\n";
    waitpid($heartbeat_pid, 0);
    print "Heartbeat dead.\n";
  }
}

compiler_server;
