#!/usr/bin/env perl

use warnings;
use strict;

use Time::HiRes qw/gettimeofday/;
use Time::Duration qw/duration/;
use Fcntl qw(:flock);

use IRCColors;
use QStatskeeper;

my $CJEOPARDY_FILE    = 'cjeopardy.txt';

sub encode { my $str = shift; $str =~ s/\\(.)/{sprintf "\\%03d", ord($1)}/ge; return $str; }
sub decode { my $str = shift; $str =~ s/\\(\d{3})/{"\\" . chr($1)}/ge; return $str }

my $args = join(' ', @ARGV);
my ($question_index) = $args =~ m/^(\d+)/;

if (not $question_index or $question_index < 0) {
  print "Usage: show <question id>\n";
  exit;
}

my @questions;
open my $fh, "<", $CJEOPARDY_FILE or die "Could not open $CJEOPARDY_FILE: $!";
@questions = <$fh>;
close $fh;

if ($question_index - 1 > scalar @questions - 1) {
  print "Question id $question_index is out of range (1 - " . (scalar @questions) . ").\n";
  exit;
}

my $question = $questions[$question_index - 1];

my ($q, $a) = map { decode $_ } split /\|/, encode($question), 2;
chomp $q;
chomp $a;

$q =~ s/\\\|/|/g;
$q =~ s/^(\d+)\) \[.*?\]\s+/$1) /;

$q =~ s/\b(this keyword|this operator|this behavior|this preprocessing directive|this escape sequence|this mode|this function specifier|this function|this macro|this predefined macro|this header|this pragma|this fprintf length modifier|this storage duration|this type qualifier|this type|this value|this operand|this many|this|these)\b/$color{bold}$1$color{reset}/gi;

print "$color{cyan}Showing question:$color{reset} $q\n";
