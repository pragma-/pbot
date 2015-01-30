#!/usr/bin/env perl

use warnings;
use strict;

use Text::Levenshtein qw(fastdistance);
use Time::HiRes qw(gettimeofday);
use Fcntl qw(:flock);

use Scorekeeper;
use IRCColors;

my $CJEOPARDY_DATA        = 'data/cjeopardy.dat';
my $CJEOPARDY_HINT        = 'data/cjeopardy.hint';
my $CJEOPARDY_LAST_ANSWER = 'data/cjeopardy.last_ans';

my $hint_only_mode = 0;

my $nick = shift @ARGV;
my $channel = shift @ARGV;
my $text = join(' ', @ARGV);

sub encode { my $str = shift; $str =~ s/\\(.)/{sprintf "\\%03d", ord($1)}/ge; return $str; }
sub decode { my $str = shift; $str =~ s/\\(\d{3})/{"\\" . chr($1)}/ge; return $str }

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel. Feel free to join #cjeopardy.\n";
  exit;
}

while($text =~ s/^\s*(is|are|the|a|an)\s+//i){};
$text =~ s/\s*\?*$//;
$text =~ s/^\s+//;
$text =~ s/\s+$//;
my $lctext = lc $text;

if (not length $lctext) {
  print "What?\n";
  exit;
}

my @data;

open my $semaphore, ">", "$CJEOPARDY_DATA-$channel.lock" or die "Couldn't create semaphore lock: $!";
flock $semaphore, LOCK_EX;

my $ret = open my $fh, "<", "$CJEOPARDY_LAST_ANSWER-$channel";
if (defined $ret) {
  my $last_nick = <$fh>;
  my $last_answers = <$fh>;
  my $last_timestamp = <$fh>;
  close $fh;

  chomp $last_nick;

  if(scalar gettimeofday - $last_timestamp <= 15) {
    $ret = open $fh, "<", "$CJEOPARDY_DATA-$channel";
    if (defined $ret) {
      @data = <$fh>;
      close $fh;
    }

    my @current_answers = map { decode $_ } split /\|/, encode $data[1] if @data;
    my @valid_answers = map { decode $_ } split /\|/, encode $last_answers;

    foreach my $answer (@valid_answers) {
      chomp $answer;
      $answer =~ s/\\\|/|/g;
      $answer =~ s/\s*{.*}\s*//;

      my $skip_last;
      if (@current_answers) {
        foreach my $current_answer (@current_answers) {
          chomp $current_answer;
          $current_answer =~ s/\\\|/|/g;
          $current_answer =~ s/\s*{.*}\s*//;

          my $distance = fastdistance(lc $answer, lc $current_answer);
          my $length = (length($answer) > length($current_answer)) ? length $answer : length $current_answer;

          if ($distance / $length < 0.15) {
            $skip_last = 1;
            last;
          }
        }
      }

      last if $skip_last;

      my $distance = fastdistance($lctext, lc $answer);
      my $length = (length($lctext) > length($answer)) ? length $lctext : length $answer;

      if ($distance / $length < 0.15) {
        if ($last_nick eq $nick) {
          print "$color{red}Er, you already correctly answered that question.$color{reset}\n";
        } else {
          print "$color{red}Too slow! $color{orange}$last_nick$color{red} got the correct answer.$color{reset}\n";
        }
        exit;
      }
    }
  }
}

if (not @data) {
  open $fh, "<", "$CJEOPARDY_DATA-$channel" or print "There is no open C Jeopardy question.  Use `cjeopardy` to get a question.\n" and exit;
  @data = <$fh>;
  close $fh;
}

my $scores = Scorekeeper->new;
$scores->begin;
my $player_id = $scores->get_player_id($nick, $channel);
my $player_data = $scores->get_player_data($player_id);

my @valid_answers = map { decode $_ } split /\|/, encode $data[1];

my $incorrect_percentage = 100;

foreach my $answer (@valid_answers) {
  chomp $answer;
  $answer =~ s/\\\|/|/g;

  my $supplemental_text;
  if ($answer =~ s/\s*{(.*)}\s*$//) {
    $supplemental_text = $1;
  }

  if ($answer =~ /^[0-9]+$/ and $lctext =~ /^[0-9]+$/) {
    my $is_wrong = 0;

    if ($lctext > $answer) {
      print "$color{red}$lctext is too high!$color{reset}\n";
      $is_wrong = 1;
    } elsif ($lctext < $answer) {
      print "$color{red}$lctext is too low!$color{reset}\n";
      $is_wrong = 1;
    }

    goto WRONG_ANSWER if $is_wrong;
  }

  my $distance = fastdistance($lctext, lc $answer);
  my $length = (length($lctext) > length($answer)) ? length $lctext : length $answer;

  my $percentage = $distance / $length * 100;

  if ($percentage < $incorrect_percentage) {
    $incorrect_percentage = $percentage; 
  }

  if ($percentage < 15) {
    if ($distance == 0) {
      print "'$color{green}$answer$color{reset}' is correct!";
    } else {
      print "'$color{green}$text$color{reset}' is close enough to '$color{green}$answer$color{reset}'. You are correct!"
    }

    if (defined $supplemental_text) {
      print " $color{teal}$supplemental_text$color{reset}\n";
    } else {
      print "\n";
    }

    my $streakers = $scores->get_all_correct_streaks($channel);

    foreach my $streaker (@$streakers) {
      next if $streaker->{nick} eq $nick;

      if ($streaker->{correct_streak} >= 3) {
        print "$color{orange}$nick$color{red} ended $color{orange}$streaker->{nick}$color{red}'s $color{orange}$streaker->{correct_streak}$color{red} correct answer streak!$color{reset}\n";
      }

      $streaker->{correct_streak} = 0;
      $scores->update_player_data($streaker->{id}, $streaker);
    }

    $player_data->{correct_answers}++;
    $player_data->{lifetime_correct_answers}++;
    $player_data->{correct_streak}++;
    $player_data->{last_correct_timestamp} = scalar gettimeofday;
    $player_data->{wrong_streak} = 0;

    if ($player_data->{correct_streak} > $player_data->{highest_correct_streak}) {
      $player_data->{highest_correct_streak} = $player_data->{correct_streak};
    }

    if ($player_data->{highest_correct_streak} > $player_data->{lifetime_highest_correct_streak}) {
      $player_data->{lifetime_highest_correct_streak} = $player_data->{highest_correct_streak};
    }

    my %streaks = (
      3  => "$color{orange}$nick$color{green} is on a $color{orange}3$color{green} correct answer streak!",
      4  => "$color{orange}$nick$color{green} is hot with a $color{orange}4$color{green} correct answer streak!",
      5  => "$color{orange}$nick$color{green} is on fire with a $color{orange}5$color{green} correct answer streak!",
      6  => "$color{orange}$nick$color{green} is ON FIRE with a $color{orange}6$color{green} correct answer streak!",
      7  => "$color{orange}$nick$color{green} is DOMINATING with a $color{orange}7$color{green} correct answer streak!",
      8  => "$color{orange}$nick$color{green} is DOMINATING with an $color{orange}8$color{green} correct answer streak!",
      9  => "$color{orange}$nick$color{green} is DOMINATING with a $color{orange}9$color{green} correct answer streak!",
      10 => "$color{orange}$nick$color{green} IS UNTOUCHABLE WITH A $color{orange}10$color{green} CORRECT ANSWER STREAK!"
    );

    if (exists $streaks{$player_data->{correct_streak}}) {
      print "$streaks{$player_data->{correct_streak}}$color{reset}\n";
    }

    $scores->update_player_data($player_id, $player_data);
    $scores->end;

    unlink "$CJEOPARDY_DATA-$channel";
    unlink "$CJEOPARDY_HINT-$channel";

    open $fh, ">", "$CJEOPARDY_LAST_ANSWER-$channel" or die "Couldn't open $CJEOPARDY_LAST_ANSWER-$channel: $!";
    my $time = scalar gettimeofday;
    print $fh "$nick\n$data[1]$time\n";
    close $fh;

    close $semaphore;

    if ($channel eq '#cjeopardy') {
      my $question = `./cjeopardy.pl $channel`;
      
      if ($hint_only_mode) {
        my $hint = `./cjeopardy_hint.pl $channel`;
        $hint =~ s/^Hint: //;
        print "Next hint: $hint\n";
      } else {
        print "$color{green}Next question$color{reset}: $question\n";
      }
    }

    exit;
  }
}

my $correct_percentage = 100 - $incorrect_percentage;
if ($correct_percentage >= 80) {
  printf "Sorry, '$color{red}$text$color{reset}' is %.1f%% correct. So close!\n", $correct_percentage;
} elsif ($correct_percentage >= 70) {
  printf "Sorry, '$color{red}$text$color{reset}' is %.1f%% correct. Almost.\n", $correct_percentage;
} elsif ($correct_percentage >= 50) {
  printf "Sorry, '$color{red}$text$color{reset}' is only %.1f%% correct.\n", $correct_percentage;
} else {
  print "Sorry, '$color{red}$text$color{reset}' is incorrect.\n";
}

WRONG_ANSWER:
$player_data->{wrong_answers}++;
$player_data->{lifetime_wrong_answers}++;
$player_data->{wrong_streak}++;
$player_data->{last_wrong_timestamp} = scalar gettimeofday;
$player_data->{correct_streak} = 0;

if ($player_data->{wrong_streak} > $player_data->{highest_wrong_streak}) {
  $player_data->{highest_wrong_streak} = $player_data->{wrong_streak};
}

if ($player_data->{highest_wrong_streak} > $player_data->{lifetime_highest_wrong_streak}) {
  $player_data->{lifetime_highest_wrong_streak} = $player_data->{highest_wrong_streak};
}

my %streaks = (
  3  => "$color{red}Guessing, are we, $color{orange}$nick$color{red}?",
  4  => "$color{red}Please use better guesses, $color{orange}$nick!",
  5  => "$color{red}Are you even trying, $color{orange}$nick$color{red}?!",
  6  => "$color{red}Try a little bit harder, $color{orange}$nick$color{red}.",
  7  => "$color{red}Maybe you should go look it up, $color{orange}$nick$color{red}.",
  8  => "$color{red}For fuck's sake, go look it up already, $color{orange}$nick$color{red}!",
  9  => "$color{red}Are you sure you weren't dropped on your head, $color{orange}$nick$color{red}?",
  10 => "$color{red}Have you been checked for mental retardation yet, $color{orange}$nick$color{red}?"
);

if (exists $streaks{$player_data->{wrong_streak}}) {
  print "$streaks{$player_data->{wrong_streak}}$color{reset}\n";
}

$scores->update_player_data($player_id, $player_data);
$scores->end;
