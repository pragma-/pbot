#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
        if ($faq{$key} =~ /$query/i) {
            $match = $key;
            last;
        }
    }
}

if ($match) {
    my $id = sprintf "%03d", $match;
    my $output = "https://mywiki.wooledge.org/BashFAQ/$id -- $faq{$match}";
    print "$rcpt: " if $rcpt;
    print "$output\n";
} else {
    print "No matches found at https://mywiki.wooledge.org/BashFAQ\n";
}
