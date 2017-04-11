#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
    return -1 if $input =~ m/forever/i;
    $input .= ' seconds' if $input =~ m/^\s*\d+\s*$/;

    my $parse = Time::ParseDate::parsedate($input, NOW => $now);

    if (not defined $parse) {
      $input =~ s/\s+$//;
      return (0, "I don't know what '$input' means. I expected a time duration like '5 minutes' or '24 hours' or 'next tuesday'.\n");
    } else {
      $seconds += $parse - $now;
    }
  }

  return $seconds;
}

1;
