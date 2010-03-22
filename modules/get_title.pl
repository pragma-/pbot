#!/usr/bin/perl -w -I /home/msmud/lib/lib/perl5/site_perl/5.10.0/

# Quick and dirty by :pragma

use LWP::UserAgent;

my ($text);

if ($#ARGV <= 0)
{
  print "Usage: !title nick URL\n";
  exit;
}

my $nick = shift(@ARGV);
$arguments = join("%20", @ARGV);

exit if($arguments =~ m/imagebin/i);
exit if($arguments =~ m/\/wiki\//i);
exit if($arguments =~ m/wikipedia.org/i);
exit if($arguments =~ m/everfall.com/i);
exit if($arguments =~ m/pastie/i);
exit if($arguments =~ m/codepad/i);
exit if($arguments =~ m/paste.*\.(?:com|org|net|ca|uk)/i);
exit if($arguments =~ m/pasting.*\.(?:com|org|net|ca|uk)/i);

my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0");
$ua->max_size(200 * 1024);

my $response = $ua->get("$arguments");

if (not $response->is_success)
{
  #print "Couldn't get link.\n";
  die "Couldn't get link: $arguments";
}

$text = $response->content;

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
$t =~ s/<em>//g;
$t =~ s/<\/em>//g;

if(length $t > 150) {
  $t = substr($t, 0, 150);
  $t = "$t [...]";
}

# $nick =~ s/^(.)(.*)/$1|$2/;

print "Title of $nick\'s link: $t\n";
