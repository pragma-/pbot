#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# ugly and hacked together

# n1256: pdftotext -layout -y 75 -H 650 -W 1000 n1256.pdf n1256.in
# n1570: pdftotext -layout -y 80 -H 650 -W 1000 n1570.pdf n1570.in
# n3047: pdftotext -layout -y 75 -H 700 -W 1000 n3047.pdf n3047.in

use warnings;
use strict;

use HTML::Entities;
use Data::Dumper;

my $debug = 100;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $input = "@ARGV";

if (not length $input) {
    print STDERR "Usage: $0 <input .txt file>\n";
    exit 1;
}

open FH, "<:encoding(UTF-8)", $input or die "Could not open $input: $!";
my @contents = <FH>;
close FH;

my $text = join '', @contents;
$text =~ s/\r//g;

my $section_title;
my $this_section = '';
my %sections;
my @last_section_number;
my @section_number;
my $last_section = '';
my @footnotes;
my $footnote      = 0;
my $last_footnote = 0;

gen_data();
gen_txt();
#gen_html();

sub gen_data {
    while ($text =~ m/^\f?\s{0,5}([0-9A-Z]+\.[0-9\.]*)/msg) {
        $last_section = $this_section;
        $this_section = $1;

        @last_section_number = @section_number;
        @section_number = split /\./, $this_section;

        print STDERR "----------------------------------\n" if $debug;
        print STDERR "Processing section [$this_section]\n" if $debug;

        validate_section_difference();

        my $section_text;

        if ($text =~ m/(.*?)^(?=\f?\s{0,4}[0-9A-Z]+\.)/msg) {
            $section_text = $1;
        } else {
            print STDERR "No section text, end of file marker found.\n";
            last;
        }

        if ($section_text =~ m/(.*?)$/msg) {
            if (length $1) {
                $section_title = $1;
                $section_title =~ s/^\s+//;
                $section_title =~ s/\s+$//;
                print STDERR "+++ set new section title: [$section_title]\n" if $debug;
            } else {
                print STDERR "--- no length for section title\n" if $debug;
            }
        } else {
            print STDERR "--- no new section title\n" if $debug;
        }

        $sections{$this_section}{title} = $section_title;

        ($section_text) = $section_text =~ m/\s*(.*)/msg;

        print STDERR "+++ $this_section [$section_title]\n" if $debug >= 2;
        print STDERR "+++ section text: [$section_text]\n" if $debug >= 2;

        if (not $section_text =~ m/^(?=\d+\s)/msg) {
            print STDERR "??? no paragraphs in section\n" if $debug;
            $section_text =~ s/~~//msg;
            $section_text =~ s/ZZZ//msg;
            $sections{$this_section}{text} = $section_text;
        } else {
            my $last_p = 0;
            my $p      = 0;

            print STDERR "+++ getting paragraphs for $this_section\n" if $debug;

            my $pretext;

            if ($section_text =~ m/^(?!\f?\d+\s)/) {
                ($pretext) = $section_text =~ m/^(.*?)^(?=\f?\d+\s)/ms;
                print STDERR "pretext captured: [$pretext]\n";
            }

            while ($section_text =~ m/^\f?(\d+)\s(.*?)^(?=\f?\d)/msgc or $section_text =~ m/^\f?(\d+)\s(.*)/msg) {
                $last_p = $p;
                $p      = $1;
                my $t   = $2;

                if (length $pretext) {
                    $t = "$pretext $t";
                    $pretext = '';
                }

                print STDERR "paragraph $p: [$t]\n" if $debug >= 3;

                if ($p - $last_p != 1) {
                    die "Paragraph diff invalid" unless ($input eq 'n1570.in' && $this_section =~ /^(?:K.3.9.(?:2|3))/);
                }

                # check for footnotes
                my @new_footnotes;
                while ($t =~ m/^\s*(\d+)\)\s*(.*?)$/mgc) {
                    $footnote = $1;
                    my $footnote_text = "$2\n";

                    print STDERR "processing 1st footnote $footnote [last: $last_footnote]\n" if $debug;
                    print STDERR "footnote text [$footnote_text]\n" if $debug;

                    if ($last_footnote - $footnote != -1) {
                        die "Footnote diff invalid";
                    }

                    $last_footnote = $footnote;

                    push @new_footnotes, $footnote;

                    print STDERR "footnote $footnote text: [$footnote_text]\n" if $debug >= 4;

                    while ($t =~ m/^(.*?)$/mgc) {
                        my $line = $1;
                        print STDERR "processing [$line]\n" if $debug;

                        if ($line =~ m/^\f/mg) {
                            print STDERR "end of footnote $footnote\n";
                            last;
                        }

                        if (not length $line or $line =~ m/^\s+$/) {
                            print STDERR "skipping empty line\n";
                            next;
                        }

                        if ($line =~ m/^\s*(\d+)\)\s*(.*?)$/mg) {
                            print STDERR "----------------\n" if $debug >= 1;
                            print STDERR "+++ added footnote $footnote: [$footnote_text]\n" if $debug >= 1;
                            $footnotes[$footnote] = $footnote_text;
                            print STDERR "----------------\n" if $debug >= 1;

                            $footnote       = $1;
                            $footnote_text  = "$2\n";

                            print STDERR "processing 2nd footnote $footnote [last: $last_footnote]\n" if $debug;

                            if ($last_footnote - $footnote != -1) {
                                die "Footnote diff invalid";
                            }

                            $last_footnote = $footnote;

                            push @new_footnotes, $footnote;

                            print STDERR "footnote $footnote text: [$footnote_text]\n" if $debug >= 4;
                            next;
                        }

                        if (not length $line or $line =~ m/^\s+$/) {
                            print STDERR "footnote $footnote: skipping empty line\n";
                        } else {
                            $footnote_text .= "$line\n";
                            print STDERR "footnote $footnote text: appending [$line]\n" if $debug >= 3;
                        }
                    }

                    print STDERR "----------------\n" if $debug >= 1;
                    print STDERR "+++ added footnote $footnote: [$footnote_text]\n" if $debug >= 1;
                    $footnotes[$footnote] = $footnote_text;
                    print STDERR "----------------\n" if $debug >= 1;
                }

                # strip footnotes from section text
                foreach my $fn (@new_footnotes) {
                    my $sub = quotemeta $footnotes[$fn];
                    $sub =~ s/(\\ )+/\\s*/g;
                    #print STDERR "subbing out [$footnote) $sub]\n";
                    $t =~ s/^\s*$fn\)\s*$sub//ms;
                }

                $t =~ s/\f//g;
                $t =~ s/~~//msg;
                $t =~ s/ZZZ//msg;

                $sections{$this_section . "p$p"}{text} = "$p $t";
                print STDERR "+++ added ${this_section}p$p:\n$p $t\n" if $debug;
            }
            print STDERR "+++ paragraphs done\n" if $debug;
        }
    }
}

