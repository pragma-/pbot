#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2010-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

use Getopt::Long qw/GetOptionsFromArray/;
use Encode;

my %standards = (
    C99 => 'n1256.out',
    C11 => 'n1570.out',
    C23 => 'n3220.out',
);

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

@ARGV = map { decode('UTF-8', $_, 1) } @ARGV;

my ($std, $search, $section, $paragraph, $debug);
my ($match, $list_only, $match_text);

{
    my $opt_error;
    local $SIG{__WARN__} = sub {
        $opt_error = shift;
        chomp $opt_error;
    };

    Getopt::Long::Configure("bundling_override");

    GetOptionsFromArray(
        \@ARGV,
        'std=s'       => \$std,
        'section|s=s' => \$section,
        'num|n=i'     => \$match,
        'text|t=s'    => \$match_text,
        'list|l'      => \$list_only,
        'debug|d=i'   => \$debug,
    );

    $std       //= 'C99';
    $section   //= '';
    $match     //= 1;
    $list_only //= 0;
    $debug     //= 0;

    $std = uc $std;

    if (not exists $standards{$std}) {
        print "Invalid -std=$std selected. Valid -std= values are: ", join(', ', sort keys %standards), "\n";
        exit 1;
    }

    my $usage = "Usage: $std [-list] [-n#] [-section <section>] [search text] [-text <regex>] -- `section` must be in the form of `X.Y[pZ]` where `X` and `Y` are section/chapter and, optionally, `pZ` is paragraph. If both `section` and `search text` are specified, then the search space will be within the specified section. Use `-n <n>` to skip to the nth match. To list only the section numbers containing 'search text', add -list. To display specific text, use `-text <regex>`.\n";

    if ($opt_error) {
        print "$opt_error: $usage\n";
        exit 1;
    }

    $search = "@ARGV";

    if (!length $section && !length $search) {
        print $usage;
        exit 1;
    }
}

# for paragraphs
use constant {
    USER_SPECIFIED    => 1,
    RESULTS_SPECIFIED => 2,
};

my $section_specified   = length $section ? 1 : 0;
my $paragraph_specified = 0;

if ($search =~ s/\b([A-Z0-9]+\.[0-9.p]*)//i) {
    $section = $1;

    if ($section =~ s/p(\d+)//i) {
        $paragraph           = $1;
        $paragraph_specified = USER_SPECIFIED;
    } else {
        $paragraph = 1;
    }

    $section_specified = 1;
}

# add trailing dot if missing
if ($section =~ /^[A-Z0-9]+$/i) {
    $section .= '.';
}

$search =~ s/^\s+//;
$search =~ s/\s+$//;

if (not length $section) {
    $section   = "1.";
    $paragraph = 1;
}

if ($list_only and not length $search) {
    print "You must specify some search text to use with -list.\n";
    exit 1;
}

open FH, "<:encoding(UTF-8)", $standards{$std} or die "Could not open $standards{$std}: $!";
my @contents = <FH>;
close FH;

my $text = join '', @contents;
$text =~ s/\r//g;

my $std_name = $standards{$std};
$std_name =~ s/(.*)\..*$/$1/;

my $result;
my $found_section       = "";
my $found_section_title = "";
my $section_title;
my $found_paragraph;
my $found   = 0;
my $matches = 0;
my $this_section;
my $comma = "";

if ($list_only) { $result = "Sections containing '$search':\n    "; }

my $qsearch = quotemeta $search;
$qsearch =~ s/\\ / /g;
$qsearch =~ s/\s+/\\s+/g;

