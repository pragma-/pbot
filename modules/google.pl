#!/usr/bin/perl -w -I /home/msmud/lib/lib/perl5/site_perl/5.10.0/

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Quick and dirty by :pragma

use LWP::UserAgent;

my ($text, $arguments, $header, $footer, $t, $matches);

$header = "";
$footer = undef;
$matches = 1;

if ($#ARGV < 0)
{
  print "Usage: google [number of results] query\n";
  die;
}

$arguments = join("+", @ARGV);

if ($arguments =~ m/([0-9]+)\+/)
{
  $matches = $1;
  $arguments =~ s/$1//;
}

my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0");

my $response = $ua->get("http://www.google.com/search?q=$arguments");

if (not $response->is_success)
{
  print "Couldn't get google information.\n";
  die;
}

$text = $response->content;

$arguments =~ s/\+/ /g;

if ($text =~ m/No pages were found/)
{
  print "No results found for '$arguments'.\n";
  die;
}

if ($text =~ m/Results/g)
{
  $text =~ m/1<\/b> - .*?<\/b> of (about )?<b>(.*?)<\/b>/g;
  $header = $2;
}

if ($text =~ m/Did you mean\:/g)
{
  $text =~ m/<i>(.*?)<\/i>/g;
  $footer = "Alternatively, try '$1' for more results.";
}

print "$arguments ($header): ";


if ($text =~ m/Showing web page information/g)
{
  $text =~ m/<p class=g>(.*?)<br>/g;
  $header = $1;
  $header =~ s/<.*?>//g;
  print "$header";

  if ($text =~ m/Description:(.*?)<br>/)
  {
    $header = $1;
    $header =~ s/<.*?>//g;
    print " - $header\n";
  }
  die;
}


$matches = 5 if ($matches > 5);

my $i = 0;

my $quote = chr(226) . chr(128) . chr(156);
my $quote2 = chr(226) . chr(128) . chr(157);
my $dash = chr(226) . chr(128) . chr(147);

while ($text =~ m/<li class=g><h3 class=r><a href=\"(.*?)\".*?>(.*?)<\/a>/g && $i < $matches)
{
  if ($i > 0)
  {
    $t = ", $2: [$1]";
  }
  else
  {
    $t = "$2: [$1]";
  }
  $t =~ s/<[^>]+>//g;
  $t =~ s/<\/[^>]+>//g;
  $t =~ s/$quote/"/g;
  $t =~ s/$quote2/"/g;
  $t =~ s/$dash/-/g;
  $t =~ s/&quot;/"/g;
  $t =~ s/&amp;/&/g;
  $t =~ s/&nsb;/ /g;
  $t =~ s/&#39;/'/g;
  $t =~ s/&lt;/</g;
  $t =~ s/&gt;/>/g;
  $t =~ s/<em>//g;
  $t =~ s/<\/em>//g;
  print $t;
  $i++;

#while ($t =~ m/(.)/g)
#{
#  print "($1) = " . ord($1). "\n";
#}

}


print " - $footer\n" if defined $footer;
