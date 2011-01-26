#!/usr/bin/perl

use warnings;
use strict;

use IO::Socket;

my $sock = IO::Socket::INET->new(
  PeerAddr => '71.93.78.61', 
  PeerPort => 9000, 
  Proto => 'tcp') || die "Cannot create socket: $!";

my $nick = shift @ARGV;
my $lang = shift @ARGV;
my $code = join ' ', @ARGV;

print $sock "compile:$nick:$lang\n";
print $sock "$code\n";
print $sock "compile:end\n";

while(my $line = <$sock>) {
  print "$line";
}

close $sock;
