#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

use Time::HiRes qw(gettimeofday);
use Time::Duration qw(concise duration);

use Scorekeeper;
use IRCColors;

my $nick      = shift @ARGV;
my $channel   = shift @ARGV;
my $command   = shift @ARGV;
my $opt       = join ' ', @ARGV;

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel. Feel free to join #cjeopardy.\n";
  exit;
}

my $scores = Scorekeeper->new;
$scores->begin;

my $rank_direction = '+';

sub sort_correct {
  if ($rank_direction eq '+') {
    return $b->{lifetime_correct_answers} <=> $a->{lifetime_correct_answers};
  } else {
    return $a->{lifetime_correct_answers} <=> $b->{lifetime_correct_answers};
  }
}

sub print_correct {
  my $player = shift @_;
  return undef if $player->{lifetime_correct_answers} == 0;
  return "$player->{nick}: $player->{lifetime_correct_answers}";
}

sub sort_wrong {
  if ($rank_direction eq '+') {
    return $a->{lifetime_wrong_answers} <=> $b->{lifetime_wrong_answers};
  } else {
    return $b->{lifetime_wrong_answers} <=> $a->{lifetime_wrong_answers};
  }
}

sub print_wrong {
  my $player = shift @_;
  return undef if $player->{lifetime_wrong_answers} == 0 and $player->{lifetime_correct_answers} == 0;
  return "$player->{nick}: $player->{lifetime_wrong_answers}";
}

sub sort_ratio {
  my $wrong_a = $a->{lifetime_wrong_answers} ? $a->{lifetime_wrong_answers} : 1;
  my $wrong_b = $b->{lifetime_wrong_answers} ? $b->{lifetime_wrong_answers} : 1;
  if ($rank_direction eq '+') {
    return $b->{lifetime_correct_answers} / $wrong_b <=> $a->{lifetime_correct_answers} / $wrong_a;
  } else {
    return $a->{lifetime_correct_answers} / $wrong_a <=> $b->{lifetime_correct_answers} / $wrong_b;
  }
}

sub print_ratio {
  my $player = shift @_;
  return undef if $player->{lifetime_wrong_answers} + $player->{lifetime_correct_answers} < 50;
  my $wrong = $player->{lifetime_wrong_answers} ? $player->{lifetime_wrong_answers} : 1;
  my $ratio = $player->{lifetime_correct_answers} / $wrong;
  return undef if $ratio == 0;
  return sprintf "$player->{nick}: %.2f", $ratio;
}

sub sort_hints {
  if ($rank_direction eq '+') {
    return $a->{lifetime_hints} <=> $b->{lifetime_hints};
  } else {
    return $b->{lifetime_hints} <=> $a->{lifetime_hints};
  }
}

sub print_hints {
  my $player = shift @_;
  return undef if $player->{lifetime_hints} == 0 and $player->{lifetime_correct_answers} == 0;
  return "$player->{nick}: $player->{lifetime_hints}";
}

sub sort_correctstreak {
  if ($rank_direction eq '+') {
    return $b->{lifetime_highest_correct_streak} <=> $a->{lifetime_highest_correct_streak};
  } else {
    return $a->{lifetime_highest_correct_streak} <=> $b->{lifetime_highest_correct_streak};
  }
}

sub print_correctstreak {
  my $player = shift @_;
  return undef if $player->{lifetime_highest_correct_streak} == 0;
  return "$player->{nick}: $player->{lifetime_highest_correct_streak}";
}

sub sort_quickeststreak {
  my $streak_a = $a->{lifetime_highest_quick_correct_streak} ? $a->{lifetime_highest_quick_correct_streak} : -1000;
  my $streak_b = $b->{lifetime_highest_quick_correct_streak} ? $b->{lifetime_highest_quick_correct_streak} : -1000;

  if ($rank_direction eq '+') {
    return $streak_b - $b->{lifetime_quickest_correct_streak} / ($streak_b / 2) <=> $streak_a - $a->{lifetime_quickest_correct_streak} / ($streak_a / 2);
  } else {
    return $streak_a - $a->{lifetime_quickest_correct_streak} / ($streak_a / 2) <=> $streak_b - $b->{lifetime_quickest_correct_streak} / ($streak_b / 2);
  }
}

sub print_quickeststreak {
  my $player = shift @_;
  return undef if $player->{lifetime_highest_quick_correct_streak} == 0;
  if ($player->{lifetime_quickest_correct_streak} < 60) {
    return "$player->{nick}: $player->{lifetime_highest_quick_correct_streak} in " . sprintf("%.2fs", $player->{lifetime_quickest_correct_streak});
  } else {
    return "$player->{nick}: $player->{lifetime_highest_quick_correct_streak} in " . concise duration $player->{lifetime_quickest_correct_streak};
  }
}

