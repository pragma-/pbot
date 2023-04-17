# File: SQLiteLoggerLayer
#
# Purpose: PerlIO::via layer to log DBI trace messages.

# SPDX-FileCopyrightText: 2014-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Utils::SQLiteLoggerLayer;

use PBot::Imports;

sub PUSHED($class, $mode, $fh = undef) {
    my $logger;
    return bless \$logger, $class;
}

sub OPEN($self, $path, $mode = undef, $fh = undef) {
    $$self = $path; # path is our PBot::Logger object
    return 1;
}

sub WRITE($self, $buf, $fh = undef) {
    $$self->log($buf); # log message
    return length($buf);
}

sub CLOSE($self) {
    $$self->close();
    return 0;
}

1;
