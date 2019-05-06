#!/usr/bin/perl

use warnings;
use strict;

use LWP::UserAgent::WithCache;

use Data::Dumper;

my %cache_opt = (
  'namespace' => 'ja',
  'cache_root' => File::Spec->catfile(File::HomeDir->my_home, '.jacache'),
  'default_expires_in' => 600 * 6 * 24);
my $ua = LWP::UserAgent::WithCache->new(\%cache_opt);

$ua->agent("Mozilla 5.0");
$ua->cookie_jar({ file => "$ENV{HOME}/.jacookies" });

my @seasons = (1 .. 35, 'superjeopardy');

foreach my $season (@seasons) {
  print "Downloading season $season ... \n";

  my $response = $ua->get("http://website.com/showseason.php?season=$season");

  if (not $response->is_success) {
    print Dumper $response;
    die;
  }

  my $text = $response->content;

  open my $fh, '>', "season-$season.html";
  print $fh "$text\n";
  close $fh;

  while ($text =~ m{http://www.website.com/showgame.php\?game_id=(\d+)}g) {
    my $gameid = $1;

    print "  Downloading game $gameid ...\n";

    $response = $ua->get("http://website.com/showgame.php?game_id=$gameid");

    if (not $response->is_success) {
      print Dumper $response;
      die;
    }

    my $gametext = $response->content;

    open $fh, '>', "game-$gameid.html";
    print $fh "$gametext\n";
    close $fh;
  }
}
