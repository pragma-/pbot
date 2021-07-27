# File: VERSION.pm
#
# Purpose: Keeps track of bot version. All of PBot is considered a single
# entity. The BUILD_REVSION constant in this file is the count of git commits
# to the PBot repository when this file was updated. This file is updated by
# the /misc/update_version script after any commits that alter PBot's behavior.
#
# See also PBot::Core::Commands::Version, which can compare current version
# against latest version on github or URL in `version.check_url` registry
# entry to notify users of the availability of a new version.
#
# TODO: The PBot::Plugin::* plugins probably should have their own version
# identifiers as a template for using versioned $HOME/PBot/Plugin/ plugins. I
# don't want to micro-manage version identifiers for PBot::Core stuff though.

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

# These are set automatically by the /misc/update_version script
use constant {
    BUILD_NAME     => "PBot",
    BUILD_REVISION => 4317,
    BUILD_DATE     => "2021-07-27",
};

sub initialize {
    # nothing to do here
}

sub version {
    return BUILD_NAME . " version " . BUILD_REVISION . " " . BUILD_DATE;
}

1;
