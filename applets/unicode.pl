#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# quick-and-dirty simplified interface to https://github.com/garabik/unicode

use warnings;
use strict;

use Encode;

if (not @ARGV) {
    print "Usage: unicode <character> | <U+XXXX code-point> | -s <search regex>\n";
    exit;
}

@ARGV = map { decode('UTF-8', $_, 1) } @ARGV;

my $args = join ' ', @ARGV;

my $search = 0;

if ($args =~ s/^-s\s+//) {
    $search = 1;
}

my $result;

if ($args =~ /^u\+/i) {
    $result = `unicode --color=off \Q$args\E`;
} elsif ($search) {
    $result = `unicode -r --max=100 --color=off \Q$args\E --format 'U+{ordc:04X} {pchar} {name};\n'`;
} else {
    $result = `unicode -s --color=off \Q$args\E --format 'U+{ordc:04X} ({utf8}) {pchar} {name} Category: {category} ({category_desc}) {opt_unicode_block}{opt_unicode_block_desc}{mirrored_desc}{opt_combining}{combining_desc}{opt_decomp}{decomp_desc};\n'`;
}

print "$result\n";
