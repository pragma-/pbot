#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

if (not @ARGV) {
    print "Usage: qalc <expression>\n";
    exit;
}

my $result = `ulimit -t 2; qalc \Q@ARGV\E`;

$result =~ s/^.*approx.\s+//;
$result =~ s/^.*=\s+//;

print "@ARGV = $result\n";
