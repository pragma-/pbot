#!/usr/bin/perl -w

use strict;

my $file;
my $match = 1;
my $matches = 0;
my $found = 0;
my $result;

print "Usage: faq [match #] <search regex>\n" and exit 0 if not defined $ARGV[0];

my $query = join(".*?", @ARGV);
$query =~ s/\s+/.*?/g;

$query =~ s/\+/\\+/g;
$query =~ s/[^\.]\*/\\*/g;
$query =~ s/^\*/\\*/g;
$query =~ s/\[/\\[/g;
$query =~ s/\]/\\]/g;

if($query =~ /^(\d+)\.\*\?/) {
  $match = $1;
  $query =~ s/^\d+\.\*\?//;
}

opendir(DIR, "/home/msmud/htdocs/C-faq/") or die "$!";

while (defined ($file = readdir DIR)) {
  open(FILE, "< /home/msmud/htdocs/C-faq/$file") or die "Can't open $file: $!";
  my @contents = <FILE>;
  my $text = join('', @contents);
  my $heading = $1 if($text =~ /^<H1>(.*?)<\/H1>$/smg);

  while($text =~ /<p><a href=(.*?) rel=.*?>(.*?)<\/a>/smg) {
    my ($link, $question) = ($1, $2);
    if($question =~ /$query/ims) {
      $question =~ s/\n/ /g;
      $question =~ s/\r/ /g;
      $question =~ s/<.*?>//g;
      $question =~ s/\s+/ /g;
      $question =~ s/&lt;/</g;
      $question =~ s/&gt;/>/g;
      $result = "$heading, $question: http://www.eskimo.com/~scs/C-faq/$link\n" if ($matches + 1 == $match);
      $found = 1;
      $matches++;
    }
  }  
  close(FILE);
}
closedir(DIR);

if($found == 1) {
  print "But there are $matches results...\n" and exit if($match > $matches);

  print "$matches results, displaying #$match: " if ($matches > 1);

  $result =~ s/&amp;/&/g;

  print "$result";
} else {
  $query =~ s/\.\*\?/ /g;
  print "No FAQs match $query\n";
}
