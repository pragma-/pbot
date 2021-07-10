#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# ugly and hacked together

use warnings;
use strict;

use HTML::Entities;
use Data::Dumper;

my $debug = 1000;

sub gen_data;
sub gen_txt;
sub gen_html;

open FH, "<n1256.txt" or die "Could not open n1256.txt: $!";

#open FH, "<n1570.txt" or die "Could not open n1570.txt: $!";
my @contents = <FH>;
close FH;

my $text = join '', @contents;
$text =~ s/\r//g;

my ($section_title, $this_section);

my %sections;
my $last_section_number = 0;
my $section_number      = 0;
my $last_section;
my @footnotes;
my $footnote      = 0;
my $last_footnote = 0;

gen_data;

#gen_txt;
gen_html;

sub gen_data {
    while ($text =~ m/^\s{0,5}([0-9A-Z]+\.[0-9\.]*)/msg) {
        $last_section_number = $section_number;
        $last_section        = $this_section;
        $this_section        = $1;

        ($section_number) = $this_section =~ /([^.]+)\./;

        print STDERR "----------------------------------\n"                           if $debug;
        print STDERR "Processing section [$this_section]; number [$section_number]\n" if $debug;

        print STDERR "this_section: [$this_section]; last_section: [$last_section]\n" if $debug >= 2;
        print STDERR "Section diff: ", ($this_section - $last_section), "\n" if $debug >= 2;

        my $diff = $section_number - $last_section_number;
        print STDERR "Diff: $diff\n" if $debug >= 2;

        if ($section_number > 0 and $diff < 0 or $diff > 1) {
            print STDERR "Diff out of bounds: $diff\n";
            last;
        }

        my $section_text;

        if ($text =~ m/(.*?)^(?=\s{0,4}[0-9A-Z]+\.)/msg) { $section_text = $1; }
        else {
            print STDERR "No section text, end of file marker found.\n";
            last;
        }

        if ($section_text =~ m/(.*?)$/msg) {
            $section_title = $1 if length $1;
            $section_title =~ s/^\s+//;
            $section_title =~ s/\s+$//;
        }

        print STDERR "$this_section [$section_title]\n" if $debug >= 2;
        $sections{$this_section}{title} = $section_title;

        print STDERR "section text: [$section_text]\n" if $debug >= 2;

        if (not $section_text =~ m/^(?=\d+\s)/msg) { $sections{$this_section}{text} = $section_text; }
        else {
            my $last_p = 0;
            my $p      = 0;
            while ($section_text =~ m/^(\d+)\s(.*?)^(?=\d)/msgc or $section_text =~ m/^(\d+)\s(.*)/msg) {
                $last_p = $p;
                $p      = $1;
                my $t = $2;

                print STDERR "paragraph $p: [$t]\n" if $debug >= 3;

                if (($last_p - $p) != -1) { die "Paragraph diff invalid"; }

                while ($t =~ m/^(\s*)(\d+)\)(\s*)(.*?)$/msg) {
                    my $leading_spaces = $1;
                    $footnote = $2;
                    my $middle_spaces = $3;
                    my $footnote_text = "$4\n";
                    print STDERR "1st footnote\n"                                         if $debug;
                    print STDERR "processing footnote $footnote [last: $last_footnote]\n" if $debug >= 2;
                    if ($last_footnote - $footnote != -1) {
                        print STDERR "footnotes dump: \n" if $debug > 5;
                        shift @footnotes;
                        my $dump = Dumper(@footnotes) if $debug > 5;

                        #print STDERR "$dump\n";
                        die "Footnote diff invalid";
                    }
                    $last_footnote = $footnote;

                    my $indent = (length $leading_spaces) + (length $footnote) + (length ')') + (length $middle_spaces);
                    $indent--;

                    print STDERR "footnote $footnote text [indent=$indent]: [$footnote_text]\n" if $debug >= 4;

                    while ($t =~ m/^(.*?)$/msgc) {
                        my $line = $1;
                        print STDERR "processing [$line]\n" if $debug;

                        if ($line =~ m/^(\s*)(\d+)\)(\s*)(.*?)$/msg) {
                            print STDERR "----------------\n"                     if $debug >= 1;
                            print STDERR "footnote $footnote: [$footnote_text]\n" if $debug >= 1;
                            $footnotes[$footnote] = $footnote_text;
                            print STDERR "----------------\n" if $debug >= 1;

                            $leading_spaces = $1;
                            $footnote       = $2;
                            $middle_spaces  = $3;
                            $footnote_text  = "$4\n";

                            print STDERR "2nd footnote\n"                                         if $debug >= 2;
                            print STDERR "processing footnote $footnote [last: $last_footnote]\n" if $debug >= 2;
                            if ($last_footnote - $footnote != -1) {
                                print STDERR "footnotes dump: \n";
                                shift @footnotes;
                                my $dump = Dumper(@footnotes);
                                print STDERR "$dump\n" if $debug >= 3;
                                die "Footnote diff invalid";
                            }
                            $last_footnote = $footnote;

                            my $indent = (length $leading_spaces) + (length $footnote) + (length ')') + (length $middle_spaces);
                            $indent--;

                            print STDERR "footnote $footnote text [indent=$indent]: [$footnote_text]\n" if $debug >= 4;
                            next;
                        }

                        if (not $line =~ m/^\s{$indent}/msg) {
                            print STDERR "INTERRUPTED FOOTNOTE\n";
                            last;
                        }
                        $footnote_text .= "$line\n";
                        print STDERR "footnote $footnote text: appending [$line]\n" if $debug >= 3;
                    }

                    print STDERR "----------------\n"                     if $debug >= 1;
                    print STDERR "footnote $footnote: [$footnote_text]\n" if $debug >= 1;
                    $footnotes[$footnote] = $footnote_text;
                    print STDERR "----------------\n" if $debug >= 1;
                }

                $sections{$this_section . "p$p"}{text} = "$p $t";
            }
        }
    }
}

