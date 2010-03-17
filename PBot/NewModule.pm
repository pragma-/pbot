# File: NewModule.pm
# Authoer: pragma_
#
# Purpose: New module skeleton

package PBot::NewModule;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw();
}

use vars @EXPORT_OK;

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Logger should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $option = delete $conf{option};

  if(defined $option) {
    # do something (optional)
  } else {
    # set default value (optional)
    $option = undef;
  }

  my $self = {
    option => $option,
  };

  bless $self, $class;

  return $self;
}

# subs here

1;
