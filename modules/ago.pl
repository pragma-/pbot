#!/usr/bin/perl

use Time::Duration;

my ($ago) = @ARGV;

if(not defined $ago) {
  print "Usage: ago <seconds>\n";
  exit 0;
}

print ago_exact($ago), "\n";
