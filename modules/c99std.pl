#!/usr/bin/perl

use warnings;
use strict;

my $debug = 0;

# for paragraphs
my $USER_SPECIFIED    = 1;
my $RESULTS_SPECIFIED = 2;

my $search = join ' ', @ARGV;

if(not length $search) {
  print "Usage: c99std [-list] [-n#] [-section <section>] [search text] -- 'section' must be in the form of X.YpZ where X and Y are section/chapter and, optionally, pZ is paragraph. If both 'section' and 'search text' are specified, then the search space will be within the specified section. You may use -n # to skip to the #th match. To list only the section numbers containing 'search text', add -list.\n";
  exit 0;
}

my ($section, $paragraph, $section_specified, $paragraph_specified, $match, $list_only, $list_titles);

$section_specified = 0;
$paragraph_specified = 0;

if($search =~ s/-section\s*([A-Z0-9\.p]+)//i or $search =~ s/\b([A-Z0-9]+\.[0-9\.p]+)//i) {
  $section = $1;

  if($section =~ s/p(\d+)//i) {
    $paragraph = $1;
    $paragraph_specified = $USER_SPECIFIED;
  } else {
    $paragraph = 1;
  }

  $section = "$section." if $section =~ m/^[A-Z0-9]+$/i;

  $section_specified = 1;
}

if($search =~ s/-n\s*(\d+)//) {
  $match = $1;
} else {
  $match = 1;
}

if($search =~ s/-list//i) {
  $list_only = 1;
  $list_titles = 1; # Added here instead of removing -titles option
}

if($search =~ s/-titles//i) {
  $list_only = 1;
  $list_titles = 1;
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

open FH, "<n1256.out" or die "Could not open n1256: $!";
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

if($list_only) {
  $result = "Sections containing '$search':\n    ";
}

my $qsearch = quotemeta $search;
$qsearch =~ s/\\ / /g;
$qsearch =~ s/\s+/\\s+/g;

while($text =~ m/^\s{0,4}([0-9A-Z]+\.[0-9\.]*)/msg) {
  $this_section = $1;

  print "----------------------------------\n" if $debug >= 2;
  print "Processing section [$this_section]\n" if $debug;

  if($section_specified and $this_section !~ m/^$section/i) {
    print "No section match, skipping.\n" if $debug >= 4;
    next;
  }

  my $section_text;

  if($text =~ m/(.*?)^(?=\s{0,4}(?!FOOTNOTE)[0-9A-Z]+\.)/msg) {
    $section_text = $1;
  } else {
    print "No section text, end of file marker found.\n" if $debug >= 4;
    last;
  }

  if($section =~ /FOOTNOTE/i) {
    $section_text =~ s/^\s{4}//ms;
    $section_text =~ s/^\s{4}FOOTNOTE.*//msi;
    $section_text =~ s/^\d.*//ms;
  } elsif ($section_text =~ m/(.*?)$/msg) {
    $section_title = $1 if length $1;
    $section_title =~ s/^\s+//;
    $section_title =~ s/\s+$//;
  }

  print "$this_section [$section_title]\n" if $debug >= 2;

  while($section_text =~ m/^(\d+)\s(.*?)^(?=\d)/msgic or $section_text =~ m/^(\d+)\s(.*)/msgi) {
    my $p = $1 ;
    my $t = $2;

    print "paragraph $p: [$t]\n" if $debug >= 3;

    if($paragraph_specified == $USER_SPECIFIED and not length $search and $p == $paragraph) {
      $result = $t if not $found;
      $found_paragraph = $p;
      $found_section = $this_section;
      $found_section_title = $section_title;
      $found = 1;
      last;
    }

    if(length $search) {
      eval {
        if($t =~ m/\b$qsearch\b/mis or $section_title =~ m/\b$qsearch\b/mis) {
          $matches++;
          if($matches >= $match) {
            if($list_only) {
              $result .= sprintf("%s%-15s", $comma, $this_section."p".$p);
              $result .= " $section_title" if $list_titles;
              $comma = ",\n    ";
            } else {
              if(not $found) {
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

      if($@) {
        print "Error in search regex; you may need to escape characters such as *, ?, ., etc.\n";
        exit 0;
      }
    }
  }

  last if $found && $paragraph_specified == $USER_SPECIFIED;
  
  if($paragraph_specified == $USER_SPECIFIED) {
    if(length $search) {
      print "No such text '$search' found within paragraph $paragraph of section $section of n1256.\n";
    } else {
      print "No such paragraph $paragraph in section $section of n1256.\n";
    }
    exit 0;
  }

  if(defined $section_specified and not length $search) {
    $found = 1;
    $found_section = $this_section;
    $found_section_title = $section_title;
    $found_paragraph = $paragraph;
    $result = $section_text;
    last;
  }
}

if(not $found and $comma eq "") {
  $search =~ s/\\s\+/ /g;
  if($section_specified) {
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

if($matches > 1 and not $list_only) {
  print "Displaying $match of $matches matches: ";
}

if($comma eq "") {
  print "\nhttp://www.iso-9899.info/n1256.html\#$found_section";
  print "p" . $found_paragraph if $paragraph_specified;
  print "\n\n";
  print "[", $found_section_title, "]\n\n" if length $found_section_title;
}

$result =~ s/\s*Constraints\s*$//;
$result =~ s/\s*Semantics\s*$//;
$result =~ s/\s*Description\s*$//;
$result =~ s/\s*Returns\s*$//;
$result =~ s/\s*Runtime-constraints\s*$//;
$result =~ s/\s*Recommended practice\s*$//;

print "$result\n";
