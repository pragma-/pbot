#!/usr/bin/env perl

package SplitLine;

use 5.020;

use warnings;
use strict;

use feature 'signatures';
no warnings 'experimental::signatures';

use parent qw(Exporter);
our @EXPORT = qw(split_line);

# splits line into quoted arguments while preserving quotes.
# a string is considered quoted only if they are surrounded by
# whitespace or json separators.
# handles unbalanced quotes gracefully by treating them as
# part of the argument they were found within.
sub split_line ($line, %opts) {
    my %default_opts = (
        strip_quotes => 0,
        keep_spaces => 0,
        preserve_escapes => 1,
    );

    %opts = (%default_opts, %opts);

    my @chars = split //, $line;

    my @args;
    my $escaped = 0;
    my $quote;
    my $token = '';
    my $last_token = '';
    my $ch = ' ';
    my $last_ch;
    my $next_ch;
    my $i = 0;
    my $pos = 0;
    my $ignore_quote = 0;
    my $spaces = 0;

    while (1) {
        $last_ch = $ch;

        if ($i >= @chars) {
            if (defined $quote) {
                # reached end, but unbalanced quote... reset to beginning of quote and ignore it
                $i = $pos;
                $ignore_quote = 1;
                $quote = undef;
                $last_ch = ' ';
                $token = $last_token;
            } else {
                # add final token and exit
                push @args, $token if length $token;
                last;
            }
        }

        $ch = $chars[$i++];
        $next_ch = $chars[$i];

        my $dquote = $quote // 'undef';
        $spaces = 0 if $ch ne ' ';

        if ($escaped) {
            if ($opts{preserve_escapes}) {
                $token .= "\\$ch";
            } else {
                $token .= $ch;
            }
            $escaped = 0;
            next;
        }

        if ($ch eq '\\') {
            $escaped = 1;
            next;
        }

        if (defined $quote) {
            if ($ch eq $quote and (not defined $next_ch or $next_ch =~ /[\s,:;})\[\].+=]/)) {
                # closing quote
                $token .= $ch unless $opts{strip_quotes};
                push @args, $token;
                $quote = undef;
                $token = '';
            } else {
                # still within quoted argument
                $token .= $ch;
            }
            next;
        }

        if (($last_ch =~ /[\s:{(\[.+=]/) and not defined $quote and ($ch eq "'" or $ch eq '"')) {
            if ($ignore_quote) {
                # treat unbalanced quote as part of this argument
                $token .= $ch;
                $ignore_quote = 0;
            } else {
                # begin potential quoted argument
                $pos = $i - 1;
                $quote = $ch;
                $last_token = $token;
                $token .= $ch unless $opts{strip_quotes};
            }
            next;
        }

        if ($ch eq ' ') {
            if (++$spaces > 1 and $opts{keep_spaces}) {
                $token .= $ch;
                next;
            } else {
                push @args, $token if length $token;
                $token = '';
                next;
            }
        }

        $token .= $ch;
    }

    return @args;
}

1;
