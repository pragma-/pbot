# File: Modifiers.pm
#
# Purpose: Implements factoid expansion modifiers.

# SPDX-FileCopyrightText: 2010-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Factoids::Modifiers;
use parent 'PBot::Core::Class';

use PBot::Imports;

sub initialize {
}

sub parse($self, $modifier, $bracketed = 0) {
    my %modifiers;

    my $interp = $self->{pbot}->{interpreter};

    my $modregex;
    my $defregex;

    if ($bracketed) {
        $modregex = qr/^:(?=.+?:?)/;
        $defregex = qr/^-([^:]+)/;
    } else {
        $modregex = qr/^:(?=[\w+-]+)/;
        $defregex = qr/^-([\w]+)/;
    }

    while ($$modifier =~ s/$modregex//) {
        if ($$modifier =~ s/^join\s*(?=\(.*?(?=\)))//) {
            my ($params, $rest) = $interp->extract_bracketed($$modifier, '(', ')', '', 1);
            $$modifier = $rest;
            my @args = $interp->split_line($params, strip_quotes => 1, strip_commas => 1);
            $modifiers{'join'} = $args[0];
            next;
        }

        if ($$modifier=~ s/^\+?sort//) {
            $modifiers{'sort+'} = 1;
            next;
        }

        if ($$modifier=~ s/^\-sort//) {
            $modifiers{'sort-'} = 1;
            next;
        }

        if ($$modifier =~ s/$defregex//) {
            $modifiers{'default'} = $1;
            next;
        }

        if ($$modifier=~ s/^pick_unique\s*(?=\(.*?(?=\)))//) {
            my ($params, $rest) = $interp->extract_bracketed($$modifier, '(', ')', '', 1);
            $$modifier = $rest;
            my @args = $interp->split_line($params, strip_quotes => 1, strip_commas => 1);

            $modifiers{'pick'} = 1;
            $modifiers{'unique'} = 1;

            if (@args == 2) {
                $modifiers{'random'} = 1;
                $modifiers{'pick_min'} = $args[0];
                $modifiers{'pick_max'} = $args[1];
            } elsif (@args == 1) {
                $modifiers{'pick_min'} = 1;
                $modifiers{'pick_max'} = $args[0];
            } else {
                push @{$modifiers{errors}}, "pick_unique(): missing argument(s)";
            }

            next;
        }

        if ($$modifier=~ s/^pick\s*(?=\(.*?(?=\)))//) {
            my ($params, $rest) = $interp->extract_bracketed($$modifier, '(', ')', '', 1);
            $$modifier = $rest;
            my @args = $interp->split_line($params, strip_quotes => 1, strip_commas => 1);

            $modifiers{'pick'} = 1;

            if (@args == 2) {
                $modifiers{'random'} = 1;
                $modifiers{'pick_min'} = $args[0];
                $modifiers{'pick_max'} = $args[1];
            } elsif (@args == 1) {
                $modifiers{'pick_min'} = 1;
                $modifiers{'pick_max'} = $args[0];
            } else {
                push @{$modifiers{errors}}, "pick(): missing argument(s)";
            }

            next;
        }

        if ($$modifier=~ s/^index\s*(?=\(.*?(?=\)))//) {
            my ($params, $rest) = $interp->extract_bracketed($$modifier, '(', ')', '', 1);
            $$modifier = $rest;
            my @args = $interp->split_line($params, strip_quotes => 1, strip_commas => 1);
            if (@args == 1) {
                $modifiers{'index'} = $args[0];
            } else {
                push @{$modifiers{errors}}, "index(): missing argument";
            }
            next;
        }

        if ($$modifier =~ s/^(enumerate|comma|ucfirst|lcfirst|title|uc|lc|json)//) {
            $modifiers{$1} = 1;
            next;
        }

        if ($$modifier =~ s/^(\w+)//) {
            push @{$modifiers{errors}}, "Unknown modifier `$1`";
        }
    }

    return %modifiers;
}

1;
