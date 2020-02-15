#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# quick and dirty

use warnings;
use strict;

use HTML::Entities;

my $STD = 'n1570.html';

my $text;

{
    local $/ = undef;
    open my $fh, "<", $STD or die "Could not open $STD: $!";
    $text = <$fh>;
    close $fh;
}

my $cfact_regex = qr/
                      (
                        \s+\S+\s+which\s+is.*?
                       |\s+\S+\s+which\s+expand.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*(EXAMPLE\s*|NOTE\s*)?)An?\s+[^.]+describes.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*(EXAMPLE\s*|NOTE\s*))An?\s+[^.]+is.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*)[^.]+shall.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*)If.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*)[^.]+is\s+named.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*)[^.]+is\s+known.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*)[^.]+are\s+known.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*)[^.]+is\s+called.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*)[^.]+are\s+called.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*)When.*?
                       |(?:\-\-\s+|\s+|<pre>\s*\d*\s*)The\s+\S+\s+function.*?
                      )
                      (?:\.(?!(\d|h))|<\/pre>)
                    /msx;

my @sections;
while ($text =~ /^<h3>(.*?)<\/h3>/mg) {
    my $section = $1;
    $section =~ s/[\[\]]//g;
    unshift @sections, [pos $text, $section];
}

while ($text =~ /$cfact_regex/gms) {
    my $fact = $1;
    next unless length $fact;

    $fact =~ s/[\n\r]/ /g;
    $fact =~ s/ +/ /g;
    $fact =~ s/^\.\s*//;
    $fact =~ s/^\s*--\s*//;
    $fact =~ s/^\d+\s*//;
    $fact =~ s/- ([a-z])/-$1/g;
    $fact =~ s/\s+\././g;
    $fact =~ s/^\s*<pre>\s*\d*\s*//;
    $fact =~ s/^\s*EXAMPLE\s*//;
    $fact =~ s/^\s*NOTE\s*//;
    $fact =~ s/^\s+//;
    $fact =~ s/\s+$//;

    my $section = '';
    foreach my $s (@sections) {
        if (pos $text >= $s->[0]) {
            $section = "[$s->[1]] ";
            last;
        }
    }

    $fact = decode_entities($fact);
    $fact =~ s/[a-z;,.]\K\d+\)//g;    # remove footnote markers

    print "$section$fact.\n";
}
