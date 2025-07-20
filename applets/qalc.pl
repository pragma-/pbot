#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2015-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

if (not @ARGV) {
    print "Usage: qalc <expression>\n";
    exit;
}

my $is_safe = `qalc export`;

if ($is_safe ne "export() = 0\n") {
    system("./qalc-safe > /dev/null");

    $is_safe = `qalc export`;
    if ($is_safe ne "export() = 0\n") {
        print "Fatal: Unable to make qalc safe. Execute `qalc-safe` and check for errors.\n";
        exit;
    }
}

my $result = `ulimit -t 2; qalc \Q@ARGV\E`;

$result =~ s/^.*approx.\s+//;
$result =~ s/^.*=\s+//;

print "@ARGV = $result\n";
