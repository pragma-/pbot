#!/usr/bin/perl

# compiler_client.pl connects to compiler_server.pl hosted at PeerAddr/PeerPort below
# and sends a nick, language and code, then retreives and prints the compilation/execution output.
#
# this way we can run the compiler virtual machine on any remote server.

use warnings;
use strict;

use IO::Socket;

my $sock = IO::Socket::INET->new(
  PeerAddr => '192.168.0.42', 
  PeerPort => 9000, 
  Proto => 'tcp');

if(not defined $sock) {
  print "Fatal error compiling: $!; try again later\n";
  die $!;
}

my $nick = shift @ARGV;
my $channel = shift @ARGV;
my $code = join ' ', @ARGV;

#$code = "{ $code";
$code =~ s/\s*}\s*$//;

my $lang = "C11";

if($code =~ s/-lang=([^ ]+)//) {
  $lang = uc $1;
}

print $sock "compile:$nick:$channel:$lang\n";
print $sock "$code\n";
print $sock "compile:end\n";

while(my $line = <$sock>) {
  print "$line";
}

close $sock;
