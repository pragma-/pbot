# File: Selectors.pm
#
# Purpose: Provides implementation of factoid selectors.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Factoids::Selectors;
use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Core::Utils::Indefinite;

use Time::HiRes qw(gettimeofday);
use Time::Duration qw(duration);

sub initialize {
}

sub make_list {
    my ($self, $context, $extracted, $settings, %opts) = @_;

    if ($extracted =~ /(.*?)(?<!\\)%\s*\(.*\)/) {
        $opts{nested}++;
        $extracted = $self->expand_selectors($context, $extracted, %opts);
        $opts{nested}--;
    }

    my @list;
    foreach my $item (split /\s*(?<!\\)\|\s*/, $extracted, -1) {
        $item =~ s/^\s+|\s+$//g;
        $item =~ s/\\\|/|/g;

        if ($settings->{'uc'}) {
            $item = uc $item;
        }

        if ($settings->{'lc'}) {
            $item = lc $item;
        }

        if ($settings->{'ucfirst'}) {
            $item = ucfirst $item;
        }

        if ($settings->{'title'}) {
            $item = ucfirst lc $item;
            $item =~ s/ (\w)/' ' . uc $1/ge;
        }

        if ($settings->{'json'}) {
            $item = $self->{pbot}->{factoids}->{variables}->escape_json($item);
        }

        push @list, $item;
    }

    if ($settings->{'unique'}) {
        foreach my $choice (@{$settings->{'choices'}}) {
            @list = grep { $_ ne $choice } @list;
        }
    }

    if ($settings->{'sort+'}) {
        @list = sort { $a cmp $b } @list;
    }

    if ($settings->{'sort-'}) {
        @list = sort { $b cmp $a } @list;
    }

    return \@list;
}

sub select_weighted_item_from_list {
    my ($self, $list, $index) = @_;

    my @weights;
    my $weight_sum = 0;

    for (my $i = 0; $i <= $#$list; $i++) {
        my $weight = 1;

        if ($list->[$i] =~ s/:weight\(([0-9.-]+)\)//) {
            $weight = $1;
        }

        $weights[$i] = [ $weight, $i ];
        $weight_sum += $weight;
    }

    if (defined $index) {
        return $list->[$index];
    }

    my $n = rand $weight_sum;

    for my $weight (@weights) {
        if ($n < $weight->[0]) {
            return $list->[$weight->[1]];
        }

        $n -= $weight->[0];
    }
}

sub select_item {
    my ($self, $context, $extracted, $modifiers, %opts) = @_;

    my %settings = $self->{pbot}->{factoids}->{modifiers}->parse($modifiers);

    if (exists $settings{errors}) {
        return "[Error: " . join ('; ', @{$settings{errors}}) . ']';
    }

    my $item;

    if (exists $settings{'index'}) {
        my $list = $self->make_list($context, $extracted, \%settings, %opts);

        my $index = $settings{'index'};

        $index = $#$list - -$index if $index < 0;
        $index = 0 if $index < 0;
        $index = $#$list if $index > $#$list;

        $item = $self->select_weighted_item_from_list($list, $index);

        # strip outer quotes
        if (not $item =~ s/^"(.*)"$/$1/) { $item =~ s/^'(.*)'$/$1/; }
    } elsif ($settings{'pick'}) {
        my $min = $settings{'pick_min'};
        my $max = $settings{'pick_max'};

        $max = 100 if $max > 100;

        my $count = $max;

        if ($settings{'random'}) {
            $count = int rand ($max + 1 - $min) + $min;
        }

        my @choices;
        $settings{'choices'} = \@choices;

        while ($count-- > 0) {
            my $list = $self->make_list($context, $extracted, \%settings, %opts);

            last if not @$list;

            $max = @$list if $settings{'unique'} and $max > @$list;
            $min = $max if $min > $max;

            my $choice = $self->select_weighted_item_from_list($list);

            push @choices, $choice;
        }

        # strip outer quotes
        foreach my $choice (@choices) {
            if (not $choice =~ s/^"(.*)"$/$1/) { $choice =~ s/^'(.*)'$/$1/; }
        }

        if ($settings{'sort+'}) {
            @choices = sort { $a cmp $b } @choices;
        }

        if ($settings{'sort-'}) {
            @choices = sort { $b cmp $a } @choices;
        }

        return @choices if wantarray;

        if (exists $settings{'join'}) {
            my $sep = $settings{'join'} // '';
            $item = join $sep, @choices;
        }
        elsif ($settings{'enumerate'} or $settings{'comma'}) {
            $item = join ', ', @choices;
            $item =~ s/(.*), /$1 and / if $settings{'enumerate'};
        }
        else {
            $item = $opts{nested} ? join('|', @choices) : "@choices";
        }
    } else {
        my $list = $self->make_list($context, $extracted, \%settings, %opts);

        $item = $self->select_weighted_item_from_list($list);

        # strip outer quotes
        if (not $item =~ s/^"(.*)"$/$1/) { $item =~ s/^'(.*)'$/$1/; }
    }

    return $item;
}

sub expand_selectors {
    my ($self, $context, $action, %opts) = @_;

    my %default_opts = (
        nested => 0,
        recursions => 0,
    );

    %opts = (%default_opts, %opts);

    return '!recursion limit!' if ++$opts{recursions} > 100;

    my $result = '';

    while (1) {
        if ($action =~ /(.*?)(?<!\\)%\s*\(.*\)/) {
            $result .= $1;
        } else {
            last;
        }

        my ($extracted, $rest) = $self->{pbot}->{interpreter}->extract_bracketed($action, '(', ')', '%', 1);

        last if not length $extracted;

        my $item = $self->select_item($context, $extracted, \$rest, %opts);

        if ($result =~ s/\b(a|an)(\s+)$//i) {
            my ($article, $trailing) = ($1, $2);
            my $fixed_article = select_indefinite_article $item;

            if ($article eq 'AN') {
                $fixed_article = uc $fixed_article;
            } elsif ($article eq 'An' or $article eq 'A') {
                $fixed_article = ucfirst $fixed_article;
            }

            $item = $fixed_article . $trailing . $item;
        }

        $result .= $item;
        $action = $rest;
    }

    $result .= $action;
    return $result;
}

1;