sub bysection {
    my $inverse = 1;
    print STDERR "section cmp $a <=> $b\n" if $debug > 10;

    my ($a1, $p1) = split /p/, $a;
    my ($b1, $p2) = split /p/, $b;

    $p1 = 0 if not defined $p1;
    $p2 = 0 if not defined $p2;

    my @k1 = split /\./, $a1;
    my @k2 = split /\./, $b1;
    my @r;

    if ($#k2 > $#k1) {
        my @t = @k1;
        @k1 = @k2;
        @k2 = @t;
        my $tp = $p1;
        $p1      = $p2;
        $p2      = $tp;
        $inverse = -1;
    } else {
        $inverse = 1;
    }

=cut
  print STDERR "k1 vals:\n";
  print STDERR Dumper(@k1), "\n";
  print STDERR "p1: $p1\n";

  print STDERR "k2 vals:\n";
  print STDERR Dumper(@k2), "\n";
  print STDERR "p2: $p2\n";
=cut

    my $i = 0;
    for (; $i < $#k1 + 1; $i++) {
        if (not defined $k2[$i]) { $r[$i] = 1; }
        else {
            print STDERR "   cmp k1[$i] ($k1[$i]) vs k2[$i] ($k2[$i])\n" if $debug >= 5;
            if   ($i == 0) { $r[$i] = $k1[$i] cmp $k2[$i]; }
            else           { $r[$i] = $k1[$i] <=> $k2[$i]; }
        }
        print STDERR "  r[$i] = $r[$i]\n" if $debug >= 5;
    }

    $r[$i] = ($p1 <=> $p2);
    print STDERR "  $p1 <=> $p2 => r[$i] = $r[$i]\n" if $debug >= 5;

    my $ret = 0;
    foreach my $rv (@r) {
        print STDERR "  checking r: $rv\n" if $debug >= 5;
        if ($rv != 0) {
            $ret = $rv;
            last;
        }
    }

    $ret = $ret * $inverse;

    print STDERR "ret $ret\n" if $debug >= 5;
    return $ret;
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

        for ($footnote = 1; $footnote < $#footnotes; $footnote++) {
            my $sub = quotemeta $footnotes[$footnote];
            $sub =~ s/(\\ )+/\\s*/g;

            #print STDERR "subbing out [$footnote) $sub]\n";
            $section_text =~ s/^\s*$footnote\)\s*$sub//ms;
        }

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
                            $footer .= "    FOOTNOTE.$number\n      $footnotes[$number]\n";
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

sub gen_html {
    print "<html>\n<body>\n";

    my $footer = "";
    my $paren  = 0;

    foreach my $this_section (sort bysection keys %sections) {
        print STDERR "writing section $this_section\n" if $debug;
        print "<a name='", encode_entities $this_section, "'>\n";
        print "<hr>\n<h3>", encode_entities $this_section, " [", encode_entities $sections{$this_section}{title}, "]</h3>\n" if not $this_section =~ m/p/;

        my $section_text = $sections{$this_section}{text};

        for ($footnote = 1; $footnote < $#footnotes; $footnote++) {
            my $sub = quotemeta $footnotes[$footnote];
            $sub =~ s/(\\ )+/\\s*/g;

            #print STDERR "subbing out [$footnote) $sub]\n";
            $section_text =~ s/^\s*$footnote\)\s*$sub//ms;
        }

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
                            $section_text =~ s/$number\)/<sup>[$number]<\/sup>/;
                            $footer .= "<a name='FOOTNOTE.$number'>\n<pre><i><b>Footnote $number)</b> ", encode_entities $footnotes[$number], "</i></pre>\n</a>\n";
                        }

                        $paren = 0;
                    }
                } else {
                    $number = "";
                }
            }
        }

        $section_text =~ s/\(([0-9.]+)\)/(<a href="#$1">$1<\/a>)/g;
        $footer       =~ s/\(([0-9.]+)\)/(<a href="#$1">$1<\/a>)/g;

        print "<pre>", $section_text, "</pre>\n";
        print "</a>\n";

        if (length $footer) {
            print $footer;
            $footer = "";
        }
    }

    print "\n</body>\n</html>\n";
}
