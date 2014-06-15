#!/usr/bin/perl

use strict;
use warnings;

use Parse::RecDescent;
use Getopt::Std;
use Data::Dumper;

# todo: 1. the entire syntax for pointers to functions.
# 2. preprocessor directives. (getting there)
# So, the problem with handling CPP directives is when they
# interrupt something. I'm open to ideas. 
# 4. functions to handle the nesting levels (ordinal number generator and CPP stack)
# 6. change returns to prints where appropriate.

our ($opt_T, $opt_t, $opt_o, $opt_P);
getopts('TPto:'); 

if ($opt_T ) {
  $::RD_TRACE = 1;
} else {
  undef $::RD_TRACE  ; 
}

$::RD_HINT = 1;
$Parse::RecDescent::skip = '\s*'; 

# This may be necessary..
# $::RD_AUTOACTION = q { [@item] };

my $parser;

if($opt_P or !eval { require PCGrammar }) {
  precompile_grammar();
  require PCGrammar;
}

$parser = PCGrammar->new() or die "Bad grammar!\n";

if ($opt_o) { 
  open(OUTFILE, ">>$opt_o"); 
  *STDOUT = *OUTFILE{IO}; 
}

my $text = "";
foreach my $arg (@ARGV) { 
  print STDERR "Opening file $arg\n";

  open(CFILE, "$arg") or die "Could not open $arg.\n";
  local $/;
  $text = <CFILE>;
  close(CFILE);

  print STDERR "parsing...\n"; 

  # for debugging...
  if ($opt_t) { 
    $::RD_TRACE = 1;
  } else {
    undef $::RD_TRACE;
  } 

  defined $parser->startrule(\$text) or die "Bad text!\n$text\n";
}

$text =~ s/\s+//g;
print "\n[$text]\n" if length $text;

sub precompile_grammar {
  print STDERR "Precompiling grammar...\n";
  open GRAMMAR, 'CGrammar.pm' or die "Could not open CGrammar.pm: $!";
  local $/;
  my $grammar = <GRAMMAR>;
  close GRAMMAR;

  Parse::RecDescent->Precompile($grammar, "PCGrammar") or die "Could not precompile: $!";
}