while ($text =~ m/^([0-9A-Z]+\.[0-9.]*)/msgi) {
    $this_section = $1;

    print "----------------------------------\n" if $debug >= 2;
    print "Processing section [$this_section]\n" if $debug;

    if ($section_specified and $this_section !~ m/^\Q$section/i) {
        print "No section match, skipping.\n" if $debug >= 4;
        next;
    }

    my $section_text;

    if ($text =~ /(.*?)^(?=(?!Footnote)[0-9A-Z]+\.)/msg) {
        $section_text = $1;
    } else {
        print "No section text, end of file marker found.\n" if $debug >= 4;
        last;
    }

    if ($section =~ /Footnote/i) {
        $section_text =~ s/^Footnote.*//msi;
        $section_text =~ s/^\d.*//ms;
        $section_text = $this_section . $section_text;
    } elsif ($section_text =~ m/(.*?)$/msg) {
        $section_title = $1 if length $1;
        $section_title =~ s/^\s+//;
        $section_title =~ s/\s+$//;
    }

    print "$this_section [$section_title]\n" if $debug >= 2;

    while ($section_text =~ m/^(\d+)\s(.*?)^(?=\d)/msgic or $section_text =~ m/^(\d+)\s(.*)/msgi) {
        my $p = $1;
        my $t = $2;

        print "paragraph $p: [$t]\n" if $debug >= 3;

        if ($paragraph_specified == USER_SPECIFIED and not length $search and $p == $paragraph) {
            $result              = $t if not $found;
            $found_paragraph     = $p;
            $found_section       = $this_section;
            $found_section_title = $section_title;
            $found               = 1;
            last;
        }

        if (length $search) {
            eval {
                if ($t =~ m/\b$qsearch\b/mis or $section_title =~ m/\b$qsearch\b/mis) {
                    $matches++;
                    if ($matches >= $match) {
                        if ($list_only) {
                            $result .= sprintf("%s%-15s", $comma, $this_section . "p" . $p);
                            $result .= " $section_title";
                            $comma = ",\n    ";
                        } else {
                            if (not $found) {
                                $result              = $t;
                                $found_section       = $this_section;
                                $found_section_title = $section_title;
                                $found_paragraph     = $p;
                                $paragraph_specified = RESULTS_SPECIFIED;
                            }
                            $found = 1;
                        }
                    }
                }
            };

            if (my $err = $@) {
                $err =~ s/.* at .*$//;
                print "Error in search regex: $err\n";
                exit 0;
            }
        }
    }

    last if $found && $paragraph_specified == USER_SPECIFIED;

    if ($paragraph_specified == USER_SPECIFIED) {
        if (length $search) {
            print "No such text '$search' in paragraph $paragraph of section $section of $std_name.\n";
        } else {
            print "No such paragraph $paragraph in section $section of $std_name.\n";
        }
        exit 1;
    }

    if (defined $section_specified and not length $search) {
        $found               = 1;
        $found_section       = $this_section;
        $found_section_title = $section_title;
        $found_paragraph     = $paragraph;
        $result              = $section_text;
        last;
    }
}

if (not $found and $comma eq "") {
    $search =~ s/\\s\+/ /g;
    if (length $search) {
        print "No such text '$search' found ";

        if ($section_specified) {
            print "within section '$section' ";
        }
    } else {
        print "No such section '$section' ";
    }
    print "in $std Draft Standard ($std_name).\n";
    exit 1;
}

$result =~ s/\Q$found_section_title// if length $found_section_title;
$result =~ s/^\s+//;
$result =~ s/\s+$//;

if ($matches > 1 and not $list_only) { print "Displaying $match of $matches matches: "; }

if ($comma eq "") {
    $found_section =~ s/Footnote/FOOTNOTE/;
    print "http://www.iso-9899.info/$std_name.html\#$found_section";
    print "p" . $found_paragraph if $paragraph_specified;
    print "\n\n";
    print "[", $found_section_title, "]\n\n" if length $found_section_title;
}

$result =~ s/\s*Constraints\s*$//;
$result =~ s/\s*Semantics\s*$//;
$result =~ s/\s*Description\s*$//;
$result =~ s/\s*Returns\s*$//;
$result =~ s/\s*Runtime-constraints\s*$//;
$result =~ s/\s*Recommended practice\s*$//;
$result =~ s/Footnote\.(\d)/Footnote $1/g;

if (length $match_text) {
    my $match_result = $result;
    $match_result =~ s/\s+/ /g;

    my $match = eval {
        my @matches = ($match_result =~ m/($match_text)/msp);
        if (@matches > 1) {
            shift @matches;
            @matches = grep { length $_ } @matches;
        }
        return [${^PREMATCH}, join (' ... ', @matches), ${^POSTMATCH}];
    };

    if ($@) {
        print "Error in -text option: $@\n";
        exit 1;
    }

    $result = '';

    if (length $match->[0]) {
        $result = '... ';
    }

    if (length $match->[1]) {
        $result .= $match->[1];
    } else {
        $result = "No text found for `$match_text`.";
    }

    if (length $match->[2]) {
        $result .= ' ...';
    }
}

print "$result\n";
