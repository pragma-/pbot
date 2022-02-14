#!/usr/bin/env perl

package InteractiveEdit;

use 5.020;

use warnings;
use strict;

use feature qw(switch  signatures);
no warnings qw(experimental::smartmatch experimental::signatures);

use LWP::UserAgent;
use FindBin qw($RealBin);
use Text::Balanced qw(extract_delimited);

use parent qw(Exporter);
our @EXPORT = qw(interactive_edit);

sub interactive_edit($self) {
    my (@last_code, $unshift_last_code);

    my $code = $self->{code};

    print "      code: [$code]\n" if $self->{debug};

    my $subcode = $code;
    while ($subcode =~ s/^\s*(-[^ ]+)\s*//) {}

    my $copy_code;
    if ($subcode =~ s/^\s*copy\s+(\S+)\s*//) {
        my $copy = $1;

        if (open LOG, "< $RealBin/../history/$copy-$self->{lang}.hist") {
            $copy_code = <LOG>;
            close LOG;
            goto COPY_ERROR if not $copy_code;;
            chomp $copy_code;
        } else {
            goto COPY_ERROR;
        }

        goto COPY_SUCCESS;

        COPY_ERROR:
        print "No history for $copy.\n";
        exit 0;

        COPY_SUCCESS:
        $code = $copy_code;
        $self->{only_show} = 1;
        $self->{copy_code} = 1;
    }

    if ($subcode =~ m/^\s*(?:and\s+)?(?:diff|show)\s+(\S+)\s*$/) {
        $self->{channel} = $1;
    }

    if (open LOG, "< $RealBin/../history/$self->{channel}-$self->{lang}.hist") {
        while (my $line = <LOG>) {
            chomp $line;
            push @last_code, $line;
        }
        close LOG;
    }

    unshift @last_code, $copy_code if defined $copy_code;

    if ($subcode =~ m/^\s*(?:and\s+)?show(?:\s+\S+)?\s*$/i) {
        if (defined $last_code[0]) {
            print "$last_code[0]\n";
        } else {
            print "No recent code to show.\n"
        }
        exit 0;
    }

    my $prevchange = $last_code[0];
    my @replacements;
    my $got_changes = 0;
    my $got_sub = 0;
    my $got_diff = 0;
    my $got_undo = 0;
    my $last_keyword;

    while ($subcode =~ s/^\s*(and)?\s*undo//) {
        splice @last_code, 0, 1;
        if (not defined $last_code[0]) {
            print "No more undos remaining.\n";
            exit 0;
        } else {
            $code = $last_code[0];
            $prevchange = $last_code[0];
            $got_undo = 1;
        }
    }

    while (1) {
        $got_sub = 0;

        $subcode =~ s/^\s*and\s+'/and $last_keyword '/ if defined $last_keyword;

        if ($subcode =~ m/^\s*(?:and\s+)?diff\b/i) {
            $got_diff = 1;
            last;
        }

        if ($subcode =~ m/^\s*(?:and\s+)?(again|run|paste)\b/i) {
            $self->{got_run} = lc $1;
            $self->{only_show} = 0;
            if ($prevchange) {
                $code = $prevchange;
            } else {
                print "No recent code to $self->{got_run}.\n";
                exit 0;
            }
        }

        if ($subcode =~ m/^\s*(and)?\s*remove \s*([^']+)?\s*'/) {
            $last_keyword = 'remove';
            my $modifier = 'first';

            $subcode =~ s/^\s*(and)?\s*//;
            $subcode =~ s/remove\s*([^']+)?\s*//i;
            $modifier = $1 if defined $1;
            $modifier =~ s/\s+$//;

            my ($e, $r) = extract_delimited($subcode, "'");

            my $text;

            if (defined $e) {
                $text = $e;
                $text =~ s/^'//;
                $text =~ s/'$//;
                $subcode = "replace $modifier '$text' with ''$r";
            } else {
                print "Unbalanced single quotes.  Usage: cc remove [all, first, .., tenth, last] 'text' [and ...]\n";
                exit 0;
            }
            next;
        }

        if ($subcode =~ s/^\s*(and)?\s*prepend '//) {
            $last_keyword = 'prepend';
            $subcode = "'$subcode";

            my ($e, $r) = extract_delimited($subcode, "'");

            my $text;

            if (defined $e) {
                $text = $e;
                $text =~ s/^'//;
                $text =~ s/'$//;
                $subcode = $r;

                $got_sub = 1;
                $got_changes = 1;

                if (not defined $prevchange) {
                    print "No recent code to prepend to.\n";
                    exit 0;
                }

                $code = $prevchange;
                $code =~ s/^/$text /;
                $prevchange = $code;
            } else {
                print "Unbalanced single quotes.  Usage: cc prepend 'text' [and ...]\n";
                exit 0;
            }
            next;
        }

        if ($subcode =~ s/^\s*(and)?\s*append '//) {
            $last_keyword = 'append';
            $subcode = "'$subcode";

            my ($e, $r) = extract_delimited($subcode, "'");

            my $text;

            if (defined $e) {
                $text = $e;
                $text =~ s/^'//;
                $text =~ s/'$//;
                $subcode = $r;

                $got_sub = 1;
                $got_changes = 1;

                if (not defined $prevchange) {
                    print "No recent code to append to.\n";
                    exit 0;
                }

                $code = $prevchange;
                $code =~ s/$/ $text/;
                $prevchange = $code;
            } else {
                print "Unbalanced single quotes.  Usage: cc append 'text' [and ...]\n";
                exit 0;
            }
            next;
        }

        if ($subcode =~ m/^\s*(and)?\s*replace\s*([^']+)?\s*'.*'\s*with\s*'.*?'/i) {
            $last_keyword = 'replace';
            $got_sub = 1;
            my $modifier = 'first';

            $subcode =~ s/^\s*(and)?\s*//;
            $subcode =~ s/replace\s*([^']+)?\s*//i;
            $modifier = $1 if defined $1;
            $modifier =~ s/\s+$//;

            my ($from, $to);
            my ($e, $r) = extract_delimited($subcode, "'");

            if (defined $e) {
                $from = $e;
                $from =~ s/^'//;
                $from =~ s/'$//;
                $from = quotemeta $from;
                $from =~ s/\\ / /g;
                $subcode = $r;
                $subcode =~ s/\s*with\s*//i;
            } else {
                print "Unbalanced single quotes.  Usage: cc replace 'from' with 'to' [and ...]\n";
                exit 0;
            }

            ($e, $r) = extract_delimited($subcode, "'");

            if (defined $e) {
                $to = $e;
                $to =~ s/^'//;
                $to =~ s/'$//;
                $subcode = $r;
            } else {
                print "Unbalanced single quotes.  Usage: cc replace 'from' with 'to' [and replace ... with ... [and ...]]\n";
                exit 0;
            }

            given($modifier) {
                when($_ eq 'all'    ) {}
                when($_ eq 'last'   ) {}
                when($_ eq 'first'  ) { $modifier = 1; }
                when($_ eq 'second' ) { $modifier = 2; }
                when($_ eq 'third'  ) { $modifier = 3; }
                when($_ eq 'fourth' ) { $modifier = 4; }
                when($_ eq 'fifth'  ) { $modifier = 5; }
                when($_ eq 'sixth'  ) { $modifier = 6; }
                when($_ eq 'seventh') { $modifier = 7; }
                when($_ eq 'eighth' ) { $modifier = 8; }
                when($_ eq 'nineth' ) { $modifier = 9; }
                when($_ eq 'tenth'  ) { $modifier = 10; }
                default { print "Bad replacement modifier '$modifier'; valid modifiers are 'all', 'first', 'second', ..., 'tenth', 'last'\n"; exit 0; }
            }

            my $replacement = {};
            $replacement->{'from'} = $from;
            $replacement->{'to'} = $to;
            $replacement->{'modifier'} = $modifier;

            push @replacements, $replacement;
            next;
        }

        if ($subcode =~ m/^\s*(and)?\s*s\/.*\//) {
            $last_keyword = undef;
            $got_sub = 1;
            $subcode =~ s/^\s*(and)?\s*s//;

            my ($regex, $to);
            my ($e, $r) = extract_delimited($subcode, '/');

            if (defined $e) {
                $regex = $e;
                $regex =~ s/^\///;
                $regex =~ s/\/$//;
                $subcode = "/$r";
            } else {
                print "Unbalanced slashes.  Usage: cc s/regex/substitution/[gi] [and s/.../.../ [and ...]]\n";
                exit 0;
            }

            ($e, $r) = extract_delimited($subcode, '/');

            if (defined $e) {
                $to = $e;
                $to =~ s/^\///;
                $to =~ s/\/$//;
                $subcode = $r;
            } else {
                print "Unbalanced slashes.  Usage: cc s/regex/substitution/[gi] [and s/.../.../ [and ...]]\n";
                exit 0;
            }

            my $suffix;
            $suffix = $1 if $subcode =~ s/^([^ ]+)//;

            if (length $suffix and $suffix =~ m/[^gi]/) {
                print "Bad regex modifier '$suffix'.  Only 'i' and 'g' are allowed.\n";
                exit 0;
            }
            if (defined $prevchange) {
                $code = $prevchange;
            } else {
                print "No recent code to change.\n";
                exit 0;
            }

            my $ret = eval {
                my ($ret, $a, $b, $c, $d, $e, $f, $g, $h, $i, $before, $after);

                if (not length $suffix) {
                    $ret = $code =~ s|$regex|$to|;
                    ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
                    $before = $`;
                    $after = $';
                } elsif ($suffix =~ /^i$/) {
                    $ret = $code =~ s|$regex|$to|i;
                    ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
                    $before = $`;
                    $after = $';
                } elsif ($suffix =~ /^g$/) {
                    $ret = $code =~ s|$regex|$to|g;
                    ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
                    $before = $`;
                    $after = $';
                } elsif ($suffix =~ /^ig$/ or $suffix =~ /^gi$/) {
                    $ret = $code =~ s|$regex|$to|gi;
                    ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
                    $before = $`;
                    $after = $';
                }

                if ($ret) {
                    $code =~ s/\$1/$a/g;
                    $code =~ s/\$2/$b/g;
                    $code =~ s/\$3/$c/g;
                    $code =~ s/\$4/$d/g;
                    $code =~ s/\$5/$e/g;
                    $code =~ s/\$6/$f/g;
                    $code =~ s/\$7/$g/g;
                    $code =~ s/\$8/$h/g;
                    $code =~ s/\$9/$i/g;
                    $code =~ s/\$`/$before/g;
                    $code =~ s/\$'/$after/g;
                }

                return $ret;
            };

            if ($@) {
                my $error = $@;
                $error =~ s/ at .* line \d+\.\s*$//;
                print "$error\n";
                exit 0;
            }

            if ($ret) {
                $got_changes = 1;
            }

            $prevchange = $code;
        }

        if ($got_sub and not $got_changes) {
            print "No substitutions made.\n";
            exit 0;
        } elsif ($got_sub and $got_changes) {
            next;
        }

        last;
    }

    if (@replacements) {
        use re::engine::RE2 -strict => 1;
        @replacements = sort { $a->{'from'} cmp $b->{'from'} or $a->{'modifier'} <=> $b->{'modifier'} } @replacements;

        my ($previous_from, $previous_modifier);

        foreach my $replacement (@replacements) {
            my $from = $replacement->{'from'};
            my $to = $replacement->{'to'};
            my $modifier = $replacement->{'modifier'};

            if (defined $previous_from) {
                if ($previous_from eq $from and $previous_modifier =~ /^\d+$/) {
                    $modifier -= $modifier - $previous_modifier;
                }
            }

            if (defined $prevchange) {
                $code = $prevchange;
            } else {
                print "No recent code to change.\n";
                exit 0;
            }

            my $ret = eval {
                my $got_change;

                my ($first_char, $last_char, $first_bound, $last_bound);
                $first_char = $1 if $from =~ m/^(.)/;
                $last_char = $1 if $from =~ m/(.)$/;

                if ($first_char =~ /\W/) {
                    $first_bound = '.?';
                } else {
                    $first_bound = '\b';
                }

                if ($last_char =~ /\W/) {
                    $last_bound = '.?';
                } else {
                    $last_bound = '\b';
                }

                if ($modifier eq 'all') {
                    if ($code =~ s/($first_bound)$from($last_bound)/$1$to$2/g) {
                        $got_change = 1;
                    }
                } elsif ($modifier eq 'last') {
                    if ($code =~ s/(.*)($first_bound)$from($last_bound)/$1$2$to$3/) {
                        $got_change = 1;
                    }
                } else {
                    my $count = 0;
                    my $unescaped = $from;
                    $unescaped =~ s/\\//g;
                    if ($code =~ s/($first_bound)$from($last_bound)/if (++$count == $modifier) { "$1$to$2"; } else { "$1$unescaped$2"; }/ge) {
                        $got_change = 1;
                    }
                }
                return $got_change;
            };

            if ($@) {
                my $error = $@;
                $error =~ s/ at .* line \d+\.\s*$//;
                print "$error\n";
                exit 0;
            }

            if ($ret) {
                $got_sub = 1;
                $got_changes = 1;
            }

            $prevchange = $code;
            $previous_from = $from;
            $previous_modifier = $modifier;
        }

        if (not $got_changes) {
            print "No replacements made.\n";
            exit 0;
        }
    }

    unless($got_undo and not $got_changes) {
        $unshift_last_code = 1 unless $copy_code and not $got_changes;
    }

    if ($copy_code and $got_changes) {
        $self->{only_show} = 0;
    }

    if ($got_undo and not $got_changes) {
        $self->{only_show} = 1;
    }

    unless (($self->{got_run} or $got_diff) and not $got_changes) {
        if ($unshift_last_code) {
            unshift @last_code, $code;
        }

        open LOG, "> $RealBin/../history/$self->{channel}-$self->{lang}.hist";

        my $i = 0;
        foreach my $line (@last_code) {
            last if (++$i > $self->{max_history});
            print LOG "$line\n";
        }

        close LOG;
    }

    if ($got_diff) {
        if ($#last_code < 1) {
            print "Not enough recent code to diff.\n"
        } else {
            use Text::WordDiff;
            my $diff = word_diff(\$last_code[1], \$last_code[0], { STYLE => 'Diff' });

            if ($diff !~ /(?:<del>|<ins>)/) {
                $diff = "No difference.";
            } else {
                $diff =~ s/<del>(.*?)(\s+)<\/del>/<del>$1<\/del>$2/g;
                $diff =~ s/<ins>(.*?)(\s+)<\/ins>/<ins>$1<\/ins>$2/g;
                $diff =~ s/<del>((?:(?!<del>).)*)<\/del>\s*<ins>((?:(?!<ins>).)*)<\/ins>/`replaced $1 with $2`/g;
                $diff =~ s/<del>(.*?)<\/del>/`removed $1`/g;
                $diff =~ s/<ins>(.*?)<\/ins>/`inserted $1`/g;
            }

            print "$diff\n";
        }
        exit 0;
    }

    $self->{code} = $code;
}

1;
