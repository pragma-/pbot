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

    # use feature ':5.20'
    feature->import::into($target, ':5.20');

    # use utf8
    utf8->import::into($target);

    # use signatures
    feature->import::into($target, 'signatures');

    # no warnings => 'experimental';
    warnings->unimport::out_of($target, 'experimental');

    # no warnings => 'deprecated';
    # note: I will be monitoring deprecations and will update PBot accordingly
    warnings->unimport::out_of($target, 'deprecated');
}

sub unimport {}

1;
