# File: VERSION.pm
# Author: pragma_
#
# Purpose: Keeps track of bot version.

# $Id$

package PBot::VERSION;

use strict;
use warnings;

# These are set automatically by the build/commit script
use constant {
  BUILD_NAME     => "PBot",
  BUILD_REVISION => 1382,
  BUILD_DATE     => "2016-07-01",
};

1;
