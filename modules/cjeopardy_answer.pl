#!/usr/bin/env perl

use warnings;
use strict;

use Text::Levenshtein qw(fastdistance);

my $CJEOPARDY_DATA = 'cjeopardy.dat';
my $CJEOPARDY_SQL  = 'cjeopardy.sqlite3';

my $channel = shift @ARGV;
my $text = join(' ', @ARGV);

sub encode { my $str = shift; $str =~ s/\\(.)/{sprintf "\\%03d", ord($1)}/ge; return $str; }
sub decode { my $str = shift; $str =~ s/\\(\d{3})/{"\\" . chr($1)}/ge; return $str }

if (not length $text) {
  print "Say 'what' one more time!\n";
  exit;
}

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel.\n";
  exit;
}

$text = lc $text;
$text =~ s/^\s*is\s*//;
$text =~ s/^\s*are\s*//;
$text =~ s/^(a|an)\s+//;
$text =~ s/\?*$//;

my @data;
open my $fh, "<", "$CJEOPARDY_DATA-$channel" or print "There is no open C Jeopardy question.  Use `cjeopardy` to get a question.\n" and exit;
@data = <$fh>;
close $fh;

my @valid_answers = map { lc decode $_ } split /\|/, encode $data[0];

foreach my $answer (@valid_answers) {
  chomp $answer;
  $answer =~ s/\\\|/|/g;

  my $distance = fastdistance($text, $answer);
  my $length = (length($text) > length($answer)) ? length $text : length $answer;

  if ($distance / $length <= 0.25) {
    my $correctness;
    if ($distance == 0) {
      $correctness = "correct!";
    } else {
      $correctness = "close enough to '$answer'. You are correct!"
    }

    print "'$text' is $correctness\n";
    unlink "$CJEOPARDY_DATA-$channel";

    if ($channel eq '#cjeopardy') {
      my $question = `./cjeopardy.pl $channel`;
      print "Next question: $question\n";
    }
    exit;
  }
}

print "Sorry, '$text' is incorrect.\n";
