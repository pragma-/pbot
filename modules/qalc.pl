#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

my $args = join ' ', @ARGV;

my $qargs = quotemeta $args;

if (not length $qargs) {
  print "Usage: qalc <expression>\n";
  exit;
}

my $result = `qalc $qargs`;

$result =~ s/^.*approx.\s+//;
$result =~ s/^.*=\s+//;

print "$args = $result\n";
# print "$result\n";
