# File: NewModule.pm
# Author: pragma_
#
# Purpose: New module skeleton

package PBot::NewModule;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Logger should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
 
  my $option = delete $conf{option};
  $option = 10 unless defined $option; # set to default value unless defined

  if(defined $option) {
    # do something (optional)
  }

  $self->{option} = $option;
}

# subs here

1;
