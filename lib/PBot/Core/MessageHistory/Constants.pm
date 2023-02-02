# File: Constants.pm
#
# Purpose: Constants related to message history.

package PBot::Core::MessageHistory::Constants;

use warnings;
use strict;
use constant;

my %constants = (
    MSG_CHAT       => 0,    # PRIVMSG, ACTION
    MSG_JOIN       => 1,    # JOIN
    MSG_DEPARTURE  => 2,    # PART, QUIT, KICK
    MSG_NICKCHANGE => 3,    # CHANGED NICK

    LINK_WEAK   => 0,  # weakly linked AKAs
    LINK_STRONG => 1,  # strongly linked AKAs
);

constant->import(\%constants);

use Exporter qw/import/;
our %EXPORT_TAGS = ('all' => [keys %constants]);
our @EXPORT_OK = (@{$EXPORT_TAGS{all}});

1;
