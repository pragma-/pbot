#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use strict;
use LWP::Simple;

$_ = get("http://www.randominsults.net/");
if (/<strong><i>(.*?)\s*<\/i><\/strong>/) {
    print "@ARGV", ': ' if @ARGV;
    print "$1\n";
} else {
    print "yo momma!";
}
