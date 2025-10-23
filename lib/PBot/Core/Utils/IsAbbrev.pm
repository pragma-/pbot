# File: IsAbbrev.pm
#
# Purpose: Check is a string is an abbreviation of another string.

# SPDX-FileCopyrightText: 2017-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Utils::IsAbbrev;

use PBot::Imports;

require Exporter;
our @ISA    = qw/Exporter/;
our @EXPORT = qw/isabbrev/;

sub isabbrev($str1, $str2) {
    return 0 if !length $str1 || !length $str2;
    return (substr($str1, 0, length $str1) eq substr($str2, 0, length $str1));
}

1;
