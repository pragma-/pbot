# File: VERSION.pm
#
# Purpose: Keeps track of bot version. Can compare current version against
# latest version on github or URL in `version.check_url` registry entry.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::VERSION;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Exporter qw/import/;
our @EXPORT = ();
our %EXPORT_TAGS = (
    'all' => [qw/BUILD_NAME BUILD_REVISION BUILD_DATE/],
);
our @EXPORT_OK = (
    @{ $EXPORT_TAGS{all} },
);

# These are set automatically by the misc/update_version script
use constant {
    BUILD_NAME     => "PBot",
    BUILD_REVISION => 4315,
    BUILD_DATE     => "2021-07-26",
};

sub initialize {
    # nothing to do here
}

sub version {
    return BUILD_NAME . " version " . BUILD_REVISION . " " . BUILD_DATE;
}

1;
