#!/usr/bin/perl -w

# Quick and dirty by :pragma

use LWP::UserAgent;
use HTML::Entities;
use Text::Levenshtein qw(fastdistance);

if ($#ARGV <= 0)
{
  print "Usage: title nick URL\n";
  exit;
}

my $nick = shift(@ARGV);
my $arguments = join("%20", @ARGV);

$arguments =~ s/\W$//;

exit if $arguments =~ m/explosm.net/i;
exit if $arguments =~ m/stackoverflow.com/i;
exit if $arguments =~ m/scratch.mit.edu/i;
exit if $arguments =~ m/c-faq.com/i;
exit if $arguments =~ m/imgur.com/i;
exit if $arguments =~ m/sprunge.us/i;
exit if $arguments =~ m/pastebin.ws/i;
exit if $arguments =~ m/hastebin.com/i;
exit if $arguments =~ m/lmgtfy.com/i;
exit if $arguments =~ m/gyazo/i;
exit if $arguments =~ m/imagebin/i;
exit if $arguments =~ m/\/wiki\//i;
exit if $arguments =~ m/github.com/i;
exit if $arguments =~ m/wiki.osdev.org/i;
exit if $arguments =~ m/wikipedia.org/i;
exit if $arguments =~ m/everfall.com/i;
exit if $arguments =~ m/fukung.net/i;
exit if $arguments =~ m/\/paste\//i;
exit if $arguments =~ m/paste\./i;
exit if $arguments =~ m/pastie/i;
exit if $arguments =~ m/ideone.com/i;
exit if $arguments =~ m/codepad.org/i;
exit if $arguments =~ m/^http\:\/\/past(e|ing)\./i;
exit if $arguments =~ m/paste.*\.(?:com|org|net|ch|ca|de|uk|info)/i;
exit if $arguments =~ m/pasting.*\.(?:com|org|net|ca|de|uk|info|ch)/i;

my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0");
$ua->max_size(200 * 1024);

my $response = $ua->get("$arguments");

if (not $response->is_success)
{
  #print "Couldn't get link.\n";
  use Data::Dumper;
  print STDERR Dumper $response;
  die "Couldn't get link: $arguments";
}

my $text = $response->content;

if($text =~ m/<title>(.*?)<\/title>/msi)
{
  $t = $1;
} else {
  #print "No title for link.\n";
  exit;
}

my $quote = chr(226) . chr(128) . chr(156);
my $quote2 = chr(226) . chr(128) . chr(157);
my $dash = chr(226) . chr(128) . chr(147);

$t =~ s/\s+/ /g;
$t =~ s/^\s+//g;
$t =~ s/\s+$//g;
$t =~ s/<[^>]+>//g;
$t =~ s/<\/[^>]+>//g;
$t =~ s/$quote/"/g;
$t =~ s/$quote2/"/g;
$t =~ s/$dash/-/g;
$t =~ s/&quot;/"/g;
$t =~ s/&#8220;/"/g;
$t =~ s/&#8221;/"/g;
$t =~ s/&amp;/&/g;
$t =~ s/&nsb;/ /g;
$t =~ s/&#39;/'/g;
$t =~ s/&lt;/</g;
$t =~ s/&gt;/>/g;
$t =~ s/&laquo;/<</g;
$t =~ s/&raquo;/>>/g;
$t =~ s/&gt;/>/g;
$t =~ s/&bull;/-/g;
$t =~ s/<em>//g;
$t =~ s/<\/em>//g;

if(length $t > 150) {
  $t = substr($t, 0, 150);
  $t = "$t [...]";
}

# $nick =~ s/^(.)(.*)/$1|$2/;

$t = decode_entities($t);

$t =~ s/^\s+//;
$t =~ s/\s+$//;

my ($file) = $arguments =~ m/.*\/(.*)$/;
$file =~ s/[_-]/ /g;

my $distance = fastdistance(lc $file, lc $t);
my $length = (length $file > length $t) ? length $file : length $t;

if($distance / $length < 0.75) {
    exit;
}

exit if $t =~ m/^Gerrit Code Review$/i;
exit if $t =~ m/pastebin/i;

print "Title of $nick\'s link: $t\n" if length $t;
