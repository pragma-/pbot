#!/usr/bin/env perl

use warnings;
use strict;

use Time::HiRes qw(gettimeofday);

use Scorekeeper;
use IRCColors;

my $hint_only_mode = 0;

my $nick      = shift @ARGV;
my $channel   = shift @ARGV;
my $command   = shift @ARGV;
my $opt_nick  = shift @ARGV;

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel. Feel free to join #cjeopardy.\n";
  exit;
}

my $scores = Scorekeeper->new;
$scores->begin;

my $player_nick = $nick;
$player_nick = $opt_nick if defined $opt_nick and lc $command eq 'score';

my $player_id = $scores->get_player_id($player_nick, $channel, 1);

if (not defined $player_id) {
  print "I don't know anybody named $player_nick\n";
  goto END;
}

my $player_data = $scores->get_player_data($player_id);

if (lc $command eq 'score') {
  my $score = "$color{orange}$player_data->{nick}$color{reset}: ";

  $score .= "$color{green}correct: $color{orange}$player_data->{correct_answers}" . ($player_data->{lifetime_correct_answers} > $player_data->{correct_answers} ? " [$player_data->{lifetime_correct_answers}]" : "") . "$color{green}, ";
  $score .= "current streak: $color{orange}$player_data->{correct_streak}$color{green}, ";
  $score .= "$color{green}highest streak: $color{orange}$player_data->{highest_correct_streak}" . ($player_data->{lifetime_highest_correct_streak} > $player_data->{highest_correct_streak} ? " [$player_data->{lifetime_highest_correct_streak}]" : "") . "$color{green}, ";
  
  $score .= "$color{red}wrong: $color{orange}$player_data->{wrong_answers}" . ($player_data->{lifetime_wrong_answers} > $player_data->{wrong_answers} ? " [$player_data->{lifetime_wrong_answers}]" : "") . "$color{red}, ";
  $score .= "current streak: $color{orange}$player_data->{wrong_streak}$color{red}, ";
  $score .= "$color{red}highest streak: $color{orange}$player_data->{highest_wrong_streak}" . ($player_data->{lifetime_highest_wrong_streak} > $player_data->{highest_wrong_streak} ? " [$player_data->{lifetime_highest_wrong_streak}]" : "") . "$color{red}, ";

  $score .= "$color{lightgreen}hints: $color{orange}$player_data->{hints}" . ($player_data->{lifetime_hints} > $player_data->{hints} ? " [$player_data->{lifetime_hints}]" : "") . "$color{reset}\n";

  print $score;
} elsif (lc $command eq 'reset') {
  $player_data->{correct_answers}      = 0;
  $player_data->{wrong_answers}        = 0;
  $player_data->{correct_streak}       = 0;
  $player_data->{wrong_streak}         = 0;
  $player_data->{highest_correct_streak} = 0;
  $player_data->{highest_wrong_streak} = 0;
  $player_data->{hints}                = 0;
  $scores->update_player_data($player_id, $player_data);
  print "Your scores for this session have been reset.\n";
}

END:
$scores->end;
