#!/usr/bin/perl

use warnings;
use strict;

use HTML::Entities;

my $debug = 9999; 

 open FH, "<n1256.txt" or die "Could not open n1256.txt: $!";
#open FH, "<n1570.txt" or die "Could not open n1570.txt: $!";
my @contents = <FH>;
close FH;

my $text = join '', @contents;
$text =~ s/\r//g;

print "<html>\n<body>\n";

my ($section_title, $this_section);

my $last_section_number = 0;
my $section_number = 0;
my $last_section;

while($text =~ m/^\s{0,4}([0-9A-Z]+\.[0-9\.]*)/msg) {
  $last_section_number = $section_number;
  $last_section = $this_section;
  $this_section = $1;

  ($section_number) = $this_section =~ /([^.]+)\./;

  print STDERR "----------------------------------\n" if $debug >= 2;
  print STDERR "Processing section [$this_section]; number [$section_number]\n" if $debug;

  print STDERR "this_section: [$this_section]; last_section: [$last_section]\n";
  print STDERR "Section diff: ", ($this_section - $last_section), "\n";

  my $diff = $section_number - $last_section_number;
  print STDERR "Diff: $diff\n" if $debug >= 2;

  if($section_number > 0 and $diff < 0 or $diff > 1) { 
     print STDERR "Diff out of bounds: $diff\n";
     last;
  }

  my $section_text;

  if($text =~ m/(.*?)^(?=\s{0,4}[0-9A-Z]+\.)/msg) {
    $section_text = $1;
  } else {
    print STDERR "No section text, end of file marker found.\n" if $debug >= 4;
    last;
  }

  if($section_text =~ m/(.*?)$/msg) {
    $section_title = $1 if length $1;
    $section_title =~ s/^\s+//;
    $section_title =~ s/\s+$//;
  }

  print STDERR "$this_section [$section_title]\n" if $debug >= 2;
  
  print "<hr>\n";
  print "<a name='$this_section'>";
  print "<h3>$this_section [$section_title]</h3>";
  print "</a>\n";

  print STDERR "section text: [$section_text]\n" if $debug >= 2;

  if(not $section_text =~ m/^(?=\d+\s)/msg) {
    print "<pre>$section_text</pre>\n";
  } else {
    while($section_text =~ m/^(\d+)\s(.*?)^(?=\d)/msgc or $section_text =~ m/^(\d+)\s(.*)/msg) {
      my $p = $1;
      my $t = $2;

      print STDERR "paragraph $p: [$t]\n" if $debug >= 3;

      $t = encode_entities($t);

      print "<a name='$this_section" . "p$p'>";
      print "<pre>$p $t</pre>\n";
      print "</a>\n";
    }
  }
}

print "\n</body>\n</html>\n";
