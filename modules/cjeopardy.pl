#!/usr/bin/env perl

use warnings;
use strict;

use Time::HiRes qw/gettimeofday/;

my $CJEOPARDY_FILE = 'cjeopardy.txt';
my $CJEOPARDY_DATA = 'cjeopardy.dat';
my $CJEOPARDY_SQL  = 'cjeopardy.sqlite3';

my $channel = shift @ARGV;
my $text = join(' ', @ARGV);

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel.\n";
  exit;
}

my @questions;
open my $fh, "<", $CJEOPARDY_FILE or die "Could not open $CJEOPARDY_FILE: $!";
while (my $question = <$fh>) {
  my ($question_only) = split /\|/, $question, 2;
  next if length $text and $question_only !~ /\Q$text\E/i;
  push @questions, $question;
}
close $fh;

if (not @questions) {
  print "No questions containing '$text' found.\n";
  exit;
}

my $question = $questions[int rand(@questions)];

my ($q, $a) = split /\|/, $question, 2;
chomp $q;
chomp $a;

$q =~ s/^\[.*?\]\s+//;
print "$q\n";

open $fh, ">", "$CJEOPARDY_DATA-$channel" or die "Could not open $CJEOPARDY_DATA-$channel: $!";
print $fh "$a\n";
print $fh gettimeofday, "\n";
close $fh;
