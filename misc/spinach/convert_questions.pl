#!/usr/bin/perl

use warnings;
use strict;
use JSON;

my $file = 'cat_questions';
open my $fh, '<', $file or die "$file: $!";

my $q = { questions => [] };
my $id = 0;

foreach my $line (<$fh>) {
  chomp $line;
  print STDERR "<$line>\n";
  $id++;
  my ($category, $question, @answers) = split /`/, $line;
  my $answer = shift @answers;
  my $h = { category => $category, question => $question, answer => $answer, alternativeSpellings => \@answers, suggestions => [], id => $id };
  push @{$q->{questions}}, $h;
}

my $json = encode_json $q;
print "$json\n";
