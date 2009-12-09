#!/usr/bin/perl -I /home/msmud/lib/perl5

use strict;
use WWW::Wikipedia;
use Text::Autoformat;
use Getopt::Std;

my %options;
getopts( 'l:', \%options );

my $term = join(' ', @ARGV);

if(not $term) {
  print "Usage: !wikipedia <term>\n";
  exit;
}

# upper-case first letter and lowercase remainder of each word
# $term =~ s/(.)(\w*)(\s?)/\u$1\l$2$3/g;

my $wiki = WWW::Wikipedia->new( language => $options{ l } || 'en' );
my $entry = $wiki->search( $term );

if ( $entry ) {
    my $text = $entry->text();
    
    if ( $text ) { 
      $text =~ s/[\n\r]/ /msg;
      $text =~ s/\[otheruses.*?\]//gsi;
      $text =~ s/\[fixbunching.*?\]//gsi;
      $text =~ s/\[wiktionary.*?\]//gsi;
      $text =~ s/\[TOC.*?\]//gsi;
      $text =~ s/\[.*?sidebar\]//gsi;
      $text =~ s/\[pp.*?\]//gsi;
      $text =~ s/'''//gs;
      
      1 while $text =~ s/{{[^{}]*}}//gs;
      1 while $text =~ s/\[quote[^\]]*\]//gsi;
      1 while $text =~ s/\[\[Image:[^\[\]]*\]\]//gsi;
      1 while $text =~ s/\[\[(File:)?([^\[\]]*)\]\]//gsi;
      
      $text =~ s/\[\[.*?\|(.*?)\]\]/$1/gs;
      $text =~ s/\[\[(.*?)\]\]/$1/gs;
      $text =~ s/<!--.*?--\s?>//gs;
      $text =~ s/\s+/ /gs;
      $text =~ s/^\s+//;
      $text =~ s/\<.*?\>.*?\<\/.*?\>//gs;
      $text =~ s/\<.*?\/\>//gs;
      
      $text =~ s/&ndash;/-/;
      
      print $text; 
    }
    else {
        print "Specific entry not found, see also: ";
        my $semi = "";
        foreach ( $entry->related() ) { print "$_$semi"; $semi = "; "; }
    }
}
else { print qq("$term" not found in wikipedia\n) }

