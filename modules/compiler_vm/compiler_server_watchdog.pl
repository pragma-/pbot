#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

use Proc::ProcessTable;
use IO::Socket;

my $SLEEP = 15;
my $MAX_PCTCPU = 25;
my $QEMU = 'qemu-system-x86';
my $MONITOR_PORT = 3335;

my $last_pctcpu = 0;

sub reset_vm {
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

while (1) {
  my $t = new Proc::ProcessTable(enable_ttys => 0);

  my ($pids, $p);

  foreach $p (@{$t->table}) {
    $pids->{$p->pid} = { fname => $p->fname, ppid => $p->ppid };
  }

  foreach $p (keys %$pids) {
    if ($pids->{$p}->{fname} eq $QEMU) {
      my $ppid = $pids->{$p}->{ppid};
      if ($pids->{$ppid}->{fname} eq 'compiler_server') {
        my $pctcpu = `top -b -n 1 -p $p | tail -n 1 | awk '{print \$9}'`;
        $pctcpu =~ s/^\s+|\s+$//g;
        print scalar localtime, " :: Got compiler qemu pid: $p; using $pctcpu cpu\n" if $pctcpu > 0;

        if ($pctcpu >= $last_pctcpu and $last_pctcpu >= $MAX_PCTCPU) {
          reset_vm;
          $last_pctcpu = 0;
        } else {
          $last_pctcpu = $pctcpu;
        }
      }
    }
  }

  sleep $SLEEP;
}
