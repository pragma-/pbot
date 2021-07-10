#!/usr/bin/env perl

# File: wiktionary.pl
#
# Purpose: Queries Wiktionary website.
#
# This is a rough first draft. There are more parts of the definitions
# to process.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

use Cache::FileCache;
use Encode;
use Getopt::Long qw/GetOptionsFromArray/;
use JSON;

binmode(STDOUT, ":utf8");

@ARGV = map { decode('UTF-8', $_, 1) } @ARGV;

my $usage = "Usage: wiktionary <term> [-e] [-p] [-l <language>] [-n <entry number>]; -e for etymology; -p for pronunciation\n";

my ($term, $lang, $section, $num, $all, $unique, $opt_e, $opt_p);

{
    my $opt_error;
    local $SIG{__WARN__} = sub {
        $opt_error = shift;
        chomp $opt_error;
    };

    Getopt::Long::Configure("bundling_override");

    GetOptionsFromArray(
        \@ARGV,
        'lang|l=s'    => \$lang,
        'section|s=s' => \$section,
        'num|n=i'     => \$num,
        'all|a'       => \$all,
        'unique|u'    => \$unique,
        'p'           => \$opt_p,
        'e'           => \$opt_e,
    );

    if ($opt_error) {
        print "$opt_error: $usage\n";
        exit 1;
    }

    $term = "@ARGV";

    if (not length $term) {
        print $usage;
        exit 1;
    }
}

$lang    //= 'English';
$section //= 'definitions';

if ($opt_p and $opt_e) {
    print "Options -e and -p cannot be used together.\n";
    exit 1;
}

if ($opt_p) {
    $unique = 1 unless defined $num;
    $section = 'pronunciations';
}

if ($opt_e) {
    $unique = 1 unless defined $num;
    $section = 'etymology';
}

$num //= 1;

my $cache = Cache::FileCache->new({ namespace => 'wiktionary', default_expires_in => '1 week' });

my $cache_id = "$term $lang";

my $entries = $cache->get($cache_id);

if (not defined $entries) {
    my $json = `python3 wiktionary.py \Q$term\E \Q$lang\E`;
    $entries = decode_json $json;
    $cache->set($cache_id, $entries);
}

my @valid_sections = qw/definitions etymology pronunciations/;

if (not grep { $_ eq $section } @valid_sections) {
    print "Unknown section `$section`. Available sections are: " . join(', ', sort @valid_sections) . "\n";
    exit 1;
}

my $entry_count = @$entries;

my $entries_text = $section;

if ($entry_count == 1) {
    $entries_text =~ s/s$//;
} else {
    $entries_text =~ s/y$/ies/;
}

if ($num > $entry_count) {
    my $are = $entry_count == 1 ? 'is' : 'are';
    print "No such entry $num. There $are $entry_count $entries_text for `$term`.\n";
    exit 1;
}

if ($unique) {
    print "$entry_count $entries_text for $term (showing unique entries):\n\n";
} else {
    print "$entry_count $entries_text for $term:\n\n";
}

my $start = 0;

if ($num <= 0 or $all or $unique) {
    $num = $entry_count;
} else {
    $start = $num - 1;
}

my @results;

for (my $i = $start; $i < $num; $i++) {
    my $entry = $entries->[$i];

    if ($section eq 'etymology') {
        my $ety = $entry->{etymology};
        chomp $ety;

        if (not length $ety or $ety =~ /This etymology is missing or incomplete./) {
            $ety = 'N/A';
        }

        push @results, $ety;
    }

    elsif ($section eq 'pronunciations') {
        if (exists $entry->{pronunciations}
                and exists $entry->{pronunciations}->{text})
        {
            my $text = join '; ', @{$entry->{pronunciations}->{text}};

            $text = 'N/A' if not length $text;

            push @results, $text;
        } else {
            push @results, 'N/A';
        }
    }

    elsif ($section eq 'definitions') {
        my $text;

        foreach my $definition (@{$entry->{definitions}}) {
            $text .= "$definition->{partOfSpeech}) ";
            $text .= join("\n\n", @{$definition->{text}}) . "\n\n";

            if (@{$definition->{examples}}) {
                $text .= "examples:\n\n";
                $text .= join("\n\n", @{$definition->{examples}}) . "\n\n";
            }

        }

        push @results, $text;
    }
}

if ($unique) {
    my %uniq;

    my $i = 0;
    foreach my $result (@results) {
        $i++;
        next if not $result or $result eq 'N/A';
        $uniq{$result} = $i unless exists $uniq{$result};
    }

    if (not keys %uniq) {
        print "No $section available for $term.\n";
        exit;
    }

    foreach my $key (sort { $uniq{$a} <=> $uniq{$b} } keys %uniq) {
        print "$uniq{$key}) $key\n\n";
    }

    exit;
}

my $i = @results == 1 ? $num - 1 : 0;
foreach my $result (@results) {
    $i++;
    next if not $result;
    print "$i) $result\n\n";
}
