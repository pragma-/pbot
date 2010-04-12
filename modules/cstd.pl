#!/usr/bin/perl

use warnings;
use strict;

my $debug = 0;

my $search = join ' ', @ARGV;

if(not length $search) {
  print "Usage: cstd [-list] [-n #] [-section <section>] [search text] -- 'section' must be in the form of X.YpZ where X and Y are section/chapter and, optionally, Z is paragraph. If both 'section' and 'search text' are specified, then the search space will be within the specified section. You may use -n # to skip to the #th match. To list only the section numbers containing 'search text', add -list.\n";
  exit 0;
}

my ($section, $paragraph, $section_specified, $paragraph_specified, $match, $list_only);

if($search =~ s/-section\s*([0-9\.p]+)//i or $search =~ s/\b(\d+\.[0-9\.p]*)//i) {
  $section = $1;

  if($section =~ s/p(\d+)//i) {
    $paragraph = $1;
    $paragraph_specified = 1;
  } else {
    $paragraph = 1;
  }

  $section = "$section." if $section =~ m/^\d+$/;

  $section_specified = 1;
}

if($search =~ s/-n\s*(\d+)//) {
  $match = $1;
} else {
  $match = 1;
}

if($search =~ s/-list//i) {
  $list_only = 1;
}

$search =~ s/^\s+//;
$search =~ s/\s+$//;

if(not defined $section) {
  $section = "1.";
  $paragraph = 1;
}

if($list_only and not length $search) {
  print "You must specify some search text to use with -list.\n";
  exit 0;
}

open FH, "<n1256.txt" or die "Could not open n1256.txt: $!";
my @contents = <FH>;
close FH;

my $text = join '', @contents;
$text =~ s/\r//g;

my $result;
my $section_title;
my $found = 0;
my $matches = 0;
my $this_section;
my $comma = "";

if($list_only) {
  $result = "Sections containing '$search': ";
}

$search =~ s/\s+/.*/g;

while($text =~ m/^\s{4}(\d+\.[0-9\.]*)/msg) {
  $this_section = $1;

  print "----------------------------------\n" if $debug >= 2;
  print "Processing section [$this_section]\n" if $debug;

  my $section_text;

  if($text =~ m/(.*?)^(?=\s{4}\d+\.)/msg) {
    $section_text = $1;
  } else {
    print "No section text, skipping.\n" if $debug >= 4;
    last;
  }

  if($section_text =~ m/(.*?)$/msg) {
    $section_title = $1 if length $1;
    $section_title =~ s/^\s+//;
    $section_title =~ s/\s+$//;
  }

  if($section_specified and $this_section !~ m/^$section/) {
    print "No section match, skipping.\n" if $debug >= 4;
    next;
  }

  print "$this_section [$section_title]\n" if $debug >= 2;

  while($section_text =~ m/^(\d+)\s(.*?)^(?=\d)/msgc or $section_text =~ m/^(\d+)\s(.*)/msg) {
    my $p = $1 ;
    my $t = $2;

    print "paragraph $p: [$t]\n" if $debug >= 3;

    if($paragraph_specified and not length $search and $p == $paragraph) {
      $found = 1;
      $result = $t;
      last;
    }

    if(length $search) {
      eval {
        if($t =~ m/\b$search\b/ms) {
          $matches++;
          if($matches >= $match) {
            if($list_only) {
              $result .= "$comma$this_section" . "p" . $p;
              $comma = ", ";
            } else {
              $result = $t;
              $paragraph = $p;
              $paragraph_specified = 1;
              $found = 1;
              last;
            }
          }
        }
      };

      if($@) {
        print "Error in search regex; you may need to escape characters such as *, ?, ., etc.\n";
        exit 0;
      }
    }
  }
  last if $found == 1;

  if($paragraph_specified) {
    print "No such paragraph '$paragraph' in section '$section' of n1256.\n";
    exit 0;
  }

  if(defined $section_specified and not length $search) {
    $found = 1;
    $result = $section_text;
    last;
  }

  $paragraph = 1;
}

if(not $found and $comma eq "") {
  $search =~ s/\.\*/ /g;
  if($section_specified) {
    print "No such text '$search' found within section '$section' in n1256.\n" if length $search;
    print "No such section '$section' in n1256.\n" if not length $search;
    exit 0;
  }

  print "No such section '$section' in n1256.\n" if not length $search;
  print "No such text '$search' found in n1256.\n" if length $search;
  exit 0;
}

$result =~ s/$section_title// if length $section_title;
$result =~ s/^\s+//;
$result =~ s/\s+$//;
$result =~ s/\s+/ /g;
$result =~ s/[\n\r]/ /g;

if($comma eq "") {
  print $this_section;
  print "p" . $paragraph if $paragraph_specified;
  print ": ";
  print "[", $section_title, "] " if length $section_title;
}

print "$result\n";
