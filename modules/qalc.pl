#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

my $args = join ' ', @ARGV;

if (not length $args) {
    print "Usage: qalc <expression>\n";
    exit;
}

my $result = `ulimit -t 2; qalc '$args'`;

$result =~ s/^.*approx.\s+//;
$result =~ s/^.*=\s+//;

print "$args = $result\n";

# print "$result\n";
