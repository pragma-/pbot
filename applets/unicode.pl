#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# quick-and-dirty simplified interface to https://github.com/garabik/unicode

use warnings;
use strict;

use Encode;

if (not @ARGV) {
    print "Usage: unicode <character> | <U+XXXX code-point or U+XXXX..[U+XXXX] range> | -s <search regex>\n";
    exit;
}

@ARGV = map { decode('UTF-8', $_, 1) } @ARGV;

my $args = join ' ', @ARGV;

my $search = 0;

if ($args =~ s/^-s\s+//) {
    $search = 1;
}

if ($args =~ /^(u\+[^.]+)\s*\.\.\s*(.*)$/i) {
    my ($from, $to) = ($1, $2);

    $from =~ s/u\+//i;
    $to   =~ s/u\+//i;

    $from = hex $from;
    $to   = hex $to;

    if ($to > 0 && $to - $from > 100) {
        print "Range limited to 100 characters.\n";
        exit;
    }
}

my $result;

if ($args =~ /^u\+/i) {
    $result = `unicode --max=100 --color=off -- \Q$args\E`;
} elsif ($search) {
    $result = `unicode -r --max=100 --color=off -format 'U+{ordc:04X} {pchar} {name};\n' -- \Q$args\E`;
} else {
    $result = `unicode -s --max=100 --color=off --format 'U+{ordc:04X} ({utf8}) {pchar} {name} Category: {category} ({category_desc}) {opt_unicode_block}{opt_unicode_block_desc}{mirrored_desc}{opt_combining}{combining_desc}{opt_decomp}{decomp_desc};\n' -- \Q$args\E`;
}

print "$result\n";
