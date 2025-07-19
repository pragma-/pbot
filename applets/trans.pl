#!/usr/bin/env perl

# quick and dirty interface to https://github.com/soimort/translate-shell

use warnings;
use strict;

use Getopt::Long qw/GetOptionsFromString/;

if (not @ARGV) {
    print "Usage: trans [options] [source]:[targets] <word or phrase>\n";
    exit;
}

my $args = quotemeta "@ARGV";
$args =~ s/\\([ :-])/$1/g;
$args =~ s/^\s+|\s+$//g;

my $opts = '-j -no-ansi -no-autocorrect -no-browser -no-pager -no-play';
$opts .= ' -b' unless $args =~ /^-/;

{
    my $opt_err;
    local $SIG{__WARN__} = sub {
        $opt_err = shift;
        chomp $opt_err;
    };

    Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case');

    my %h;
    my @allowed = qw/V version H help M man T reference R reference-english S list-engines list-languages list-languages-english list-codes list-all L linguist e engine b brief d dictionary identify show-original show-original-phonetics show-translation show-translation-phonetics show-prompt-message show-languages show-original-dictionary show-dictionary show-alternatives hl host s sl source from t tl target to/;
    my ($ret, $rest) = GetOptionsFromString($args, \%h, @allowed);

    if ($opt_err) {
        print "$opt_err\n";
        exit;
    }

    if ($ret != 1) {
        print "Error parsing options.\n";
        exit;
    }
}

my $result = `trans $opts $args`;
print "$result\n";
