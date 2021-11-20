#!/usr/bin/perl -w

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# quick and dirty by :pragma

use strict;
use LWP::Simple;

my ($result, $manpage, $section, $text, $name, $includes, $prototype, $description);

if ($#ARGV < 0) {
    print "Which command would you like information about?\n";
    die;
}

$manpage = join("+", @ARGV);
$section = "3";

if ($manpage =~ m/([0-9]+)\+(.*)/) {
    $section = $1;
    $manpage = $2;
}

if (!($section == 2 || $section == 3)) {
    print "I'm only interested in displaying information about sections 2 or 3.\n";
    exit 0;
}

$text = get("http://node1.yo-linux.com/cgi-bin/man2html?cgi_command=$manpage&cgi_section=$section&cgi_keyword=m");

$manpage =~ s/\+/ /g;

if ($text =~ m/No.*?entry\sfor(.*)/i) {
    print "No entry for$1";
    die;
}

#$text =~ m/<\/A>.*?NAME\n/gs;

if ($text =~ m/(.*?)SYNOPSIS/gsi) { $name = $1; }

my $i = 0;
while ($text =~ m/#include &lt;(.*?)&gt;/gsi) {
    $includes .= ", " if ($i > 0);
    $includes .= "$1";
    $i++;
}

$prototype = "$1 $2$manpage($3);" if ($text =~ m/SYNOPSIS.*^\s+(.*?)\s+(\*?)$manpage\s*\((.*?)\)\;?\n.*DESC/ms);

$description = "$manpage $1" if ($text =~ m/DESCRIPTION.*?$manpage(.*?)\./gsi);
$description =~ s/\-\s+//g;

if (not defined $prototype) {
    print "No prototype found for $manpage";
    exit 0;
}

$result = "Includes: $includes - " if (defined $includes);
$result .= "$prototype" if (defined $prototype);

$result =~ s/^\s+//g;
$result =~ s/\s+/ /g;
$result =~ s/\n//g;
$result =~ s/\r//g;
$result =~ s/\<A HREF.*?>//g;
$result =~ s/\<\/A>//g;
$result =~ s/&quot;//g;

print "$result - http://www.iso-9899.info/man?$manpage";