sub bysection {
    my $inverse = 1;

    my ($a1, $p1) = split /p/, $a;
    my ($b1, $p2) = split /p/, $b;

    $p1 //= 0;
    $p2 //= 0;

    my @k1 = split /\./, $a1;
    my @k2 = split /\./, $b1;
    my @r;

    if ($#k2 > $#k1) {
        my @tk = @k1;
           @k1 = @k2;
           @k2 = @tk;
        my $tp = $p1;
           $p1 = $p2;
           $p2 = $tp;
        $inverse = -1;
    } else {
        $inverse = 1;
    }

    my $i = 0;
    for (; $i < $#k1 + 1; $i++) {
        if (not defined $k2[$i]) { $r[$i] = 1; }
        else {
            if   ($i == 0) { $r[$i] = $k1[$i] cmp $k2[$i]; }
            else           { $r[$i] = $k1[$i] <=> $k2[$i]; }
        }
    }

    $r[$i] = ($p1 <=> $p2);

    my $ret = 0;
    foreach my $rv (@r) {
        if ($rv != 0) {
            $ret = $rv;
            last;
        }
    }

    return $ret * $inverse;
}

sub gen_txt {
    my $footer = "";
    my $paren  = 0;
    my $section_head;
    my $section_title;

    foreach my $this_section (sort bysection keys %sections) {
        print STDERR "writing section $this_section\n" if $debug;
        if (not $this_section =~ m/p/) {
            print "    $this_section $sections{$this_section}{title}\n";
            $section_head  = $this_section;
            $section_title = $sections{$this_section}{title};
        }

        my $section_text = $sections{$this_section}{text};

        while ($section_text =~ m/^(.*?)$/msg) {
            my $line = $1;

            print STDERR "paren reset, line [$line]\n" if $debug >= 8;
            my $number = "";
            while ($line =~ m/(.)/g) {
                my $c = $1;

                if    ($c =~ m/[0-9]/) { $number .= $c; }
                elsif ($c eq ' ')      { $number = ""; }
                elsif ($c eq '(') {
                    $paren++;
                    print STDERR "got $paren (\n" if $debug >= 8;
                } elsif ($c eq ')') {
                    $paren--;
                    print STDERR "got $paren )\n" if $debug >= 8;

                    if ($paren == -1) {
                        if (length $number and defined $footnotes[$number]) {
                            print STDERR "Got footnote $number here!\n" if $debug;
                            $footer .= "\nFOOTNOTE.$number) $footnotes[$number]\n";
                        }

                        $paren = 0;
                    }
                } else {
                    $number = "";
                }
            }
        }

        print "$section_text\n";

        if (length $footer) {
            print $footer;
            $footer = "";
        }
    }
}

