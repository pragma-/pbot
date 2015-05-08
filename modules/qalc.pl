#!/usr/bin/env perl

use warnings;
use strict;

my $args = join ' ', @ARGV;

my $qargs = quotemeta $args;

my $result = `qalc $qargs`;

$result =~ s/^.*approx.\s+//;
$result =~ s/^.*=\s+//;

print "$args = $result\n";
# print "$result\n";
