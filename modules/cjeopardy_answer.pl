#!/usr/bin/env perl

use warnings;
use strict;

use Text::Levenshtein qw(fastdistance);
use Time::HiRes qw(gettimeofday);

my $CJEOPARDY_DATA = 'cjeopardy.dat';
my $CJEOPARDY_HINT = 'cjeopardy.hint';
my $CJEOPARDY_LAST_ANSWER = 'cjeopardy.last_ans';

my $hint_only_mode = 0;

my $channel = shift @ARGV;
my $nick = shift @ARGV;
my $text = join(' ', @ARGV);

sub encode { my $str = shift; $str =~ s/\\(.)/{sprintf "\\%03d", ord($1)}/ge; return $str; }
sub decode { my $str = shift; $str =~ s/\\(\d{3})/{"\\" . chr($1)}/ge; return $str }

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel.\n";
  exit;
}

$text =~ s/^\s*is\s+//i;
$text =~ s/^\s*are\s+//i;
$text =~ s/^(a|an)\s+//i;
$text =~ s/\s*\?*$//;
$text =~ s/^\s+//;
$text =~ s/\s+$//;
my $lctext = lc $text;

if (not length $lctext) {
  print "What?\n";
  exit;
}

my @data;

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
          print "Er, you already correctly answered that question.\n";
        } else {
          print "Too slow! $last_nick got the correct answer.\n";
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

my @valid_answers = map { decode $_ } split /\|/, encode $data[1];

foreach my $answer (@valid_answers) {
  chomp $answer;
  $answer =~ s/\\\|/|/g;

  my $supplemental_text;
  if ($answer =~ s/\s*{(.*)}\s*$//) {
    $supplemental_text = $1;
  }

  my $distance = fastdistance($lctext, lc $answer);
  my $length = (length($lctext) > length($answer)) ? length $lctext : length $answer;

  if ($distance / $length < 0.15) {
    if ($distance == 0) {
      print "'$answer' is correct!";
    } else {
      print "'$text' is close enough to '$answer'. You are correct!"
    }

    if (defined $supplemental_text) {
      print " $supplemental_text\n";
    } else {
      print "\n";
    }

    unlink "$CJEOPARDY_DATA-$channel";
    unlink "$CJEOPARDY_HINT-$channel";

    open $fh, ">", "$CJEOPARDY_LAST_ANSWER-$channel" or die "Couldn't open $CJEOPARDY_LAST_ANSWER-$channel: $!";
    my $time = scalar gettimeofday;
    print $fh "$nick\n$data[1]$time\n";
    close $fh;

    if ($channel eq '#cjeopardy') {
      my $question = `./cjeopardy.pl $channel`;
      
      if ($hint_only_mode) {
        my $hint = `./cjeopardy_hint.pl $channel`;
        $hint =~ s/^Hint: //;
        print "Next hint: $hint\n";
      } else {
        print "Next question: $question\n";
      }
    }
    exit;
  }
}

print "Sorry, '$text' is incorrect.\n";
