#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# quick-and-dirty

use warnings;
use strict;

use Encode;

if (not @ARGV) {
    print "Usage: unicode <character | U+XXXX code-point | search regex>\n";
    exit;
}

@ARGV = map { decode('UTF-8', $_, 1) } @ARGV;

my $args = join ' ', @ARGV;

my $search = 0;

if ($args =~ s/^-s\s+// || length $args > 1) {
    $search = 1;
}

my $result;

if ($args =~ /^u\+/i) {
    $result = `unicode --color=off \Q$args\E`;
} elsif ($search) {
    $result = `unicode -r --color=off \Q$args\E --format 'U+{ordc:04X} {pchar} {name}\n'`;
} else {
    $result = `unicode -s --color=off \Q$args\E`;
}

$result = join '; ', split /\n/, $result;

print "$result\n";
