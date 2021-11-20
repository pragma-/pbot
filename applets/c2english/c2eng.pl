#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use strict;
use warnings;

use lib '.';

use Parse::RecDescent;
use Getopt::Std;

sub precompile_grammar {
    print STDERR "Precompiling grammar...\n";
    open GRAMMAR, 'CGrammar.pm' or die "Could not open CGrammar.pm: $!";
    local $/;
    my $grammar = <GRAMMAR>;
    close GRAMMAR;
    Parse::RecDescent->Precompile($grammar, "PCGrammar") or die "Could not precompile: $!";
}

sub flatten {
    map { ref eq 'ARRAY' ? flatten(@$_) : $_ } @_
}

sub isfalse {
    istrue($_[0], 'zero')
}

sub istrue {
    my @parts = split /(?<!,) and /, $_[0];
    my $truthy = defined $_[1] ? $_[1] : 'nonzero';
    my ($result, $and) = ('', '');
    foreach my $part (@parts) {
        $result .= $and;
        if($part !~ /(discard the result|result discarded|greater|less|equal|false$)/) {
            $result .= "$part is $truthy";
        } else {
            $result .= $part;
        }
        $and = ' and ';
    }
    $result =~ s/is $truthy and the result discarded/is evaluated and the result discarded/g;
    $result =~ s/is ((?:(?!evaluated).)+) and the result discarded/is evaluated to be $1 and the result discarded/g;
    return $result;
}

sub main {
    my ($opt_T, $opt_t, $opt_o, $opt_P);
    getopts('TPto:');

    if ($opt_T ) {
        $::RD_TRACE = 1;
    }

    $::RD_HINT = 1;
    $Parse::RecDescent::skip = '\s*';

    my $parser;

    if ($opt_P or !eval { require PCGrammar }) {
        precompile_grammar();
        require PCGrammar;
    }

    $parser = PCGrammar->new or die "Bad grammar!\n";

    if ($opt_o) {
        open(OUTFILE, ">>$opt_o");
        *STDOUT = *OUTFILE{IO};
    }

    my $text;

    foreach my $arg (@ARGV) {
        print STDERR "Opening file $arg\n";

        open(CFILE, "$arg") or die "Could not open $arg.\n";
        local $/;
        $text = <CFILE>;
        close(CFILE);

        print STDERR "parsing...\n";

        my $result = $parser->startrule(\$text) or die "Bad text!\n$text\n";

        $text =~ s/^\s+|\s+$//g;

        if(length $text) {
            print "Bad parse at: $text";
        } else {
            my $output = join('', flatten($result));

            # beautification
            my @quotes;
            $output =~ s/(?:\"((?:\\\"|(?!\").)*)\")/push @quotes, $1; '"' . ('-' x length $1) . '"'/ge;

            $output =~ s/\ban un/a un/g;
            $output =~ s/\ban UTF/a UTF/g;
            $output =~ s/the value the expression/the value of the expression/g;
            $output =~ s/the value the member/the value of the member/g;
            $output =~ s/the value the/the/g;
            $output =~ s/of evaluate/of/g;
            $output =~ s/the evaluate the/the/g;
            $output =~ s/by evaluate the/by the/g;
            $output =~ s/the a /the /g;
            $output =~ s/Then if it has the value/If it has the value/g;
            $output =~ s/result of the expression a generic-selection/result of a generic-selection/g;
            $output =~ s/the result of the expression (an?) (16-bit character|32-bit character|wide character|UTF-8) string/$1 $2 string/gi;
            $output =~ s/the function a generic-selection/the function resulting from a generic-selection/g;
            $output =~ s/\.\s+Then exit switch block/ and then exit switch block/g;
            $output =~ s/,\././g;
            $output =~ s/of unspecified length //g;
            while($output =~ s/const const/const/g){};

            foreach my $quote (@quotes) {
                next unless $quote;
                $output =~ s/"-+"/"$quote"/;
            }

            print $output;
        }
    }
}

main;
