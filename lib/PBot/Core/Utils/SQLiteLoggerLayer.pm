# File: SQLiteLoggerLayer
#
# Purpose: PerlIO::via layer to log DBI trace messages.

# SPDX-FileCopyrightText: 2014-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Utils::SQLiteLoggerLayer;

use PBot::Imports;

sub PUSHED {
    my ($class, $mode, $fh) = @_;
    my $logger;
    return bless \$logger, $class;
}

sub OPEN {
    my ($self, $path, $mode, $fh) = @_;
    $$self = $path; # path is our PBot::Logger object
    return 1;
}

sub WRITE {
    my ($self, $buf, $fh) = @_;
    $$self->log($buf); # log message
    return length($buf);
}

sub CLOSE {
    my ($self) = @_;
    $$self->close();
    return 0;
}

1;
