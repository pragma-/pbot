#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;
use HTML::DOM;
use HTML::Entities;
use JSON;

my $questions = { questions => [] };

my $debug = 0;
my $kill_id = 9999999;
#$kill_id = 10;

my @files = glob '*game*.html';

my $id = 0;

foreach my $file (@files) {
  print "Processing $file...\n";

  my $text;

  {
    open my $fh, '<', $file or die "Couldn't open $file: $!";
    local $/ = undef;
    $text = <$fh>;
    close $fh;
  }

  my $doc = HTML::DOM->new;
  $doc->write($text);

  my @rounds = $doc->getElementsByClassName('round');
  my $round_nr = 0;

  foreach my $round (@rounds) {
    $round_nr++;
    print "  Round $round_nr!\n";

    my ($category, $question, $answer);

    my @categories = $round->getElementsByClassName('category_name');
    my @clues = $round->getElementsByClassName('clue');

    foreach my $clue (@clues) {
      my $div = $clue->getElementsByTagName('div');

      if (not defined $div->[0]) {
        print "No div!\n";
        next;
      }

      my $mouseover = $div->[0]->{onmouseover};
      my $mouseout = $div->[0]->{onmouseout};

      my $clue_values = $div->[0]->getElementsByClassName('clue_value');

      if (not defined $clue_values->[0]) {
        $clue_values = $div->[0]->getElementsByClassName('clue_value_daily_double');
      }

      if (not defined $clue_values->[0]) {
        print "No clue value.\n";
        die;
      }

      my $clue_value = $clue_values->[0]->innerHTML;

      if ($debug) {
        print "    mouseover: $mouseover\n";
        print "    mouseout: $mouseout\n";
        print "    clue value: $clue_value\n";
      }

      my ($col, $row);
      if ($mouseover =~ m/J_(\d+)_(\d+)/) {
        $col = $1;
        $row = $2;
      } else {
        print "Failed to find col, row\n";
        print "    mouseover: $mouseover\n";
        print "    mouseout: $mouseout\n";
        die;
      }

      if ($mouseover =~ m{<em class="correct_response">(.*?)</em>}) {
        $answer = $1;
      } else {
        print "Failed to find answer.\n";
        print "    mouseover: $mouseover\n";
        print "    mouseout: $mouseout\n";
        die;
      }

      if ($mouseout =~ m/toggle\('clue[^']+', '[^']+', '(.*?)'\)$/) {
        $question = $1;
      } else {
        print "Failed to find question.\n";
        print "    mouseover: $mouseover\n";
        print "    mouseout: $mouseout\n";
        die;
      }

      print "row: $row, col: $col\n";

      $category = $categories[$col - 1]->innerHTML;

      $category =~ s/\\'/'/g;
      $question =~ s/\\'/'/g;
      $answer =~ s/\\'/'/g;

      next if $category =~ m/<a href/;
      next if $question =~ m/<a href/;
      next if $answer =~ m/<a href/;

      $category =~ s/<[^>]*>//gs;
      $question =~ s/<[^>]*>//gs;
      $answer =~ s/<[^>]*>//gs;

      $category = decode_entities $category;
      $question = decode_entities $question;
      $answer = decode_entities $answer;

      $answer =~ s/\(.*?\)//g;

      $category =~ s/^\s+|\s+$//g;
      $question =~ s/^\s+|\s+$//g;
      $answer =~ s/^\s+|\s+$//g;

      if ($clue_value =~ m/(\d+,?\d+)$/) {
        $clue_value = $1;
      } elsif ($clue_value =~ m/(\d+)$/) {
        $clue_value = $1;
      }

      $clue_value =~ s/,//g;

      if (not $clue_value) {
        print "Bad clue value.\n";
        die;
      }

      print "$id: [$category] $question ($answer) $clue_value\n";

      my @alternates = split / or |\//i, $answer;
      my $answer = shift @alternates;

      if (@alternates) {
        print "Has alternates: [$answer] ", join (', ', @alternates), "\n";
      }

      # "numify" values for JSON
      $id += 0;
      $clue_value += 0;

      my $new_question = {
        alternativeSpellings => \@alternates,
        suggestions => [],
        question => $question,
        id => ++$id,
        answer => $answer,
        category => $category,
        last_seen => 0,
        value => $clue_value
      };

      push @{$questions->{questions}}, $new_question;
    }
  }
  last if $id >= $kill_id;
}

my $json = encode_json $questions;
open my $fh, '>', 'jeopardy.json';
print $fh "$json\n";
close $fh;
