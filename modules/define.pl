#!/usr/bin/perl -w -I /home/msmud/lib/lib/perl5/site_perl/5.10.0/

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# quick and dirty by :pragma

use LWP::Simple;

my ($defint, $phrase, $text, $entry, $entries, $i);

if ($#ARGV < 0)
{
  print "What phrase would you like to define?\n";
  die;
}

$phrase = join("%20", @ARGV);

$entry = 1;

if ($phrase =~ m/([0-9]+)%20(.*)/)
{
  $entry = $1;
  $phrase = $2;
}

$text = get("http://dictionary.reference.com/browse/$phrase");

$phrase =~ s/\%20/ /g;

if ($text =~ m/no dictionary results/i)
{
  print "No entry found for '$phrase'. ";


  if ($text =~ m/Did you mean <a class.*?>(.*?)<\/a>/g)
  {
    print "Did you mean '$1'?  Alternate suggestions: ";

    $i = 90;
    $comma = "";
    while ($text =~ m/<div id="spellSuggestWrapper"><li .*?><a href=.*?>(.*?)<\/a>/g && $i > 0)
    {
      print "$comma$1";
      $i--;
      $comma = ", ";
    }
  }

#  if ($text =~ m/Encyclopedia suggestions:/g)
#  {
#    print "Suggestions: ";
#
#    $i = 30;
#    while ($text =~ m/<a href=".*?\/search\?r=13&amp;q=.*?>(.*?)<\/a>/g
# && $i > 0)
#    {
#      print "$1, ";
#      $i--;
#    }
#  }

  print "\n";
  exit 0;
}

if ($text =~ m/- (.*?) dictionary result/g)
{
  $entries = $1;
}

$entries = 1 if (not defined $entries);

if ($entry > $entries)
{
  print "No entry found for $phrase.\n";
  exit 0;
}

print "$phrase: ";

$i = $entry;

$defint = "";

my $quote = chr(226) . chr(128) . chr(156);
my $quote2 = chr(226) . chr(128) . chr(157);
my $dash = chr(226) . chr(128) . chr(147);

while ($i <= $entries)
{
  if ($text =~ m/<td>(.*?)<\/td>/gs)
  {
    $defint = $1;
  }

  # and now for some fugly beautifying regexps...

  $defint =~ s/$quote/"/g;
  $defint =~ s/$quote2/"/g;
  $defint =~ s/$dash/-/g;
  $defint =~ s/<b>Pronun.*?<BR>//gsi;
  $defint =~ s/<.*?>//gsi;
  $defint =~ s/\&nbsp\;/ /gi;
  $defint =~ s/\&.*?\;//g;
  $defint =~ s/\r\n//gs;
  $defint =~ s/\( P \)//gs;
  $defint =~ s/\s+/ /gs;

  if ($defint =~ /interfaceflash/) {
    $i++;
    next;
  }

  $i++ and next if $defint eq " ";

  print "$i) $defint ";

  $i++;
}

print "\n";
