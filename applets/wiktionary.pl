#!/usr/bin/env perl

# File: wiktionary.pl
#
# Purpose: Queries Wiktionary website.
#
# This is a rough first draft. There are more parts of the definitions
# to process.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

use Cache::FileCache;
use Encode;
use Getopt::Long qw/GetOptionsFromArray/;
use JSON;

sub flatten { map { ref eq 'ARRAY' ? flatten(@$_) : $_ } @_ }

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

$all //= 1;

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

my $cache_id = encode('UTF-8', "$term $lang");

my $entries = $cache->get($cache_id);

if (not defined $entries) {
    my $json = `python3 wiktionary.py \Q$term\E \Q$lang\E`;
    $entries = eval { decode_json $json };
    if ($@) {
        print "$json\n";
        print "$@\n";
        die;
    }
    $cache->set($cache_id, $entries);
}

if ($ENV{DEBUG}) {
    use Data::Dumper;
    print Dumper($entries), "\n";
}

my @valid_sections = qw/definitions etymology pronunciations participle/;

if (not grep { $_ eq $section } @valid_sections) {
    print "Unknown section `$section`. Available sections are: " . join(', ', sort @valid_sections) . "\n";
    exit 1;
}

my $entries_text = $section;

if (ref $entries eq 'HASH') {
    $entries_text =~ s/y$/ies/;
    print "No $entries_text for `$term`";

    if ($entries->{languages}->@*) {
        print " in $lang; try ", (join ', ', $entries->{languages}->@*);
    } else {
        print " found in any languages";
    }

    if ($entries->{disambig}->@*) {
        print "; see also: ", (join ', ', $entries->{disambig}->@*);
    }

    print "\n";
    exit;
}

my $total_entries_count = @$entries;

if ($total_entries_count == 0) {
    $entries_text =~ s/y$/ies/;
    print "No $entries_text for `$term`.\n";
    exit 1;
}

if ($num > $total_entries_count) {
    if ($total_entries_count == 1) {
        $entries_text =~ s/s$//;
    } else {
        $entries_text =~ s/y$/ies/;
    }

    my $are = $total_entries_count == 1 ? 'is' : 'are';
    print "No such entry $num. There $are $total_entries_count $entries_text for `$term`.\n";
    exit 1;
}

my $start = 0;

if ($num <= 0 or $all or $unique) {
    $num = $total_entries_count;
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

        push @results, $ety unless $ety eq 'N/A' and not $all;
    }

    elsif ($section eq 'pronunciations') {
        if (exists $entry->{pronunciations}
                and exists $entry->{pronunciations}->{text})
        {
            my $text = join '; ', @{$entry->{pronunciations}->{text}};

            $text = 'N/A' if not length $text;

            push @results, $text unless $text eq 'N/A' and not $all;
        } else {
            push @results, 'N/A';
        }
    }

    elsif ($section eq 'definitions') {
        my $text;

        foreach my $definition (@{$entry->{definitions}}) {
            $text .= "$definition->{partOfSpeech}) ";

            my $entry = -1;

            foreach my $def (flatten @{$definition->{text}}) {
                $def =~ s/^#//;
                $text .= "$def\n";

                if (@{$definition->{examples}}) {
                    foreach my $example (@{$definition->{examples}}) {
                        if ($example->{index} == $entry) {
                            $text .= "  ($example->{text})\n";
                        }
                    }
                }

                $entry++;
                $text .= "\n";
            }
        }

        push @results, $text if length $text;
    }
}

if (not @results) {
    $entries_text =~ s/y$/ies/;
    print "There are no $entries_text for `$term`.\n";
    exit 1;
}

if ($unique) {
    my %uniq;

    my $i = 0;
    foreach my $result (@results) {
        $i++;
        next if not $result or $result eq 'N/A';
        $uniq{$result} .= "$i,";
    }

    if (not keys %uniq) {
        print "No $section available for $term.\n";
        exit;
    }

    no warnings; # sorting "1,2,3" numerically
    foreach my $key (sort { $uniq{$a} <=> $uniq{$b} } keys %uniq) {
        my ($q, $p);
        $uniq{$key} =~ s/,$//;
        $uniq{$key} =~ s/\b(\d+)(?{$q=$1+1})(?:,(??{$q})\b(?{$p=$q++})){2,}/$1-$p/g;
        print "$uniq{$key}) $key\n\n";
    }
    use warnings;

    exit;
}

my $i = @results == 1 ? $num - 1 : 0;
foreach my $result (@results) {
    $i++;
    next if not $result;
    print "$i) $result\n";
}
