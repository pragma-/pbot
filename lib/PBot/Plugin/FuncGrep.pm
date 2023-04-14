# File: FuncGrep.pm
#
# Purpose: Registers the grep Function

# SPDX-FileCopyrightText: 2020-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::FuncGrep;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize($self, %conf) {
    $self->{pbot}->{functions}->register(
        'grep',
        {
            desc   => 'prints region of text that matches regex',
            usage  => 'grep <regex>',
            subref => sub { $self->func_grep(@_) }
        }
    );
}

sub unload($self) {
    $self->{pbot}->{functions}->unregister('grep');
}

sub func_grep($self, $regex, @rest) {
    my $text = "@rest";

    my $result = eval {
        my $result = '';

        my $search_regex = $regex;

        if ($search_regex !~ s/^\^/\\b/) {
            $search_regex = "\\S*$search_regex";
        }

        if ($search_regex !~ s/\$$/\\b/) {
            $search_regex = "$search_regex\\S*";
        }

        my $matches = 0;

        while ($text =~ /($search_regex)/igms) {
            $result .= "$1\n";
            $matches++;
        }

        return "grep: '$regex' not found" if not $matches;
        return $result;
    };

    if ($@) {
        $@ =~ s/ at.*$//;
        $@ =~ s/marked by .* HERE in m\/\(//;
        $@ =~ s/\s*\)\/$//;
        return "grep: $@";
    }

    return $result;
}

1;
