# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Example;

use warnings;
use strict;

use feature 'unicode_strings';
use Carp ();

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{event_dispatcher}->register_handler('irc.public', sub { $self->on_public(@_) });
}

sub unload {
  my $self = shift;
  # perform plugin clean-up here
  $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
}

sub on_public {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);

  if ($event->{interpreted}) {
    $self->{pbot}->{logger}->log("Message was already handled by the interpreter.\n");
    return 0;
  }

  $self->{pbot}->{logger}->log("Example plugin: got message from $nick!$user\@$host: $msg\n");
  return 0;
}

1;
