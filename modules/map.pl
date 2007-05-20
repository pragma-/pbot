#!/usr/bin/perl

use strict;
use LWP::Simple;

my ($text, $buffer, $location);

if($#ARGV < 0)
{
  print "Try again. Please specify the location you would like to search for nearby cities around.\n";
  die;
}
  
$location = join("+", @ARGV);

$location =~ s/,/%2C/;

if($location =~ m/\+-(.*)/)
{
  # -arguments?
  $location =~ s/\+-.*//;
}

$text = get("http://weather.yahoo.com/search/weather2?p=$location");

$location =~ s/\+/ /g;
$location =~ s/%2C/,/g;

if($text =~ m/No match found/)
{
  print "$location is not a valid location for this service.\n"; 
  die;
}

my $found = 0;
my $buf;
my $i;

if($text =~ m/location matches\:/g)
{
  $buf = "Multiple locations found: ";

  while($text =~ m/<a\shref="\/forecast\/(.*?)">(.*?)<\/a>/g)
  {
    $i = $1;
    $buffer = $2;

    $buffer =~ s/<b>//g;
    $buffer =~ s/<\/b>//g;
    $buffer =~ s/^\s+//;

    $buf = $buf . "$buffer - "; 

    if($location =~ m/$buffer/i)
    {
      $text = get("http://weather.yahoo.com/forecast/$i");
      $found = 1;
    }
  }
  $buf = $buf. "please specify one of these.\n";
  if (not $found)
  {
    print $buf;
    die;
  }
}

  my ($country, $state, $city);

  $text =~ m/<a href="\/">Weather<\/a>\s>/g;
  $text =~ m/<a href=.*?>(.*?)<\/a>\s>/g;
  $country = $1;

  if($country eq "North America")
  {
    $text =~ m/<a href=.*?>(.*?)<\/a>\s>/g;
    $country = $1;
  }

  if($country ne "Canada")
  {
    $text =~ m/<a href=.*?>(.*?)<\/a>\s>/g;
    $state = $1;
  }

  $text =~ m/^(.*?)<\/b><\/font>/mg;
  $city = $1;

  $text =~ m/Nearby.*?Locations/sgi;

  print "$country, $state, $city - Nearby Locations: ";

  while($text =~ m/<a href=\"\/forecast\/.*?\.html\">(.*?)<\/a>/gi)
  {
    $buf = $1;
    $buf =~ s/<.*?>//gi;
    print "$buf, ";
  }
  print "\n";
