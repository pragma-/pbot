#!/usr/bin/env perl

use warnings;
use strict;

use Text::Levenshtein qw(fastdistance);

my $CJEOPARDY_DATA = 'cjeopardy.dat';
my $CJEOPARDY_HINT = 'cjeopardy.hint';

my $channel = shift @ARGV;
my $text = join(' ', @ARGV);

sub encode { my $str = shift; $str =~ s/\\(.)/{sprintf "\\%03d", ord($1)}/ge; return $str; }
sub decode { my $str = shift; $str =~ s/\\(\d{3})/{"\\" . chr($1)}/ge; return $str }

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel.\n";
  exit;
}

$text = lc $text;
$text =~ s/^\s*is\s*//;
$text =~ s/^\s*are\s*//;
$text =~ s/^(a|an)\s+//;
$text =~ s/\s*\?*$//;
$text =~ s/^\s+//;
$text =~ s/\s+$//;

if (not length $text) {
  print "What?\n";
  exit;
}

my @data;
open my $fh, "<", "$CJEOPARDY_DATA-$channel" or print "There is no open C Jeopardy question.  Use `cjeopardy` to get a question.\n" and exit;
@data = <$fh>;
close $fh;

my @valid_answers = map { decode $_ } split /\|/, encode $data[1];

foreach my $answer (@valid_answers) {
  chomp $answer;
  $answer =~ s/\\\|/|/g;

  my $distance = fastdistance($text, lc $answer);
  my $length = (length($text) > length($answer)) ? length $text : length $answer;

  if ($distance / $length < 0.15) {
    my $correctness;
    if ($distance == 0) {
      $correctness = "correct!";
    } else {
      $correctness = "close enough to '$answer'. You are correct!"
    }

    print "'$answer' is $correctness\n";
    unlink "$CJEOPARDY_DATA-$channel";
    unlink "$CJEOPARDY_HINT-$channel";

    if ($channel eq '#cjeopardy') {
      my $question = `./cjeopardy.pl $channel`;
      print "Next question: $question\n";
    }
    exit;
  }
}

print "Sorry, '$text' is incorrect.\n";
