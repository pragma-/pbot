#!/usr/bin/env perl

use warnings;
use strict;

package PBot::Utils::ParseDate;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/parsedate/;

use Time::HiRes qw/gettimeofday/;

require Time::ParseDate;

sub parsedate {
  my $input = shift @_;
  my $now = gettimeofday;
  my @inputs = split /(?:,?\s+and\s+|\s*,\s*)/, $input;

  my $seconds = 0;
  foreach my $input (@inputs) {
    $input .= ' seconds' if $input =~ m/^\d+$/;
    my $parse = Time::ParseDate::parsedate($input, NOW => $now);

    if (not defined $parse) {
      return (0, "I don't know what '$input' means.\n");
    } else {
      $seconds += $parse - $now;
    }
  }

  return ($seconds, undef);
}

1;
