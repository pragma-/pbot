#!/usr/bin/perl

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
my $result  = $engine->search($arguments);

print "$nick: ";

print '(', $result->formattedTotalResults, " results)\n";

if (not @{$result->items}) {
  print "No results found\n";
  exit;
}

my $comma = "";
foreach my $item (@{$result->items}) {
  print $comma, decode_entities $item->title, ': <', $item->link, ">\n";
  $comma = " -- ";
  last if --$matches <= 0;
}

print "\n";
