#!/usr/bin/perl

use warnings;
use strict;

use LWP::UserAgent;
use URI::Escape;
use HTML::Entities;
use HTML::Parse;
use HTML::FormatText;

if($#ARGV <= 0) {
  print "Usage: $0 <nick> <code>\n";
  exit 0;
}

my $nick = shift @ARGV;
my $code = join ' ', @ARGV;

my $lang = "C";
$lang = $1 if $code =~ s/-lang=([^\b\s]+)//i;

my @languages = qw/C C++ D Haskell Lua OCaml PHP Perl Python Ruby Scheme Tcl/;

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

if(($lang eq "C" or $lang eq "C++") and not $code =~ m/\w+ main\s?\([^)]+\)\s?{/) {
  $code = "int main(void) { $code ; return 0; }";
}

my $escaped_code = uri_escape($code, "\0-\377");

my %post = ( 'lang' => $lang, 'code' => $code, 'private' => 'True', 'run' => 'True', 'submit' => 'Submit' );

my $response = $ua->post("http://codepad.org", \%post);

if(not $response->is_success) {
  print "There was an error compiling the code.\n";
  die $response->status_line;
}

my $text = $response->decoded_content;
my $redirect = $response->request->uri;

my $output;

$text =~ s/<a style="" name="output-line-\d+">\d+<\/a>//g;

if($text =~ /<span class="heading">Output:<\/span>.+?<div class="code">(.*)<\/div>.+?<\/table>/si) {
  $output = "$1";
} else {
  $output = "<pre>No output.</pre>";
}

$output = decode_entities($output);
$output = HTML::FormatText->new->format(parse_html($output));

$output =~ s/[\n\r]/ /g;
$output =~ s/\s+/ /g;
$output =~ s/^\s+//g;
$output =~ s/\s+$//g;

print "$nick: $output\n";
