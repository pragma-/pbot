#!/usr/bin/perl -w -I /home/msmud/lib/lib/perl5/site_perl/5.10.0/

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# quick and dirty by :pragma

use Games::Dice qw/roll roll_array/;

my ($result, $rolls, $show);

if ($#ARGV <0)
{
  print "Usage: roll [-show] <dice roll>; e.g.: roll 3d6+1. To see all individual dice rolls, add -show.\n";
  die;
}

$rolls = join("", @ARGV);

if($rolls =~ s/\s*-show\s*//) {
  $show = 1;
}

if($rolls =~ m/^\s*(\d+)d\d+(?:\+?-?\d+)?\s*$/) {
  if($1 > 100) {
    print "Sorry, maximum of 100 rolls.\n";
    die;
  }
} else {
  print "Usage: roll [-show] <dice roll>; e.g.: roll 3d6+1. To see all individual dice rolls, add -show.\n";
  die;
}

if($show) {
  my @results = roll_array $rolls;
  $result = 0;
  foreach my $n (@results) {
    $result += $n;
  }
  print "/me rolled $rolls for @results totaling $result.\n";
} else {
  $result = roll $rolls;
  print "/me rolled $rolls for $result.\n";
}
