#!/usr/bin/perl -w

# SPDX-FileCopyrightText: 2009-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# Quick and dirty by :pragma

use LWP::UserAgent;

my ($text, $t);

my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0");

my %post = ('number' => '4', 'collection[]' => '20thcent');

my $response = $ua->post("http://www.quotationspage.com/random.php3", \%post);

if (not $response->is_success) {
    print "Couldn't get quote information.\n";
    die;
}

$text = $response->content;

$text =~ m/<dt class="quote"><a.*?>(.*?)<\/a>.*?<dd class="author"><div.*?><a.*?>.*?<b>(.*?)<\/b>/g;
$t = "\"$1\" -- $2.";

my $quote  = chr(226) . chr(128) . chr(156);
my $quote2 = chr(226) . chr(128) . chr(157);
my $dash   = chr(226) . chr(128) . chr(147);

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

print "$t\n";
