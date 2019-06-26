#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

my $debug = 0;

# for paragraphs
my $USER_SPECIFIED    = 1;
my $RESULTS_SPECIFIED = 2;

my $search = join ' ', @ARGV;

if (not length $search) {
  print "Usage: cstd [-list] [-n#] [-section <section>] [search text] -- 'section' must be in the form of X.YpZ where X and Y are section/chapter and, optionally, pZ is paragraph. If both 'section' and 'search text' are specified, then the search space will be within the specified section. You may use -n # to skip to the #th match. To list only the section numbers containing 'search text', add -list.\n";
  exit 0;
}

my ($section, $paragraph, $section_specified, $paragraph_specified, $match, $list_only, $list_titles);

$section_specified = 0;
$paragraph_specified = 0;

if ($search =~ s/-section\s*([0-9\.p]+)//i or $search =~ s/\b(\d+\.[0-9\.p]*)//i) {
  $section = $1;

  if ($section =~ s/p(\d+)//i) {
    $paragraph = $1;
    $paragraph_specified = $USER_SPECIFIED;
  } else {
    $paragraph = 1;
  }

  $section = "$section." if $section =~ m/^\d+$/;

  $section_specified = 1;
}

if ($search =~ s/-n\s*(\d+)//) {
  $match = $1;
} else {
  $match = 1;
}

if ($search =~ s/-list//i) {
  $list_only = 1;
  $list_titles = 1; # Added here instead of removing -titles option
}

if ($search =~ s/-titles//i) {
  $list_only = 1;
  $list_titles = 1;
}

$search =~ s/^\s+//;
$search =~ s/\s+$//;

if (not defined $section) {
  $section = "1.";
  $paragraph = 1;
}

if ($list_only and not length $search) {
  print "You must specify some search text to use with -list.\n";
  exit 0;
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

if ($list_only) {
  $result = "Sections containing '$search':\n    ";
}

$search =~ s/\s/\\s+/g;

while ($text =~ m/^\s{4,6}(\d+\.[0-9\.]*)/msg) {
  $this_section = $1;

  print "----------------------------------\n" if $debug >= 2;
  print "Processing section [$this_section]\n" if $debug;

  my $section_text;

  if ($text =~ m/(.*?)^(?=\s{4,6}\d+\.)/msg) {
    $section_text = $1;
  } else {
    print "No section text, end of file marker found.\n" if $debug >= 4;
    last;
  }

  if ($section_text =~ m/(.*?)$/msg) {
    $section_title = $1 if length $1;
    $section_title =~ s/^\s+//;
    $section_title =~ s/\s+$//;
  }

  if ($section_specified and $this_section !~ m/^$section/) {
    print "No section match, skipping.\n" if $debug >= 4;
    next;
  }

  print "$this_section [$section_title]\n" if $debug >= 2;

  while ($section_text =~ m/^(\d+)\s(.*?)^(?=\d)/msgc or $section_text =~ m/^(\d+)\s(.*)/msg) {
    my $p = $1 ;
    my $t = $2;

    print "paragraph $p: [$t]\n" if $debug >= 3;

    if ($paragraph_specified == $USER_SPECIFIED and not length $search and $p == $paragraph) {
      $result = $t if not $found;
      $found_paragraph = $p;
      $found_section = $this_section;
      $found_section_title = $section_title;
      $found = 1;
      last;
    }

    if (length $search) {
      eval {
        if ($t =~ m/\b$search/mis or $section_title =~ m/\b$search/mis) {
          $matches++;
          if ($matches >= $match) {
            if ($list_only) {
              $result .= sprintf("%s%-15s", $comma, $this_section."p".$p);
              $result .= " $section_title" if $list_titles;
              $comma = ",\n    ";
            } else {
              if (not $found) {
                $result = $t;
                $found_section = $this_section;
                $found_section_title = $section_title;
                $found_paragraph = $p;
                $paragraph_specified = $RESULTS_SPECIFIED;
              }
              $found = 1;
            }
          }
        }
      };

      if ($@) {
        print "Error in search regex; you may need to escape characters such as *, ?, ., etc.\n";
        exit 0;
      }
    }
  }

  last if $found && $paragraph_specified == $USER_SPECIFIED;

  if ($paragraph_specified == $USER_SPECIFIED) {
    print "No such paragraph '$paragraph' in section '$section' of n1256.\n";
    exit 0;
  }

  if (defined $section_specified and not length $search) {
    $found = 1;
    $found_section = $this_section;
    $found_section_title = $section_title;
    $found_paragraph = $paragraph;
    $result = $section_text;
    last;
  }
}

if (not $found and $comma eq "") {
  $search =~ s/\\s\+/ /g;
  if ($section_specified) {
    print "No such text '$search' found within section '$section' in C99 Draft Standard (n1256).\n" if length $search;
    print "No such section '$section' in C99 Draft Standard (n1256).\n" if not length $search;
    exit 0;
  }

  print "No such section '$section' in C99 Draft Standard (n1256).\n" if not length $search;
  print "No such text '$search' found in C99 Draft Standard (n1256).\n" if length $search;
  exit 0;
}

$result =~ s/$found_section_title// if length $found_section_title;
$result =~ s/^\s+//;
$result =~ s/\s+$//;
=cut
$result =~ s/\s+/ /g;
$result =~ s/[\n\r]/ /g;
=cut

if ($matches > 1 and not $list_only) {
  print "Displaying \#$match of $matches matches: ";
}

if ($comma eq "") {
=cut
  print $found_section;
  print "p" . $found_paragraph if $paragraph_specified;
=cut
  print "\nhttp://blackshell.com/~msmud/cstd.html\#$found_section";
  print "p" . $found_paragraph if $paragraph_specified;
  print "\n\n";
  print "[", $found_section_title, "]\n\n" if length $found_section_title;
}

print "$result\n";
