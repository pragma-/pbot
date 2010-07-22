#!/usr/bin/perl

use warnings;
use strict;

use HTML::Entities;

my $debug = 0;

# for paragraphs
my $USER_SPECIFIED    = 1;
my $RESULTS_SPECIFIED = 2;


my ($section, $paragraph, $section_specified, $paragraph_specified, $match, $list_only);

$section_specified = 0;
$paragraph_specified = 0;
$match = 1;

if(not defined $section) {
  $section = "1.";
  $paragraph = 1;
}

open FH, "<n1256.txt" or die "Could not open n1256.txt: $!";
my @contents = <FH>;
close FH;

my $text = join '', @contents;
$text =~ s/\r//g;

my $result;
my $found_section = "";
my $found_section_title = "";
my $section_title;
my $found_paragraph;
my $found = 0;
my $matches = 0;
my $this_section;
my $comma = "";

print "<html>\n<body>\n";

#$debug = 9999;

my $last_section_number = 0;
my $section_number = 0;

while($text =~ m/^\s{4,6}(\d+\.[0-9\.]*)/msg) {
  $last_section_number = $section_number;
  $this_section = $1;

  ($section_number) = $this_section =~ /([^.]+)\./;

  print "----------------------------------\n" if $debug >= 2;
  print "Processing section [$this_section]; number [$section_number]\n" if $debug;


  my $diff = $section_number - $last_section_number;
  print "Diff: $diff\n" if $debug >= 2;

  if($section_number > 0 and $diff < 0 or $diff > 1) { 
     die "Diff out of bounds: $diff";
  }

  my $section_text;

  if($text =~ m/(.*?)^(?=\s{4,6}\d+\.)/msg) {
    $section_text = $1;
  } else {
    print "No section text, end of file marker found.\n" if $debug >= 4;
    last;
  }

  if($section_text =~ m/(.*?)$/msg) {
    $section_title = $1 if length $1;
    $section_title =~ s/^\s+//;
    $section_title =~ s/\s+$//;
  }

  print "$this_section [$section_title]\n" if $debug >= 2;
  
  print "<hr>\n";
  print "<a name='$this_section'>";
  print "<h3>$this_section [$section_title]</h3>";
  print "</a>\n";
        
  while($section_text =~ m/^(\d+)\s(.*?)^(?=\d)/msgc or $section_text =~ m/^(\d+)\s(.*)/msg) {
    my $p = $1 ;
    my $t = $2;


    print "paragraph $p: [$t]\n" if $debug >= 3;

    $t = encode_entities($t);

    print "<a name='$this_section" . "p$p'>";
    print "<pre>$p $t</pre>\n";
    print "</a>\n";
  }

  last if $found && $paragraph_specified == $USER_SPECIFIED;
  
  if($paragraph_specified == $USER_SPECIFIED) {
    print "No such paragraph '$paragraph' in section '$section' of n1256.\n";
    exit 0;
  }
}

print "\n</body>\n</html>\n";

