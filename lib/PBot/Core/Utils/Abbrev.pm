# File: Abbrev.pm
#
# Purpose: Check if a string is an abbreviation of another string or list
# of strings.

# SPDX-FileCopyrightText: 2017-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Utils::Abbrev;

use PBot::Imports;

require Exporter;
our @ISA    = qw/Exporter/;
our @EXPORT = qw/isabbrev deabbrev/;

sub isabbrev($str1, $str2) {
    return 0 if !length $str1 || !length $str2;
    return (substr($str1, 0, length $str1) eq substr($str2, 0, length $str1));
}

sub deabbrev($abbrev, @list) {
    return () if !length $abbrev || !@list;

    my @expansions;

    foreach my $item (@list) {
        if (isabbrev($abbrev, $item)) {
            push @expansions, $item;
        }
    }

    return @expansions;
}

1;
