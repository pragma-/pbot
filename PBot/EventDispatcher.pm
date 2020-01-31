# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::EventDispatcher;

use warnings;
use strict;

use feature 'unicode_strings';

use IO::Select;
use Carp ();

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference in " . __FILE__);
  $self->{handlers} = { any => [] };
}

sub register_handler {
  my ($self, $event_type, $sub) = @_;

  my ($package, $filename, $line, $subroutine) = caller(1);
  my $info = "$filename:$line; $subroutine";
  $self->{pbot}->{logger}->log("Adding handler for $event_type: $info\n") if $self->{pbot}->{registry}->get_value('eventdispatcher', 'debug');
  push @{$self->{handlers}->{$event_type}}, [$sub, $info];
}

sub dispatch_event {
  my ($self, $event_type, $event_data) = @_;
  my $ret = undef;

  if (exists $self->{handlers}->{$event_type}) {
    for (my $i = 0; $i < @{$self->{handlers}->{$event_type}}; $i++) {
      my $ref = @{$self->{handlers}->{$event_type}}[$i];
      my ($handler, $info) = ($ref->[0], $ref->[1]);
      $self->{pbot}->{logger}->log("Dispatching $event_type to handler $info\n") if $self->{pbot}->{registry}->get_value('eventdispatcher', 'debug');

      eval {
        $ret = $handler->($event_type, $event_data);
      };

      if ($@) {
        chomp $@;
        $self->{pbot}->{logger}->log("Error in event handler: $@\n");
        $self->{pbot}->{logger}->log("Removing handler.\n");
        splice @{$self->{handlers}->{$event_type}}, $i--, 1;
      }

      return $ret if $ret;
    }
  }

  for (my $i = 0; $i < @{$self->{handlers}->{any}}; $i++) {
    my $ref = @{$self->{handlers}->{any}}[$i];
    my ($handler, $info) = ($ref->[0], $ref->[1]);
    $self->{pbot}->{logger}->log("Dispatching any to handler $info\n") if $self->{pbot}->{registry}->get_value('eventdispatcher', 'debug');

    eval {
      $ret = $handler->($event_type, $event_data);
    };

    if ($@) {
      chomp $@;
      $self->{pbot}->{logger}->log("Error in event handler: $@\n");
      $self->{pbot}->{logger}->log("Removing handler.\n");
      splice @{$self->{handlers}->{any}}, $i--, 1;
    }

    return $ret if $ret;
  }

  return $ret;
}

1;
