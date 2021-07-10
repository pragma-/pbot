#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

use Time::HiRes qw/gettimeofday/;
use Time::Duration qw/duration/;
use Fcntl qw(:flock);

use lib ".";

use IRCColors;
use QStatskeeper;

my $CJEOPARDY_FILE    = 'cjeopardy.txt';
my $CJEOPARDY_DATA    = 'data/cjeopardy.dat';
my $CJEOPARDY_FILTER  = 'data/cjeopardy.filter';
my $CJEOPARDY_HINT    = 'data/cjeopardy.hint';
my $CJEOPARDY_SHUFFLE = 'data/cjeopardy.shuffle';

my $TIMELIMIT = 300;

my $channel = shift @ARGV;
my $text = join(' ', @ARGV);

sub encode { my $str = shift; $str =~ s/\\(.)/{sprintf "\\%03d", ord($1)}/ge; return $str; }
sub decode { my $str = shift; $str =~ s/\\(\d{3})/{"\\" . chr($1)}/ge; return $str }

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel. Feel free to join #cjeopardy.\n";
  exit;
}

open my $semaphore, ">", "$CJEOPARDY_DATA-$channel.lock" or die "Couldn't create semaphore lock: $!";
flock $semaphore, LOCK_EX;

my $ret = open my $fh, "<", "$CJEOPARDY_DATA-$channel";
if (defined $ret) {
  my $last_question = <$fh>;
  my $last_answer = <$fh>;
  my $last_timestamp = <$fh>;

  if (scalar gettimeofday - $last_timestamp <= $TIMELIMIT) {
    my $duration = duration($TIMELIMIT - scalar gettimeofday - $last_timestamp);
    print "$color{magneta}The current question is$color{reset}: $last_question";
    print "$color{red}You may request a new question in $duration.$color{reset}\n";
    close $fh;
    exit;
  }
  close $fh;
}

my $filter_regex;
my $filter_text;
$ret = open $fh, "<", "$CJEOPARDY_FILTER-$channel";
if (defined $ret) {
  my $words = <$fh>;
  close $fh;

  chomp $words;

  $filter_text = $words;
  $filter_text =~ s/,/, /g;
  $filter_text =~ s/, ([^,]+)$/ or $1/;

#  print "[Filter active!]\n";

  my @w = split /,/, $words;
  my $sep = '';
  $filter_regex .= '(?:';
  foreach my $word (@w) {
    $filter_regex .= $sep;
    $filter_regex .= $word =~ m/^[a-zA-Z0-9]/ ? '\b' : '\B';
    $filter_regex .= quotemeta $word;
    $filter_regex .= $word =~ m/[a-zA-Z0-9]$/ ? '\b' : '\B';
    $sep = '|';
  }
  $filter_regex .= ')';
}

my $question_index;
my $shuffles = 0;

NEXT_QUESTION:

if (not length $text) {
  $ret = open $fh, "<", "$CJEOPARDY_SHUFFLE-$channel";
  if (defined $ret) {
    my @indices = <$fh>;
    $question_index = shift @indices;
    close $fh;

    if (not @indices) {
      print "$color{teal}(Shuffling.)$color{reset}\n";
      shuffle_questions(0);
      $shuffles++;
    } else {
      open my $fh, ">", "$CJEOPARDY_SHUFFLE-$channel" or print "Failed to shuffle questions.\n" and exit;
      foreach my $index (@indices) {
        print $fh $index;
      }
      close $fh;
    }
  } else {
    print "$color{teal}(Shuffling!)$color{reset}\n";
    $question_index = shuffle_questions(1);
    $shuffles++;
  }
}

my @questions;
open $fh, "<", $CJEOPARDY_FILE or die "Could not open $CJEOPARDY_FILE: $!";
while (my $question = <$fh>) {
  my ($question_only) = map { decode $_ } split /\|/, encode($question), 2;
  $question_only =~ s/\\\|/|/g;
  next if length $text and $question_only !~ /\Q$text\E/i;
  next if defined $filter_regex and $question_only =~ /$filter_regex/i;
  push @questions, $question;
}
close $fh;

if (not @questions) {
  if (length $text) {
    print "No questions containing '$text' found.\n";
  } else {
    if ($shuffles <= 1) {
      goto NEXT_QUESTION;
    } else {
      print "No questions available.\n";
    }
  }
  exit;
}

if (length $text) {
  $question_index = int rand(@questions);
}

my $question = $questions[$question_index];

if (not defined $question) {
  goto NEXT_QUESTION;
}

my ($q, $a) = map { decode $_ } split /\|/, encode($question), 2;
chomp $q;
chomp $a;

$q =~ s/\\\|/|/g;
$q =~ s/^(\d+)\) \[.*?\]\s+/$1) /;
my $id = $1;

$q =~ s/\b(this keyword|this operator|this behavior|this preprocessing directive|this escape sequence|this mode|this function specifier|this function|this macro|this predefined macro|this header|this pragma|this fprintf length modifier|this storage duration|this type qualifier|this type|this value|this operand|this many|this|these)\b/$color{bold}$1$color{reset}/gi;
print "$q\n";

open $fh, ">", "$CJEOPARDY_DATA-$channel" or die "Could not open $CJEOPARDY_DATA-$channel: $!";
print $fh "$q\n";
print $fh "$a\n";
print $fh scalar gettimeofday, "\n";
close $fh;

unlink "$CJEOPARDY_HINT-$channel";

my $qstats = QStatskeeper->new;
$qstats->begin;

my $qdata = $qstats->get_question_data($id);

$qdata->{asked_count}++;
$qdata->{last_asked} = gettimeofday;
$qdata->{last_touched} = gettimeofday;
$qdata->{wrong_streak} = 0;

$qstats->update_question_data($id, $qdata);
$qstats->end;

close $semaphore;

=cut
my $hint = `./cjeopardy_hint.pl candide $channel`;
print $hint;
=cut

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


