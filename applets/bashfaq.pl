#!/usr/bin/perl -w

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

my $query = "@ARGV";
print "Usage: faq <id or search text>\n" and exit 0 if not length $query;

my (%faq, $match);

open(FILE, "< bashfaq.txt") or print "Can't open Bash FAQ: $!" and exit 1;

foreach my $line (<FILE>) {
    if ($line =~ /^(\d+)\.\s+(.*)$/) {
        $faq{$1} = $2;
    }
}

close FILE;

if ($query =~ / >/) {
    $rcpt = $query;
    $query =~ s/ +>.*$//;
    $rcpt =~ s/^.* > *//;
}

if (exists $faq{$query}) {
    $match = $query;
} else {
    foreach my $key (keys %faq) {
        if ($faq{$key} =~ /\Q$query\E/i) {
            $match = $key;
            last;
        }
    }
}

if ($match) {
    my $id = sprintf "%03d", $match;
    print "$rcpt: " if $rcpt;
    print "https://mywiki.wooledge.org/BashFAQ/$id -- $faq{$match}\n";
} else {
    print "No matches found at https://mywiki.wooledge.org/BashFAQ\n";
}
