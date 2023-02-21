#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2010-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use Time::Duration;

my ($ago) = @ARGV;

if (not defined $ago) {
    print "Usage: ago <seconds>\n";
    exit 0;
}

print ago_exact($ago), "\n";
