#!/usr/bin/env perl

use warnings;
use strict;

use Fcntl qw(:flock);

my $MAX_WORDS = 3;

my $CJEOPARDY_DATA   = 'data/cjeopardy.dat';
my $CJEOPARDY_FILTER = 'data/cjeopardy.filter';

my $channel = shift @ARGV;
my $filter  = join(' ', @ARGV);

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel. Feel free to join #cjeopardy.\n";
  exit;
}

if (not length $filter) {
  my $ret = open my $fh, '<', "$CJEOPARDY_FILTER-$channel";
  if (not defined $ret) {
    print "There is no filter active for $channel. Usage: filter <comma or space separated list of words> or `filter clear` to clear.\n";
    exit;
  }

  my $words = <$fh>;
  close $fh;
  chomp $words;
  $words =~ s/,/, /;
  $words =~ s/, ([^,]+)$/ or $1/;
  print "Filter active. Questions containing $words will be skipped. Usage: filter <comma or space separated list of words> or `filter clear` to clear.\n";
  exit;
}

open my $semaphore, ">", "$CJEOPARDY_DATA-$channel.lock" or die "Couldn't create semaphore lock: $!";
flock $semaphore, LOCK_EX;

$filter = lc $filter;

if ($filter eq 'clear') {
  unlink "$CJEOPARDY_FILTER-$channel";
  print "Filter cleared.\n";
  exit;
}

$filter =~ s/(^\s+|\s+$)//g;
my @words = split /[ ,]+/, $filter;

if (not @words) {
  print "What?\n";
  exit;
}

if (@words > $MAX_WORDS) {
  print "Too many words. You may set up to $MAX_WORDS word" . ($MAX_WORDS == 1 ? '' : 's') . " in the filter.\n";
  exit;
}

open my $fh, '>', "$CJEOPARDY_FILTER-$channel" or die "Couldn't open $CJEOPARDY_FILTER-$channel: $!";
print $fh join ',', @words;
print $fh "\n";
close $fh;

my $w = join ', ', @words;
$w =~ s/, ([^,]+)$/ or $1/;
print "Questions containing $w will be skipped.\n";
exit;
