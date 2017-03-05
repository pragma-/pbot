#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# quick and dirty by :pragma

my $command = join(' ', @ARGV);

my @args = split(' ', $command); # because @ARGV may be one quoted argument
if (@args < 2) {
  print "Usage: cdecl <explain|declare|cast|set|...> <code>, see http://linux.die.net/man/1/cdecl\n";
  die;
}

$command = quotemeta($command);
$command =~ s/\\ / /g;

my $result = `/usr/bin/cdecl -c $command`;

chomp $result;
$result =~ s/\n/, /g;

print $result;
