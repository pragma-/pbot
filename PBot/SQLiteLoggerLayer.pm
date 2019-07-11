# File: SQLiteLoggerLayer
# Author: pragma_
#
# Purpose: PerlIO::via layer to log DBI trace messages

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::SQLiteLoggerLayer;

use strict;
use warnings;

use feature 'unicode_strings';

sub PUSHED
{
  my ($class, $mode, $fh) = @_;
  my $logger;
  return bless \$logger, $class;
}

sub OPEN {
  my ($self, $path, $mode, $fh) = @_;
  # $path is actually our logger object
  $$self = $path;
  return 1;
}

sub WRITE
{
  my ($self, $buf, $fh) = @_;
  $$self->log($buf);
  return length($buf);
}

sub CLOSE {
  my $self = shift;
  $$self->close();
  return 0;
}

1;
