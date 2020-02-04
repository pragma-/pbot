# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::SelectHandler;

use warnings;
use strict;

use feature 'unicode_strings';

use IO::Select;
use Carp ();

sub new {
  Carp::croak("Options to SelectHandler should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference in SelectHandler");
  $self->{select} = IO::Select->new();
  $self->{readers} = {};
  $self->{buffers} = {};
}

sub add_reader {
  my ($self, $handle, $sub) = @_;
  $self->{select}->add($handle);
  $self->{readers}->{$handle} = $sub;
  $self->{buffers}->{$handle} = "";
}

sub remove_reader {
  my ($self, $handle) = @_;
  $self->{select}->remove($handle);
  delete $self->{readers}->{$handle};
  delete $self->{buffers}->{$handle};
}

sub do_select {
  my ($self) = @_;
  my $length = 8192;
  my @ready = $self->{select}->can_read(0);
  foreach my $fh (@ready) {
    my $ret = sysread($fh, my $buf, $length);

    if (not defined $ret) {
      $self->{pbot}->{logger}->log("Error with $fh: $!\n");
      $self->remove_reader($fh);
      next;
    }

    if ($ret == 0) {
      if (length $self->{buffers}->{$fh}) {
        $self->{readers}->{$fh}->($self->{buffers}->{$fh});
      }
      $self->remove_reader($fh);
      next;
    }

    $self->{buffers}->{$fh} .= $buf;

    if (not exists $self->{readers}->{$fh}) {
      $self->{pbot}->{logger}->log("Error: no reader for $fh\n");
    } else {
      if ($ret < $length) {
        $self->{readers}->{$fh}->($self->{buffers}->{$fh});
        $self->{buffers}->{$fh} = "";
      }
    }
  }
}

1;
