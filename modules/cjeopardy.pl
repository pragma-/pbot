#!/usr/bin/env perl

use warnings;
use strict;

use Time::HiRes qw/gettimeofday/;
use Time::Duration qw/duration/;

my $CJEOPARDY_FILE    = 'cjeopardy.txt';
my $CJEOPARDY_DATA    = 'cjeopardy.dat';
my $CJEOPARDY_SHUFFLE = 'cjeopardy.shuffle';

my $TIMELIMIT = 300;

my $channel = shift @ARGV;
my $text = join(' ', @ARGV);

sub encode { my $str = shift; $str =~ s/\\(.)/{sprintf "\\%03d", ord($1)}/ge; return $str; }
sub decode { my $str = shift; $str =~ s/\\(\d{3})/{"\\" . chr($1)}/ge; return $str }

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel.\n";
  exit;
}

my $ret = open my $fh, "<", "$CJEOPARDY_DATA-$channel";
if (defined $ret) {
  my $last_question = <$fh>;
  my $last_answer = <$fh>;
  my $last_timestamp = <$fh>;
  
  if (scalar gettimeofday - $last_timestamp <= $TIMELIMIT) {
    my $duration = duration($TIMELIMIT - scalar gettimeofday - $last_timestamp);
    print "The current question is: $last_question";
    print "You may request a new question in $duration.\n";
    close $fh;
    exit;
  }
}

my $question_index;

if (not length $text) {
  $ret = open $fh, "<", "$CJEOPARDY_SHUFFLE-$channel";
  if (defined $ret) {
    my @indices = <$fh>;
    $question_index = shift @indices;
    close $fh;

    if (not @indices) {
      print "(Shuffling.)\n";
      shuffle_questions(0);
    } else {
      open my $fh, ">", "$CJEOPARDY_SHUFFLE-$channel" or print "Failed to shuffle questions.\n" and exit;
      foreach my $index (@indices) {
        print $fh $index;
      }
      close $fh;
    }
  } else {
    print "(Shuffling!)\n";
    $question_index = shuffle_questions(1);
  }
}

my @questions;
open $fh, "<", $CJEOPARDY_FILE or die "Could not open $CJEOPARDY_FILE: $!";
while (my $question = <$fh>) {
  my ($question_only) = map { decode $_ } split /\|/, encode($question), 2;
  $question_only =~ s/\\\|/|/g;
  next if length $text and $question_only !~ /\Q$text\E/i;
  push @questions, $question;
}
close $fh;

if (not @questions) {
  print "No questions containing '$text' found.\n";
  exit;
}

if (length $text) {
  $question_index = int rand(@questions);
}

my $question = $questions[$question_index];

my ($q, $a) = map { decode $_ } split /\|/, encode($question), 2;
chomp $q;
chomp $a;

$q =~ s/\\\|/|/g;
$q =~ s/^\[.*?\]\s+//;

print "$q\n";

open $fh, ">", "$CJEOPARDY_DATA-$channel" or die "Could not open $CJEOPARDY_DATA-$channel: $!";
print $fh "$q\n";
print $fh "$a\n";
print $fh scalar gettimeofday, "\n";
close $fh;


sub shuffle_questions {
  my $return_index = shift @_;

  open my $fh, "<", $CJEOPARDY_FILE or die "Could not open $CJEOPARDY_FILE: $!";
  my (@indices, $i);
  while (<$fh>) {
    push @indices, $i++;
  }
  close $fh;

  open $fh, ">", "$CJEOPARDY_SHUFFLE-$channel" or die "Could not open $CJEOPARDY_SHUFFLE-$channel: $!";
  while (@indices) {
    my $random_index = int rand(@indices);
    my $index = $indices[$random_index];
    print $fh "$index\n";
    splice @indices, $random_index, 1;

    if ($return_index and @indices == 1) {
      close $fh;
      return $indices[0];
    }
  }
  close $fh;
}


