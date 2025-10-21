#!/usr/bin/perl

# SPDX-FileCopyrightText: 2009-2025 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use strict;
use warnings;

srand;

open my $fh, '<', 'insults.txt' or die $!;

my $line;

while (<$fh>) {
    $line = $_ if rand($.) < 1;
}

chomp $line;
print "@ARGV", ': ' if @ARGV;
print "$line\n";