sub sort_wrongstreak {
  if ($rank_direction eq '+') {
    return $a->{lifetime_highest_wrong_streak} <=> $b->{lifetime_highest_wrong_streak};
  } else {
    return $b->{lifetime_highest_wrong_streak} <=> $a->{lifetime_highest_wrong_streak};
  }
}

sub print_wrongstreak {
  my $player = shift @_;
  return undef if $player->{lifetime_highest_wrong_streak} == 0 and $player->{lifetime_correct_answers} == 0;
  return "$player->{nick}: $player->{lifetime_highest_wrong_streak}";
}

sub sort_quickest {
  if ($rank_direction eq '+') {
    return $a->{quickest_correct} <=> $b->{quickest_correct};
  } else {
    return $b->{quickest_correct} <=> $a->{quickest_correct};
  }
}

sub print_quickest {
  my $player = shift @_;

  return undef if $player->{quickest_correct} == 0;

  my $quickest;
  if ($player->{quickest_correct} < 60) {
    $quickest = sprintf("%.2fs", $player->{quickest_correct});
  } else {
    $quickest = concise duration($player->{quickest_correct});
  }

  return "$player->{nick}: $quickest";
}

if (lc $command eq 'rank') {
  my %ranks = (
    correct        => { sort => \&sort_correct,        print => \&print_correct,         title => 'correct answers'                },
    wrong          => { sort => \&sort_wrong,          print => \&print_wrong,           title => 'wrong answers'                  },
    quickest       => { sort => \&sort_quickest,       print => \&print_quickest,        title => 'quickest answer'                },
    ratio          => { sort => \&sort_ratio,          print => \&print_ratio,           title => 'correct/wrong ratio'            },
    correctstreak  => { sort => \&sort_correctstreak , print => \&print_correctstreak,   title => 'correct answer streak'          },
    quickeststreak => { sort => \&sort_quickeststreak, print => \&print_quickeststreak,  title => 'quickest correct answer streak' },
    wrongstreak    => { sort => \&sort_wrongstreak,    print => \&print_wrongstreak,     title => 'wrong answer streak'            },
    hints          => { sort => \&sort_hints,          print => \&print_hints,           title => 'hints used'                     },
  );

  if (not $opt) {
    print "Usage: rank [-]<keyword> [offset] or rank [-]<nick>; available keywords: ";
    print join ', ', sort keys %ranks;
    print ".\n";
    print "Prefixing the keyword or nick with a dash will invert the sort direction for each category. Specifying an offset will start ranking at that offset.\n";
    goto END;
  }

  $opt = lc $opt;

  if ($opt =~ s/^([+-])//) {
    $rank_direction = $1;
  }

  my $offset = 1;
  if ($opt =~ s/\s+(\d+)$//) {
    $offset = $1;
  }

  if (not exists $ranks{$opt}) {
    my $player_id = $scores->get_player_id($opt, $channel, 1);
    my $player_data = $scores->get_player_data($player_id);

    if (not defined $player_id) {
      print "I don't know anybody named $opt\n";
      goto END;
    }

    my $players = $scores->get_all_players($channel);
    my @rankings;

    foreach my $key (sort keys %ranks) {
      if ($key eq 'ratio' && $player_data->{lifetime_correct_answers} + $player_data->{lifetime_wrong_answers} < 50) {
        my $needed_answers = 50 - ($player_data->{lifetime_correct_answers} + $player_data->{lifetime_wrong_answers});
        push @rankings, "$ranks{$key}->{title}: ($needed_answers more answers for rank)";
        next;
      }

      my $sort_method = $ranks{$key}->{sort};
      @$players = sort $sort_method @$players;

      my $rank = 0;
      my $stats;
      my $last_value = -1;
      foreach my $player (@$players) {
        next if $player->{nick} eq 'lern2play' and $opt ne 'lern2play';
        next if $player->{nick} eq 'keep2play' and $opt ne 'keep2play';

        $stats = $ranks{$key}->{print}->($player);

        if (defined $stats) {
          my ($value) = $stats =~ /[^:]+:\s+(.*)/;
          $rank++ if $value ne $last_value;
          $last_value = $value;
        } else {
          $rank++ if lc $player->{nick} eq $opt;
        }

        last if lc $player->{nick} eq $opt;
      }
      if (not $rank) {
        push @rankings, "$ranks{key}->{title}: N/A";
      } else {
        if (not $stats) {
          push @rankings, "$ranks{$key}->{title}: N/A";
        } else {
          $stats =~ s/[^:]+:\s+//;
          push @rankings, "$ranks{$key}->{title}: #$rank ($stats)";
        }
      }
    }

    if (lc $nick ne $opt) {
      print "$player_data->{nick}'s rankings: ";
    } else {
      print "Your rankings: ";
    }
    print join ', ', @rankings;
    print "\n";

    goto END;
  }

  my $players = $scores->get_all_players($channel);

  my $sort_method = $ranks{$opt}->{sort};
  @$players = sort $sort_method @$players;

  my @ranking;
  my $rank = 0;
  my $last_value = -1;
  foreach my $player (@$players) {
    next if $player->{nick} eq 'lern2play';
    next if $player->{nick} eq 'keep2play';
    my $entry = $ranks{$opt}->{print}->($player);
    if (defined $entry) {
      my ($value) = $entry =~ /[^:]+:\s+(.*)/;
      $rank++ if $value ne $last_value;
      $last_value = $value;
      next if $rank < $offset;
      push @ranking, "#$rank $entry" if defined $entry;
      last if scalar @ranking >= 15;
    }
  }

  if (not scalar @ranking) {
    if ($offset > 1) {
      print "No rankings available for $channel at offset #$offset.\n";
    } else {
      print "No rankings available for $channel yet.\n";
    }
  } else {
    print "Rankings for $ranks{$opt}->{title}: ";
    print join ', ', @ranking;
    print "\n";
  }

  goto END;
}

