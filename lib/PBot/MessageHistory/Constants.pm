# File: Constants.pm
#
# Purpose: Constants related to message history.

package PBot::MessageHistory::Constants;

use Exporter qw/import/;

our @EXPORT = ();

our %EXPORT_TAGS = (
    'all' => [qw/MSG_CHAT MSG_JOIN MSG_DEPARTURE MSG_NICKCHANGE/],
);

our @EXPORT_OK = (
    @{ $EXPORT_TAGS{all} },
);

use constant {
    MSG_CHAT       => 0,    # PRIVMSG, ACTION
    MSG_JOIN       => 1,    # JOIN
    MSG_DEPARTURE  => 2,    # PART, QUIT, KICK
    MSG_NICKCHANGE => 3,    # CHANGED NICK
};

1;
