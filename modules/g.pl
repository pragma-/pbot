#!/usr/bin/perl

# Quick and dirty by :pragma

use warnings;
use strict;

use Google::Search;
use HTML::Entities;

my ($nick, $arguments, $matches);

$matches = 3;
$nick = shift @ARGV;

if ($#ARGV < 0)
{
  print "Usage: google [number of results] query\n";
  die;
}

$arguments = join(" ", @ARGV);

if($arguments =~ m/^([0-9]+)/)
{
  $matches = $1;
  $arguments =~ s/^$1//;
}

my $search = Google::Search->Web(query => $arguments, referrer => 'http://blackshell.com');

print "$nick: ";

if(not $search->first) {
  if($search->error) {
    print $search->error->reason, "\n";
  } else {
    print "No results found\n";
  }
    exit;
}

my $comma = "";
while( my $result = $search->next) {
    print $comma, decode_entities $result->titleNoFormatting, ": ", $result->uri;
    $comma = " -- ";
    last if --$matches <= 0;
}

print "\n";
