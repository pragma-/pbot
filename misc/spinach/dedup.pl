#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Data::Dumper;
use Time::HiRes qw(gettimeofday);
use Text::Fuzzy;

open my $handle, '<questions' or die $@;
chomp(my @lines = <$handle>); close $handle;

my @lc;
# Normalize blanks
for my $i (0 .. $#lines) {
	$lines[$i] =~ s/(---+|__+|\.\.\.\.+)/_____/g;
  $lc[$i] = lc $lines[$i];
  $lc[$i] =~ s/^(.*): //
}

my $max_distance = 4;

my %remove;

for my $i (0 .. $#lines) {
  print STDERR "$i\n";
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
