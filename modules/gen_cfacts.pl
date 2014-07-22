#!/bin/env perl

# quick and dirty

use warnings;
use strict;

my $STD = 'n1570-cfact.txt';

my $text;
{
  local $/ = undef;
  open my $fh, "<", $STD or die "Could not open $STD: $!";
  $text = <$fh>;
  close $fh;
}

my $cfact_regex = qr/
                      (
                        A(n)?\s+[^.]+is[^.]+\.
                       |\.\s+[^.]+shall[^.]+\.
                       |If[^.]+\.
                       |\.\s+[^.]+is\s+known[^.]+\.
                       |\.\s+[^.]+is\s+called[^.]+\.
                      )
                    /msx;

my @sections;
while ($text =~ /^\s{4}([A-Z\d]+\.[0-9\.]* +.*?)\r\n/mg) {
  unshift @sections, [pos $text, $1];
}

while ($text =~ /$cfact_regex/gms) {
  my $fact = $1;
  next unless length $fact;

  $fact =~ s/[\n\r]/ /g;
  $fact =~ s/ +/ /g;
  $fact =~ s/^\.\s*//;
  $fact =~ s/^\s*--\s*//;
  $fact =~ s/^\d+\s*//;
  $fact =~ s/- ([a-z])/-$1/g;
  $fact =~ s/\s+\././g;

  my $section = '';
  foreach my $s (@sections) {
    if (pos $text >= $s->[0]) {
      $section = "[$s->[1]] ";
      last;
    }
  }

  next if length "$section$fact" > 400;

  print "$section$fact\n";
}
