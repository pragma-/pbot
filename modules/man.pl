#!/usr/bin/perl -w

# quick and dirty by :pragma

use strict;
use LWP::Simple;

my ($result, $manpage, $section, $text, $name, $includes, $prototype, $conforms, $description);

if ($#ARGV < 0) {
  print "Which command would you like information about?\n";
  die;
}

#$manpage = join(" ", @ARGV);
$manpage = join("+", @ARGV);

$section = "3";

#if($manpage =~ m/([0-9]+)\s+(.*)/) {
if($manpage =~ m/([0-9]+)\+(.*)/) {
#  $section = "$1 ";
  $section = $1;
  $manpage = $2;
}

if(!($section == 2 || $section == 3))
{
  print "I'm only interested in displaying information from section 2 or 3.\n";
  exit 0;
}

#my $page = `man $section$manpage -w 2>&1`;
#if($page =~ m/No.*?entry\sfor(.*)/i) {
#  print "No entry for$1\n";
#  exit 0;
#}

#$text = `groff -t -e -mandoc -Tascii $page`;
#$text =~ s/\e.*?m//g;

#$text = get("http://node1.yo-linux.com/cgi-bin/man2html?cgi_command=$manpage&cgi_section=$section&cgi_keyword=m");

$text = 
get("http://www.freebsd.org/cgi/man.cgi?query=$manpage&sektion=$section&apropos=0&manpath=FreeBSD+6.2-RELEASE&format=ascii");

if($text =~ m/Sorry, no data found/)
{
  print "No information found for $manpage in section $section.\n";
  exit 0;
}

$text =~ m/^\s+NAME/gsm;
if($text =~ m/(.*?)SYNOPSIS/gsi) {
  $name = $1;
}

my $i = 0;
while ($text =~ m/#include <(.*?)>/gsi) {
  $includes .= ", " if($i > 0);
  $includes .= "$1";
  $i++;
}

$prototype = "$1 $2$manpage($3);"
  if($text =~ m/SYNOPSIS.*^\s+(.*?)\s+(\*?)$manpage\s*\((.*?)\)\;?\n.*DESC/ms);

if($text =~ m/DESCRIPTION.*?$manpage(.*?)\./si) {
  $description = "$manpage $1";
  $description =~ s/\-\s+//g;
}

if ($text =~ m/^CONFORMING TO.*?^\s+The\s$manpage\s.*conforms to\s(.*?)$/ms) {
  $conforms = $1;
  } elsif ($text =~ m/^CONFORMING TO.*?^\s+The\s+$manpage\s+.*?is\s+compatible\s+with\s+(.*?)$/ms) {
  $conforms = "$1 ...";
} elsif ($text =~ m/^CONFORMING TO.*?^\s+(.*?)\.\s/ms or
         $text =~ m/^CONFORMING TO.*?^\s+(.*?)$/ms) {
  $conforms = $1;
}

$result = "";
$result .= "$name - " if (not defined $includes);
$result .= "Includes: $includes - " if (defined $includes);
$result .= "$prototype - " if (defined $prototype);
$result .= "$conforms - " if (defined $conforms);
$result .= $description;

$result =~ s/^\s+//g;
$result =~ s/\s+/ /g;
$result =~ s/ANSI - C/ANSI C/g;
$result =~ s/\n//g;
$result =~ s/\r//g;
$result =~ s/\<A HREF.*?>//g;
$result =~ s/\<\/A>//g;
$result =~ s/&quot;//g;

print "$result - http://www.iso-9899.info/man?$manpage";
