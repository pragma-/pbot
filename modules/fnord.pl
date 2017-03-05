#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

open FH, "<fnord.txt" or die "Fnord?";

my @lines = <FH>;

close FH;

print "$lines[int rand($#lines + 1)]\n";
