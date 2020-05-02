# File: FuncGrep.pm
# Author: pragma-
#
# Purpose: Registers the grep Function

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::FuncGrep;
use parent 'Plugins::Plugin';

use warnings; use strict;
use feature 'unicode_strings';

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{functions}->register(
        'grep',
        {
            desc   => 'prints region of text that matches regex',
            usage  => 'grep <regex>',
            subref => sub { $self->func_grep(@_) }
        }
    );
}

sub unload {
    my $self = shift;
    $self->{pbot}->{functions}->unregister('grep');
}

sub func_grep {
    my $self = shift @_;
    my $regex = shift @_;
    my $text = "@_";

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
