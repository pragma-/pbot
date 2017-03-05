#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

my $CFACTS = 'cfacts.txt';
my $CJEOPARDY_DATA = 'cjeopardy.dat';

my $text = join(' ', @ARGV);

sub encode { my $str = shift; $str =~ s/\\(.)/{sprintf "\\%03d", ord($1)}/ge; return $str; }
sub decode { my $str = shift; $str =~ s/\\(\d{3})/{"\\" . chr($1)}/ge; return $str }

my $jeopardy_answers;
open my $fh, "<", $CJEOPARDY_DATA;
if (defined $fh) {
  $jeopardy_answers = <$fh>;
  close $fh;
}

my @valid_answers = map { lc decode $_ } split /\|/, encode $jeopardy_answers;

my @facts;
open $fh, "<", $CFACTS or die "Could not open $CFACTS: $!";
while (my $fact = <$fh>) {
  next if length $text and $fact !~ /\Q$text\E/i;
  next if grep { $fact =~ /\Q$_\E/i } @valid_answers;
  push @facts, $fact;
}
close $fh;

if (not @facts) {
  print "No fact containing text $text found.\n";
} else {
  print $facts[int rand(@facts)], "\n";
}
