# File: NewModule.pm
# Authoer: pragma_
#
# Purpose: New module skeleton

package PBot::BotAdminStuff;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw(%admins);
}

use vars @EXPORT_OK;

%admins = ();

sub loggedin {
  my ($nick, $host) = @_;

  if(exists $admins{$nick} && $host =~ /$admins{$nick}{host}/
     && exists $admins{$nick}{login}) {
    return 1;
  } else {
    return 0;
  }
}

sub load_admins {
}

sub save_admins {
}

1;
