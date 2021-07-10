#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

use Time::HiRes qw(gettimeofday);
use Time::Duration qw(duration concise);
use POSIX 'strftime';

use lib ".";

use QStatskeeper;

my $command   = shift @ARGV;
my $opt       = join ' ', @ARGV;

$command = '' if not defined $command;
$opt = '' if not defined $opt;

my $rank_direction = '+';

sub sort_correct {
  if ($rank_direction eq '+') {
    return $b->{correct} <=> $a->{correct};
  } else {
    return $a->{correct} <=> $b->{correct};
  }
}

sub print_correct {
  my $qdata = shift @_;
  return undef if $qdata->{correct} == 0;
  return "$qdata->{id} ($qdata->{correct})";
}

sub sort_wrong {
  if ($rank_direction eq '+') {
    return $b->{wrong} <=> $a->{wrong};
  } else {
    return $a->{wrong} <=> $b->{wrong};
  }
}

sub print_wrong {
  my $qdata = shift @_;
  return undef if $qdata->{wrong} == 0;
  return "$qdata->{id} ($qdata->{wrong})";
}

sub sort_wrongstreak {
  if ($rank_direction eq '+') {
    return $b->{highest_wrong_streak} <=> $a->{highest_wrong_streak};
  } else {
    return $a->{highest_wrong_streak} <=> $b->{highest_wrong_streak};
  }
}

sub print_wrongstreak {
  my $qdata = shift @_;
  return undef if $qdata->{highest_wrong_streak} == 0;
  return "$qdata->{id} ($qdata->{highest_wrong_streak})";
}

sub sort_hints {
  if ($rank_direction eq '+') {
    return $b->{hints} <=> $a->{hints};
  } else {
    return $a->{hints} <=> $b->{hints};
  }
}

sub print_hints {
  my $qdata = shift @_;
  return undef if $qdata->{hints} == 0;
  return "$qdata->{id} ($qdata->{hints})";
}

sub sort_quickest {
  if ($rank_direction eq '+') {
    return $a->{quickest_answer_time} <=> $b->{quickest_answer_time};
  } else {
    return $b->{quickest_answer_time} <=> $a->{quickest_answer_time};
  }
}

sub print_quickest {
  my $qdata = shift @_;
  return undef if $qdata->{quickest_answer_time} == 0;
  if ($qdata->{quickest_answer_time} < 60) {
    return "$qdata->{id} (" . sprintf("%.02fs", $qdata->{quickest_answer_time}) . ")";
  } else {
    return "$qdata->{id} (" . (concise duration $qdata->{quickest_answer_time}) . ")";
  }
}

sub sort_longest {
  if ($rank_direction eq '+') {
    return $b->{longest_answer_time} <=> $a->{longest_answer_time};
  } else {
    return $a->{longest_answer_time} <=> $b->{longest_answer_time};
  }
}

sub print_longest {
  my $qdata = shift @_;
  return undef if $qdata->{longest_answer_time} == 0;
  if ($qdata->{longest_answer_time} < 60) {
    return "$qdata->{id} (" . sprintf("%.02fs", $qdata->{longest_answer_time}) . ")";
  } else {
    return "$qdata->{id} (" . (concise duration $qdata->{longest_answer_time}) . ")";
  }
}

sub sort_average {
  if ($rank_direction eq '+') {
    return $a->{average_answer_time} <=> $b->{average_answer_time};
  } else {
    return $b->{average_answer_time} <=> $a->{average_answer_time};
  }
}

sub print_average {
  my $qdata = shift @_;
  return undef if $qdata->{average_answer_time} == 0;
  if ($qdata->{average_answer_time} < 60) {
    return "$qdata->{id} (" . sprintf("%.02fs", $qdata->{average_answer_time}) . ")";
  } else {
    return "$qdata->{id} (" . (concise duration $qdata->{average_answer_time}) . ")";
  }
}

if (lc $command eq 'rank') {
  my %ranks = (
    correct        => { sort => \&sort_correct,        print => \&print_correct,         title => 'correct answers'                },
    wrong          => { sort => \&sort_wrong,          print => \&print_wrong,           title => 'wrong answers'                  },
    wrongstreak    => { sort => \&sort_wrongstreak,    print => \&print_wrongstreak,     title => 'wrong answer streak'            },
    hints          => { sort => \&sort_hints,          print => \&print_hints,           title => 'hints used'                     },
    quickest       => { sort => \&sort_quickest,       print => \&print_quickest,        title => 'quickest answer time'           },
    longest        => { sort => \&sort_longest,        print => \&print_longest,         title => 'longest answer time'            },
    average        => { sort => \&sort_average,        print => \&print_average,         title => 'average answer time'            },
  );

  if (not $opt) {
    print "Usage: qstats rank [-]<keyword> [offset] or rank [-]<question id>; available keywords: ";
    print join ', ', sort keys %ranks;
    print ".\n";
    print "Prefixing the keyword or question id with a dash will invert the sort direction for each category. Specifying an offset will start ranking at that offset.\n";
    exit;
  }

  my $qstats = QStatskeeper->new;
  $qstats->begin;

  $opt = lc $opt;

  if ($opt =~ s/^([+-])//) {
    $rank_direction = $1;
  }

  my $offset = 1;
  if ($opt =~ s/\s+(\d+)$//) {
    $offset = $1;
  }

  if (not exists $ranks{$opt}) {
    print "Ranking specific questions coming soon.\n";
    $qstats->end;
    exit;
  }

  my $qdatas = $qstats->get_all_questions();

  my $sort_method = $ranks{$opt}->{sort};
  @$qdatas = sort $sort_method @$qdatas;

  my @ranking;
  my $rank = 0;
  my $last_value = -1;
  foreach my $qdata (@$qdatas) {
    my $entry = $ranks{$opt}->{print}->($qdata);
    if (defined $entry) {
      my ($value) = $entry =~ /\((.*)\)$/;
      $rank++ if $value ne $last_value;
      $last_value = $value;
      next if $rank < $offset;
      push @ranking, "#$rank $entry" if defined $entry;
      last if scalar @ranking >= 15;
    }
  }

  if (not scalar @ranking) {
    if ($offset > 1) {
      print "No rankings available at offset #$offset.\n";
    } else {
      print "No rankings available yet.\n";
    }
  } else {
    print "Rankings for $ranks{$opt}->{title}: ";
    print join ', ', @ranking;
    print "\n";
  }

  $qstats->end;
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
