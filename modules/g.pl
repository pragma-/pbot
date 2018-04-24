#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

use WWW::Google::CustomSearch;
use HTML::Entities;

my $api_key = '';
my $cx      = '';

my ($nick, $arguments, $matches);

$matches = 3;
$nick = shift @ARGV;

if ($#ARGV < 0) {
  print "Usage: google [number of results] query\n";
  exit;
}

$arguments = join ' ', @ARGV;

if($arguments =~ s/^([0-9]+)//) {
  $matches = $1;
}

my $engine  = WWW::Google::CustomSearch->new(api_key => $api_key, cx => $cx, quotaUser => $nick);

print "$nick: ";

if ($arguments =~ m/(.*)\svs\s(.*)/i) {
  my ($a, $b) = ($1, $2);
  my $result1 = $engine->search("\"$a\" -\"$b\"");
  my $result2 = $engine->search("\"$b\" -\"$a\"");

  if (not defined $result1 or not defined $result1->items or not @{$result1->items}) {
    print "No results for $a\n";
    exit;
  }

  if (not defined $result2 or not defined $result2->items or not @{$result2->items}) {
    print "No results for $b\n";
    exit;
  }

  print "$a: (", $result1->formattedTotalResults, ") ", decode_entities $result1->items->[0]->title, " <", $result1->items->[0]->link, "> VS $b: (", $result2->formattedTotalResults, ") ", decode_entities $result2->items->[0]->title, " <", $result2->items->[0]->link, ">\n";
  exit;
}

my $result  = $engine->search($arguments);

if (not defined $result or not defined $result->items or not @{$result->items}) {
  print "No results found\n";
  exit;
}

print '(', $result->formattedTotalResults, " results)\n";

my $comma = "";
foreach my $item (@{$result->items}) {
  print $comma, decode_entities $item->title, ': <', $item->link, ">\n";
  $comma = " -- ";
  last if --$matches <= 0;
}

print "\n";
