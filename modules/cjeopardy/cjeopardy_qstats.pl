#!/usr/bin/env perl

use warnings;
use strict;

use Time::HiRes qw(gettimeofday);
use Time::Duration qw(duration concise);
use POSIX 'strftime';

use QStatskeeper;
use IRCColors;

my $command   = shift @ARGV;
my $opt       = join ' ', @ARGV;

$command = '' if not defined $command;
$opt = '' if not defined $opt;

if (lc $command eq 'rank') {
  print "QStats rankings coming soon.\n";
} elsif ($command =~ m/^\d+$/) {
  my $qstats = QStatskeeper->new;
  $qstats->begin;

  if (not $qstats->find_question($command)) {
    print "No such question $command.\n";
    $qstats->end;
    exit;
  }

  my $qdata = $qstats->get_question_data($command);
  my $wrong_answers = $qstats->get_wrong_answers($command);
  $qstats->end;

  my $stats = "Question $command: ";

  $stats .= "asked: $qdata->{asked_count}";
  if ($qdata->{last_asked}) {
    my $date = strftime '%b %e %H:%M %Y', localtime $qdata->{last_asked};
    $stats .= " (last on $date)";
  }
  $stats .= ", ";

  $stats .= "correct: $qdata->{correct}";
  if ($qdata->{last_correct_time}) {
    my $date = strftime '%b %e %H:%M %Y', localtime $qdata->{last_correct_time};
    $stats .= " (last by $qdata->{last_correct_nick} on $date)";
  }
  $stats .= ", ";

  $stats .= "wrong: $qdata->{wrong}, wrong streak: $qdata->{wrong_streak}, highest wrong streak: $qdata->{highest_wrong_streak}, ";

  $stats .= "hints: $qdata->{hints}, ";

  $stats .= "quickest: ";
  if ($qdata->{quickest_answer_time}) {
    if ($qdata->{quickest_answer_time} < 60) {
      $stats .= sprintf("%.2fs", $qdata->{quickest_answer_time});
    } else {
      $stats .= concise duration $qdata->{quickest_answer_time};
    }
    my $date = strftime '%b %e %H:%M %Y', localtime $qdata->{quickest_answer_date};
    $stats .= " by $qdata->{quickest_answer_nick} on $date";
  } else {
    $stats .= "N/A";
  }
  $stats .= ", ";

  $stats .= "longest: ";
  if ($qdata->{longest_answer_time}) {
    if ($qdata->{longest_answer_time} < 60) {
      $stats .= sprintf("%.2fs", $qdata->{longest_answer_time});
    } else {
      $stats .= concise duration $qdata->{longest_answer_time};
    }
    my $date = strftime '%b %e %H:%M %Y', localtime $qdata->{longest_answer_date};
    $stats .= " by $qdata->{longest_answer_nick} on $date";
  } else {
    $stats .= "N/A";
  }
  $stats .= ", ";

  $stats .= "average: ";
  if ($qdata->{average_answer_time}) {
    if ($qdata->{average_answer_time} < 60) {
      $stats .= sprintf("%.2fs", $qdata->{average_answer_time});
    } else {
      $stats .= concise duration $qdata->{average_answer_time};
    }
  } else {
    $stats .= "N/A";
  }

  if (@$wrong_answers) {
    $stats .= ", wrong answers: ";
    my $count = 0;
    my $sep = "";
    foreach my $answer (sort { $b->{count} <=> $a->{count} } @$wrong_answers) {
      last if ++$count >= 10;
      $stats .= $sep;
      $stats .= $answer->{answer};
      if ($answer->{count} > 1) {
        $stats .= "($answer->{count})";
      }
      $sep = ", ";
    }
  }

  print "$stats\n";
} else {
  print "Usage: `qstats <question id>` or `qstats rank [keyword]`; See `qstats rank` for available keywords.\n";
}
