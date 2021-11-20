#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

open FH, "<fnord.txt" or die "Fnord?";

my @lines = <FH>;

close FH;

print "$lines[int rand($#lines + 1)]\n";
