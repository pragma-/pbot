#!/usr/bin/perl -w

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use strict;
use LWP::Simple;

$_ = get("http://www.randominsults.net/");
if (/<strong><i>(.*?)\s*<\/i><\/strong>/) {
    print "@ARGV", ': ' if @ARGV;
    print "$1\n";
} else {
    print "yo momma!";
}
