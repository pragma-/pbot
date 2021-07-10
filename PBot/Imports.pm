# File: Imports.pm
#
# Purpose: Boilerplate imports for PBot packages.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Imports;

use Import::Into;

sub import {
    my $target = caller;

    # use strict
    strict->import::into($target);

    # use warnings
    warnings->import::into($target);

    # use feature ':5.16'
    feature->import::into($target, ':5.16');

    # use utf8
    utf8->import::into($target);

    # no if $] >= 5.018, warnings => 'experimental';
    warnings->unimport::out_of($target, 'experimental') if $] >= 5.018
}

sub unimport {
}

1;
