# File: VERSION.pm
#
# Purpose: Keeps track of bot version constants.
#
# Rather than each PBot::Core package having its own version identifier, all
# of PBot is considered a single package. The BUILD_REVSION constant is the
# count of git commits to the PBot repository.
#
# See also the version command in PBot::Core::Commands::Version. It can compare
# the local PBot version against latest version on GitHub (or the URL in
# the `version.check_url` registry entry) to notify users of the availability
# of a new version.
#
# TODO: The PBot::Plugin::* plugins probably should have their own version
# identifiers as a template for versioned $HOME/PBot/Plugin/ plugins.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::VERSION;

# These are set by the /misc/update_version script
use constant {
    BUILD_NAME     => "PBot",
    BUILD_REVISION => 4318,
    BUILD_DATE     => "2021-07-27",
};

1;
