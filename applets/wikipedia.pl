#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2009-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use strict;
use WWW::Wikipedia;
use HTML::Parse;
use HTML::FormatText;

my $term = join(' ', @ARGV);

if (not $term) {
    print "Usage: !wikipedia <term>\n";
    exit;
}

my $wiki  = WWW::Wikipedia->new(language => 'en');
my $entry = $wiki->search($term);

if ($entry) {
    my $text = $entry->text();

    if ($text) {
        $text =~ s/\{\{.*?}}//msg;
        $text =~ s/\[\[//g;
        $text =~ s/\]\]//g;
        $text =~ s/<ref>.*?<\/ref>//g;
        $text =~ s/__[A-Z]+__//g;
        $text =~ s/\s+\(\)//msg;
        $text = HTML::FormatText->new->format(parse_html($text));
        print $text;
    } else {
        print "Specific entry not found, see also: ";
        my $semi = "";
        foreach ($entry->related()) { print "$semi$_"; $semi = "; "; }
    }
} else {
    print qq("$term" not found in Wikipedia\n);
}

