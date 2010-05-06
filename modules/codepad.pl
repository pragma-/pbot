#!/usr/bin/perl

use warnings;
use strict;

use LWP::UserAgent;
use URI::Escape;
use HTML::Entities;
use HTML::Parse;
use HTML::FormatText;
use IPC::Open2;

my @languages = qw/C C++ D Haskell Lua OCaml PHP Perl Python Ruby Scheme Tcl/;

my %preludes = ( 'C' => "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n",
                 'C++' => "#include <iostream>\n#include <cstdio>\n",
               );

if($#ARGV <= 0) {
  print "Usage: cc [-lang=<language>] <code>\n";
  exit 0;
}

my $nick = shift @ARGV;
my $code = join ' ', @ARGV;

open FILE, ">> codepad_log.txt";
print FILE "$nick: $code\n";

my $lang = "C";
$lang = $1 if $code =~ s/-lang=([^\b\s]+)//i;

my $show_url = 0;
$show_url = 1 if $code =~ s/-showurl//i;

my $found = 0;
foreach my $l (@languages) {
  if(uc $lang eq uc $l) {
    $lang = $l;
    $found = 1;
    last;
  }
}

if(not $found) {
  print "$nick: Invalid language '$lang'.  Supported languages are: @languages\n";
  exit 0;
}

my $ua = LWP::UserAgent->new();

$ua->agent("Mozilla/5.0");
push @{ $ua->requests_redirectable }, 'POST';

$code =~ s/#include <([^>]+)>/\n#include <$1>\n/g;
$code =~ s/#([^ ]+) (.*?)\\n/\n#$1 $2\n/g;
$code =~ s/#([\w\d_]+)\\n/\n#$1\n/g;

my $precode = $preludes{$lang} . $code;
$code = '';

if($lang eq "C" or $lang eq "C++") {
  my $has_main = 0;
  
  my $prelude = '';
  $prelude = "$1$2" if $precode =~ s/^\s*(#.*)(#.*?[>\n])//s;
  
  while($precode =~ s/([a-zA-Z0-9_]+)\s+([a-zA-Z0-9_]+)\s*\((.*?)\)\s*{(.*?)}//) {
    my ($ret, $ident, $params, $body) = ($1, $2, $3, $4);
    $code .= "$ret $ident($params) { $body }\n\n";
    $has_main = 1 if $ident eq 'main';
  }

  $precode =~ s/^\s+//;
  $precode =~ s/\s+$//;

  if(not $has_main) {
    $code = "$prelude\n\n$code\n\nint main(int argc, char **argv) { $precode return 0;}\n";
  } else {
    $code = "$prelude\n\n$code\n\n$precode\n";
  }
} else {
  $code = $precode;
}

if($lang eq "C" or $lang eq "C++") {
  $code = pretty($code);
}

my %post = ( 'lang' => $lang, 'code' => $code, 'private' => 'True', 'run' => 'True', 'submit' => 'Submit' );
my $response = $ua->post("http://codepad.org", \%post);

if(not $response->is_success) {
  print "There was an error compiling the code.\n";
  die $response->status_line;
}

my $text = $response->decoded_content;
my $url = $response->request->uri;
my $output;

# remove line numbers
$text =~ s/<a style="" name="output-line-\d+">\d+<\/a>//g;

if($text =~ /<span class="heading">Output:<\/span>.+?<div class="code">(.*)<\/div>.+?<\/table>/si) {
  $output = "$1";
} else {
  $output = "<pre>No output.</pre>";
}

$output = decode_entities($output);
$output = HTML::FormatText->new->format(parse_html($output));

$output =~ s/^\s+//;

$output =~ s/\s*Line\s+\d+\s+://g;
$output =~ s/ \(first use in this function\)//g;
$output =~ s/error: \(Each undeclared identifier is reported only once.*?\)//g;
$output =~ s/error: (.*?).error/error: $1; error/g;

print FILE localtime() . "\n";
print FILE "$nick: [ $url ] $output\n\n";
close FILE;

if($show_url) {
  print "$nick: [ $url ] $output\n";
} else {
  print "$nick: $output\n";
}

sub pretty {
  my $code = join '', @_;
  my $result;

  my $pid = open2(\*IN, \*OUT, 'astyle -xUpf');
  print OUT "$code\n";
  close OUT;
  while(my $line = <IN>) {
    $result .= $line;
  }
  close IN;
  waitpid($pid, 0);
  return $result;
}

