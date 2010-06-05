#!perl

use warnings;
use strict;

use POSIX qw(strftime);

my $svn_info = `svn info -r head`;
my ($rev) = $svn_info =~ /Last Changed Rev: (\d+)/;
my $date = strftime "%Y-%m-%d", localtime;

$rev++;

print "New version: $rev $date\n";

open my $in, '<', "PBot/VERSION.pm" or die "Couldn't open VERSION.pm for reading: $!";
my @lines = <$in>;
close $in;

open my $out, '>', "PBot/VERSION.pm" or die "Couldn't open VERSION.pm for writing: $!";

foreach my $text (@lines) {
  $text =~ s/BUILD_NAME\s+=> ".*",/BUILD_NAME     => "PBot",/;
  $text =~ s/BUILD_REVISION\s+=> \d+,/BUILD_REVISION => $rev,/;
  $text =~ s/BUILD_DATE\s+=> ".*",/BUILD_DATE     => "$date",/;

  print $out $text;
}

close $out;
