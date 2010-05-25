#!/usr/bin/perl

use warnings;
use strict;

open FH, "<fnord.txt" or die "Fnord?";

my @lines = <FH>;

close FH;

print "$lines[int rand($#lines + 1)]\n";
