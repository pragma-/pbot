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

my $opts = '-j -no-ansi -no-autocorrect';
$opts .= ' -b' unless $args =~ /^-/;

if ($args =~ m/-pager/) {
    print "I don't think so.\n";
    exit;
}

my $result = `trans $opts $args`;
print "$result\n";
