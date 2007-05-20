#!/usr/bin/perl -w

use strict;
use LWP::Simple;

my $html;

if($#ARGV < 0)
{
  print "Usage: !gtop15 country\n";
  exit 0;
}

my $country = join " ", @ARGV;

$country = lc $country;

$html = get("http://www.google.com/press/intl-zeitgeist.html");

defined $html or die "Oops, couldn't get the data.";

my %countries;

while($html =~ m/<a href="#(.*?)" class="style10">(.*?)<\/a>/g)
{
  $countries{$1} = $2;
}

my $found = 0;

if(not defined $countries{$country})
{
  foreach my $c (values %countries)
  {
    if(lc $c eq $country)
    {
      $found = 1;
      $country = $c;
      last;
    }
  }
}
else
{
  $found = 1;
}

if($found == 0)
{
  print "Unknown country, valid countries are ";
  foreach my $c (sort keys %countries)
  {
    print "$c,";
  }
  exit 0;
}

my %countries2;

if(length($country) == 2)
{
  %countries2 = %countries;
}
else
{
  %countries2 = reverse %countries;
}

print "Top 15 Google search queries ($countries2{$country}): ";

$country = $countries2{$country} if(length($country) == 2);

$html =~ m/<td colspan="3"\s*class="zeit_monthly_head">.*?<b>\s*$country\s*<\/b>/gms;

my $i = 15;
while($html =~ m/<a href=".*?"\s*class="zeit_link">\s*(.*?)\s*<\/a>(.*?)<\/li>/gms)
{
  my $result = $1;
  if(length $2)
  {
    $2 =~ m/<span\s*class="zeit_small_txt">\s*(.*?)<\/span>/;
    $result = $1;
  }
  else
  {
    $result=~s/[^\t -~]//g;

#    print "[[$1]]\n";
#    my $p = $1;
#    $result = "";
#    while($p =~ m/(.)/g)
#    {
#      print $1 . "[" . ord($1) . "]";
#      next;

#      if(ord($1) > 122)
#      {
#        $p =~ m/./g;
#        next;
#      }
#      next if(ord($1) < 97 && ord($1) > 122 && ord($1) < 65 && ord($1) > 90
#         && ord($1) < 48 && ord($1) > 57);
    
#      $result .= $1;
#    }
  }
  print "$result, ";
  last if(--$i == 0);
}
