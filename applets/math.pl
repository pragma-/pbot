#!/usr/bin/perl -w

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# Quick and dirty by :pragma

use Math::Units qw(convert);

my ($arguments, $response, $invalid, @conversion);

my @valid_keywords = (
    'sin',   'cos',     'tan',     'atan',  'exp',   'int',  'hex',  'oct',  'log', 'sqrt',
    'floor', 'ceil',    'asin',    'acos',  'log10', 'sinh', 'cosh', 'tanh', 'abs',
    'pi',    'deg2rad', 'rad2deg', 'atan2', 'cbrt'
);

if ($#ARGV < 0) {
    print "Dumbass.\n";
    exit 0;
}

$arguments = join(' ', @ARGV);

my $raw = 0;
if ($arguments =~ s/^-raw\s+//) {
    $raw = 1;
}

my $orig_arguments = $arguments;

$arguments =~ s/(the )*(ultimate )*answer.*question of life(,? the universe,? and everything)?\s?/42/gi;
$arguments =~ s/(the )*(ultimate )*meaning of (life|existence|everything)?/42/gi;
$arguments =~ s/baker'?s dozen/13/g;

if ($arguments =~ s/(\d+\s?)([^ ]+)\s+to\s+([^ ]+)\s*$/$1/) { @conversion = ($2, $3); }

if ($arguments =~ m/([\$`\|{}"'#@=?\[\]])/ or $arguments =~ m/(~~)/) { $invalid = $1; }
else {
    while ($arguments =~ /([a-zA-Z0-9]+)/g) {
        my $keyword = $1;
        next if $keyword =~ m/^[0-9]+$/;
        $invalid = $keyword and last if not grep { /^$keyword$/ } @valid_keywords;
    }
}

if ($invalid) {
    print "Illegal symbol '$invalid' in equation\n";
    exit 1;
}

$response = eval("use POSIX qw/ceil floor/; use Math::Trig; use Math::Complex;" . $arguments);

if ($@) {
    my $error = $@;
    $error =~ s/[\n\r]+//g;
    $error =~ s/ at \(eval \d+\) line \d+.//;
    $error =~ s/ at EOF$//;
    $error =~ s/Died at .*//;
    print $error;
    exit 1;
}

if (@conversion) {
    my $result = eval { convert($response, $conversion[0], $conversion[1]); };
    if ($@) {
        print "Unknown conversion from $conversion[0] to $conversion[1]. Units are case-sensitive (Hz, not hz).\n";
        exit 1;
    }
    $response = "$result $conversion[1]";
}

if ($raw) {
    print "$response\n";
} else {
    print "$orig_arguments = $response\n";
}
