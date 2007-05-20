#!/usr/bin/perl -w

# quick and dirty by :pragma

use strict;
use LWP::UserAgent;

my ($result, $acro, $entries, $text);

if ($#ARGV <0)
{
  print "What is the acronym you'd like to know about?\n";
  die;
}

$acro = join("+", @ARGV);

my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0");

my $response = $ua->post("http://www.acronymsearch.com/index.php",
  [ acronym => $acro, act => 'search' ]);

if (not $response->is_success)
{
  print "Couldn't get acronym information.\n";
  die;
}

$text = $response->content;

$acro =~ s/\+/ /g;

if($text =~ m/No result found/)
{
  print "Sorry, couldn't figure out what '$acro' stood for.\n";
  die;
}

$entries = 1;
$entries = $1 if($text =~ m/"2">(.*?) results? found/gi);

print "$acro ($entries entries): ";

$acro="";

while($text =~ m/<td width=.*?>(.*?)<\/td>/gsi)
{
  $acro = "$acro$1, ";
}

$acro =~ s/\s+\[slang\]//gi;
$acro =~ s/\s+\[joke\]//gi;
$acro =~ s/\s+/ /g;
$acro =~ s/<.*?>//g;
$acro =~ s/&nbsp;//g;
$acro =~ s/, , $//;
$acro = substr($acro, 0, 300);
print "$acro\n";
