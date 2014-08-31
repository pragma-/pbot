#!/usr/bin/env perl

use warnings;
use strict;

use Time::HiRes qw/gettimeofday/;
use Time::Duration qw/duration/;

my $CJEOPARDY_DATA = 'cjeopardy.dat';
my $CJEOPARDY_HINT = 'cjeopardy.hint';

my @hints = (0.90, 0.75, 0.50, 0.25, 0.10);
my $timeout = 60;

my $channel = shift @ARGV;

sub encode { my $str = shift; $str =~ s/\\(.)/{sprintf "\\%03d", ord($1)}/ge; return $str; }
sub decode { my $str = shift; $str =~ s/\\(\d{3})/{"\\" . chr($1)}/ge; return $str }

if ($channel !~ /^#/) {
  print "Sorry, C Jeopardy must be played in a channel. Feel free to join #cjeopardy.\n";
  exit;
}

my @data;
open my $fh, "<", "$CJEOPARDY_DATA-$channel" or print "There is no open C Jeopardy question.  Use `cjeopardy` to get a question.\n" and exit;
@data = <$fh>;
close $fh;

my @valid_answers = map { decode $_ } split /\|/, encode $data[1];

my ($hint, $length) = ('', 0);
foreach my $answer (@valid_answers) {
  chomp $answer;
  $answer =~ s/\\\|/|/g;

  my $supplemental_text;
  if ($answer =~ s/\s*{(.*)}\s*$//) {
    $supplemental_text = $1;
  }

  if (length $answer > $length) {
    $length = length $answer;
    $hint = $answer;
  }
}

my ($hint_counter, $last_timeout);
my $ret = open $fh, "<", "$CJEOPARDY_HINT-$channel";
if (defined $ret) {
  $hint_counter = <$fh>;
  $last_timeout = <$fh>;
  close $fh;
}

$last_timeout = 0 if not defined $last_timeout;

my $duration = scalar gettimeofday - $last_timeout;
if ($duration < $timeout) {
  $duration = duration($timeout - $duration);
  unless ($duration eq 'just now') {
    print "Please wait $duration before requesting another hint.\n";
    exit;
  }
}

$hint_counter++;

open $fh, ">", "$CJEOPARDY_HINT-$channel" or die "Couldn't open $CJEOPARDY_HINT-$channel: $!";
print $fh "$hint_counter\n";
print $fh scalar gettimeofday, "\n";
close $fh;

my $hidden_character_count = int length ($hint) * $hints[$hint_counter > $#hints ? $#hints : $hint_counter];
my $spaces = () = $hint =~ / /g;
my $dashes = () = $hint =~ /-/g;
my $underscores = () = $hint =~ /_/g;

my @indices;
while (@indices <= $hidden_character_count - $spaces - $dashes - $underscores) {
  my $index = int rand($length);
  my $char = substr($hint, $index, 1);
  next if $char eq ' ';
  next if $char eq '-';
  next if $char eq '_';
  next if grep { $index eq $_ } @indices;
  push @indices, $index; 
}

foreach my $index (@indices) {
  substr $hint, $index, 1, '.';
}

print "Hint: $hint\n";
