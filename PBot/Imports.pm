# File: Imports.pm
#
# Purpose: Boilerplate imports for PBot packages.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
