#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Data::Dumper;
use Time::HiRes qw(gettimeofday);
use Text::Fuzzy;

open my $handle, '<questions' or die $@;
chomp(my @lines = <$handle>); close $handle;

my %remove;

my $max_distance = 2;

print STDERR "Fixing up questions...\n";

my @lc;
for my $i (0 .. $#lines) {
  # normalize blanks
	$lines[$i] =~ s/(---+|__+|\.\.\.\.+)/_____/g;

  # fix stupid shit
  $lines[$i] =~ s/\s*(?:category|potpourri)\s*:\s*//gi;
  $lines[$i] =~ s/^Useless Trivia: What word means/Definitions: What word means/i;
  $lines[$i] =~ s/^useless triv \d+/Useless Trivia/i;
  $lines[$i] =~ s/^general\s*(?:knowledge)?\s*\p{PosixPunct}\s*//i;
  $lines[$i] =~ s/^(?:\(|\[)(.*?)(?:\)|\])\s*/$1: /;
  $lines[$i] =~ s/star\s?wars/Star Wars/ig;
  $lines[$i] =~ s/\s+/ /g;
  $lines[$i] =~ s/(\w:)(\w)/$1 $2/g;
  $lines[$i] =~ s/^sport\s*[:-]\s*(.*?)\s*[:-]/$1: /i;
  $lines[$i] =~ s/^trivia\s*[:;-]\s*//i;
  $lines[$i] =~ s/^triv\s*[:;-]\s*//i;

  my @stuff = split /`/, $lines[$i];

  if (@stuff != 2) {
    print STDERR "Removing, doesn't have 2 stuffs: $i: $lines[$i]\n";
    $remove{$i} = 1;
  }

  if (not length $stuff[1]) {
    print STDERR "Removing, doesn't have answer: $i: $lines[$i]\n";
    $remove{$i} = 1;
  }

  if ($stuff[0] !~ m/ /) {
    print STDERR "Removing, doesn't have spaces: $i: $lines[$i]\n";
    $remove{$i} = 1;
  }

  # normalize differences
  $lc[$i] = lc $lines[$i];
  $lc[$i] =~ s/^(.{3,30}?)\s*[:;-]//;
  $lc[$i] =~ s/\p{PosixPunct}//g;
}

print STDERR "Removing duplicates...\n";

for my $i (0 .. $#lines) {
  print STDERR "$i\n" if $i % 50 == 0;
  next if exists $remove{$i};

  my $tf = Text::Fuzzy->new($lc[$i]);
  $tf->set_max_distance($max_distance);

  my $length_a = length $lines[$i];

  for my $j ($i .. $#lines) {
    next if $i == $j;
    next if exists $remove{$j};

    my $distance = $tf->distance($lc[$j]);

    next if $distance > $max_distance;

    print STDERR "distance: $distance for\n\t$lines[$i] ($i)\n\t$lines[$j] ($j)\n";

    my $length_b = length $lines[$j];

    if ($length_a > $length_b) {
      $remove{$j} = 1;
      print STDERR "keeping $lines[$i] ($i)\n";
    } else {
      $remove{$i} = 1;
      print STDERR "keeping $lines[$j] ($j)\n";
    }
  }
}

for my $i (0 .. $#lines) {
  next if exists $remove{$i};
  print "$lines[$i]\n";
}