sub make_link {
    my ($text) = @_;
    if (exists $sections{$text}) {
        return "<a href='#$text'>$text</a>";
    } else {
        return $text;
    }
}

sub linkify {
    my ($text) = @_;
    $text =~ s/\b((?:[A-Z]|[1-9])\.(?:\.?[0-9]+)*)\b/make_link($1)/ge;
    return $text;
}

sub gen_html {
    print "<html>\n<body>\n";

    foreach my $section (qw/ABSTRACT. CONTENTS. FOREWORD. INTRO./) {
        foreach my $paragraph (sort bysection keys %sections) {
            if ($paragraph =~ m/^$section/) {
                write_html_section($paragraph);
                delete $sections{$paragraph};
            }
        }
        delete $sections{$section};
    }

    foreach my $section (sort bysection keys %sections) {
        write_html_section($section);
    }

    print "\n</body>\n</html>\n";
}

sub write_html_section {
    my ($this_section) = @_;

    my $footer = "";
    my $paren  = 0;

    print STDERR "writing section [$this_section]\n" if $debug;

    print "<a name='", encode_entities($this_section), "'></a>\n";

    if (not $this_section =~ m/p/) {
        print "<hr>\n<h3>", encode_entities($this_section), " [", encode_entities($sections{$this_section}{title}), "]</h3>\n";
    }

    my $section_text = $sections{$this_section}{text};

    next if not length $section_text;

    $section_text = encode_entities $section_text;

    while ($section_text =~ m/^(.*?)$/msg) {
        my $line = $1;

        print STDERR "paren reset, line [$line]\n" if $debug >= 8;
        my $number = "";
        while ($line =~ m/(.)/g) {
            my $c = $1;

            if    ($c =~ m/[0-9]/) { $number .= $c; }
            elsif ($c eq ' ')      { $number = ""; }
            elsif ($c eq '(') {
                $paren++;
                print STDERR "got $paren (\n" if $debug >= 8;
            } elsif ($c eq ')') {
                $paren--;
                print STDERR "got $paren )\n" if $debug >= 8;

                if ($paren == -1) {
                    if (length $number and defined $footnotes[$number]) {
                        print STDERR "Got footnote $number here!\n" if $debug;
                        $section_text =~ s/$number\)/<a href='#FOOTNOTE.$number'><sup>[$number]<\/sup><\/a>/;
                        $footer .= "<a name='FOOTNOTE.$number'>\n<pre><i><b>Footnote $number)</b> ".encode_entities($footnotes[$number])."</i></pre>\n</a>\n";
                    }

                    $paren = 0;
                }
            } else {
                $number = "";
            }
        }
    }

    $section_text = linkify($section_text);
    $footer = linkify($footer);

    if ($this_section eq 'CONTENTS.') {
        $section_text =~ s/Annex ([A-Z])/<a href='#$1.'>Annex $1<\/a>/mg;
        $section_text =~ s/^(\d+\.)/<a href='#$1'>$1<\/a>/mg;
        $section_text =~ s/^Foreword/<a href='#FOREWORD.'>Foreword<\/a>/mg;
        $section_text =~ s/^Introduction/<a href='#INTRO.'>Introduction<\/a>/mg;
    }

    print "<pre>", $section_text, "</pre>\n";

    if (length $footer) {
        print $footer;
        $footer = '';
    }
}

