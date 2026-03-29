#!/usr/bin/perl

# SPDX-FileCopyrightText: 2009-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use v5.26;
use warnings;

use feature 'signatures';
no warnings 'experimental::signatures';

use lib '.';
use QuoteDB;
use Getopt::Long 'GetOptionsFromArray';

my $usage = 'Usage: quote [text] [-a <author>] [-c] [-h] [-i] -- Use -c to show remaining/total count; -h to hide author; -i to show id';

my ($text, $author, $channel, $show_count, $hide_author, $show_id);

$channel = shift @ARGV;

if (not defined $channel) {
    print "Must have channel as first argument.\n";
    exit 1;
}

{
    my $opt_error;
    local $SIG{__WARN__} = sub {
        $opt_error = shift;
        chomp $opt_error;
    };

    Getopt::Long::Configure('bundling_override');

    GetOptionsFromArray(
        \@ARGV,
        'author|a=s'    => \$author,
        'count|c'       => \$show_count,
        'hide|h'        => \$hide_author,
        'id|i'          => \$show_id,
    );

    $text = "@ARGV";

    if ($opt_error) {
        print "$opt_error: $usage\n";
        exit 1;
    }

    if (!length $text && !length $author) {
        print "$usage\n";
        exit 1;
    }
}

my $db = QuoteDB->new();

$db->begin();

my $quote = $db->get_random_quote($channel, $text, $author);

if (!defined $quote) {
    print "No quote found.\n";
} else {
    if ($show_count) {
        my ($total, $remaining) = $db->count_random_quote($channel, $text, $author);

        if (defined $total && $total > 0) {
            $total = $total->{'COUNT(*)'};
            $remaining = $total - $remaining->{'COUNT(*)'};
            print "$remaining/$total ";
        }
    }

    if ($show_id) {
        print "$quote->{id}: ";
    }

    if ($hide_author) {
        print "$quote->{text}\n";
    } else {
        print "$quote->{text} -- $quote->{author}\n";
    }
}

$db->end();
