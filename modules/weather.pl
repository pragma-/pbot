#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use LWP::Simple;

my ($text, $weather, $location, $date, $i, $day, @days);

if ($#ARGV < 0)
{
  print "Try again. Please specify the location you would like weather for.\n";
  die;
}

$location = join("+", @ARGV);

$location =~ s/,/%2C/;

if ($location =~ m/\+-(.*)/)
{
  $date = $1;
  $location =~ s/\+-.*//;
}

$i = 0;

$text = get("http://weather.yahoo.com/search/weather2?p=$location");

$location =~ s/\+/ /g;
$location =~ s/%2C/,/g;

if ($text =~ m/No match found/)
{
  print "$location is not a valid location for this service.\n";
  die;
}

my $found = 0;
my $buf;


if ($text =~ m/location matches\:/g)
{
  $buf = "Multiple locations found: ";

  while ($text =~ m/<a\shref="\/forecast\/(.*?)">(.*?)<\/a>/g)
  {
    $i = $1;
    $weather = $2;

    $weather =~ s/<b>//g;
    $weather =~ s/<\/b>//g;
    $weather =~ s/^\s+//;

    $buf = $buf . "$weather - ";

    if ($location =~ m/$weather/i)
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

  my ($update, $temp, $high, $low, $tempc, $highc, $lowc, $cond,
      $today, $tonight, $country, $state, $city, $humid, $wind,
      $sunup, $sundown, $feels, $feelsc);

  $text =~ m/<a href="\/">Weather<\/a>\s>/g;
  $text =~ m/<a href=.*?>(.*?)<\/a>\s>/g;
  $country = $1;

  if ($country eq "North America")
  {
    $text =~ m/<a href=.*?>(.*?)<\/a>\s>/g;
    $country = $1;
  }

  if ($country ne "Canada")
  {
    $text =~ m/<a href=.*?>(.*?)<\/a>\s>/g;
    $state = $1;
  }

  $text =~ m/^(.*?)<\/b><\/font>/mg;
  $city = $1;

  $update = $1
    if $text =~ m/at:\s(.*?)<\/font><\/td>/gi;


  while ($text =~
m/<td\swidth\=\".*?align\=center\scolspan\=.*?\sface\=.*?\s.*?<b>(.*?)<\/b>/g)
  {
    push(@days, $1);
  }

  foreach $day (@days)
  {
    if ($date =~ m/$day/i)
    {
      $date = $i;
      last;
    }
    $i = $i + 1;
  }

  if ($i > 4 && $date ne "")
  {
    print("\'$date\' is not a valid day, valid days for $country, $state, $city are: ",
          join(" ", @days[1,2,3,4]), "\n");
    die;
  }

  $text =~ m/Currently:/g;
  $temp = $1
  if ($text =~ m/<b>(.*?)&deg/g);

  if ($date == 0)
  {
    $text =~ m/Arial\ssize=2>(.*?)</g;
    $cond = $1
  }
  else
  {
    for($i = 0; $i <= $date; $i++)
    {
      $text =~ m/<td\salign.*?\scolspan.*?size=2>(.*?)&/mgi;
      $cond = $1;
    }
  }

  if ($cond eq "Unknown")
  {
    for($i = 0; $i <= $date; $i++)
    {
      $text =~ m/<td\salign.*?\scolspan.*?size=2>(.*?)&/mgi;
      $cond = $1;
    }
  }

  for($i = 0; $i <= $date; $i++)
  {
    $text =~
m/<td\salign=right\scolspan=1.*?face=Arial>High\:.*?size=3\sface=Arial>\n\s\s(.*?)\&/sgi;
    $high = $1;
  }

  for($i = 0; $i <= $date; $i++)
  {
    $text =~
m/<td\salign=right\scolspan=1.*?face=Arial>Low\:.*?size=3\sface=Arial>\n\s(.*?)\&/sgi;
    $low = $1;
  }

  if ($text =~ m/More Current Conditions<\/b>/g)
  {

  $text =~ m/Feels Like:/g;
  $feels = $1
  if ($text =~ m/size=2>\n(.*?)&deg/sg);

  $text =~ m/Wind:/g;
  $wind = $1
  if ($text =~ m/size=2>\n(.*?)</sg);

  $wind =~ s/\n//g;
  $wind =~ s/\r//g;

  $text =~ m/Humidity:/g;
  $humid = $1
  if ($text =~ m/size=2>\n(.*?)\n/sg);

  $text =~ m/Sunrise:/g;
  $sunup = $1
  if ($text =~ m/size=2>\n(.*?)</sg);

  $text =~ m/Sunset:/g;
  $sundown = $1
  if ($text =~ m/size=2>\n(.*?)</sg);
  }

  $today = "Today: $1"
    if $text =~ m/<b>Today:<\/b>\s(.*?)<p>/g;

  $tonight = "Tonight: $1"
    if $text =~ m/<b>Tonight:<\/b>\s(.*?)<p>/g;

  $feelsc = int(5/9*($feels - 32));
  $tempc = int(5/9*($temp - 32));
  $highc = int(5/9*($high - 32));
  $lowc  = int(5/9*($low - 32));

  if ($date > 0)
  {
    $date = "[".$days[$date]."] ";
  }

  $date =~ s/Mon/Monday/i;
  $date =~ s/Tue/Tuesday/i;
  $date =~ s/Wed/Wednesday/i;
  $date =~ s/Thu/Thursday/i;
  $date =~ s/Fri/Friday/i;
  $date =~ s/Sat/Saturday/i;
  $date =~ s/Sun/Sunday/i;


  if ($date eq "")
  {
  print "$country, $state, $city (Updated $update): Temp: ".$temp."F/".$tempc."C (Feels like: $feels"."F/".$feelsc."C), ".
        "High: ".$high."F/".$highc."C, Low: ".$low."F/".$lowc."C, ".
        "Sky: $cond, Humidity: $humid, Wind: $wind, Sunrise: $sunup, Sunset: $sundown, $today $tonight\n";
  }
  else
  {
  print "$country, $state, $city (Updated $update): $date".
        "High: ".$high."F/".$highc."C, Low: ".$low."F/".$lowc."C, ".
        "Sky: $cond.\n";
  }
