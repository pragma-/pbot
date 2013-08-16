#!/usr/bin/perl

use warnings;
use strict;

use Text::Balanced qw(extract_codeblock extract_delimited);

my $code = join ' ', @ARGV;
my $output;

$code =~ s/#include <([^>]+)>/\n#include <$1>\n/g;
$code =~ s/#([^ ]+) (.*?)\\n/\n#$1 $2\n/g;
$code =~ s/#([\w\d_]+)\\n/\n#$1\n/g;

my $precode = $code;
$code = '';

my $has_main = 0;

my $prelude = '';
$prelude = "$1$2" if $precode =~ s/^\s*(#.*)(#.*?[>\n])//s;

my $preprecode = $precode;

while($preprecode =~ s/([ a-zA-Z0-9\_\*\[\]]+)\s+([a-zA-Z0-9_*]+)\s*\((.*?)\)\s*({.*)//) {
  my ($ret, $ident, $params, $potential_body) = ($1, $2, $3, $4);

  $ret =~ s/^\s+//;
  $ret =~ s/\s+$//;

  if($ret eq "else" or $ret eq "while") {
    $precode .= "$ret $ident ($params) $potential_body";
    next;
  } else {
    $precode =~ s/([ a-zA-Z0-9\_\*\[\]]+)\s+([a-zA-Z0-9_*]+)\s*\((.*?)\)\s*({.*)//;
  }

  my @extract = extract_codeblock($potential_body, '{}');
  my $body;
  if(not defined $extract[0]) {
    $output = "error: unmatched brackets for function '$ident';\n";
    $body = $extract[1];
  } else {
    $body = $extract[0];
    $preprecode .= $extract[1];
    $precode .= $extract[1];
  }
  $code .= "$ret $ident($params) $body\n\n";
  $has_main = 1 if $ident eq 'main';
}

$precode =~ s/^\s+//;
$precode =~ s/\s+$//;

if(not $has_main) {
  $code = "$prelude\n\n$code\n\nint main(void) { $precode\n return 0;}\n";
} else {
  $code = "$prelude\n\n$precode\n\n$code\n";
}

$code =~ s/\|n/\n/g;
$code =~ s/^\s+//;
$code =~ s/\s+$//;

chdir "$ENV{HOME}/blackshell/msmud/babel-buster/code" or die "Could not chdir: $!";

open my $fh, '>', 'code.c' or die "Could not write code: $!";
print $fh $code;
close $fh;

$output = `./c2e 2>/dev/null code.c` if not defined $output;

if(not $has_main) {
  $output =~ s/Let main be a function returning an integer.  It is called with no arguments.  To perform the function, //;
  $output =~ s/\s*(Then|Next,|Continuing on, we next)?\s*return 0.//i;
  $output =~ s/^(.)/uc $1/e;
}

$output =~ s/"a"/a/g;
$output =~ s/whose initial value is/with value being/g;
$output =~ s/each element of which is a(n?)/of type a$1/g;
$output =~ s/\s+s\s*$//g;
$output =~ s/variable/object/g;
$output =~ s/of type a character/of type char/g;
$output =~ s/of type an integer/of type int/g;
$output =~ s/to a character/to char/g;
$output =~ s/to an integer/to int/g;
$output =~ s/with no arguments returning/with unspecified arguments returning/g;
$output =~ s/with argument a void/with no arguments/g;
$output =~ s/\s*After that,\s*$//;
$output =~s/as long as zero does not equal 1/while the condition is true/g;

$output =~ s/\s+/ /;
if($output eq " ") {
  print "Does not compute.  I only know about C89 and valid code.\n";
  exit;
}

print "$output\n";