# this mess of code verifies that two given section numbers are within 1 unit of distance of each other
# this ensures that no sections were skipped due to misparses
sub validate_section_difference {
    if (@last_section_number && $last_section_number[0] !~ /(?:ABSTRACT|CONTENTS|FOREWORD|INTRO)/) {
        my $fail = 0;
        my $skip = 0;

        print STDERR "comparing last section ", join('.', @last_section_number), " vs ", join('.', @section_number), "\n";

        if (@section_number > @last_section_number) {
            if (@section_number - @last_section_number != 1) {
                $fail = 1;
                print STDERR "size difference too great\n";
            }

            unless ($fail) {
                if ($section_number[0] =~ /^[A-Z]+$/) {
                    if ($last_section_number[0] =~ /^[A-Z]+$/) {
                        for (my $i = 0; $i < @last_section_number; $i++) {
                            if ($section_number[$i] ne $last_section_number[$i]) {
                                $fail = 1;
                                print STDERR "digits different\n";
                                last;
                            }
                        }
                    } else {
                        print STDERR "disregarding section namespace change from number to alphabet\n";
                        $skip = 1;
                    }
                } else {
                    for (my $i = 0; $i < @last_section_number; $i++) {
                        if ($section_number[$i] ne $last_section_number[$i]) {
                            $fail = 1;
                            print STDERR "digits different\n";
                            last;
                        }
                    }
                }
            }

            if (!$skip && ($fail || $section_number[$#section_number] != 1)) {
                print STDERR "difference too great ", join('.', @last_section_number), " vs ", join('.', @section_number), "\n";
                die;
            }
        } elsif (@last_section_number > @section_number) {
            if ($section_number[0] =~ /^[A-Z]+$/) {
                if ($last_section_number[0] =~ /^[A-Z]+$/) {
                    if ($section_number[0] ne $last_section_number[0]) {
                        if (ord($section_number[0]) - ord($last_section_number[0]) != 1) {
                            $fail = 1;
                            print STDERR "letter difference too great\n";
                        } else {
                            $skip = 1;
                            print STDERR "letter difference good\n";
                        }
                    }

                    unless ($fail) {
                        for (my $i = 1; $i < @section_number - 1; $i++) {
                            if ($section_number[$i] != $last_section_number[$i]) {
                                if ($section_number[$i] - $last_section_number[$i] != 1) {
                                    print STDERR "digit difference too great\n";
                                    $fail = 1;
                                }
                                last;
                            }
                        }
                    }
                } else {
                    print STDERR "disregarding section namespace change from number to alphabet\n";
                    $skip = 1;
                }
            } else {
                for (my $i = 0; $i < @section_number - 1; $i++) {
                    if ($section_number[$i] != $last_section_number[$i]) {
                        if ($section_number[$i] - $last_section_number[$i] != 1) {
                            print STDERR "digit difference too great\n";
                            $fail = 1;
                        }
                        last;
                    }
                }
            }

            if (!$skip && ($fail || $section_number[$#section_number] - $last_section_number[$#section_number] != 1)) {
                print STDERR "difference too great ", join('.', @last_section_number), " vs ", join('.', @section_number), "\n";
                die;
            }
        } else {
            my @rev_last = reverse @last_section_number;
            my @rev_curr = reverse @section_number;

            if ($rev_curr[$#rev_curr] =~ /^[A-Z]+$/) {
                if ($rev_last[$#rev_last] =~ /^[A-Z]+$/) {
                    if ($rev_curr[$#rev_curr] ne $rev_last[$#rev_last]) {
                        if (ord($rev_curr[$#rev_curr]) - ord($rev_last[$#rev_last]) != 1) {
                            $fail = 1;
                            print STDERR "letter difference too great\n";
                        }
                    }
                    for (my $i = 1; $i < @rev_curr; $i++) {
                        if ($rev_curr[$i] != $rev_last[$i]) {
                            if ($rev_curr[$i] - $rev_last[$i] > 1) {
                                $fail = 1;
                            }
                            last;
                        }
                    }
                } else {
                    print STDERR "disregarding section namespace change from number to alphabet\n";
                    $skip = 1;
                }
            } else {
                for (my $i = 0; $i < @rev_curr; $i++) {
                    if ($rev_curr[$i] != $rev_last[$i]) {
                        if ($rev_curr[$i] - $rev_last[$i] > 1) {
                            $fail = 1;
                        }
                        last;
                    }
                }
            }

            if (!$skip && $fail) {
                print STDERR "difference too great ", join('.', @last_section_number), " vs ", join('.', @section_number), "\n";
                die;
            }
        }
    }
}
