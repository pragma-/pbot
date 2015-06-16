# File: Refresher.pm
# Author: pragma_
#
# Purpose: Refreshes/reloads module subroutines. Does not refresh/reload
# module member data, only subroutines.

package PBot::Refresher;

use warnings;
use strict;

use Module::Refresh;
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot} = $pbot;

  $self->{refresher} = Module::Refresh->new;

  $pbot->{commands}->register(sub { return $self->refresh(@_) }, "refresh", 90);
}

sub refresh {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  eval {
    if (not $arguments) {
      $self->{pbot}->{logger}->log("Refreshing all modified modules\n");
      $self->{refresher}->refresh;
    } else {
      $self->{pbot}->{logger}->log("Refreshing module $arguments\n");
      if ($self->{refresher}->refresh_module_if_modified($arguments)) {
        $self->{pbot}->{logger}->log("Refreshed module.\n");
      } else {
        $self->{pbot}->{logger}->log("Module had no changes; not refreshed.\n");
      }
    }
  };
  $self->{pbot}->{logger}->log("Error refreshing: $@\n") if $@;
}

1;
