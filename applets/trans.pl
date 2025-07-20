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
$args =~ s/\s+--\s+/ /g;

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
    my @allowed = qw/V version H help M man T reference R reference-english S list-engines list-languages list-languages-english list-codes list-all L=s linguist=s e=s engine=s b brief d dictionary identify show-original=s show-original-phonetics=s show-translation=s show-translation-phonetics=s show-prompt-message=s show-languages=s show-original-dictionary=s show-dictionary=s show-alternatives=s hl=s host=s s=s sl=s source=s from=s t=s tl=s target=s to=s/;
    my ($ret, $rest) = GetOptionsFromString($args, \%h, @allowed);

    if ($opt_err) {
        print "$opt_err\n";
        exit;
    }

    if ($ret != 1) {
        print "Error parsing options.\n";
        exit;
    }

    if (not @$rest) {
        print "Missing phrase to translate.\n";
        exit;
    }
}

my $result = `trans $opts $args`;
print "$result\n";