my $player_nick = $nick;
$player_nick = $opt if $opt and lc $command eq 'score';

my $player_id = $scores->get_player_id($player_nick, $channel, 1);

if (not defined $player_id) {
  print "I don't know anybody named $player_nick\n";
  goto END;
}

my $player_data = $scores->get_player_data($player_id);

if (lc $command eq 'score') {
  my $score = "$player_data->{nick}: " unless lc $nick eq lc $player_nick;

  $score .= "correct: $player_data->{correct_answers}" . ($player_data->{lifetime_correct_answers} > $player_data->{correct_answers} ? " [$player_data->{lifetime_correct_answers}]" : "") . ", ";
  $score .= "current correct streak: $player_data->{correct_streak}, ";
  $score .= "highest correct streak: $player_data->{highest_correct_streak}" . ($player_data->{lifetime_highest_correct_streak} > $player_data->{highest_correct_streak} ? " [$player_data->{lifetime_highest_correct_streak}]" : "") . ", ";
  $score .= "quickest correct streak: ";
  $score .= ($player_data->{highest_quick_correct_streak} > 0 ? "$player_data->{highest_quick_correct_streak} in " . (concise duration $player_data->{quickest_correct_streak}) : "N/A") . ($player_data->{lifetime_highest_quick_correct_streak} > $player_data->{highest_quick_correct_streak} ? " [$player_data->{lifetime_highest_quick_correct_streak} in " . (concise duration $player_data->{lifetime_quickest_correct_streak}) . "]" : "") . ", ";
  
  $score .= "quickest answer: ";

  if ($player_data->{quickest_correct} == 0) {
    $score .= "N/A";
  } elsif ($player_data->{quickest_correct} < 60) {
    $score .= sprintf("%.2fs", $player_data->{quickest_correct});
  } else {
    $score .= concise duration($player_data->{quickest_correct});
  }

  $score .= ", ";

  $score .= "wrong: $player_data->{wrong_answers}" . ($player_data->{lifetime_wrong_answers} > $player_data->{wrong_answers} ? " [$player_data->{lifetime_wrong_answers}]" : "") . ", ";
  $score .= "current wrong streak: $player_data->{wrong_streak}, ";
  $score .= "highest wrong streak: $player_data->{highest_wrong_streak}" . ($player_data->{lifetime_highest_wrong_streak} > $player_data->{highest_wrong_streak} ? " [$player_data->{lifetime_highest_wrong_streak}]" : "") . ", ";

  $score .= "ratio: ";
  my $wrong = $player_data->{wrong_answers} ? $player_data->{wrong_answers} : 1;
  $score .= sprintf("%.2f", $player_data->{correct_answers} / $wrong);
  if ($player_data->{lifetime_correct_answers} > 0) {
    $wrong = $player_data->{lifetime_wrong_answers} ? $player_data->{lifetime_wrong_answers} : 1;
    $score .= sprintf(" [%.2f]", $player_data->{lifetime_correct_answers} / $wrong);
  }
  $score .= ", ";

  $score .= "hints: $player_data->{hints}" . ($player_data->{lifetime_hints} > $player_data->{hints} ? " [$player_data->{lifetime_hints}]" : "") . "\n";

  print $score;
} elsif (lc $command eq 'reset') {
  $player_data->{correct_answers}              = 0;
  $player_data->{wrong_answers}                = 0;
  $player_data->{correct_streak}               = 0;
  $player_data->{wrong_streak}                 = 0;
  $player_data->{highest_correct_streak}       = 0;
  $player_data->{highest_wrong_streak}         = 0;
  $player_data->{hints}                        = 0;
  $player_data->{correct_streak_timestamp}     = 0;
  $player_data->{highest_quick_correct_streak} = 0;
  $player_data->{quickest_correct_streak}      = 0;
  $scores->update_player_data($player_id, $player_data);
  print "Your scores for this session have been reset.\n";
}

END:
$scores->end;
