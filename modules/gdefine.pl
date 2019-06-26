#!/usr/bin/perl -w -I /home/msmud/lib/lib/perl5/site_perl/5.10.0/

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# quick and dirty by :pragma

use strict;
use LWP::UserAgent;

my ($defint, $phrase, $text, $entry, $entries, $i);
my @defs;

if ($#ARGV < 0)
{
  print "What phrase would you like to define?\n";
  die;
}

$phrase = join("+", @ARGV);

$entry = 1;

if ($phrase =~ m/([0-9]+)\+(.*)/)
{
  $entry = $1;
  $phrase = $2;
}

my $ua = LWP::UserAgent->new;
$ua->agent("howdy");
my $response = $ua->get("http://www.google.com/search?q=define:$phrase");
$phrase =~ s/\+/ /g;

if (not $response->is_success) {
        exit(1);
}

$text = $response->content;
if ($text =~ m/No definitions were found/i)
{
  print "No entry found for '$phrase'. ";
  print "\n";
  exit 1;
}

print "$phrase: ";

$i = $entry;

while ($i <= $entry + 5)
{
  if ($text =~ m/<li>(.*?)<br>/gs)
  {
    push @defs, $1;
  }
  $i++;
}

my %uniq = map { $_ => 1 } @defs;
@defs = keys %uniq;

my $comma = "";

for($i = 1; $i <= $#defs + 1; $i++) {

# and now for some fugly beautifying regexps...

  my $quote = chr(226) . chr(128) . chr(156);
  my $quote2 = chr(226) . chr(128) . chr(157);
  my $dash = chr(226) . chr(128) . chr(147);

  $_ = $defs[$i-1];

  s/$quote/"/g;
  s/$quote2/"/g;
  s/$dash/-/g;
  s/<b>Pronun.*?<BR>//gsi;
  s/<.*?>//gsi;
  s/\&nbsp\;/ /gi;
  s/\&.*?\;//g;
  s/\r\n//gs;
  s/\( P \)//gs;
  s/\s+/ /gs;

  print "$i) $_$comma";
  $comma = ", ";
}
