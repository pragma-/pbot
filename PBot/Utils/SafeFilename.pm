# File: SafeFilename.pm
#
# Purpose: for strings containing filenames, translates potentially unsafe
# characters into safe expansions; e.g. "foo/bar" becomes "foo&fslash;bar".

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Utils::SafeFilename;

use PBot::Imports;

require Exporter;
our @ISA    = qw/Exporter/;
our @EXPORT = qw/safe_filename/;

sub safe_filename {
    my ($name) = @_;
    my $safe = '';

    while ($name =~ m/(.)/gms) {
        if    ($1 eq '&') { $safe .= '&amp;'; }
        elsif ($1 eq '/') { $safe .= '&fslash;'; }
        else              { $safe .= $1; }
    }

    return lc $safe;
}

1;
