#!/usr/bin/env perl

use warnings;
use strict;

my $CFACTS = 'cfacts.txt';

my $text = join(' ', @ARGV);

my @facts;
open my $fh, "<", $CFACTS or die "Could not open $CFACTS: $!";
while (my $fact = <$fh>) {
  next if length $text and $fact !~ /\Q$text\E/i;
  push @facts, $fact;
}
close $fh;

if (not @facts) {
  print "No fact containing text $text found.\n";
} else {
  print $facts[int rand(@facts)], "\n";
}
