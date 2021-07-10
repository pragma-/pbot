#!/usr/bin/perl -w

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# quick and dirty by :pragma

my $command = join(' ', @ARGV);

my @args = split(' ', $command);    # because @ARGV may be one quoted argument
if (@args < 2) {
    print "Usage: cdecl <explain|declare|cast|set|...> <code>, see http://linux.die.net/man/1/cdecl (Don't use this command.  Use `english` instead.)\n";
    die;
}

$command = quotemeta($command);
$command =~ s/\\ / /g;

my $result = `/usr/bin/cdecl -c $command`;

chomp $result;
$result =~ s/\n/, /g;

print $result;
print " (Don't use this command. It can only handle C90 declarations -- poorly. Use `english` instead, which can translate any complete C11 code.)"
  if $result =~ m/^declare/;
print "\n";
