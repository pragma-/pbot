#!/usr/bin/perl -w

# SPDX-FileCopyrightText: 2005-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

my $match   = 1;
my $matches = 0;
my $found   = 0;

print "Usage: faq [match #] <search regex>\n" and exit 0 if not defined $ARGV[0];

my $query = join(".*?", @ARGV);
$query =~ s/\s+/.*?/g;

$query =~ s/\+/\\+/g;
$query =~ s/[^\.]\*/\\*/g;
$query =~ s/^\*/\\*/g;
$query =~ s/\[/\\[/g;
$query =~ s/\]/\\]/g;

if ($query =~ /^(\d+)\.\*\?/) {
    $match = $1;
    $query =~ s/^\d+\.\*\?//;
}

open(FILE, "< cfaq-questions.html") or print "Can't open cfaq-questions.html: $!" and exit 1;
my @contents = <FILE>;
close(FILE);

my ($heading, $question_full, $question_link, $question_number, $question_text, $result);

foreach my $line (@contents) {
    if ($line =~ m/^<H4>(.*?)<\/H4>/) {
        $heading = $1;
        next;
    }

    if ($line =~ m/<p><a href="(.*?)" rel=subdocument>(.*?)<\/a>/) {
        ($question_link, $question_number) = ($1, $2);

        if (defined $question_full) {
            if ($question_full =~ m/$query/i) {
                $matches++;
                $found = 1;
                if ($match == $matches) {
                    $question_text =~ s/\s+/ /g;
                    $result = $question_text;
                }
            }
        }

        $question_full = "$question_number $question_link ";
        $question_text = "http://c-faq.com/$question_link - $heading, $question_number: ";
        next;
    }

    if (defined $question_full) {
        $line =~ s/[\n\r]/ /g;
        $line =~ s/(<pre>|<\/pre>|<TT>|<\/TT>|<\/a>|<br>)//g;
        $line =~ s/<a href=".*?">//g;
        $line =~ s/&nbsp;/ /g;
        $line =~ s/&amp;/&/g;
        $line =~ s/&lt;/</g;
        $line =~ s/&gt;/>/g;

        $question_full .= $line;
        $question_text .= $line;
    }
}

if ($found == 1) {
    print "But there are $matches results...\n" and exit if ($match > $matches);

    print "$matches results, displaying #$match: " if ($matches > 1);

    print "$result\n";
} else {
    $query =~ s/\.\*\?/ /g;
    print "No FAQs match $query\n";
}
