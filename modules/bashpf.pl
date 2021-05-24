#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

my $query = "@ARGV";
print "Usage: pf <id or search text>\n" and exit 0 if not length $query;

my (%pf, $match);

open(FILE, "< bashpf.txt") or print "Can't open Bash Pitfalls: $!" and exit 1;

foreach my $line (<FILE>) {
    if ($line =~ /^(\d+)\.\s+(.*)$/) {
        $pf{$1} = $2;
    }
}

close FILE;

if ($query =~ / >/) {
    $rcpt = $query;
    $query =~ s/ +>.*$//;
    $rcpt =~ s/^.* > *//;
}

if (exists $pf{$query}) {
    $match = $query;
} else {
    foreach my $key (keys %pf) {
        if ($pf{$key} =~ /$query/i) {
            $match = $key;
            last;
        }
    }
}

if ($match) {
    my $id = "pf$match";
    print "$rcpt: " if $rcpt;
    print "https://mywiki.wooledge.org/BashPitfalls#$id -- Don't do this! -- $pf{$match}\n";
} else {
    print "No matches found at https://mywiki.wooledge.org/BashPitfalls\n";
}
