# File: SafeFilename.pm
#
# Purpose: for strings containing filenames, translates potentially unsafe
# characters into safe expansions; e.g. "foo/bar" becomes "foo&fslash;bar".

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Utils::SafeFilename;

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
