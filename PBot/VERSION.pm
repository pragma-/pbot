# File: VERSION.pm
# Author: pragma_
#
# Purpose: Keeps track of bot version.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# $Id$

package PBot::VERSION;

use strict;
use warnings;

BEGIN {
  use Exporter;
  our @ISA = 'Exporter';
  our @EXPORT_OK = qw(version);
}

# These are set automatically by the build/commit script
use constant {
  BUILD_NAME     => "PBot",
  BUILD_REVISION => 2004,
  BUILD_DATE     => "2018-02-16",
};

sub new {
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->{pbot}  = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  return $self;
}

sub version {
  return BUILD_NAME . " revision " . BUILD_REVISION . " " . BUILD_DATE;
}

1;
