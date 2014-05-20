# File: SQLiteLoggerLayer
# Author: pragma_
#
# Purpose: PerlIO::via layer to log DBI trace messages

package PBot::SQLiteLoggerLayer;

use strict;
use warnings;

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
