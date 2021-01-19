#!/usr/bin/env perl

# quick and dirty interface to https://github.com/soimort/translate-shell

use warnings;
use strict;

if (not @ARGV) {
    print "Usage: trans [options] [source]:[targets] <word or phrase>\n";
    exit;
}

my $args = quotemeta "@ARGV";
$args =~ s/\\([ :-])/$1/g;
$args =~ s/^\s+|\s+$//g;

my $opts = '-j';
$opts .= ' -b' unless $args =~ /^-/;

my $result = `trans $opts $args`;

$result =~ s/\e\[\d+m//g;

print "$result\n";
