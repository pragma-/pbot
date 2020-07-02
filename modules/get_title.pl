#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Quick and dirty by :pragma

use LWP::UserAgent;
use HTML::Entities;
use Text::Levenshtein qw(fastdistance);
use Time::HiRes qw(gettimeofday);

if ($#ARGV <= 0) {
    print "Usage: title nick URL\n";
    exit;
}

my $nick      = shift(@ARGV);
my $arguments = join("%20", @ARGV);

print STDERR "nick: [$nick], args: [$arguments]\n";

$arguments =~ s/\W$//;

exit if $arguments =~ m{https?://ibb.co/}i;
exit if $arguments =~ m{googlesource.com/}i;
exit if $arguments =~ m{https?://git}i;
exit if $arguments =~ m{https://.*swissborg.com}i;
exit if $arguments =~ m{https://streamable.com}i;
exit if $arguments =~ m{https://matrix.org}i;
exit if $arguments =~ m{https://freenode.net/news/spam-shake}i;
exit if $arguments =~ m{https://twitter.com/ISCdotORG}i;
exit if $arguments =~ m{https://evestigatorsucks.com}i;
exit if $arguments =~ m{https://MattSTrout.com}i;
exit if $arguments =~ m{https://encyclopediadramatica.rs/Freenodegate}i;
exit if $arguments =~ m{https://bryanostergaard.com}i;
exit if $arguments =~ m{https://williampitcock.com}i;
exit if $arguments =~ m{https?://coliru\..*}i;
exit if $arguments =~ m{https://www.youtube.com/user/l0de/live}i;
exit if $arguments =~ m{localhost}i;
exit if $arguments =~ m{127}i;
exit if $arguments =~ m{192.168}i;
exit if $arguments =~ m{file://}i;
exit if $arguments =~ m{\.\.}i;
exit if $arguments =~ m{https?://www.irccloud.com/pastebin}i;
exit if $arguments =~ m{http://smuj.ca/cl}i;
exit if $arguments =~ m{/man\d+/}i;
exit if $arguments =~ m{godbolt.org}i;
exit if $arguments =~ m{man\.cgi}i;
exit if $arguments =~ m{wandbox}i;
exit if $arguments =~ m{ebay.com/itm}i;
exit if $arguments =~ m/prntscr.com/i;
exit if $arguments =~ m/imgbin.org/i;
exit if $arguments =~ m/jsfiddle.net/i;
exit if $arguments =~ m/port70.net/i;
exit if $arguments =~ m/notabug.org/i;
exit if $arguments =~ m/flickr.com/i;
exit if $arguments =~ m{www.open-std.org/jtc1/sc22/wg14/www/docs/dr}i;
exit if $arguments =~ m/cheezburger/i;
exit if $arguments =~ m/rafb.me/i;
exit if $arguments =~ m/rextester.com/i;
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
if ($arguments =~ /youtube|youtu.be|googlevideo/) {
    $ua->agent("Googlebot");
} else {
    $ua->agent("Mozilla/5.0");
}
$ua->max_size(200 * 1024);

my $response = $ua->get("$arguments");

if (not $response->is_success) {

    #print "Couldn't get link.\n";
    use Data::Dumper;
    print STDERR Dumper $response;
    die "Couldn't get link: $arguments";
}

my $text = $response->decoded_content;

if ($text =~ m/<title>(.*?)<\/title>/msi) { $t = $1; }
else {
    use Data::Dumper;
    print STDERR Dumper $response;
    #print "No title for link.\n";
    exit;
}

my $quote  = chr(226) . chr(128) . chr(156);
my $quote2 = chr(226) . chr(128) . chr(157);
my $dash   = chr(226) . chr(128) . chr(147);

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

if (length $t > 150) {
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
my $length   = (length $file > length $t) ? length $file : length $t;

if ($distance / $length < 0.75) { exit; }

exit if $t !~ m/\s/;                                 # exit if title is only one word -- this isn't usually interesting
exit if $t =~ m{christel}i;
exit if $t =~ m{^Loading}i;
exit if $t =~ m{streamable}i;
exit if $t =~ m{freenode}i;
exit if $t =~ m{ico scam}i;
exit if $t =~ m{Freenode head of infrastructure}i;
exit if $t =~ m{ISC on Twitter}i;
exit if $t =~ m{spambot.*freenode}i;
exit if $t =~ m{freenode.*spambot}i;
exit if $t =~ m{christel};
exit if $t =~ m/^Coliru Viewer$/i;
exit if $t =~ m/^Gerrit Code Review$/i;
exit if $t =~ m/^Public Git Hosting -/i;
exit if $t =~ m/git\/blob/i;
exit if $t =~ m/\sdiff\s/i;
exit if $t =~ m/- Google Search$/;
exit if $t =~ m/linux cross reference/i;
exit if $t =~ m/screenshot/i;
exit if $t =~ m/pastebin/i;
exit if $t =~ m/past[ea]/i;
exit if $t =~ m/^[0-9_-]+$/;
exit if $t =~ m/^Index of \S+$/;
exit if $t =~ m/(?:sign up|login)/i;

my @data;
if (open my $fh, "<", "last-title-$nick.dat") {
    @data = <$fh>;
    close $fh;

    chomp $data[0];
    exit if $t eq $data[0] and scalar gettimeofday - $data[1] < 1800;
}

open my $fh, ">", "last-title-$nick.dat";
print $fh "$t\n";
print $fh scalar gettimeofday, "\n";
close $fh;

print "Title of $nick\'s link: $t\n" if length $t;
